
from __future__ import annotations

import asyncio
import hashlib
import importlib
import inspect
import json
import logging
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    # Lets `import scraper` work no matter which directory the process starts in
    # (important for Windows Task Scheduler / services).
    sys.path.insert(0, BASE_DIR)

try:
    from dotenv import load_dotenv

    load_dotenv(os.path.join(BASE_DIR, ".env"))
except ImportError:  # python-dotenv is optional
    pass

from pymongo import ASCENDING, MongoClient, UpdateOne
from pymongo.errors import BulkWriteError, PyMongoError

from eligibility_engine import StructuredRuleExtractor, ApprovalStatus

try:
    import redis
except ImportError:  # redis is optional; cache refresh is skipped without it
    redis = None

logger = logging.getLogger("schemesathi.updater")


# --------------------------------------------------------------------------- #
# Environment helpers
# --------------------------------------------------------------------------- #
def env_str(name: str, default: str) -> str:
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    return value.strip()


def env_int(name: str, default: int, minimum: Optional[int] = None) -> int:
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    try:
        value = int(raw.strip())
    except ValueError:
        logger.warning("Invalid integer for %s=%r; using default %s", name, raw, default)
        return default
    if minimum is not None and value < minimum:
        logger.warning("%s=%s is below minimum %s; using default %s", name, value, minimum, default)
        return default
    return value


def env_float(name: str, default: float, minimum: Optional[float] = None) -> float:
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    try:
        value = float(raw.strip())
    except ValueError:
        logger.warning("Invalid number for %s=%r; using default %s", name, raw, default)
        return default
    if minimum is not None and value < minimum:
        logger.warning("%s=%s is below minimum %s; using default %s", name, value, minimum, default)
        return default
    return value


def env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    return raw.strip().lower() in ("1", "true", "yes", "y", "on")


# --------------------------------------------------------------------------- #
# Constants / assumptions about the existing scraper
# --------------------------------------------------------------------------- #
# Used only when scraper.py exposes no state list of its own and STATES is unset.
DEFAULT_STATES_AND_UTS: Tuple[str, ...] = (
    # 28 states
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa",
    "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala",
    "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland",
    "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
    "Uttar Pradesh", "Uttarakhand", "West Bengal",
    # 8 union territories
    "Andaman and Nicobar Islands", "Chandigarh",
    "Dadra and Nagar Haveli and Daman and Diu", "Delhi", "Jammu and Kashmir",
    "Ladakh", "Lakshadweep", "Puducherry",
)

# Scraper function names tried (in order) when SCRAPER_FUNCTION is not set.
# The function must accept the state name as its first argument.
CANDIDATE_SCRAPER_FUNCTIONS: Tuple[str, ...] = (
    "get_schemes_by_state", "scrape_schemes_by_state", "fetch_schemes_by_state",
    "scrape_state_schemes", "fetch_state_schemes", "get_state_schemes",
    "scrape_schemes", "fetch_schemes", "get_schemes", "scrape_state", "scrape",
)

# Names under which scraper.py might expose its supported state list.
CANDIDATE_STATE_ATTRS: Tuple[str, ...] = (
    "STATES", "INDIAN_STATES", "STATES_AND_UTS", "STATE_LIST", "ALL_STATES",
    "SUPPORTED_STATES", "STATE_NAMES",
)
CANDIDATE_STATE_FUNCS: Tuple[str, ...] = (
    "get_states", "get_all_states", "get_supported_states", "list_states",
)

NAME_KEYS = ("name", "scheme_name", "schemeName", "scheme", "title", "scheme_title", "schemeTitle")
URL_KEYS = ("url", "link", "scheme_url", "source_url", "href", "official_url")
RESULT_LIST_KEYS = ("schemes", "data", "results", "items", "records")

# Fields that change on every scrape and must not count as a "change".
VOLATILE_KEYS = frozenset(
    k.casefold()
    for k in (
        "_id", "scraped_at", "scrapedat", "fetched_at", "fetchedat", "timestamp",
        "last_updated", "lastupdated", "updated_at", "updatedat", "created_at",
        "createdat", "last_scraped", "last_seen_at",
    )
)

BULK_CHUNK = 500
LOOKUP_CHUNK = 1000
_WS = re.compile(r"\s+")


class ScrapeError(Exception):
    """Scrape failed or produced nothing usable; existing data must be kept."""


# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class UpdaterConfig:
    mongo_uri: str = "mongodb://localhost:27017"
    mongo_db: str = "schemesathi"
    schemes_collection: str = "schemes"
    mongo_timeout_ms: int = 10000
    redis_enabled: bool = True
    redis_url: str = "redis://localhost:6379/0"
    redis_prefix: str = "schemesathi:schemes"
    cache_ttl: int = 0
    scraper_module: str = "scraper"
    scraper_function: str = ""
    states: Optional[Tuple[str, ...]] = None
    scrape_retries: int = 2
    retry_backoff: float = 5.0
    state_delay: float = 1.0
    batch_size: int = 4
    batch_delay: float = 30.0
    rate_limit_backoff: float = 60.0

    @classmethod
    def from_env(cls) -> "UpdaterConfig":
        raw_states = os.getenv("STATES", "")
        states = tuple(s.strip() for s in raw_states.split(",") if s.strip()) or None
        return cls(
            mongo_uri=env_str("MONGO_URI", cls.mongo_uri),
            mongo_db=env_str("MONGO_DB", cls.mongo_db),
            schemes_collection=env_str("SCHEMES_COLLECTION", cls.schemes_collection),
            mongo_timeout_ms=env_int("MONGO_TIMEOUT_MS", cls.mongo_timeout_ms, minimum=1000),
            redis_enabled=env_bool("REDIS_ENABLED", True),
            redis_url=env_str("REDIS_URL", cls.redis_url),
            redis_prefix=env_str("REDIS_KEY_PREFIX", cls.redis_prefix).rstrip(":"),
            cache_ttl=env_int("CACHE_TTL_SECONDS", 0, minimum=0),
            scraper_module=env_str("SCRAPER_MODULE", cls.scraper_module),
            scraper_function=env_str("SCRAPER_FUNCTION", ""),
            states=states,
            scrape_retries=env_int("SCRAPE_RETRIES", 2, minimum=0),
            retry_backoff=env_float("SCRAPE_RETRY_BACKOFF", 5.0, minimum=0.0),
            state_delay=env_float("STATE_DELAY_SECONDS", 1.0, minimum=0.0),
            batch_size=env_int('BATCH_SIZE', 4, minimum=1),
            batch_delay=env_float('BATCH_DELAY_SECONDS', 30.0, minimum=0.0),
            rate_limit_backoff=env_float('RATE_LIMIT_BACKOFF_SECONDS', 60.0, minimum=5.0),
        )


# --------------------------------------------------------------------------- #
# Result containers
# --------------------------------------------------------------------------- #
@dataclass
class StateResult:
    state: str
    scraped: int = 0
    new: int = 0
    changed: int = 0
    unchanged: int = 0
    invalid: int = 0
    duplicates: int = 0
    error: Optional[str] = None
    source: str = ''


@dataclass
class UpdateSummary:
    states_total: int = 0
    states_ok: int = 0
    failed: Dict[str, str] = field(default_factory=dict)
    new: int = 0
    changed: int = 0
    unchanged: int = 0
    invalid: int = 0
    duplicates: int = 0
    cache_refreshed: bool = False
    aborted: bool = False
    duration: float = 0.0
    api_successes: int = 0
    fallback_used: int = 0

    @property
    def success(self) -> bool:
        """True when at least one state synced, or there was nothing to do."""
        return self.states_total == 0 or self.states_ok > 0

    def as_log_line(self) -> str:
        failed_detail = ''
        if self.failed:
            failed_detail = ' | failed: ' + '; '.join(
                f'{s}={v}' for s, v in sorted(self.failed.items())
            )
        return (
            'states_ok=%d/%d failed=%d api=%d fallback=%d '
            'new=%d changed=%d unchanged=%d invalid=%d '
            'duplicates=%d cache_refreshed=%s aborted=%s duration=%.1fs%s'
            % (
                self.states_ok, self.states_total, len(self.failed),
                self.api_successes, self.fallback_used,
                self.new, self.changed, self.unchanged, self.invalid,
                self.duplicates, self.cache_refreshed, self.aborted,
                self.duration, failed_detail,
            )
        )


