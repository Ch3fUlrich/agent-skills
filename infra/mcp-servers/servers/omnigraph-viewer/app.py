"""Minimal read-only web viewer for the Omnigraph memory graph.

Holds the Omnigraph bearer token server-side (the browser never sees it) and
renders projects + typed memory nodes as HTML. Human authentication is handled
in front of this service (Authelia SSO via Caddy); this app itself is read-only
and unauthenticated at the app layer by design — never expose it without the
SSO/proxy in front.
"""
import html
import os

import requests
from flask import Flask, Response

OMNIGRAPH_URL = os.environ.get("OMNIGRAPH_URL", "http://omnigraph-server:8080").rstrip("/")
OMNIGRAPH_TOKEN = os.environ.get("OMNIGRAPH_TOKEN", "")
GRAPH_ID = os.environ.get("OMNIGRAPH_GRAPH", "memory")
TIMEOUT = float(os.environ.get("OMNIGRAPH_TIMEOUT", "10"))

app = Flask(__name__)
_headers = {"Authorization": f"Bearer {OMNIGRAPH_TOKEN}"}

# Section title -> stored query name.
SECTIONS = [
    ("Projects", "list_projects"),
    ("Decisions", "list_decisions"),
    ("Rules", "list_rules"),
    ("Preferences", "list_preferences"),
    ("Conventions", "list_conventions"),
    ("Components", "list_components"),
]


def _run_query(name: str):
    """Return (columns, rows) for a stored query, or (None, error_str)."""
    url = f"{OMNIGRAPH_URL}/graphs/{GRAPH_ID}/queries/{name}"
    try:
        r = requests.post(url, json={}, headers=_headers, timeout=TIMEOUT)
        r.raise_for_status()
        body = r.json()
        return body.get("columns", []), body.get("rows", [])
    except Exception as exc:  # noqa: BLE001 - surface any failure in the UI
        return None, str(exc)


def _list_graphs():
    try:
        r = requests.get(f"{OMNIGRAPH_URL}/graphs", headers=_headers, timeout=TIMEOUT)
        r.raise_for_status()
        return [g.get("graph_id") for g in r.json().get("graphs", [])]
    except Exception:  # noqa: BLE001
        return []


def _cell(value) -> str:
    if value is None:
        return '<span class="null">—</span>'
    return html.escape(str(value))


def _render_section(title: str, name: str) -> str:
    cols, rows = _run_query(name)
    if cols is None:  # error
        return (
            f'<section><h2>{html.escape(title)}</h2>'
            f'<p class="err">query failed: {html.escape(str(rows))}</p></section>'
        )
    short = [c.split(".", 1)[-1] for c in cols]
    head = "".join(f"<th>{html.escape(c)}</th>" for c in short)
    body = ""
    for row in rows:
        cells = "".join(f"<td>{_cell(row.get(c))}</td>" for c in cols)
        body += f"<tr>{cells}</tr>"
    empty = '<tr><td colspan="99" class="null">no rows</td></tr>'
    return (
        f'<section><h2>{html.escape(title)} '
        f'<span class="count">{len(rows)}</span></h2>'
        f'<div class="scroll"><table><thead><tr>{head}</tr></thead>'
        f'<tbody>{body or empty}</tbody></table></div></section>'
    )


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Omnigraph Memory Viewer</title><style>
:root{{color-scheme:light dark;--bg:#0f1115;--card:#1a1e27;--fg:#e6e9ef;--mut:#8b93a7;--acc:#6ea8fe;--bd:#2a3040}}
@media (prefers-color-scheme:light){{:root{{--bg:#f6f7f9;--card:#fff;--fg:#1a1e27;--mut:#5b6472;--acc:#2563eb;--bd:#e3e6ec}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.5 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif}}
header{{padding:20px 24px;border-bottom:1px solid var(--bd)}}
h1{{margin:0;font-size:18px}}.sub{{color:var(--mut);font-size:13px;margin-top:4px}}
main{{padding:20px 24px;max-width:1100px;margin:0 auto}}
section{{background:var(--card);border:1px solid var(--bd);border-radius:12px;padding:16px 18px;margin-bottom:18px}}
h2{{margin:0 0 12px;font-size:15px;display:flex;align-items:center;gap:8px}}
.count{{background:var(--acc);color:#fff;border-radius:999px;font-size:12px;padding:1px 9px;font-weight:600}}
.scroll{{overflow-x:auto}}table{{border-collapse:collapse;width:100%;font-size:13px}}
th,td{{text-align:left;padding:7px 10px;border-bottom:1px solid var(--bd);vertical-align:top}}
th{{color:var(--mut);font-weight:600;text-transform:capitalize;white-space:nowrap}}
td{{max-width:520px}}.null{{color:var(--mut)}}.err{{color:#e5484d}}
.pill{{font-size:12px;color:var(--mut)}}a{{color:var(--acc)}}
</style></head><body>
<header><h1>Omnigraph Memory Viewer</h1>
<div class="sub">graph <b>{graph}</b> &middot; server {server} &middot; graphs: {graphs} &middot; read-only</div>
</header><main>{body}</main></body></html>"""


@app.get("/healthz")
def healthz():
    return Response("ok", mimetype="text/plain")


@app.get("/")
def index():
    graphs = ", ".join(_list_graphs()) or "(none)"
    body = "".join(_render_section(t, n) for t, n in SECTIONS)
    page = PAGE.format(
        graph=html.escape(GRAPH_ID),
        server=html.escape(OMNIGRAPH_URL),
        graphs=html.escape(graphs),
        body=body,
    )
    return Response(page, mimetype="text/html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8090")))
