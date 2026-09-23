#!/usr/bin/env python3
"""Basic docs validation: broken images, broken links, orphaned "diagram below" intros.

Usage:
  python3 check-docs.py source <docs_dir>            # scan .md/.mdx source files
  python3 check-docs.py live <sitemap_url> [prefix]  # crawl published pages from a sitemap
Options:
  --no-external   skip checking http(s) links (images are still checked)

Exit codes:
    0  no errors (warnings may still be printed)
    1  at least one error
    2  usage
    3  could not fetch the sitemap (usually a network restriction)
"""
import re, sys, os, concurrent.futures as cf, urllib.request, urllib.error
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse

UA = {"User-Agent": "docs-check/1.0"}
MD_IMG = re.compile(r'!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?[^)]*\)')
MD_LINK = re.compile(r'(?<!!)\[[^\]]*\]\(\s*<?([^)\s>]+)>?[^)]*\)')
TAG_SRC = re.compile(r'<(?:img|Image|Frame)[^>]*\ssrc=["\']([^"\']+)["\']', re.I)
TAG_HREF = re.compile(r'\shref=["\']([^"\']+)["\']', re.I)
INTRO = re.compile(r'(diagram|image|screenshot|figure) (below|above)', re.I)
INLINE_CODE = re.compile(r'`[^`]*`')
QUOTED = re.compile(r'"[^"]*"')

def status(url):
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method, headers=UA)
            with urllib.request.urlopen(req, timeout=15) as r:
                return r.status
        except urllib.error.HTTPError as e:
            if method == "HEAD" and e.code in (403, 405, 501):
                continue
            return e.code
        except Exception as e:
            return f"ERR {type(e).__name__}"
    return "ERR"

def check_urls(urls):
    with cf.ThreadPoolExecutor(16) as ex:
        return dict(zip(urls, ex.map(status, urls)))

def ok(s):
    return isinstance(s, int) and 200 <= s < 400

def resolve_local(docs_dir, src_file, target):
    path = target.split("#")[0].split("?")[0]
    if not path:
        return True
    base = docs_dir if path.startswith("/") else os.path.dirname(src_file)
    cand = os.path.normpath(os.path.join(base, path.lstrip("/")))
    tries = [cand, cand + ".md", cand + ".mdx", os.path.join(cand, "index.md"), os.path.join(cand, "index.mdx")]
    # Mintlify-style absolute routes may carry a site prefix (e.g. /ax/...): also try dropping leading segments
    parts = path.lstrip("/").split("/")
    for i in range(1, min(3, len(parts))):
        c = os.path.join(docs_dir, *parts[i:])
        tries += [c, c + ".md", c + ".mdx", os.path.join(c, "index.mdx")]
    return any(os.path.exists(t) for t in tries)

def scan_source(docs_dir, external):
    findings, remote = [], {}
    for root, _, files in os.walk(docs_dir):
        if "node_modules" in root or "/." in root:
            continue
        for fn in files:
            if not fn.endswith((".md", ".mdx")):
                continue
            fp = os.path.join(root, fn)
            lines = open(fp, encoding="utf-8", errors="replace").read().splitlines()
            in_code = False
            for n, line in enumerate(lines, 1):
                if line.strip().startswith("```"):
                    in_code = not in_code
                if in_code:
                    continue
                line = INLINE_CODE.sub("", line)
                imgs = [m.group(2) for m in MD_IMG.finditer(line)] + TAG_SRC.findall(line)
                links = MD_LINK.findall(line) + TAG_HREF.findall(line)
                for m in MD_IMG.finditer(line):
                    if not m.group(1).strip():
                        findings.append((fp, n, "warn", "image has no alt text", m.group(2)))
                for u in imgs:
                    if u.startswith("http"):
                        remote.setdefault(u, []).append((fp, n, "image"))
                    elif not resolve_local(docs_dir, fp, u):
                        findings.append((fp, n, "error", "local image not found", u))
                for u in links:
                    if u.startswith(("mailto:", "#", "tel:")) or u in imgs:
                        continue
                    if u.startswith("http"):
                        if external:
                            remote.setdefault(u, []).append((fp, n, "link"))
                    elif not resolve_local(docs_dir, fp, u):
                        findings.append((fp, n, "error", "internal link target not found", u))
                if INTRO.search(QUOTED.sub("", line)):
                    window = "\n".join(lines[n:n + 6])
                    if not (MD_IMG.search(window) or TAG_SRC.search(window) or "```mermaid" in window):
                        findings.append((fp, n, "warn", "text promises a diagram/image but none follows", line.strip()[:80]))
    for u, s in check_urls(list(remote)).items():
        if not ok(s):
            for fp, n, kind in remote[u]:
                findings.append((fp, n, "error", f"broken remote {kind} (HTTP {s})", u))
    return findings

class Collector(HTMLParser):
    def __init__(self):
        super().__init__(); self.imgs, self.links = [], []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "img" and a.get("src"):
            self.imgs.append(a["src"])
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
        return r.read().decode("utf-8", "replace")

def scan_live(sitemap, prefix, external):
    try:
        xml = fetch(sitemap)
    except Exception as e:
        print(f"Could not fetch sitemap {sitemap}: {e}\n"
              "This is usually a network or proxy restriction on this machine, not a docs problem.")
        sys.exit(3)
    pages = [p for p in re.findall(r"<loc>([^<]+)</loc>", xml) if not prefix or prefix in p]
    findings, remote = [], {}
    for page in pages:
        try:
            c = Collector(); c.feed(fetch(page))
        except Exception as e:
            findings.append((page, 0, "error", f"page failed to load ({e})", page)); continue
        host = urlparse(page).netloc
        for u in c.imgs:
            u = urljoin(page, u)
            if not u.startswith("data:"):
                remote.setdefault(u, []).append((page, 0, "image"))
        for u in c.links:
            u = urljoin(page, u).split("#")[0]
            if not u.startswith("http"):
                continue
            if external or urlparse(u).netloc == host:
                remote.setdefault(u, []).append((page, 0, "link"))
    for u, s in check_urls(list(remote)).items():
        if not ok(s):
            for pg, n, kind in remote[u]:
                findings.append((pg, n, "error", f"broken {kind} (HTTP {s})", u))
    return findings, len(pages)

def report(findings, scanned):
    errs = [f for f in findings if f[2] == "error"]
    warns = [f for f in findings if f[2] == "warn"]
    print(f"Scanned {scanned}. {len(errs)} errors, {len(warns)} warnings.\n")
    for f in sorted(errs) + sorted(warns):
        loc = f"{f[0]}:{f[1]}" if f[1] else f[0]
        print(f"[{f[2].upper()}] {loc}\n    {f[3]}: {f[4]}")
    return 1 if errs else 0

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    external = "--no-external" not in sys.argv
    if len(args) < 2 or args[0] not in ("source", "live"):
        print(__doc__); sys.exit(2)
    if args[0] == "source":
        f = scan_source(args[1], external)
        n = sum(1 for r, _, fs in os.walk(args[1]) for x in fs if x.endswith((".md", ".mdx")))
        sys.exit(report(f, f"{n} files"))
    f, n = scan_live(args[1], args[2] if len(args) > 2 else "", external)
    sys.exit(report(f, f"{n} pages"))