# --------------------------------------------------------------------------- #
# Scraper adapter (reuses the existing scraper.py; contains no scraping logic)
# --------------------------------------------------------------------------- #
def load_scraper(module_name: str, function_name: str) -> Tuple[Any, Callable[..., Any]]:
    """Load the existing scraper as either a module function or a scraper class."""
    module = importlib.import_module(module_name)

    if function_name:
        func = getattr(module, function_name, None)
        if not callable(func):
            raise RuntimeError(
                "SCRAPER_FUNCTION=%r was not found (or is not callable) in module %r"
                % (function_name, module_name)
            )
        return module, func

    for candidate in CANDIDATE_SCRAPER_FUNCTIONS:
        func = getattr(module, candidate, None)
        if callable(func):
            logger.info("Using scraper function %s.%s", module_name, candidate)
            return module, func

    # Support the project's existing MySchemeScraper class (instance method).
    for class_name in ("MySchemeScraper", "SchemeScraper", "Scraper"):
        cls = getattr(module, class_name, None)
        if inspect.isclass(cls):
            instance = cls()
            for method_name in ("scrape_schemes", "scrape_state", "fetch_schemes", "get_schemes"):
                method = getattr(instance, method_name, None)
                if callable(method):
                    logger.info("Using scraper class %s.%s", class_name, method_name)
                    return module, lambda state, _method=method: _method(state)

    public = sorted(
        n for n, v in vars(module).items()
        if callable(v) and not n.startswith("_") and getattr(v, "__module__", None) == module.__name__
    )
    raise RuntimeError(
        "Could not auto-detect a per-state scraper in %r. Set SCRAPER_FUNCTION to a function "
        "that accepts a state name. Public callables found: %s"
        % (module_name, ", ".join(public) or "none")
    )


def _as_state_list(value: Any) -> Optional[List[str]]:
    if isinstance(value, dict):
        value = list(value.keys())
    elif isinstance(value, (set, frozenset)):
        value = sorted(value, key=str)
    if isinstance(value, (list, tuple)) and value and all(isinstance(v, str) and v.strip() for v in value):
        seen: Set[str] = set()
        ordered = []
        for v in value:
            v = v.strip()
            if v.casefold() not in seen:
                seen.add(v.casefold())
                ordered.append(v)
        return ordered
    return None


def discover_states(module: Any) -> List[str]:
    """Prefer the scraper's own list of supported states/UTs, else use the defaults."""
    for attr in CANDIDATE_STATE_ATTRS:
        found = _as_state_list(getattr(module, attr, None))
        if found:
            logger.info("Using %d states/UTs from %s.%s", len(found), module.__name__, attr)
            return found
    for func_name in CANDIDATE_STATE_FUNCS:
        func = getattr(module, func_name, None)
        if callable(func):
            try:
                if inspect.signature(func).parameters and any(
                    p.default is inspect.Parameter.empty
                    and p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD, p.KEYWORD_ONLY)
                    for p in inspect.signature(func).parameters.values()
                ):
                    continue
                result = func()
                if inspect.isawaitable(result):
                    result = _run_awaitable(result)
                found = _as_state_list(result)
                if found:
                    logger.info("Using %d states/UTs from %s.%s()", len(found), module.__name__, func_name)
                    return found
            except Exception as exc:  # noqa: BLE001 - discovery must never crash the run
                logger.debug("State discovery via %s failed: %s", func_name, exc)
    logger.info("scraper has no state list; using built-in list of %d states/UTs", len(DEFAULT_STATES_AND_UTS))
    return list(DEFAULT_STATES_AND_UTS)


async def _await(awaitable: Any) -> Any:
    return await awaitable


def _run_awaitable(awaitable: Any) -> Any:
    return asyncio.run(_await(awaitable))


def extract_records(result: Any) -> Optional[List[Dict[str, Any]]]:
    """Normalise whatever the scraper returned into a list of dict records."""
    if result is None:
        return None
    if inspect.isgenerator(result):
        result = list(result)
    if isinstance(result, dict):
        for key in RESULT_LIST_KEYS:
            inner = result.get(key)
            if isinstance(inner, (list, tuple)):
                result = inner
                break
        else:
            return None
    if isinstance(result, tuple) and result and isinstance(result[0], (list, tuple)):
        result = result[0]  # e.g. (schemes, metadata)
    if not isinstance(result, (list, tuple)):
        return None

    records: List[Dict[str, Any]] = []
    for item in result:
        if isinstance(item, dict):
            records.append(item)
        elif isinstance(item, str) and item.strip():
            records.append({"name": item.strip()})
    return records


# --------------------------------------------------------------------------- #
# Document building
# --------------------------------------------------------------------------- #
def _norm(text: str) -> str:
    return _WS.sub(" ", str(text)).strip().casefold()


def _first_text(record: Dict[str, Any], keys: Sequence[str]) -> Optional[str]:
    lowered = {str(k).casefold(): v for k, v in record.items()}
    for key in keys:
        value = lowered.get(key.casefold())
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _safe_key(key: Any) -> str:
    text = str(key).replace(".", "_")
    if text.startswith("$"):
        text = "_" + text[1:]
    return text or "_"


