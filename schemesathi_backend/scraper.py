import csv
import io
import json
import os
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Tuple
import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env'))

class MySchemeScraper:
    BASE_URL = os.environ['BASE_URL']
    API_URL = os.environ['API_URL']
    DETAIL_API_URL = os.environ['DETAIL_API_URL']
    DOCUMENTS_API_URL = os.environ['DOCUMENTS_API_URL']
    DATASET_JSON = os.environ['DATASET_JSON']
    DATASET_CSV = os.environ['DATASET_CSV']
    CACHE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.myscheme_dataset_cache.json')
    PAGE_SIZE = 50
    MAX_PAGES = 100

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36', 'Accept': 'application/json, text/plain, */*', 'Accept-Language': 'en-US,en;q=0.9', 'Origin': self.BASE_URL, 'Referer': self.BASE_URL + '/'})
        self.states = self._load_states()
        self._api_key: Optional[str] = os.environ.get('MYSCHEME_API_KEY')
        self._detail_errors = 0
        self._dataset_index: Optional[Dict[str, Dict]] = None
        self._pw = None
        self._browser = None
        self._page = None
        self._browser_fail_streak = 0
        # NEW: per-scheme stash of detail-API / __NEXT_DATA__ JSON, shared by eligibility + documents
        self._payloads: Dict[Tuple[str, str], Dict] = {}
        # NEW: parallel prefetch cache + worker count (set MYSCHEME_WORKERS=1 to disable prefetch)
        self._prefetched: Dict[Tuple[str, str], Dict] = {}
        self._doc_debug_done = False
        self._docs_api = {'ok': 0, 'fail': 0}
        self._docs_lock = threading.Lock()
        try:
            self.max_workers = max(1, int(os.environ.get('MYSCHEME_WORKERS', '2')))
        except ValueError:
            self.max_workers = 2
        try:
            self.prefetch_delay = float(os.environ.get('MYSCHEME_PREFETCH_DELAY', '0.5'))
        except ValueError:
            self.prefetch_delay = 0.5
        self.last_429_at = None  # set to time.time() whenever a 429 is received

    def _load_states(self) -> Dict[str, str]:
        names = ['Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry']
        return {name: name for name in names}

    def get_available_states(self) -> List[str]:
        return list(self.states.keys())

    def _resolve_state(self, state: str) -> Optional[str]:
        state = state.strip()
        aliases = {'mp': 'Madhya Pradesh', 'm.p.': 'Madhya Pradesh', 'up': 'Uttar Pradesh', 'u.p.': 'Uttar Pradesh', 'mh': 'Maharashtra', 'rj': 'Rajasthan', 'gj': 'Gujarat', 'dl': 'Delhi', 'hr': 'Haryana', 'pb': 'Punjab', 'ka': 'Karnataka', 'tn': 'Tamil Nadu', 'ap': 'Andhra Pradesh', 'ts': 'Telangana', 'uk': 'Uttarakhand', 'wb': 'West Bengal', 'br': 'Bihar', 'cg': 'Chhattisgarh', 'jh': 'Jharkhand', 'od': 'Odisha', 'ga': 'Goa', 'kl': 'Kerala'}
        key = state.lower()
        if key in aliases:
            return aliases[key]
        if state in self.states:
            return state
        for available_state in self.states:
            if key in available_state.lower() or available_state.lower() in key:
                return available_state
        return None

    def _discover_api_key(self) -> Optional[str]:
        if self._api_key:
            return self._api_key
        try:
            home = self.session.get(self.BASE_URL + '/', timeout=20)
            home.raise_for_status()
            soup = BeautifulSoup(home.text, 'html.parser')
            scripts = [s['src'] for s in soup.find_all('script', src=True) if '_next/static' in s['src']]
            seen = set()
            key_re = re.compile(r'''x-api-key["']?\s*[:=,]\s*["']([A-Za-z0-9]{20,})["']''')
            for src in scripts:
                if src in seen:
                    continue
                seen.add(src)
                url = src if src.startswith('http') else self.BASE_URL + src
                try:
                    js = self.session.get(url, timeout=20).text
                except requests.RequestException:
                    continue
                match = key_re.search(js)
                if match:
                    self._api_key = match.group(1)
                    return self._api_key
        except requests.RequestException as e:
            print(f'Could not load MyScheme homepage: {e}')
        return None

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
            state = ', '.join((str(x) for x in beneficiary_state))
        else:
            state = beneficiary_state or ''
        return {'slug': slug, 'title': fields.get('schemeName') or fields.get('schemeShortTitle', ''), 'description': fields.get('briefDescription', ''), 'ministry': fields.get('nodalMinistryName', ''), 'level': fields.get('level', ''), 'categories': categories if isinstance(categories, list) else [categories], 'tags': fields.get('tags', []), 'state': state, 'url': f'{self.BASE_URL}/schemes/{slug}' if slug else ''}

    def _fetch_schemes_api(self, state: str) -> Optional[List[Dict]]:
        print('Trying live MyScheme API...')
        key = self._discover_api_key()
        if not key:
            print('Could not find API key.')
            return None
        headers = {'x-api-key': key}
        query = json.dumps([{'identifier': 'beneficiaryState', 'value': state}])
        schemes: List[Dict] = []
        total = None
        try:
            page = 0
            max_page_retries = max(1, int(os.environ.get('SCRAPE_RETRIES', '3')))
            while page < self.MAX_PAGES:
                params = {'lang': 'en', 'q': query, 'keyword': '', 'sort': '',
                          'from': page * self.PAGE_SIZE, 'size': self.PAGE_SIZE}
                page_attempt = 0
                while page_attempt <= max_page_retries:
                    response = self.session.get(self.API_URL, params=params,
                                                headers=headers, timeout=30)
                    if response.status_code == 429:
                        self.last_429_at = time.time()
                        retry_after = response.headers.get('Retry-After', '')
                        try:
                            wait = min(int(retry_after), 120)
                        except (ValueError, TypeError):
                            wait = 30
                        print(f'  [429] rate-limited on page {page}; waiting {wait}s '
                              f'(attempt {page_attempt+1}/{max_page_retries+1})...')
                        time.sleep(wait)
                        page_attempt += 1
                        continue
                    break  # non-429: proceed
                if response.status_code != 200:
                    print(f'API returned HTTP {response.status_code}')
                    return None
                items, page_total = self._find_hits(response.json())
                if page_total is not None:
                    total = page_total
                if not items:
                    break
                schemes.extend(self._normalise_api_item(item) for item in items)
                print(f'  fetched {len(schemes)}' + (f'/{total}' if total else ''))
                if total is not None and len(schemes) >= total:
                    break
                time.sleep(0.5)
                page += 1
        except (requests.RequestException, ValueError) as e:
            print(f'API fetch error: {e}')
            return None
        return schemes or None

    def _load_dataset(self) -> List[Dict]:
        if os.path.exists(self.CACHE_FILE):
            try:
                with open(self.CACHE_FILE, encoding='utf-8') as file:
                    return json.load(file)
            except (OSError, ValueError):
                pass
        rows: List[Dict] = []
        print('Downloading fallback dataset...')
        try:
            response = self.session.get(self.DATASET_JSON, timeout=60)
            response.raise_for_status()
            data = response.json()
            if isinstance(data, dict):
                for value in data.values():
                    if isinstance(value, list):
                        data = value
                        break
            rows = [item for item in data if isinstance(item, dict)]
        except (requests.RequestException, ValueError) as e:
            print(f'JSON dataset failed: {e}')
            try:
                response = self.session.get(self.DATASET_CSV, timeout=60)
                response.raise_for_status()
                text = response.content.decode('utf-8-sig')
                rows = list(csv.DictReader(io.StringIO(text)))
            except requests.RequestException as e2:
                print(f'CSV dataset failed too: {e2}')
        if rows:
            try:
                with open(self.CACHE_FILE, 'w', encoding='utf-8') as file:
                    json.dump(rows, file, ensure_ascii=False)
            except OSError:
                pass
        return rows

    def _fetch_from_github_dataset(self, state: str) -> List[Dict]:
        print('Using public dataset fallback...')
        wanted = self._normalise_text(state)
        schemes = []
        for row in self._load_dataset():
            region = row.get('State / UT / Ministry', '')
            level = str(row.get('Level', '')).lower()
            if 'central' in level:
                continue
            normalized_region = self._normalise_text(region)
            if normalized_region == wanted or wanted in normalized_region:
                app_proc = row.get('Application Process') or ''
                # Extract any apply URLs from application process text or use official link
                found_links = re.findall(r'https?://[^\s<>"\'\)]+', app_proc)
                apply_link = found_links[0] if found_links else (row.get('Official Link') or '')
                schemes.append({
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
                })
        print(f'Found {len(schemes)} schemes in fallback dataset')
        return schemes

    @staticmethod
    def _normalise_text(text: str) -> str:
        text = str(text).lower()
        text = text.replace('&', ' and ')
        return re.sub('[^a-z0-9]+', ' ', text).strip()

    @staticmethod
    def _collect_eligibility(node, found: List[str], depth: int=0) -> None:
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
            preferred = [key for key in value if key.endswith('_md') or key in ('text', 'description')]
            keys = preferred if preferred else list(value.keys())
            for key in keys:
                MySchemeScraper._flatten_text(value[key], output)

    @staticmethod
    def _dedupe_join(parts: List[str]) -> str:
        seen = set()
        unique = []
        for part in parts:
            if part not in seen:
                seen.add(part)
                unique.append(part)
        return '\n\n'.join(unique).strip()

    def _fetch_eligibility_api(self, slug: str) -> str:
        if not slug:
            return ''
        prefetched = self._prefetched.pop(('api', slug), None)
        if prefetched:
            self._payloads[('api', slug)] = prefetched
            found: List[str] = []
            self._collect_eligibility(prefetched, found)
            return self._dedupe_join(found)
        key = self._discover_api_key()
        if not key:
            return ''
        try:
            response = self.session.get(self.DETAIL_API_URL, params={'slug': slug, 'lang': 'en'}, headers={'x-api-key': key}, timeout=30)
            if response.status_code == 429:
                self.last_429_at = time.time()
                retry_after = response.headers.get('Retry-After', '')
                try:
                    wait = min(int(retry_after), 120)
                except (ValueError, TypeError):
                    wait = 30
                time.sleep(wait)
                # one retry
                response = self.session.get(
                    self.DETAIL_API_URL,
                    params={'slug': slug, 'lang': 'en'},
                    headers={'x-api-key': key},
                    timeout=30,
                )
            if response.status_code != 200:
                self._detail_errors += 1
                return ''
            payload = response.json()
            self._payloads[('api', slug)] = payload  # NEW: reused by documents extraction
            found: List[str] = []
            self._collect_eligibility(payload, found)
            return self._dedupe_join(found)
        except (requests.RequestException, ValueError):
            self._detail_errors += 1
            return ''

    def _fetch_eligibility_page(self, slug: str) -> str:
        if not slug:
            return ''
        prefetched = self._prefetched.pop(('page', slug), None)
        if prefetched:
            self._payloads[('page', slug)] = prefetched
            found: List[str] = []
            self._collect_eligibility(prefetched, found)
            return self._dedupe_join(found)
        try:
            response = self.session.get(f'{self.BASE_URL}/schemes/{slug}', timeout=30)
            response.raise_for_status()
            match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', response.text, re.S)
            if not match:
                return ''
            data = json.loads(match.group(1))
            self._payloads[('page', slug)] = data  # NEW: reused by documents extraction
            found: List[str] = []
            self._collect_eligibility(data, found)
            return self._dedupe_join(found)
        except (requests.RequestException, ValueError):
            return ''

    @staticmethod
    def _slug_of(scheme: Dict) -> str:
        return scheme.get('slug') or scheme.get('url', '').rstrip('/').split('/')[-1]

    def _prefetch_one(self, kind: str, slug: str, headers: Dict) -> Optional[Dict]:
        """Network-only worker (thread-safe: touches no shared scraper state)."""
        max_retries = 2
        for attempt in range(max_retries + 1):
            try:
                if kind == 'api':
                    response = self.session.get(
                        self.DETAIL_API_URL,
                        params={'slug': slug, 'lang': 'en'},
                        headers=headers,
                        timeout=30,
                    )
                else:
                    response = self.session.get(
                        f'{self.BASE_URL}/schemes/{slug}', timeout=30
                    )
                if response.status_code == 429:
                    self.last_429_at = time.time()
                    retry_after = response.headers.get('Retry-After', '')
                    try:
                        wait = min(int(retry_after), 120)
                    except (ValueError, TypeError):
                        wait = 15
                    if attempt < max_retries:
                        time.sleep(wait)
                        continue
                    # exhausted retries for this slug
                    return {'__rate_limited__': True}
                if kind == 'api':
                    return response.json() if response.status_code == 200 else None
                else:
                    response.raise_for_status()
                    match = re.search(
                        r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
                        response.text, re.S
                    )
                    return json.loads(match.group(1)) if match else None
            except (requests.RequestException, ValueError):
                return None
        return None

    def _prefetch_details(self, schemes: List[Dict]) -> None:
        """Download detail JSON for many schemes in parallel. Purely an accelerator:
        anything missing or failed is simply fetched by the normal sequential chain."""
        if self.max_workers <= 1:
            return
        try:
            todo: Dict[str, Dict] = {}
            for scheme in schemes:
                slug = self._slug_of(scheme)
                has_docs = bool(scheme.get('documents_required'))
                if slug and slug not in todo and not (scheme.get('eligibility') and has_docs):
                    todo[slug] = scheme
            if len(todo) < 2:
                return
            key = self._discover_api_key()
            workers = min(self.max_workers, len(todo), 2)  # hard cap at 2 to avoid 429s
            from requests.adapters import HTTPAdapter
            adapter = HTTPAdapter(pool_connections=workers, pool_maxsize=workers)
            self.session.mount('https://', adapter)
            print(f'Prefetching details in parallel ({workers} workers)...')
            lock = threading.Lock()
            stats = {'ok': 0, 'fail': 0}

            def api_task(slug: str):
                with lock:
                    if stats['fail'] >= 3 and stats['ok'] == 0:
                        return slug, None, None  # API looks down; stop hammering it
                payload = self._prefetch_one('api', slug, {'x-api-key': key}) if key else None
                if payload and payload.get('__rate_limited__'):
                    payload = None
                if self.prefetch_delay > 0:
                    time.sleep(self.prefetch_delay)
                with lock:
                    stats['ok' if payload else 'fail'] += 1
                docs = self._docs_api_try(payload) if payload else None
                return slug, payload, docs

            need_page: List[str] = []
            with ThreadPoolExecutor(max_workers=workers) as pool:
                for slug, payload, docs in pool.map(api_task, list(todo)):
                    if docs is not None:
                        self._prefetched[('docs', slug)] = docs
                    if payload:
                        self._prefetched[('api', slug)] = payload
                        found: List[str] = []
                        self._collect_eligibility(payload, found)
                        if not todo[slug].get('eligibility') and not found:
                            need_page.append(slug)
                    elif not todo[slug].get('eligibility'):
                        need_page.append(slug)
            if need_page:
                with ThreadPoolExecutor(max_workers=workers) as pool:
                    results = pool.map(lambda sl: (sl, self._prefetch_one('page', sl, {})), need_page)
                    for slug, payload in results:
                        if payload:
                            self._prefetched[('page', slug)] = payload
        except Exception as e:  # never let the accelerator break the scrape
            print(f'Parallel prefetch skipped ({e}); continuing sequentially.')

    def _fetch_eligibility_dataset(self, slug: str) -> str:
        if not slug:
            return ''
        if self._dataset_index is None:
            self._dataset_index = {row.get('Scheme Slug', ''): row for row in self._load_dataset()}
        row = self._dataset_index.get(slug)
        if not row:
            return ''
        return (row.get('Eligibility Criteria') or row.get('Eligibility (General)', '') or '').strip()

    # ------------------------------------------------------------------
    # NEW: documents-required extraction (same priority chain as eligibility)
    # ------------------------------------------------------------------
    @staticmethod
    def _flatten_rich_text(value, output: List[str]) -> None:
        """Flatten MyScheme rich-text nodes ({type, children:[{text}]}) into one line per block."""
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
                    line = ''.join((c if isinstance(c, str) else str(c.get('text', '')) for c in children)).strip()
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
    def _extract_application_process_from_payload(payload: Dict) -> Tuple[str, str, List[str], str]:
        """
        Extract application process steps, primary apply link, all links, and modes
        from detail API or page JSON payload.
        Returns: (application_process, primary_apply_link, all_apply_links, application_mode)
        """
        process_blocks: List[str] = []
        apply_links: List[str] = []
        modes: List[str] = []

        if not isinstance(payload, dict):
            return '', '', [], ''

        # Traverse data -> en -> applicationProcess
        data_node = payload.get('data') if isinstance(payload.get('data'), dict) else payload
        en_node = data_node.get('en') if isinstance(data_node.get('en'), dict) else data_node
        app_proc = en_node.get('applicationProcess') or data_node.get('applicationProcess')

        if isinstance(app_proc, list):
            for mode_entry in app_proc:
                if not isinstance(mode_entry, dict):
                    continue
                mode = str(mode_entry.get('mode') or '').strip()
                if mode and mode not in modes:
                    modes.append(mode)

                url = str(mode_entry.get('url') or '').strip()
                if url and url.startswith('http') and url not in apply_links:
                    apply_links.append(url)

                md = mode_entry.get('process_md')
                if md and isinstance(md, str) and md.strip():
                    clean_md = (
                        md.replace('&quot;', '"')
                        .replace('&amp;', '&')
                        .replace('&lt;', '<')
                        .replace('&gt;', '>')
                        .strip()
                    )
                    header = f"### Mode: {mode}" if mode else "### Application Process"
                    process_blocks.append(f"{header}\n{clean_md}")
                    for m in re.finditer(r'\[([^\]]+)\]\((https?://[^\s\)]+)\)', clean_md):
                        found_link = m.group(2).strip()
                        if found_link not in apply_links:
                            apply_links.append(found_link)
                elif mode_entry.get('process'):
                    steps: List[str] = []
                    MySchemeScraper._flatten_rich_text(mode_entry.get('process'), steps)
                    if steps:
                        header = f"### Mode: {mode}" if mode else "### Application Process"
                        process_blocks.append(f"{header}\n" + '\n'.join(steps))

        full_process = '\n\n'.join(process_blocks).strip()
        primary_link = apply_links[0] if apply_links else ''
        mode_str = ', '.join(modes) if modes else ''
        return full_process, primary_link, apply_links, mode_str

    def fetch_application_process(self, scheme: Dict) -> Tuple[str, str, List[str], str]:
        """
        Fetch application process details and links for a scheme.
        Reuses payloads already cached during eligibility or documents fetch.
        """
        slug = self._slug_of(scheme)
        if not slug:
            return '', '', [], ''

        # 1. Try from cached/prefetched payloads
        for kind in ('api', 'page'):
            payload = self._payloads.get((kind, slug)) or self._prefetched.get((kind, slug))
            if payload:
                proc, prim_link, all_links, mode = self._extract_application_process_from_payload(payload)
                if proc or prim_link:
                    return proc, prim_link, all_links, mode

        # 2. Try fetching detail API if not exhausted
        if self._detail_errors < 3:
            payload = self._get_payload('api', slug)
            if payload:
                proc, prim_link, all_links, mode = self._extract_application_process_from_payload(payload)
                if proc or prim_link:
                    return proc, prim_link, all_links, mode

        # 3. Fallback to dataset index
        if self._dataset_index is None and os.path.exists(self.CACHE_FILE):
            try:
                self._dataset_index = {row.get('Scheme Slug', ''): row for row in self._load_dataset()}
            except Exception:
                pass

        if self._dataset_index and slug in self._dataset_index:
            row = self._dataset_index[slug]
            proc = str(row.get('Application Process') or '').strip()
            links = re.findall(r'https?://[^\s<>"\'\)]+', proc)
            official = str(row.get('Official Link') or '').strip()
            prim_link = links[0] if links else official
            mode = str(row.get('Application Mode') or '').strip()
            return proc, prim_link, links, mode

        return '', '', [], ''

    @staticmethod
    def _collect_documents(node, found: List[str], depth: int=0) -> None:
        if depth > 8:
            return
        if isinstance(node, dict):
            skip = ('faq', 'faqs')
            doc_keys = [k for k in node if ('document' in str(k).lower() or str(k).lower().endswith('docs')) and str(k).lower() not in skip]
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

    def _get_payload(self, kind: str, slug: str) -> Optional[Dict]:
        """Return the stashed API/page JSON; on a miss, call the existing fetcher (which stashes it)."""
        if (kind, slug) not in self._payloads:
            if kind == 'api':
                if self._detail_errors >= 3:
                    return None
                self._fetch_eligibility_api(slug)
            else:
                self._fetch_eligibility_page(slug)
        return self._payloads.get((kind, slug))

    def _fetch_documents_api(self, slug: str) -> str:
        payload = self._get_payload('api', slug)
        if not payload:
            return ''
        found: List[str] = []
        self._collect_documents(payload, found)
        return self._dedupe_join(found)

    def _fetch_documents_page(self, slug: str) -> str:
        payload = self._get_payload('page', slug)
        if not payload:
            return ''
        found: List[str] = []
        self._collect_documents(payload, found)
        return self._dedupe_join(found)

    def _fetch_documents_dataset(self, slug: str) -> str:
        if not slug:
            return ''
        if self._dataset_index is None:
            # Only use the dataset for documents if it is already cached on disk;
            # never trigger a download just for documents.
            if not os.path.exists(self.CACHE_FILE):
                return ''
            self._dataset_index = {row.get('Scheme Slug', ''): row for row in self._load_dataset()}
        row = self._dataset_index.get(slug)
        if not row:
            return ''
        return (row.get('Documents Required', '') or '').strip()

    def _fetch_documents_browser(self, slug: str, timeout: int=4000) -> str:
        if not slug or self._page is None:
            return ''
        selector = '#documents-required, #documents_required, #documents'
        try:
            if not self._page.url.rstrip('/').endswith(f'/schemes/{slug}'):
                self._page.goto(f'{self.BASE_URL}/schemes/{slug}', wait_until='domcontentloaded', timeout=45000)
            self._page.wait_for_selector(selector, state='attached', timeout=timeout)
            element = self._page.query_selector(selector)
            if element is None:
                return ''
            text = (element.inner_text() or element.text_content() or '').strip()
            text = text.replace('\ufeff', '').strip()
            text = re.sub(r'^\s*documents?\s*required\s*', '', text, flags=re.I).strip()
            self._browser_fail_streak = 0
            return text
        except Exception:
            self._browser_fail_streak += 1
            return ''

    def fetch_documents(self, scheme: Dict) -> str:
        existing = scheme.get('documents_required') or ''
        if isinstance(existing, list):
            existing = '\n'.join((str(x) for x in existing))
        existing = str(existing).strip()
        if existing:
            return existing
        slug = scheme.get('slug') or scheme.get('url', '').rstrip('/').split('/')[-1]
        if not slug:
            return ''
        # 0) Dedicated documents endpoint (prefetched in parallel; falls through if unavailable).
        text = self._documents_from_endpoint(slug)
        if text:
            return text
        # 1) Reuse JSON already fetched for eligibility: zero extra requests.
        for kind in ('api', 'page'):
            payload = self._payloads.get((kind, slug))
            if payload:
                found: List[str] = []
                self._collect_documents(payload, found)
                text = self._dedupe_join(found)
                if text:
                    return text
                self._debug_payload_keys(kind, slug, payload)
        # 2) Only fetch if eligibility was pre-filled (so nothing was fetched for this scheme).
        if ('ran', slug) not in self._payloads:
            if self._detail_errors < 3:
                text = self._fetch_documents_api(slug)
                if text:
                    return text
            text = self._fetch_documents_page(slug)
            if text:
                return text
        if self._page is not None and self._browser_fail_streak < 5:
            print(f"    → browser fallback (documents): {scheme.get('title', slug)}")
            text = self._fetch_documents_browser(slug)
            if text:
                return text
        return self._fetch_documents_dataset(slug)

    def _docs_api_try(self, payload: Dict) -> Optional[str]:
        """Call the separate documents endpoint for one scheme. Returns the text ('' if the scheme
        has none) or None if the endpoint failed. Thread-safe; stops after 3 failures with 0 successes."""
        try:
            scheme_id = payload['data']['_id']
        except (KeyError, TypeError):
            return None
        with self._docs_lock:
            if self._docs_api['fail'] >= 3 and self._docs_api['ok'] == 0:
                return None
        try:
            response = self.session.get(self.DOCUMENTS_API_URL.format(id=scheme_id), params={'lang': 'en'}, headers={'x-api-key': self._api_key or ''}, timeout=30)
            good = response.status_code == 200
            data = response.json() if good else None
        except (requests.RequestException, ValueError):
            good, data = False, None
        with self._docs_lock:
            self._docs_api['ok' if good else 'fail'] += 1
        if not good:
            return None
        found: List[str] = []
        self._collect_documents(data, found)
        return self._dedupe_join(found)

    def _documents_from_endpoint(self, slug: str) -> str:
        prefetched = self._prefetched.pop(('docs', slug), None)
        if prefetched is not None:
            return prefetched
        payload = self._payloads.get(('api', slug))
        if payload:
            return self._docs_api_try(payload) or ''
        return ''

    def _debug_payload_keys(self, kind: str, slug: str, payload: Dict) -> None:
        """Print the response's key paths once, so a missing documents key can be located."""
        if self._doc_debug_done:
            return
        self._doc_debug_done = True
        paths: List[str] = []

        def walk(node, path: str, depth: int) -> None:
            if depth > 4 or len(paths) >= 60 or not isinstance(node, dict):
                return
            for key, value in node.items():
                new_path = f'{path}.{key}' if path else str(key)
                paths.append(new_path)
                walk(value, new_path, depth + 1)

        walk(payload, '', 0)
        print(f'    [documents debug] no documents key found in {kind} JSON for "{slug}". Key paths: ' + ', '.join(paths))

    def _documents_browser_pass(self, schemes: List[Dict]) -> None:
        """Final pass: read the #documents-required section from the rendered page for any
        scheme whose documents were not in the JSON. Set MYSCHEME_DOCS_BROWSER=0 to skip."""
        if os.environ.get('MYSCHEME_DOCS_BROWSER', '1') == '0':
            return
        missing = [sc for sc in schemes if not sc.get('documents_required') and self._slug_of(sc)]
        if not missing or not self._start_browser():
            return
        print(f'\nDocuments missing from JSON for {len(missing)} schemes; reading them from the page...')
        self._browser_fail_streak = 0
        filled = 0
        misses_in_a_row = 0
        for index, scheme in enumerate(missing, 1):
            text = self._fetch_documents_browser(self._slug_of(scheme), timeout=15000)
            if text:
                scheme['documents_required'] = text
                filled += 1
                misses_in_a_row = 0
            else:
                misses_in_a_row += 1
                if misses_in_a_row >= 15:
                    print('  Browser found no documents for 15 schemes in a row; stopping this pass.')
                    break
            if index % 10 == 0 or index == len(missing):
                print(f'  {index}/{len(missing)} checked ({filled} filled from page)')

    def _start_browser(self) -> bool:
        if self._page is not None:
            return True
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            print('Playwright is not installed.')
            print('Browser fallback disabled.')
            return False
        try:
            self._pw = sync_playwright().start()
            self._browser = self._pw.chromium.launch(headless=True)
            context = self._browser.new_context(user_agent=self.session.headers['User-Agent'], locale='en-US')
            context.route('**/*', lambda route: route.abort() if route.request.resource_type in ('image', 'media', 'font') else route.continue_())
            self._page = context.new_page()
            print('Playwright browser started for final fallback.')
            return True
        except Exception as e:
            print(f'Could not start browser: {e}')
            if "Executable doesn't exist" in str(e) or 'playwright install' in str(e):
                print('Fix: run   playwright install chromium   (one-time download), then run again.')
            self._stop_browser()
            return False

    def _stop_browser(self) -> None:
        for obj, method in ((self._browser, 'close'), (self._pw, 'stop')):
            try:
                if obj:
                    getattr(obj, method)()
            except Exception:
                pass
        self._page = None
        self._browser = None
        self._pw = None

    def _fetch_eligibility_browser(self, slug: str) -> str:
        if not slug:
            return ''
        if self._page is None:
            return ''
        try:
            url = f'{self.BASE_URL}/schemes/{slug}'
            self._page.goto(url, wait_until='domcontentloaded', timeout=45000)
            self._page.wait_for_selector('#eligibility', state='attached', timeout=20000)
            element = self._page.query_selector('#eligibility')
            if element is None:
                return ''
            text = (element.inner_text() or element.text_content() or '').strip()
            text = re.sub(r'^\s*eligibility\s*', '', text, flags=re.I).strip()
            self._browser_fail_streak = 0
            return text
        except Exception:
            self._browser_fail_streak += 1
            return ''

    def fetch_eligibility(self, scheme: Dict) -> str:
        existing = (scheme.get('eligibility') or '').strip()
        if existing:
            return existing
        slug = scheme.get('slug') or scheme.get('url', '').rstrip('/').split('/')[-1]
        if not slug:
            return ''
        self._payloads[('ran', slug)] = {}  # marker: eligibility chain already fetched for this slug
        if self._detail_errors < 3:
            print(f"    → detail API: {scheme.get('title', slug)}")
            text = self._fetch_eligibility_api(slug)
            if text:
                return text
        print(f"    → page JSON: {scheme.get('title', slug)}")
        text = self._fetch_eligibility_page(slug)
        if text:
            return text
        if self._browser_fail_streak < 5 and self._start_browser():
            print(f"    → browser fallback: {scheme.get('title', slug)}")
            text = self._fetch_eligibility_browser(slug)
            if text:
                return text
        print(f"    → dataset fallback: {scheme.get('title', slug)}")
        return self._fetch_eligibility_dataset(slug)

    def add_eligibility(self, schemes: List[Dict]) -> None:
        total = len(schemes)
        print(f'\nFetching eligibility, documents, and application process for {total} schemes...')
        self._detail_errors = 0
        self._browser_fail_streak = 0
        filled = 0
        docs_filled = 0
        app_filled = 0
        browser_used = False
        try:
            self._prefetch_details(schemes)
            for index, scheme in enumerate(schemes, 1):
                _slug = self._slug_of(scheme)
                served = ('api', _slug) in self._prefetched or ('page', _slug) in self._prefetched
                if scheme.get('eligibility'):
                    filled += 1
                else:
                    eligibility = self.fetch_eligibility(scheme)
                    scheme['eligibility'] = eligibility
                    if eligibility:
                        filled += 1
                documents = self.fetch_documents(scheme)
                scheme['documents_required'] = documents
                if documents:
                    docs_filled += 1

                # Extract application process and apply links
                app_proc, apply_link, all_apply_links, app_mode = self.fetch_application_process(scheme)
                if app_proc:
                    scheme['application_process'] = app_proc
                    app_filled += 1
                elif not scheme.get('application_process'):
                    scheme['application_process'] = ''

                if apply_link:
                    scheme['apply_link'] = apply_link
                elif not scheme.get('apply_link'):
                    scheme['apply_link'] = scheme.get('official_link') or ''

                if all_apply_links:
                    scheme['apply_links'] = all_apply_links

                if app_mode and not scheme.get('application_mode'):
                    scheme['application_mode'] = app_mode

                if self._page is not None:
                    browser_used = True
                if index % 10 == 0 or index == total:
                    print(f'  {index}/{total} done ({filled} with eligibility, {docs_filled} with documents, {app_filled} with application process)')
                if not served:
                    time.sleep(0.2)
            if self._docs_api['ok'] or self._docs_api['fail']:
                print(f"  Documents endpoint: {self._docs_api['ok']} ok, {self._docs_api['fail']} failed")
            self._documents_browser_pass(schemes)
        finally:
            self._payloads.clear()
            self._prefetched.clear()
            self._stop_browser()
        if browser_used:
            print('Browser fallback was used only where other methods failed.')

    def scrape_schemes(self, state: str, include_eligibility: bool=True) -> List[Dict]:
        resolved_state = self._resolve_state(state)
        if not resolved_state:
            print(f"State '{state}' not found.")
            print('Available states:')
            print(', '.join(self.get_available_states()))
            return []
        state = resolved_state
        print(f'\nScraping schemes for: {state}')
        schemes = self._fetch_schemes_api(self.states[state])
        api_schemes = schemes
        source = 'MyScheme API'
        if not schemes:
            print('\nLive API unavailable or returned zero; trying GitHub dataset fallback...')
            schemes = self._fetch_from_github_dataset(state)
            source = 'GitHub dataset'
            if schemes and api_schemes is not None:
                source = 'GitHub dataset'  # API returned 0 (not None=error), fallback used
            elif api_schemes is None and schemes:
                source = 'GitHub dataset'  # API errored, fallback succeeded
        if not schemes:
            # Both sources returned zero or failed entirely.
            # Return [] — the worker's ScrapeError guard will preserve existing DB records.
            print(f'  Both API and fallback returned zero schemes for {state}; preserving existing data.')
            return []
        if schemes and include_eligibility:
            self.add_eligibility(schemes)
        scraped_at = time.strftime('%Y-%m-%d %H:%M:%S')
        for scheme in schemes:
            scheme.setdefault('state', state)
            if not scheme.get('state'):
                scheme['state'] = state
            scheme['source'] = source
            scheme['scraped_at'] = scraped_at
        print(f'\nSuccessfully found {len(schemes)} schemes for {state}')
        print(f'Primary source used: {source}')
        return schemes
