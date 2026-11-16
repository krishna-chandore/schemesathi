"""Redis helpers. NOTE: this file must NOT be called redis.py - that shadows the `redis` package."""
import json
import logging
import os
import zlib
import time
from typing import Any, Dict, Iterable, Optional

import redis
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger("schemesathi.redis")

REDIS_URL = os.getenv("REDIS_URL")
if not REDIS_URL:
    raise RuntimeError("REDIS_URL not found in .env file")

# Skip a single value bigger than this (managed Redis often caps request size). Per-state keys stay intact.
MAX_VALUE_BYTES = int(os.getenv("REDIS_MAX_VALUE_BYTES", str(64 * 1024 * 1024)))


def build_client(url: Optional[str] = None) -> "redis.Redis":
    return redis.from_url(
        url or REDIS_URL,
        decode_responses=False,  # values may be compressed bytes
        socket_timeout=30,
        socket_connect_timeout=10,
        retry_on_timeout=True,
        health_check_interval=30,
    )


redis_client = build_client()


def safe_set(client, key: str, value, ttl: Optional[int] = None, attempts: int = 4) -> bool:
    """SET with retries + backoff. One key per call (no giant pipelines). Never raises."""
    size = len(value) if isinstance(value, (bytes, bytearray)) else len(value.encode("utf-8"))
    if size > MAX_VALUE_BYTES:
        logger.error("Skipping %s: %.1f MB exceeds REDIS_MAX_VALUE_BYTES", key, size / 1e6)
        return False
    for attempt in range(1, attempts + 1):
        try:
            client.set(key, value, ex=ttl if ttl and ttl > 0 else None)
            return True
        except (redis.exceptions.ConnectionError, redis.exceptions.TimeoutError) as exc:
            logger.warning("Redis SET %s failed (%d/%d): %s", key, attempt, attempts, exc)
            time.sleep(min(2 ** attempt, 15))
        except redis.exceptions.RedisError as exc:
            logger.error("Redis SET %s failed permanently: %s", key, exc)
            return False
    return False


def dump_docs(docs: Iterable[Dict[str, Any]]) -> str:
    """Same JSON shape as json.dumps(list), built piecewise to avoid a 2x memory spike."""
    return "[" + ",".join(json.dumps(d, ensure_ascii=False, default=str) for d in docs) + "]"


def _compress_enabled() -> bool:
    return os.getenv("REDIS_COMPRESS", "true").strip().lower() in ("1", "true", "yes", "y", "on")


def decode_value(raw):
    """Read a cached value: handles zlib-compressed bytes and plain JSON."""
    if raw is None:
        return None
    if isinstance(raw, (bytes, bytearray)):
        raw = zlib.decompress(raw) if raw[:1] == b"\x78" else bytes(raw)
        raw = raw.decode("utf-8")
    return json.loads(raw)


# Backwards-compatible helpers from the old redis.py
def get_schemes(state):
    return decode_value(redis_client.get(f"schemes:{state}"))


def save_schemes(state, schemes, ttl=86400):
    payload = json.dumps(schemes, ensure_ascii=False)
    value = zlib.compress(payload.encode("utf-8"), 6) if _compress_enabled() else payload
    return safe_set(redis_client, f"schemes:{state}", value, ttl)