def _sanitize_keys(value: Any) -> Any:
    if isinstance(value, dict):
        return {_safe_key(k): _sanitize_keys(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize_keys(v) for v in value]
    return value


def _strip_volatile(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _strip_volatile(v) for k, v in value.items() if str(k).casefold() not in VOLATILE_KEYS}
    if isinstance(value, list):
        return [_strip_volatile(v) for v in value]
    return value


@dataclass
class SchemeDoc:
    key: str
    name: str
    state: str
    url: Optional[str]
    content_hash: str
    data: Dict[str, Any]


def build_scheme_doc(state: str, record: Dict[str, Any]) -> Optional[SchemeDoc]:
    """Turn a raw scraped record into a storable document, or None if unusable."""
    try:
        clean = json.loads(json.dumps(record, default=str, ensure_ascii=False))
    except (TypeError, ValueError):
        return None
    if not isinstance(clean, dict):
        return None

    name = _first_text(clean, NAME_KEYS)
    url = _first_text(clean, URL_KEYS)
    identity = name or url
    if not identity:
        return None

    data = _sanitize_keys(clean)
    canonical = json.dumps(
        _strip_volatile(data), sort_keys=True, ensure_ascii=False, separators=(",", ":")
    )
    content_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    key = hashlib.sha1(("%s|%s" % (_norm(state), _norm(identity))).encode("utf-8")).hexdigest()
    return SchemeDoc(
        key=key, name=name or identity, state=state, url=url, content_hash=content_hash, data=data
    )


def _chunks(items: Iterable[Any], size: int) -> Iterator[List[Any]]:
    batch = list(items)
    for i in range(0, len(batch), size):
        yield batch[i:i + size]


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.casefold()).strip("-") or "unknown"


def _json_default(obj: Any) -> str:
    if isinstance(obj, datetime):
        return obj.isoformat()
    return str(obj)


