#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# tools/check_js.sh  —  JavaScript syntax validator for index.html
#
# Usage:
#   bash tools/check_js.sh              # one-shot check
#   bash tools/check_js.sh --watch      # re-check on every save (needs inotifywait)
#
# Requirements: python3 (with jinja2 installed), node
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$PROJECT_DIR/web_ui/templates/index.html"
TMP_JS="/tmp/_roche_nxt_check.js"
TMP_PY="/tmp/_roche_nxt_check.py"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Write the Python extractor/checker to a temp file to avoid heredoc quoting issues
cat > "$TMP_PY" << 'PYEOF'
import sys, re

try:
    from jinja2 import Environment, FileSystemLoader
except ImportError:
    print("ERROR: jinja2 not installed.  Run: pip install jinja2", file=sys.stderr)
    sys.exit(1)

project_dir = sys.argv[1]

env = Environment(loader=FileSystemLoader(project_dir + '/web_ui/templates'))
html = env.get_template('index.html').render(has_auth_session=False)
scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
js = '\n'.join(scripts)

with open(sys.argv[2], 'w') as f:
    f.write(js)

lines = js.split('\n')
issues = []

# ── Check 1: Two statements mangled on one line
#    Pattern: `];varname="long string...`  or  `);varname="long string...`
for i, raw in enumerate(lines):
    s = raw.rstrip()
    if re.search(r'[)\]]\s*;\s*[a-zA-Z_]\w*\s*=\s*["\'][^"\']{10,}', s) and \
       re.search(r'[)\]]\s*;\s*[a-zA-Z_]', s):
        issues.append(f"  MANGLED_STMT     line {i+1}: {s[:110]}")

# ── Check 2: Functions using html+= without declaring var html
func_pat = re.compile(r'function\s+(\w+)\s*\([^)]*\)\s*\{', re.MULTILINE)
for m in func_pat.finditer(js):
    fname = m.group(1)
    start = m.end()
    depth = 1
    pos = start
    while pos < len(js) and depth > 0:
        if js[pos] == '{':
            depth += 1
        elif js[pos] == '}':
            depth -= 1
        pos += 1
    body = js[start:pos]
    if re.search(r'\bhtml\s*\+=', body) and not re.search(r'\bvar\s+html\s*=', body):
        lineno = js[:m.start()].count('\n') + 1
        issues.append(f"  MISSING_VAR_HTML line {lineno}: function {fname}()")

if issues:
    print(f"EXTRA ISSUES FOUND ({len(issues)}):")
    for iss in issues:
        print(iss)
    sys.exit(2)
else:
    print(f"Extra checks OK  ({len(lines)} JS lines, no issues)")
PYEOF

check_once() {
    echo -e "${CYAN}[check_js]${NC} Extracting JavaScript from index.html ..."
    if ! python3 "$TMP_PY" "$PROJECT_DIR" "$TMP_JS"; then
        echo -e "${RED}✗ Extra checks found issues — see above${NC}"
        return 1
    fi

    # Detect node binary (some systems install it as 'nodejs')
    NODE_BIN=""
    for candidate in node nodejs; do
        if command -v "$candidate" &>/dev/null; then
            NODE_BIN="$candidate"
            break
        fi
    done

    if [[ -z "$NODE_BIN" ]]; then
        echo -e "${YELLOW}⚠  node/nodejs not found — skipping full syntax check${NC}"
        echo -e "${YELLOW}   Install with: sudo apt install nodejs   (or: nvm install --lts)${NC}"
        echo -e "${GREEN}✓ Python checks passed (node unavailable for full check)${NC}"
        return 0
    fi

    echo -e "${CYAN}[check_js]${NC} Running Node.js syntax check ($NODE_BIN) ..."
    if "$NODE_BIN" --check "$TMP_JS" 2>&1; then
        echo -e "${GREEN}✓ JavaScript syntax OK${NC}"
        return 0
    else
        echo -e "${RED}✗ JavaScript syntax ERROR — see above${NC}"
        echo -e "${YELLOW}  Tip: open $TMP_JS and search for the line number reported above${NC}"
        return 1
    fi
}

if [[ "${1:-}" == "--watch" ]]; then
    echo -e "${CYAN}[check_js]${NC} Watching $TEMPLATE for changes (Ctrl-C to stop) ..."
    check_once || true
    while inotifywait -q -e close_write "$TEMPLATE" 2>/dev/null; do
        echo ""
        check_once || true
    done
else
    check_once
fi
