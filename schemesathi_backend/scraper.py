import csv
import io
import json
import os
import random
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Tuple

import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env'))

CENTRAL = 'Central'  # pseudo-"state" used to scrape/store Central (all-India) schemes
DETAIL_KEYS = ('eligibility', 'documents_required', 'application_process',
               'apply_link', 'apply_links', 'application_mode')


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


class RateLimiter:
    """Global, thread-safe pacing. A 429 from any thread slows down ALL threads."""

    def __init__(self, rps: float):
        self.base = 1.0 / max(rps, 0.1)
        self.interval = self.base
        self.max_interval = self.base * 8
        self.next_at = 0.0
        self.lock = threading.Lock()

    def wait(self) -> None:
        with self.lock:
            now = time.monotonic()
            slot = max(now, self.next_at)
            self.next_at = slot + self.interval
        delay = slot - now
        if delay > 0:
            time.sleep(delay)

    def penalize(self, seconds: float) -> None:
        with self.lock:
            self.next_at = max(self.next_at, time.monotonic() + seconds)
            self.interval = min(self.interval * 1.5, self.max_interval)

    def relax(self) -> None:
        with self.lock:
            self.interval = max(self.base, self.interval * 0.97)


class MySchemeScraper:
    BASE_URL = os.environ['BASE_URL']
    API_URL = os.environ['API_URL']
    DETAIL_API_URL = os.environ['DETAIL_API_URL']
    DOCUMENTS_API_URL = os.environ['DOCUMENTS_API_URL']
    DATASET_JSON = os.environ['DATASET_JSON']
    DATASET_CSV = os.environ['DATASET_CSV']
    _HERE = os.path.dirname(os.path.abspath(__file__))
    CACHE_FILE = os.path.join(_HERE, '.myscheme_dataset_cache.json')
    DETAIL_CACHE_FILE = os.path.join(_HERE, '.myscheme_detail_cache.json')
    PAGE_SIZE = _env_int('MYSCHEME_PAGE_SIZE', 50)
    MAX_PAGES = 200

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Origin': self.BASE_URL,
            'Referer': self.BASE_URL + '/',
        })
        self.max_workers = max(1, _env_int('MYSCHEME_WORKERS', 4))
        adapter = HTTPAdapter_(self.max_workers)
        self.session.mount('https://', adapter)
        self.session.mount('http://', adapter)

        self.limiter = RateLimiter(_env_float('MYSCHEME_RPS', 3.0))
        self.max_retries = _env_int('SCRAPE_HTTP_RETRIES', 5)
        self.detail_ttl = _env_float('MYSCHEME_DETAIL_TTL_HOURS', 168.0) * 3600
        # 'dataset' (default): use the bulk dataset for details when it has them (0 requests per scheme),
        # hit the live API only for gaps. 'live': always hit the live API (slow, freshest).
        self.detail_mode = os.environ.get('MYSCHEME_DETAIL_MODE', 'dataset').strip().lower()

        self.states = {n: n for n in self._state_names()}
        self.states[CENTRAL] = CENTRAL
        self._api_key: Optional[str] = os.environ.get('MYSCHEME_API_KEY')
        self._key_lock = threading.Lock()
        self._api_failures = 0
        self._listing_partial = False
        self._dataset_index: Optional[Dict[str, Dict]] = None
        self._dataset_rows: Optional[List[Dict]] = None
        self._dataset_lock = threading.Lock()
        self._cache_lock = threading.Lock()
        self._detail_cache: Dict[str, Dict] = self._load_detail_cache()
        self.last_429_at = None  # set to time.time() whenever a 429 is received

    # ------------------------------------------------------------------ states
    @staticmethod
    def _state_names() -> List[str]:
        return ['Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat',
                'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh',
                'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan',
                'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
                'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
                'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry']

    def get_available_states(self) -> List[str]:
        return list(self.states.keys())

    def _resolve_state(self, state: str) -> Optional[str]:
        state = state.strip()
        key = state.lower()
        if key in ('central', 'all india', 'national', 'centre', 'union'):
            return CENTRAL
        aliases = {'mp': 'Madhya Pradesh', 'm.p.': 'Madhya Pradesh', 'up': 'Uttar Pradesh', 'u.p.': 'Uttar Pradesh',
                   'mh': 'Maharashtra', 'rj': 'Rajasthan', 'gj': 'Gujarat', 'dl': 'Delhi', 'hr': 'Haryana',
                   'pb': 'Punjab', 'ka': 'Karnataka', 'tn': 'Tamil Nadu', 'ap': 'Andhra Pradesh',
                   'ts': 'Telangana', 'uk': 'Uttarakhand', 'wb': 'West Bengal', 'br': 'Bihar',
                   'cg': 'Chhattisgarh', 'jh': 'Jharkhand', 'od': 'Odisha', 'ga': 'Goa', 'kl': 'Kerala'}
        if key in aliases:
            return aliases[key]
        if state in self.states:
            return state
        for available in self.states:
            if key in available.lower() or available.lower() in key:
                return available
        return None

    # -------------------------------------------------------------- HTTP layer
    def _retry_after(self, response, attempt: int) -> float:
        try:
            return min(float(response.headers.get('Retry-After', '')), 120.0)
        except (ValueError, TypeError):
            return min(5.0 * (2 ** attempt), 120.0) + random.random() * 2

    def _get(self, url: str, params=None, headers=None, timeout: int = 30, retries: Optional[int] = None):
        """Paced GET with retry/backoff. Returns a Response (possibly non-200) or None."""
        retries = self.max_retries if retries is None else retries
        response = None
        for attempt in range(retries + 1):
            self.limiter.wait()
            try:
                response = self.session.get(url, params=params, headers=headers, timeout=timeout)
            except requests.RequestException:
                response = None
                if attempt < retries:
                    time.sleep(min(2 ** attempt, 30) + random.random())
                continue
            if response.status_code in (429, 503):
                self.last_429_at = time.time()
                self.limiter.penalize(self._retry_after(response, attempt))
                continue
            if response.status_code >= 500:
                time.sleep(min(2 ** attempt, 30) + random.random())
                continue
            self.limiter.relax()
            return response
        return response

    def _discover_api_key(self) -> Optional[str]:
        if self._api_key:
            return self._api_key
        with self._key_lock:
            if self._api_key:
                return self._api_key
            home = self._get(self.BASE_URL + '/', timeout=20)
            if home is None or home.status_code != 200:
                print('Could not load MyScheme homepage')
                return None
            soup = BeautifulSoup(home.text, 'html.parser')
            scripts = [s['src'] for s in soup.find_all('script', src=True) if '_next/static' in s['src']]
            key_re = re.compile(r'''x-api-key["']?\s*[:=,]\s*["']([A-Za-z0-9]{20,})["']''')
            for src in dict.fromkeys(scripts):
                url = src if src.startswith('http') else self.BASE_URL + src
                js = self._get(url, timeout=20, retries=1)
                if js is None or js.status_code != 200:
                    continue
                match = key_re.search(js.text)
                if match:
                    self._api_key = match.group(1)
                    return self._api_key
        return None

    # ----------------------------------------------------------------- listing
    @staticmethod
    def _find_hits(payload: Dict) -> Tuple[List[Dict], Optional[int]]:
        node = payload.get('data', payload)
        if not isinstance(node, dict):
            return ([], None)
        hits_node = node.get('hits', {})
        if not isinstance(hits_node, dict):
            return ([], None)
        items = hits_node.get('items', [])
        if not isinstance(items, list):
            items = []
        total = None
        summary = node.get('summary', {})
        if isinstance(summary, dict):
            total = summary.get('total')
        if total is None:
            page = hits_node.get('page', {})
            if isinstance(page, dict):
                total = page.get('total')
        return (items, total)

    def _normalise_api_item(self, item: Dict) -> Dict:
        fields = item.get('fields', item)
        slug = fields.get('slug', '')
        categories = fields.get('schemeCategory') or []
        beneficiary_state = fields.get('beneficiaryState')
        if isinstance(beneficiary_state, list):
            state = ', '.join(str(x) for x in beneficiary_state)
        else:
            state = beneficiary_state or ''
        return {
            'slug': slug,
            'title': fields.get('schemeName') or fields.get('schemeShortTitle', ''),
            'description': fields.get('briefDescription', ''),
            'ministry': fields.get('nodalMinistryName', ''),
            'level': fields.get('level', ''),
            'categories': categories if isinstance(categories, list) else [categories],
            'tags': fields.get('tags', []),
            'state': state,
            'url': f'{self.BASE_URL}/schemes/{slug}' if slug else '',
        }

    def _fetch_listing(self, filters: List[Dict]) -> Optional[List[Dict]]:
        """Fetch the scheme listing. Page 0 tells us the total, the rest are fetched concurrently."""
        key = self._discover_api_key()
        if not key:
            print('Could not find API key.')
            return None
        headers = {'x-api-key': key}
        query = json.dumps(filters)

        def page(n: int):
            r = self._get(self.API_URL, headers=headers, params={
                'lang': 'en', 'q': query, 'keyword': '', 'sort': '',
                'from': n * self.PAGE_SIZE, 'size': self.PAGE_SIZE})
            if r is None or r.status_code != 200:
                return None
            try:
                return self._find_hits(r.json())
            except ValueError:
                return None

        first = page(0)
        if first is None:
            return None
        items, total = first
        pages: Dict[int, Optional[List[Dict]]] = {0: items}
        if items:
            if total:
                n_pages = min(-(-total // self.PAGE_SIZE), self.MAX_PAGES)
                numbers = list(range(1, n_pages))
                with ThreadPoolExecutor(max_workers=self.max_workers) as pool:
                    for n, res in zip(numbers, pool.map(page, numbers)):
                        pages[n] = res[0] if res else None
                for n in [n for n, v in pages.items() if v is None]:  # one sequential retry pass
                    res = page(n)
                    pages[n] = res[0] if res else None
            else:
                n = 1
                while n < self.MAX_PAGES:
                    res = page(n)
                    if not res or not res[0]:
                        break
                    pages[n] = res[0]
                    n += 1
        self._listing_partial = any(v is None for v in pages.values())
        seen, schemes = set(), []
        for n in sorted(pages):
            for item in pages[n] or []:
                scheme = self._normalise_api_item(item)
                ident = scheme['slug'] or scheme['title']
                if ident and ident not in seen:
                    seen.add(ident)
                    schemes.append(scheme)
        print(f'  listing: {len(schemes)} schemes' + (f' (API total {total})' if total else '')
              + (' [PARTIAL]' if self._listing_partial else ''))
        return schemes or None

    def _fetch_central_api(self) -> Optional[List[Dict]]:
        print('Fetching Central schemes...')
        schemes = self._fetch_listing([{'identifier': 'level', 'value': 'Central'}])
        if schemes:
            return schemes
        # Filter unsupported/empty: pull everything and keep level == Central.
        print('  level filter returned nothing; scanning full listing for Central schemes...')
        everything = self._fetch_listing([])
        if not everything:
            return None
        central = [s for s in everything if 'central' in str(s.get('level', '')).lower()]
        return central or None

    # ----------------------------------------------------------------- dataset
    def _load_dataset(self) -> List[Dict]:
        with self._dataset_lock:
            if self._dataset_rows is not None:
                return self._dataset_rows
            rows: List[Dict] = []
            if os.path.exists(self.CACHE_FILE):
                try:
                    with open(self.CACHE_FILE, encoding='utf-8') as f:
                        rows = json.load(f)
                except (OSError, ValueError):
                    rows = []
            if not rows:
                print('Downloading fallback dataset...')
                r = self._get(self.DATASET_JSON, timeout=60, retries=2)
                try:
                    if r is not None and r.status_code == 200:
                        data = r.json()
                        if isinstance(data, dict):
                            for value in data.values():
                                if isinstance(value, list):
                                    data = value
                                    break
                        rows = [i for i in data if isinstance(i, dict)]
                except ValueError:
                    rows = []
                if not rows:
                    r = self._get(self.DATASET_CSV, timeout=60, retries=2)
                    if r is not None and r.status_code == 200:
                        rows = list(csv.DictReader(io.StringIO(r.content.decode('utf-8-sig'))))
                if rows:
                    try:
                        with open(self.CACHE_FILE, 'w', encoding='utf-8') as f:
                            json.dump(rows, f, ensure_ascii=False)
                    except OSError:
                        pass
            self._dataset_rows = rows
            self._dataset_index = {r.get('Scheme Slug', ''): r for r in rows}
            return rows

    def _dataset_row(self, slug: str) -> Optional[Dict]:
        self._load_dataset()
        return (self._dataset_index or {}).get(slug)

    @staticmethod
    def _normalise_text(text: str) -> str:
        text = str(text).lower().replace('&', ' and ')
        return re.sub('[^a-z0-9]+', ' ', text).strip()

    @staticmethod
    def _row_to_scheme(row: Dict) -> Dict:
        region = row.get('State / UT / Ministry', '')
        app_proc = row.get('Application Process') or ''
        found_links = re.findall(r'https?://[^\s<>"\'\)]+', app_proc)
        apply_link = found_links[0] if found_links else (row.get('Official Link') or '')
        return {
            'slug': row.get('Scheme Slug', ''),
            'title': row.get('Scheme Name', ''),
            'description': row.get('Description', ''),
            'ministry': region,
            'benefits': row.get('Benefits', ''),
            'eligibility': row.get('Eligibility Criteria') or row.get('Eligibility (General)', ''),
            'exclusions': row.get('Exclusions / Ineligibility', ''),
            'documents_required': row.get('Documents Required', ''),
            'application_mode': row.get('Application Mode', ''),
            'application_process': app_proc,
            'apply_link': apply_link,
            'apply_links': found_links,
            'level': row.get('Level', ''),
            'tags': row.get('Tags / Categories', ''),
            'official_link': row.get('Official Link', ''),
            'url': row.get('MyScheme URL', ''),
        }

    def _fetch_from_github_dataset(self, state: str) -> List[Dict]:
        print('Using public dataset fallback...')
        wanted = self._normalise_text(state)
        schemes = []
        for row in self._load_dataset():
            is_central = 'central' in str(row.get('Level', '')).lower()
            if state == CENTRAL:
                if not is_central:
                    continue
            else:
                if is_central:
                    continue
                region = self._normalise_text(row.get('State / UT / Ministry', ''))
                if not (region == wanted or wanted in region):
                    continue
            schemes.append(self._row_to_scheme(row))
        print(f'Found {len(schemes)} schemes in fallback dataset')
        return schemes

    # ------------------------------------------------- payload parsing helpers
    @staticmethod
    def _collect_eligibility(node, found: List[str], depth: int = 0) -> None:
        if depth > 8:
            return
        if isinstance(node, dict):
            for key, value in node.items():
                key_lower = str(key).lower()
                if key_lower in ('faq', 'faqs'):
                    continue
                if 'eligib' in key_lower:
                    MySchemeScraper._flatten_text(value, found)
                else:
                    MySchemeScraper._collect_eligibility(value, found, depth + 1)
        elif isinstance(node, list):
            for value in node:
                MySchemeScraper._collect_eligibility(value, found, depth + 1)

    @staticmethod
    def _flatten_text(value, output: List[str]) -> None:
        if isinstance(value, str):
            text = value.strip()
            if text:
                output.append(text)
        elif isinstance(value, list):
            for item in value:
                MySchemeScraper._flatten_text(item, output)
        elif isinstance(value, dict):
            preferred = [k for k in value if k.endswith('_md') or k in ('text', 'description')]
            for key in (preferred if preferred else list(value.keys())):
                MySchemeScraper._flatten_text(value[key], output)

    @staticmethod
    def _dedupe_join(parts: List[str]) -> str:
        seen, unique = set(), []
        for part in parts:
            if part not in seen:
                seen.add(part)
                unique.append(part)
        return '\n\n'.join(unique).strip()

    @staticmethod
    def _flatten_rich_text(value, output: List[str]) -> None:
        if isinstance(value, str):
            text = value.strip()
            if text:
                output.append(text)
        elif isinstance(value, list):
            for item in value:
                MySchemeScraper._flatten_rich_text(item, output)
        elif isinstance(value, dict):
            children = value.get('children')
            if isinstance(children, list):
                inline = all(isinstance(c, str) or (isinstance(c, dict) and 'children' not in c) for c in children)
                if inline:
                    line = ''.join(c if isinstance(c, str) else str(c.get('text', '')) for c in children).strip()
                    if line:
                        output.append(line)
                else:
                    for child in children:
                        MySchemeScraper._flatten_rich_text(child, output)
            elif isinstance(value.get('text'), str):
                text = value['text'].strip()
                if text:
                    output.append(text)
            else:
                for key, item in value.items():
                    if key != 'type':
                        MySchemeScraper._flatten_rich_text(item, output)

    @staticmethod
    def _collect_documents(node, found: List[str], depth: int = 0) -> None:
        if depth > 8:
            return
        if isinstance(node, dict):
            skip = ('faq', 'faqs')
            doc_keys = [k for k in node if ('document' in str(k).lower() or str(k).lower().endswith('docs'))
                        and str(k).lower() not in skip]
            md_keys = [k for k in doc_keys if str(k).lower().endswith('_md')]
            for key in (md_keys or doc_keys):
                MySchemeScraper._flatten_rich_text(node[key], found)
            for key, value in node.items():
                if key in doc_keys or str(key).lower() in skip:
                    continue
                MySchemeScraper._collect_documents(value, found, depth + 1)
        elif isinstance(node, list):
            for value in node:
                MySchemeScraper._collect_documents(value, found, depth + 1)

    @staticmethod
    def _extract_application_process_from_payload(payload: Dict) -> Tuple[str, str, List[str], str]:
        process_blocks: List[str] = []
        apply_links: List[str] = []
        modes: List[str] = []
        if not isinstance(payload, dict):
            return '', '', [], ''
        data_node = payload.get('data') if isinstance(payload.get('data'), dict) else payload
        en_node = data_node.get('en') if isinstance(data_node.get('en'), dict) else data_node
        app_proc = en_node.get('applicationProcess') or data_node.get('applicationProcess')
        if isinstance(app_proc, list):
            for entry in app_proc:
                if not isinstance(entry, dict):
                    continue
                mode = str(entry.get('mode') or '').strip()
                if mode and mode not in modes:
                    modes.append(mode)
                url = str(entry.get('url') or '').strip()
                if url.startswith('http') and url not in apply_links:
                    apply_links.append(url)
                md = entry.get('process_md')
                if md and isinstance(md, str) and md.strip():
                    clean = (md.replace('&quot;', '"').replace('&amp;', '&')
                             .replace('&lt;', '<').replace('&gt;', '>').strip())
                    header = f'### Mode: {mode}' if mode else '### Application Process'
                    process_blocks.append(f'{header}\n{clean}')
                    for m in re.finditer(r'\[([^\]]+)\]\((https?://[^\s\)]+)\)', clean):
                        link = m.group(2).strip()
                        if link not in apply_links:
                            apply_links.append(link)
                elif entry.get('process'):
                    steps: List[str] = []
                    MySchemeScraper._flatten_rich_text(entry.get('process'), steps)
                    if steps:
                        header = f'### Mode: {mode}' if mode else '### Application Process'
                        process_blocks.append(f'{header}\n' + '\n'.join(steps))
        return ('\n\n'.join(process_blocks).strip(), apply_links[0] if apply_links else '',
                apply_links, ', '.join(modes))

    @staticmethod
    def _slug_of(scheme: Dict) -> str:
        return scheme.get('slug') or scheme.get('url', '').rstrip('/').split('/')[-1]

    # ------------------------------------------------------- detail cache (disk)
    def _load_detail_cache(self) -> Dict[str, Dict]:
        try:
            with open(self.DETAIL_CACHE_FILE, encoding='utf-8') as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _save_detail_cache(self) -> None:
        with self._cache_lock:
            try:
                tmp = self.DETAIL_CACHE_FILE + '.tmp'
                with open(tmp, 'w', encoding='utf-8') as f:
                    json.dump(self._detail_cache, f, ensure_ascii=False)
                os.replace(tmp, self.DETAIL_CACHE_FILE)
            except OSError:
                pass

    def _cache_get(self, slug: str) -> Optional[Dict]:
        entry = self._detail_cache.get(slug)
        if entry and (time.time() - entry.get('_ts', 0)) < self.detail_ttl:
            return entry
        return None

    # --------------------------------------------------------- detail fetching
    def _detail_api(self, slug: str) -> Optional[Dict]:
        key = self._discover_api_key()
        if not key or self._api_failures >= 8:
            return None
        r = self._get(self.DETAIL_API_URL, params={'slug': slug, 'lang': 'en'}, headers={'x-api-key': key})
        if r is not None and r.status_code == 200:
            try:
                self._api_failures = 0
                return r.json()
            except ValueError:
                pass
        if r is None or r.status_code not in (429, 503):
            self._api_failures += 1
        return None

    def _detail_page(self, slug: str) -> Optional[Dict]:
        r = self._get(f'{self.BASE_URL}/schemes/{slug}', retries=2)
        if r is None or r.status_code != 200:
            return None
        match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', r.text, re.S)
        if not match:
            return None
        try:
            return json.loads(match.group(1))
        except ValueError:
            return None

    def _docs_endpoint(self, payload: Dict) -> str:
        try:
            scheme_id = payload['data']['_id']
        except (KeyError, TypeError):
            return ''
        r = self._get(self.DOCUMENTS_API_URL.format(id=scheme_id), params={'lang': 'en'},
                      headers={'x-api-key': self._api_key or ''}, retries=3)
        if r is None or r.status_code != 200:
            return ''
        try:
            found: List[str] = []
            self._collect_documents(r.json(), found)
            return self._dedupe_join(found)
        except ValueError:
            return ''

    def _from_dataset_complete(self, slug: str) -> Optional[Dict]:
        row = self._dataset_row(slug)
        if not row:
            return None
        elig = (row.get('Eligibility Criteria') or row.get('Eligibility (General)') or '').strip()
        docs = (row.get('Documents Required') or '').strip()
        proc = str(row.get('Application Process') or '').strip()
        official = str(row.get('Official Link') or '').strip()
        if not (elig and docs and (proc or official)):
            return None
        links = re.findall(r'https?://[^\s<>"\'\)]+', proc)
        return {'eligibility': elig, 'documents_required': docs, 'application_process': proc,
                'apply_link': links[0] if links else official, 'apply_links': links,
                'application_mode': str(row.get('Application Mode') or '').strip(), '_live': True}

    def _collect_details(self, slug: str) -> Dict:
        if self.detail_mode != 'live':
            fast = self._from_dataset_complete(slug)
            if fast:
                return fast
        live = False
        payloads: List[Dict] = []
        api = self._detail_api(slug)
        if api:
            payloads.append(api)

        def elig_of(p: Dict) -> str:
            found: List[str] = []
            self._collect_eligibility(p, found)
            return self._dedupe_join(found)

        eligibility = elig_of(api) if api else ''
        page = None
        if not eligibility:
            page = self._detail_page(slug)
            if page:
                payloads.append(page)
                eligibility = elig_of(page)
        if eligibility:
            live = True

        documents = ''
        for p in payloads:
            found: List[str] = []
            self._collect_documents(p, found)
            documents = self._dedupe_join(found)
            if documents:
                break
        if not documents and api:
            documents = self._docs_endpoint(api)
        if documents:
            live = True

        proc = link = mode = ''
        links: List[str] = []
        for p in payloads:
            proc, link, links, mode = self._extract_application_process_from_payload(p)
            if proc or link:
                break

        if not (eligibility and documents and (proc or link)):  # fill gaps from the dataset
            row = self._dataset_row(slug)
            if row:
                eligibility = eligibility or (row.get('Eligibility Criteria') or row.get('Eligibility (General)') or '').strip()
                documents = documents or (row.get('Documents Required') or '').strip()
                if not (proc or link):
                    proc = str(row.get('Application Process') or '').strip()
                    links = re.findall(r'https?://[^\s<>"\'\)]+', proc)
                    link = links[0] if links else str(row.get('Official Link') or '').strip()
                    mode = str(row.get('Application Mode') or '').strip()

        return {'eligibility': eligibility, 'documents_required': documents, 'application_process': proc,
                'apply_link': link, 'apply_links': links, 'application_mode': mode, '_live': live}

    def _fill_one(self, scheme: Dict) -> None:
        slug = self._slug_of(scheme)
        if not slug:
            return
        d = self._cache_get(slug)
        if d is None:
            d = self._collect_details(slug)
            if d.pop('_live', False):
                d['_ts'] = time.time()
                with self._cache_lock:
                    self._detail_cache[slug] = d
        for k in DETAIL_KEYS:
            v = d.get(k)
            if v and not scheme.get(k):
                scheme[k] = v

    def add_eligibility(self, schemes: List[Dict]) -> None:
        """Fill eligibility, documents, and application process (parallel, rate-limited, cached)."""
        todo = [s for s in schemes if self._slug_of(s) and not (
            s.get('eligibility') and s.get('documents_required') and s.get('application_process'))]
        total = len(todo)
        print(f'\nFetching details for {total} of {len(schemes)} schemes '
              f'({self.max_workers} workers, ~{1 / self.limiter.base:.1f} req/s)...')
        self._api_failures = 0
        done = 0
        try:
            with ThreadPoolExecutor(max_workers=self.max_workers) as pool:
                for _ in pool.map(self._safe_fill, todo):
                    done += 1
                    if done % 25 == 0 or done == total:
                        print(f'  {done}/{total} done')
                        self._save_detail_cache()
        finally:
            self._save_detail_cache()
        for s in schemes:
            s.setdefault('eligibility', '')
            s.setdefault('documents_required', '')
            if not s.get('application_process'):
                s['application_process'] = ''
            if not s.get('apply_link'):
                s['apply_link'] = s.get('official_link') or ''

    def _safe_fill(self, scheme: Dict) -> None:
        try:
            self._fill_one(scheme)
        except Exception as e:  # one bad scheme must not kill the state
            print(f'  detail fetch failed for {self._slug_of(scheme)}: {e}')

    # ------------------------------------------------------------- entry point
    LISTING_KEYS = ('slug', 'title', 'description', 'ministry', 'level', 'categories', 'tags', 'url')

    def _reuse_known(self, schemes: List[Dict], known: Dict[str, Dict]) -> set:
        """Copy stored details onto schemes whose listing is unchanged and recently verified."""
        refresh = _env_float('MYSCHEME_REFRESH_DAYS', 7.0) * 86400
        reused = set()
        for scheme in schemes:
            slug = self._slug_of(scheme)
            kd = known.get(slug)
            if not kd or not kd.get('eligibility'):
                continue  # new scheme, or details were never fetched properly
            if any(kd.get(k) != scheme.get(k) for k in self.LISTING_KEYS):
                continue  # listing changed -> re-fetch
            try:
                age = time.time() - time.mktime(time.strptime(kd.get('scraped_at', ''), '%Y-%m-%d %H:%M:%S'))
            except ValueError:
                continue
            if age > refresh:
                continue  # periodic safety re-check
            for k, v in kd.items():
                if k not in self.LISTING_KEYS and k not in ('state', 'source', 'scraped_at'):
                    scheme[k] = v
            reused.add(slug)
        return reused

    def scrape_schemes(self, state: str, include_eligibility: bool = True,
                       known: Optional[Dict[str, Dict]] = None) -> List[Dict]:
        resolved = self._resolve_state(state)
        if not resolved:
            print(f"State '{state}' not found.")
            print('Available states:')
            print(', '.join(self.get_available_states()))
            return []
        state = resolved
        print(f'\nScraping schemes for: {state}')
        self._listing_partial = False
        t_list = time.monotonic()

        if state == CENTRAL:
            schemes = self._fetch_central_api()
        else:
            schemes = self._fetch_listing([{'identifier': 'beneficiaryState', 'value': state}])
        source = 'MyScheme API'

        if not schemes:
            print('\nLive API unavailable or returned zero; trying GitHub dataset fallback...')
            schemes = self._fetch_from_github_dataset(state)
            source = 'GitHub dataset'
        elif self._listing_partial:
            have = {self._slug_of(s) for s in schemes}
            extra = [s for s in self._fetch_from_github_dataset(state) if self._slug_of(s) not in have]
            print(f'  merged {len(extra)} schemes missing from the partial API listing')
            schemes = schemes + extra

        print(f'  [timing] listing for {state}: {time.monotonic() - t_list:.1f}s')
        if not schemes:
            print(f'  Both API and fallback returned zero schemes for {state}; preserving existing data.')
            return []

        reused = self._reuse_known(schemes, known) if known else set()
        if known:
            print(f'  unchanged (details reused from DB): {len(reused)}; to fetch: {len(schemes) - len(reused)}')
        if include_eligibility:
            t0 = time.monotonic()
            self.add_eligibility([sc for sc in schemes if self._slug_of(sc) not in reused])
            print(f'  [timing] details for {state}: {time.monotonic() - t0:.1f}s')

        scraped_at = time.strftime('%Y-%m-%d %H:%M:%S')
        for scheme in schemes:
            if state == CENTRAL or not scheme.get('state'):
                scheme['state'] = state
            kd = known.get(self._slug_of(scheme)) if known and self._slug_of(scheme) in reused else None
            scheme['source'] = kd.get('source', source) if kd else source
            scheme['scraped_at'] = kd.get('scraped_at', scraped_at) if kd else scraped_at
        print(f'\nSuccessfully found {len(schemes)} schemes for {state}')
        print(f'Primary source used: {source}')
        return schemes


def HTTPAdapter_(workers: int):
    from requests.adapters import HTTPAdapter
    size = max(workers * 2, 10)
    return HTTPAdapter(pool_connections=size, pool_maxsize=size)