# --------------------------------------------------------------------------- #
# The updater
# --------------------------------------------------------------------------- #
class SchemeUpdater:
    def __init__(
        self,
        config: Optional[UpdaterConfig] = None,
        scraper_func: Optional[Callable[..., Any]] = None,
        scraper_module: Any = None,
    ) -> None:
        self.cfg = config or UpdaterConfig.from_env()

        if scraper_func is None:
            scraper_module, scraper_func = load_scraper(self.cfg.scraper_module, self.cfg.scraper_function)
        self._scrape = scraper_func

        if self.cfg.states:
            self.states: List[str] = list(self.cfg.states)
        elif scraper_module is not None:
            self.states = discover_states(scraper_module)
        else:
            self.states = list(DEFAULT_STATES_AND_UTS)

        self._mongo = MongoClient(self.cfg.mongo_uri, serverSelectionTimeoutMS=self.cfg.mongo_timeout_ms)
        self.collection = self._mongo[self.cfg.mongo_db][self.cfg.schemes_collection]
        self._redis = self._connect_redis()
        self._ensure_indexes()
        self._seen_states: Set[str] = set()

    # -- lifecycle ---------------------------------------------------------- #
    def __enter__(self) -> "SchemeUpdater":
        return self

    def __exit__(self, *exc_info: Any) -> None:
        self.close()

    def close(self) -> None:
        try:
            self._mongo.close()
        except Exception:  # noqa: BLE001
            pass
        if self._redis is not None:
            try:
                self._redis.close()
            except Exception:  # noqa: BLE001
                pass

    # -- setup -------------------------------------------------------------- #
    def _connect_redis(self) -> Any:
        if not self.cfg.redis_enabled:
            logger.info("Redis cache refresh disabled (REDIS_ENABLED=false)")
            return None
        if redis is None:
            logger.warning("redis package not installed; cache refresh will be skipped (pip install redis)")
            return None
        try:
            return redis.Redis.from_url(
                self.cfg.redis_url,
                decode_responses=True,
                socket_timeout=5,
                socket_connect_timeout=5,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not create Redis client (%s); cache refresh will be skipped", exc)
            return None

    def _ensure_indexes(self) -> None:
        self.collection.create_index([("scheme_key", ASCENDING)], unique=True, name="uniq_scheme_key")
        self.collection.create_index([("state", ASCENDING), ("name", ASCENDING)], name="state_name")

    # -- scraping (delegated to the existing scraper) ------------------------ #
    def _scrape_once(self, state: str) -> List[Dict[str, Any]]:
        result = self._scrape(state)
        if inspect.isawaitable(result):
            result = _run_awaitable(result)
        records = extract_records(result)
        if records is None:
            raise ScrapeError("scraper returned an unrecognised result type: %s" % type(result).__name__)
        if not records:
            raise ScrapeError("scraper returned no schemes")
        return records

    def _scrape_with_retries(self, state: str) -> List[Dict[str, Any]]:
        attempts = self.cfg.scrape_retries + 1
        last_exc: Optional[BaseException] = None
        for attempt in range(1, attempts + 1):
            try:
                return self._scrape_once(state)
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                exc_str = str(exc)
                is_rate_limit = '429' in exc_str or 'rate limit' in exc_str.lower()
                logger.warning('[%s] scrape attempt %d/%d failed: %s', state, attempt, attempts, exc)
                if attempt < attempts:
                    # Exponential backoff: 5, 10, 20 ... capped at 300s
                    backoff = min(self.cfg.retry_backoff * (2 ** (attempt - 1)), 300.0)
                    if is_rate_limit:
                        # Try to extract explicit wait time from exception message
                        m = re.search(r'(\d+)\s*s', exc_str)
                        if m:
                            backoff = min(float(m.group(1)), 300.0)
                        logger.warning(
                            '[%s] 429 detected; waiting %.0fs before retry attempt %d/%d',
                            state, backoff, attempt + 1, attempts,
                        )
                    else:
                        logger.info('[%s] waiting %.0fs before retry attempt %d/%d',
                                    state, backoff, attempt + 1, attempts)
                    time.sleep(backoff)
        raise ScrapeError(str(last_exc) if last_exc else 'unknown scrape failure')

    # -- synchronisation ------------------------------------------------------ #
    def sync_state(self, state: str, records: List[Dict[str, Any]]) -> StateResult:
        """Insert new schemes, update changed ones, leave everything else untouched."""
        result = StateResult(state=state, scraped=len(records))

        docs: Dict[str, SchemeDoc] = {}
        for record in records:
            doc = build_scheme_doc(state, record)
            if doc is None:
                result.invalid += 1
            elif doc.key in docs:
                result.duplicates += 1
            else:
                docs[doc.key] = doc
        if not docs:
            raise ScrapeError("no valid scheme records after validation")

        existing: Dict[str, Optional[str]] = {}
        for chunk in _chunks(docs.keys(), LOOKUP_CHUNK):
            cursor = self.collection.find(
                {"scheme_key": {"$in": chunk}}, {"scheme_key": 1, "content_hash": 1}
            )
            for row in cursor:
                existing[row["scheme_key"]] = row.get("content_hash")

        now = datetime.now(timezone.utc)
        ops: List[UpdateOne] = []
        unchanged_keys: List[str] = []
        for key, doc in docs.items():
            if key in existing and existing[key] == doc.content_hash:
                unchanged_keys.append(key)
                continue

            # New or changed content: Extract structured rules according to flowchart
            raw_eligibility = (
                doc.data.get("eligibility")
                or doc.data.get("Eligibility Criteria")
                or doc.data.get("Eligibility (General)")
                or ""
            )
            raw_documents = (
                doc.data.get("documents_required")
                or doc.data.get("Documents Required")
                or ""
            )
            source_url = doc.url or doc.data.get("official_link") or doc.data.get("url")

            extracted_rules = StructuredRuleExtractor.extract_from_scheme(
                scheme_key=key,
                name=doc.name,
                state=doc.state,
                raw_eligibility=raw_eligibility,
                raw_documents=raw_documents,
                source_url=source_url,
                auto_approve=False,  # Enters admin approval pipeline
            )

            set_fields: Dict[str, Any] = {
                "name": doc.name,
                "state": doc.state,
                "source_url": source_url,
                "content_hash": doc.content_hash,
                "data": doc.data,
                "is_active": True,
                "is_new": (key not in existing),  # Mark as new scheme if inserting for first time
                "application_status": "open",
                "structured_rules": extracted_rules.model_dump(mode="json"),
                "original_eligibility_text": raw_eligibility,
                "original_documents_text": raw_documents,
                "approval_status": extracted_rules.approval_status.value,
                "consecutive_fetch_failures": 0,
                "updated_at": now,
                "last_seen_at": now,
            }

            ops.append(
                UpdateOne(
                    {"scheme_key": key},
                    {
                        "$set": set_fields,
                        "$setOnInsert": {"created_at": now},
                    },
                    upsert=True,
                )
            )
        result.unchanged = len(unchanged_keys)

        created = modified = 0
        write_errors: List[str] = []
        for chunk in _chunks(ops, BULK_CHUNK):
            try:
                res = self.collection.bulk_write(chunk, ordered=False)
                created += res.upserted_count
                modified += res.modified_count
            except BulkWriteError as exc:
                details = exc.details or {}
                created += details.get("nUpserted", 0)
                modified += details.get("nModified", 0)
                for err in details.get("writeErrors", [])[:3]:
                    write_errors.append(str(err.get("errmsg", err)))
        result.new = created
        result.changed = modified

        for chunk in _chunks(unchanged_keys, LOOKUP_CHUNK):
            try:
                self.collection.update_many(
                    {"scheme_key": {"$in": chunk}}, {"$set": {"last_seen_at": now, "is_active": True}}
                )
            except PyMongoError as exc:
                logger.warning("[%s] could not update last_seen_at: %s", state, exc)
                break

        if write_errors:
            result.error = "MongoDB write errors, e.g.: %s" % "; ".join(write_errors)
        return result

    # -- cache ---------------------------------------------------------------- #
    def _state_key(self, state: str) -> str:
        return "%s:state:%s" % (self.cfg.redis_prefix, _slug(state))

    def _all_key(self) -> str:
        return "%s:all" % self.cfg.redis_prefix

    def _meta_key(self) -> str:
        return "%s:last_updated" % self.cfg.redis_prefix

    def _plan_cache_refresh(self, ok_states: Sequence[str], dirty: Set[str]) -> Tuple[Set[str], bool]:
        """Decide which cache entries to rebuild: changed states + any cold/missing entries."""
        states = set(dirty)
        refresh_all = bool(dirty)
        try:
            for state in ok_states:
                if not self._redis.exists(self._state_key(state)):
                    states.add(state)
            if ok_states and not self._redis.exists(self._all_key()):
                refresh_all = True
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not inspect Redis cache (%s); refreshing changed states only", exc)
        return states, refresh_all or bool(states)

    def refresh_cache(self, states: Iterable[str], refresh_all: bool = True) -> bool:
        """Rebuild cache entries from MongoDB (the source of truth). Never raises."""
        if self._redis is None:
            return False
        try:
            ttl = self.cfg.cache_ttl if self.cfg.cache_ttl > 0 else None
            pipe = self._redis.pipeline(transaction=False)
            for state in sorted(set(states)):
                docs = list(self.collection.find({"state": state}, {"_id": 0}).sort("name", ASCENDING))
                if docs:
                    pipe.set(self._state_key(state), json.dumps(docs, default=_json_default), ex=ttl)
            if refresh_all:
                all_docs = list(self.collection.find({}, {"_id": 0}).sort([("state", ASCENDING), ("name", ASCENDING)]))
                pipe.set(self._all_key(), json.dumps(all_docs, default=_json_default), ex=ttl)
            pipe.set(self._meta_key(), datetime.now(timezone.utc).isoformat(), ex=ttl)
            pipe.execute()
            return True
        except Exception as exc:  # noqa: BLE001 - cache problems must not fail the sync
            logger.error("Redis cache refresh failed (MongoDB data is intact): %s", exc)
            return False

    # -- orchestration ---------------------------------------------------------- #
    def run_update(
        self,
        states: Optional[Sequence[str]] = None,
        should_stop: Optional[Callable[[], bool]] = None,
    ) -> UpdateSummary:
        started = time.monotonic()
        targets = list(states) if states else list(self.states)

        # Deduplication guard: skip states already processed in this updater's lifetime
        targets = [s for s in targets if s not in self._seen_states]

        summary = UpdateSummary(states_total=len(targets))
        ok_states: List[str] = []  # states that synced successfully
        dirty: Set[str] = set()

        # Split into batches
        batch_size = self.cfg.batch_size
        batches: List[List[str]] = [
            targets[i:i + batch_size] for i in range(0, len(targets), batch_size)
        ]
        total_batches = len(batches)
        logger.info(
            'Scheme update started for %d states/UTs in %d batch(es) of up to %d',
            len(targets), total_batches, batch_size,
        )

        state_index = 0  # global index across all batches (for _pause)
        for batch_num, batch in enumerate(batches, 1):
            if should_stop is not None and should_stop():
                summary.aborted = True
                logger.warning('Stop requested; aborting before batch %d', batch_num)
                break

            logger.info(
                'Batch %d/%d: %s',
                batch_num, total_batches, ', '.join(batch),
            )

            for state in batch:
                if should_stop is not None and should_stop():
                    summary.aborted = True
                    logger.warning('Stop requested; aborting before %s', state)
                    break

                # Capture last_429_at before this state so we can detect new 429s
                scraper_instance = None
                pre_429 = None
                # Access the scraper instance if it exposes last_429_at
                try:
                    # The scraper func is a lambda wrapping an instance method;
                    # get the instance from the closure.
                    inner = getattr(self._scrape, '__self__', None)
                    if inner is None:
                        # Try closure
                        import inspect as _inspect
                        closure = getattr(self._scrape, '__closure__', None) or []
                        for cell in closure:
                            try:
                                obj = cell.cell_contents
                                if hasattr(obj, 'last_429_at'):
                                    inner = obj
                                    break
                            except ValueError:
                                pass
                    scraper_instance = inner
                    if scraper_instance is not None:
                        pre_429 = scraper_instance.last_429_at
                except Exception:
                    pass

                try:
                    records = self._scrape_with_retries(state)
                except Exception as exc:  # noqa: BLE001
                    logger.error('[%s] scrape failed; existing data preserved: %s', state, exc)
                    summary.failed[state] = str(exc)
                    self._pause(state_index, len(targets))
                    state_index += 1
                    self._write_progress(ok_states, summary)
                    continue

                # Detect if a 429 occurred during this state's scrape
                if scraper_instance is not None:
                    post_429 = scraper_instance.last_429_at
                    if post_429 is not None and post_429 != pre_429:
                        logger.warning(
                            '[%s] 429 was received during scrape; '
                            'sleeping %.0fs before next state',
                            state, self.cfg.rate_limit_backoff,
                        )
                        time.sleep(self.cfg.rate_limit_backoff)
                        scraper_instance.last_429_at = None  # reset

                try:
                    res = self.sync_state(state, records)
                except Exception as exc:  # noqa: BLE001
                    logger.error('[%s] synchronisation failed; scraped data discarded: %s', state, exc)
                    summary.failed[state] = str(exc)
                    dirty.add(state)
                    self._pause(state_index, len(targets))
                    state_index += 1
                    self._write_progress(ok_states, summary)
                    continue

                # Determine source from scraped records
                source = ''
                if records:
                    source = records[0].get('source', '')
                res.source = source
                if source == 'MyScheme API':
                    summary.api_successes += 1
                elif source in ('GitHub dataset', 'fallback'):
                    summary.fallback_used += 1

                summary.new += res.new
                summary.changed += res.changed
                summary.unchanged += res.unchanged
                summary.invalid += res.invalid
                summary.duplicates += res.duplicates
                if res.new or res.changed:
                    dirty.add(state)
                if res.error:
                    logger.error('[%s] %s', state, res.error)
                    summary.failed[state] = res.error
                else:
                    summary.states_ok += 1
                    ok_states.append(state)
                    self._seen_states.add(state)
                logger.info(
                    '[%s] scraped=%d new=%d changed=%d unchanged=%d '
                    'invalid=%d duplicates=%d source=%s',
                    state, res.scraped, res.new, res.changed, res.unchanged,
                    res.invalid, res.duplicates, res.source,
                )
                self._pause(state_index, len(targets))
                state_index += 1
                self._write_progress(ok_states, summary)

            else:
                # Normal end of batch (no break from should_stop)
                if batch_num < total_batches and self.cfg.batch_delay > 0:
                    logger.info(
                        'Batch %d/%d complete; sleeping %.0fs before next batch...',
                        batch_num, total_batches, self.cfg.batch_delay,
                    )
                    time.sleep(self.cfg.batch_delay)
                continue
            # should_stop broke inner loop
            break

        if self._redis is not None and (ok_states or dirty):
            to_refresh, refresh_all = self._plan_cache_refresh(ok_states, dirty)
            if to_refresh or refresh_all:
                summary.cache_refreshed = self.refresh_cache(to_refresh, refresh_all)
                if summary.cache_refreshed:
                    logger.info(
                        'Redis cache refreshed (%d state entries, all=%s)',
                        len(to_refresh), refresh_all,
                    )
            else:
                logger.info('No changes detected; Redis cache already up to date')

        summary.duration = time.monotonic() - started
        logger.info('Scheme update finished: %s', summary.as_log_line())

        # Enhanced multi-line human-readable summary
        logger.info(
            '\n' + '=' * 60 + '\n'
            'SCHEME UPDATE SUMMARY\n'
            '  Total states processed : %d\n'
            '  Successful             : %d\n'
            '  Failed                 : %d\n'
            '  API successes          : %d\n'
            '  Fallback used          : %d\n'
            '  New schemes            : %d\n'
            '  Changed schemes        : %d\n'
            '  Unchanged schemes      : %d\n'
            '  Total execution time   : %.1f s\n'
            + ('  Failed states:\n' + '\n'.join(
                f'    - {s}: {e}' for s, e in sorted(summary.failed.items())
            ) if summary.failed else '') +
            '\n' + '=' * 60,
            summary.states_total, summary.states_ok, len(summary.failed),
            summary.api_successes, summary.fallback_used,
            summary.new, summary.changed, summary.unchanged,
            summary.duration,
        )

        if summary.failed:
            logger.warning('Failed states: %s', ', '.join(sorted(summary.failed)))
        return summary

    def _pause(self, index: int, total: int) -> None:
        if index < total - 1 and self.cfg.state_delay > 0:
            time.sleep(self.cfg.state_delay)

    def _write_progress(self, ok_states: List[str], summary: 'UpdateSummary') -> None:
        """Persist a compact progress snapshot after each state. Never raises."""
        try:
            progress_path = os.path.join(BASE_DIR, 'logs', 'update_progress.json')
            os.makedirs(os.path.dirname(progress_path), exist_ok=True)
            data = {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'states_done': list(ok_states),
                'states_failed': dict(summary.failed),
                'new': summary.new,
                'changed': summary.changed,
                'unchanged': summary.unchanged,
            }
            with open(progress_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception as exc:  # noqa: BLE001
            logger.debug('Could not write progress file: %s', exc)


# --------------------------------------------------------------------------- #
# Combined updater + scheduled worker
# --------------------------------------------------------------------------- #
import argparse
import signal
import threading
from contextlib import contextmanager


class SingleRunLock:
    """Prevent two copies of this worker from updating MongoDB simultaneously."""
    def __init__(self, path: str) -> None:
        self.path = path
        self.file = None

    def acquire(self) -> bool:
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        self.file = open(self.path, "a+b")
        try:
            if os.name == "nt":
                import msvcrt
                self.file.seek(0)
                if self.file.read(1) == b"":
                    self.file.seek(0)
                    self.file.write(b"0")
                    self.file.flush()
                self.file.seek(0)
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (OSError, BlockingIOError):
            self.file.close()
            self.file = None
            return False

    def release(self) -> None:
        if self.file is None:
            return
        try:
            if os.name == "nt":
                import msvcrt
                self.file.seek(0)
                msvcrt.locking(self.file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        self.file.close()
        self.file = None


def configure_logging() -> None:
    level = getattr(logging, env_str("LOG_LEVEL", "INFO").upper(), logging.INFO)
    log_path = env_str("WORKER_LOG_FILE", os.path.join(BASE_DIR, "logs", "scheme_updater.log"))
    os.makedirs(os.path.dirname(log_path) or ".", exist_ok=True)
    handlers: List[logging.Handler] = [logging.StreamHandler()]
    try:
        from logging.handlers import RotatingFileHandler
        handlers.append(RotatingFileHandler(log_path, maxBytes=5_000_000, backupCount=3, encoding="utf-8"))
    except OSError:
        logging.getLogger(__name__).warning("File logging unavailable; using console only")
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)s [%(name)s] %(message)s", handlers=handlers)


def run_cycle(stop_event: Optional[threading.Event] = None) -> int:
    lock_path = env_str("WORKER_LOCK_FILE", os.path.join(BASE_DIR, "logs", "scheme_updater.lock"))
    lock = SingleRunLock(lock_path)
    if not lock.acquire():
        logger.warning("Another updater process is running; skipping this cycle")
        return 2
    try:
        with SchemeUpdater() as updater:
            summary = updater.run_update(should_stop=(stop_event.is_set if stop_event else None))
        return 0 if summary.success else 1
    except Exception:
        logger.exception("Scheme update cycle crashed")
        return 1
    finally:
        lock.release()


def main() -> int:
    configure_logging()
    parser = argparse.ArgumentParser(description="SchemeSathi scheme updater and scheduled worker")
    parser.add_argument("--once", action="store_true", help="run one update cycle and exit")
    args = parser.parse_args()

    stop_event = threading.Event()
    def request_stop(signum: int, _frame: Any) -> None:
        logger.info("Shutdown requested (signal %s)", signum)
        stop_event.set()

    for sig_name in ("SIGINT", "SIGTERM", "SIGBREAK"):
        sig = getattr(signal, sig_name, None)
        if sig is not None:
            try:
                signal.signal(sig, request_stop)
            except (ValueError, OSError):
                pass

    if args.once:
        return run_cycle(stop_event)

    interval_hours = env_float("UPDATE_INTERVAL_HOURS", 6.0, minimum=0.1)
    run_on_startup = env_bool("RUN_ON_STARTUP", True)
    logger.info("Worker started; interval=%s hours; run_on_startup=%s", interval_hours, run_on_startup)

    if run_on_startup and not stop_event.is_set():
        run_cycle(stop_event)

    while not stop_event.is_set():
        # Event.wait supports prompt shutdown without busy-waiting.
        if stop_event.wait(interval_hours * 3600):
            break
        run_cycle(stop_event)

    logger.info("Worker stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
