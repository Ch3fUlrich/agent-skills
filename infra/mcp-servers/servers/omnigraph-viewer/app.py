"""Read-only web viewer for the Omnigraph memory graph.

Holds the Omnigraph bearer token server-side (the browser never sees it) and
exposes the graph to the browser as JSON. The frontend (index.html-in-a-string
below) renders project tabs, an interactive force-directed graph with node/edge
details, a filterable/sortable table, and search highlighting.

Human auth is handled in front of this service (Authelia via Caddy); the app has
no auth of its own — never expose it without the SSO/proxy in front.
"""
import html
import json
import os

import requests
from flask import Flask, Response, jsonify, request

OMNIGRAPH_URL = os.environ.get("OMNIGRAPH_URL", "http://omnigraph-server:8080").rstrip("/")
OMNIGRAPH_TOKEN = os.environ.get("OMNIGRAPH_TOKEN", "")
GRAPH_ID = os.environ.get("OMNIGRAPH_GRAPH", "memory")
TIMEOUT = float(os.environ.get("OMNIGRAPH_TIMEOUT", "15"))

app = Flask(__name__)
_headers = {"Authorization": f"Bearer {OMNIGRAPH_TOKEN}"}

NODE_TYPES = ["Project", "Decision", "Rule", "Preference", "Convention", "Component", "Task"]
# Which field is the human label / the main body text, per node type.
LABEL_FIELD = {
    "Project": "name", "Decision": "title", "Rule": "statement",
    "Preference": "statement", "Convention": "name", "Component": "name", "Task": "title",
}


def _branches():
    try:
        r = requests.get(f"{OMNIGRAPH_URL}/graphs/{GRAPH_ID}/branches", headers=_headers, timeout=TIMEOUT)
        r.raise_for_status()
        return r.json().get("branches", ["main"])
    except Exception:  # noqa: BLE001
        return ["main"]


def _export(branch):
    """POST export -> list of NDJSON records (nodes + edges) for a branch."""
    url = f"{OMNIGRAPH_URL}/graphs/{GRAPH_ID}/export"
    params = {"branch": branch} if branch and branch != "main" else None
    r = requests.post(url, json={}, params=params, headers=_headers, timeout=TIMEOUT)
    r.raise_for_status()
    out = []
    for line in r.text.splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


def _build_graph(branch):
    records = _export(branch)
    nodes = {}
    edges_seen = set()
    edges = []
    for rec in records:
        if "edge" in rec:
            key = (rec["edge"], rec.get("from"), rec.get("to"))
            if key in edges_seen:
                continue  # de-dup (edges aren't slug-keyed, merges can duplicate)
            edges_seen.add(key)
            edges.append({"type": rec["edge"], "from": rec.get("from"), "to": rec.get("to")})
        elif "type" in rec:
            data = rec.get("data", {})
            slug = data.get("slug")
            if slug:
                nodes[slug] = {"type": rec["type"], "data": data}

    project_slugs = {s for s, n in nodes.items() if n["type"] == "Project"}
    # attribute each node to the project(s) it edges into
    proj_of = {s: set() for s in nodes}
    for e in edges:
        if e["to"] in project_slugs and e["from"] in proj_of:
            proj_of[e["from"]].add(e["to"])
    for s in project_slugs:
        proj_of[s].add(s)

    out_nodes = []
    for slug, n in nodes.items():
        data = n["data"]
        label = data.get(LABEL_FIELD.get(n["type"], "slug")) or slug
        projs = sorted(proj_of.get(slug, set()))
        is_global = (data.get("scope") == "global") or (not projs and n["type"] != "Project")
        out_nodes.append({
            "id": slug, "type": n["type"], "label": label,
            "fields": data, "projects": projs, "global": is_global,
        })
    projects = sorted(
        ({"id": s, "name": nodes[s]["data"].get("name", s)} for s in project_slugs),
        key=lambda p: p["name"],
    )
    return {"nodes": out_nodes, "edges": edges, "projects": projects, "branch": branch}


@app.get("/healthz")
def healthz():
    return Response("ok", mimetype="text/plain")


@app.get("/api/graph")
def api_graph():
    branch = request.args.get("branch", "main")
    if branch not in _branches():
        branch = "main"
    try:
        return jsonify(_build_graph(branch))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": str(exc), "nodes": [], "edges": [], "projects": [], "branch": branch}), 200


@app.get("/api/branches")
def api_branches():
    return jsonify({"branches": _branches()})


@app.get("/")
def index():
    return Response(PAGE.replace("__GRAPH__", html.escape(GRAPH_ID)), mimetype="text/html")


PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Omnigraph Memory</title>
<style>
:root{color-scheme:light dark;
 --bg:#0f1115;--panel:#161a22;--card:#1b202b;--fg:#e6e9ef;--mut:#8b93a7;--bd:#2a3040;--acc:#6ea8fe;
 --Project:#f6c453;--Decision:#6ea8fe;--Rule:#e5675f;--Preference:#b98cf0;--Convention:#57c98a;--Component:#4bc4d6;--Task:#c7a3ff;}
@media (prefers-color-scheme:light){:root{--bg:#f5f6f8;--panel:#fff;--card:#fff;--fg:#1a1e27;--mut:#5b6472;--bd:#e3e6ec;--acc:#2563eb;}}
*{box-sizing:border-box}html,body{margin:0;height:100%}
body{background:var(--bg);color:var(--fg);font:14px/1.5 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;display:flex;flex-direction:column}
header{display:flex;gap:12px;align-items:center;flex-wrap:wrap;padding:10px 16px;border-bottom:1px solid var(--bd);background:var(--panel)}
header h1{font-size:15px;margin:0;font-weight:650}
header .sp{flex:1}
input,select,button{background:var(--card);color:var(--fg);border:1px solid var(--bd);border-radius:8px;padding:6px 10px;font:inherit}
button{cursor:pointer}button.on{background:var(--acc);color:#fff;border-color:var(--acc)}
#search{min-width:220px}
.tabs{display:flex;gap:6px;padding:8px 16px;border-bottom:1px solid var(--bd);flex-wrap:wrap;background:var(--panel)}
.tab{padding:5px 12px;border-radius:999px;border:1px solid var(--bd);cursor:pointer;font-size:13px;background:var(--card)}
.tab.on{background:var(--acc);color:#fff;border-color:var(--acc)}
main{flex:1;display:flex;min-height:0}
#stage{flex:1;position:relative;overflow:hidden}
svg{width:100%;height:100%;display:block}
.link{stroke:var(--mut);stroke-opacity:.45}
.link.hl{stroke:var(--acc);stroke-opacity:1;stroke-width:2px}
.link.dim{stroke-opacity:.06}
.node{cursor:pointer}
.node circle{stroke:var(--bg);stroke-width:2px}
.node text{font-size:11px;fill:var(--fg);pointer-events:none}
.node.dim{opacity:.12}
.node.hl circle{stroke:var(--acc);stroke-width:3px}
.elabel{font-size:9px;fill:var(--mut);pointer-events:none}
#side{width:320px;border-left:1px solid var(--bd);background:var(--panel);overflow:auto;padding:14px}
#side h3{margin:.1em 0 .4em;font-size:14px}
#side .k{color:var(--mut);font-size:12px;margin-top:8px}
#side .v{white-space:pre-wrap;word-break:break-word}
#side .pill{display:inline-block;font-size:11px;padding:1px 8px;border-radius:999px;color:#fff}
#side .muted{color:var(--mut)}
#legend{position:absolute;left:10px;bottom:10px;background:var(--panel);border:1px solid var(--bd);border-radius:10px;padding:8px 10px;font-size:12px;max-width:240px}
#legend label{display:inline-flex;align-items:center;gap:5px;margin:2px 6px 2px 0;cursor:pointer}
.dot{width:10px;height:10px;border-radius:50%;display:inline-block}
#table{flex:1;overflow:auto;padding:0 16px 16px}
#table.hidden,#stage.hidden{display:none}
section{margin-top:16px}
section h2{font-size:14px;display:flex;gap:8px;align-items:center}
.count{background:var(--acc);color:#fff;border-radius:999px;font-size:11px;padding:1px 8px}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{text-align:left;padding:6px 9px;border-bottom:1px solid var(--bd);vertical-align:top}
th{color:var(--mut);cursor:pointer;user-select:none;white-space:nowrap;position:sticky;top:0;background:var(--panel)}
th.sort:after{content:" ↕";opacity:.5}th.asc:after{content:" ↑"}th.desc:after{content:" ↓"}
td{max-width:520px}
tr.match{outline:2px solid var(--acc);outline-offset:-2px}
.err{color:#e5675f;padding:16px}
</style></head><body>
<header>
  <h1>Omnigraph Memory <span class="muted" style="color:var(--mut);font-weight:400">· __GRAPH__</span></h1>
  <button id="v-graph" class="on">Graph</button>
  <button id="v-table">Table</button>
  <input id="search" placeholder="search nodes / edges…">
  <span class="sp"></span>
  <label class="muted" style="color:var(--mut)">branch</label>
  <select id="branch"></select>
</header>
<div class="tabs" id="tabs"></div>
<main>
  <div id="stage">
    <svg id="svg"><g id="links"></g><g id="elabels"></g><g id="nodes"></g></svg>
    <div id="legend"></div>
  </div>
  <div id="table" class="hidden"></div>
  <div id="side"><p class="muted">Click a node or edge for details.</p></div>
</main>
<script>
const S={data:null,branch:"main",tab:"all",view:"graph",q:"",types:new Set(),sim:null};
const TYPES=["Project","Decision","Rule","Preference","Convention","Component","Task"];
const COLOR=t=>getComputedStyle(document.documentElement).getPropertyValue("--"+t).trim()||"#888";
const $=s=>document.querySelector(s);
const esc=s=>(s==null?"":String(s)).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));

async function load(){
  const r=await fetch("/api/graph?branch="+encodeURIComponent(S.branch));
  S.data=await r.json();
  if(S.data.error){$("#side").innerHTML='<p class="err">'+esc(S.data.error)+'</p>';}
  S.types=new Set(TYPES);
  buildTabs();buildLegend();render();
}
async function loadBranches(){
  const r=await fetch("/api/branches");const b=(await r.json()).branches||["main"];
  $("#branch").innerHTML=b.map(x=>`<option ${x===S.branch?"selected":""}>${esc(x)}</option>`).join("");
}
function buildTabs(){
  const t=[{id:"all",name:"All"},{id:"global",name:"Global"}].concat((S.data.projects||[]).map(p=>({id:p.id,name:p.name})));
  $("#tabs").innerHTML=t.map(x=>`<div class="tab ${x.id===S.tab?"on":""}" data-id="${esc(x.id)}">${esc(x.name)}</div>`).join("");
  $("#tabs").querySelectorAll(".tab").forEach(el=>el.onclick=()=>{S.tab=el.dataset.id;buildTabs();render();});
}
function buildLegend(){
  $("#legend").innerHTML="<b>types</b><br>"+TYPES.map(t=>
    `<label><input type=checkbox data-t="${t}" ${S.types.has(t)?"checked":""}><span class=dot style="background:${COLOR(t)}"></span>${t}</label>`).join("");
  $("#legend").querySelectorAll("input").forEach(cb=>cb.onchange=()=>{cb.checked?S.types.add(cb.dataset.t):S.types.delete(cb.dataset.t);render();});
}
// which nodes are visible under the current tab + type filter
function visibleNodes(){
  return (S.data.nodes||[]).filter(n=>{
    if(!S.types.has(n.type))return false;
    if(S.tab==="all")return true;
    if(S.tab==="global")return n.global;
    return n.projects.includes(S.tab)||n.id===S.tab;
  });
}
function matches(n){
  if(!S.q)return false;const q=S.q.toLowerCase();
  return (n.id+" "+n.type+" "+Object.values(n.fields||{}).join(" ")).toLowerCase().includes(q);
}
function render(){
  $("#v-graph").classList.toggle("on",S.view==="graph");
  $("#v-table").classList.toggle("on",S.view==="table");
  $("#stage").classList.toggle("hidden",S.view!=="graph");
  $("#table").classList.toggle("hidden",S.view!=="table");
  $("#legend").style.display=S.view==="graph"?"":"none";
  if(S.view==="graph")renderGraph();else renderTable();
}
/* ---------- force-directed graph (vanilla) ---------- */
function renderGraph(){
  const svg=$("#svg"),W=svg.clientWidth||800,H=svg.clientHeight||600;
  const vis=visibleNodes(),ids=new Set(vis.map(n=>n.id));
  const links=(S.data.edges||[]).filter(e=>ids.has(e.from)&&ids.has(e.to));
  // preserve positions across renders
  const prev=S.pos||{};S.pos={};
  vis.forEach(n=>{const p=prev[n.id];S.pos[n.id]={x:p?p.x:W/2+(Math.random()-.5)*W*.6,y:p?p.y:H/2+(Math.random()-.5)*H*.6,vx:0,vy:0};});
  if(S.sim)cancelAnimationFrame(S.sim);
  let ticks=0;
  function step(){
    const P=S.pos;
    for(const a of vis){for(const b of vis){if(a.id>=b.id)continue;
      const pa=P[a.id],pb=P[b.id];let dx=pa.x-pb.x,dy=pa.y-pb.y,d=Math.hypot(dx,dy)||1;
      const f=3000/(d*d);pa.vx+=dx/d*f;pa.vy+=dy/d*f;pb.vx-=dx/d*f;pb.vy-=dy/d*f;}}
    for(const e of links){const pa=P[e.from],pb=P[e.to];if(!pa||!pb)continue;
      let dx=pb.x-pa.x,dy=pb.y-pa.y,d=Math.hypot(dx,dy)||1,f=(d-90)*0.01;
      pa.vx+=dx/d*f;pa.vy+=dy/d*f;pb.vx-=dx/d*f;pb.vy-=dy/d*f;}
    for(const n of vis){const p=P[n.id];p.vx+=(W/2-p.x)*0.002;p.vy+=(H/2-p.y)*0.002;
      if(n._drag)continue;p.x+=p.vx*=.85;p.y+=p.vy*=.85;p.x=Math.max(20,Math.min(W-20,p.x));p.y=Math.max(20,Math.min(H-20,p.y));}
    draw(vis,links);
    if(++ticks<300)S.sim=requestAnimationFrame(step);
  }
  function draw(vis,links){
    const P=S.pos;
    $("#links").innerHTML=links.map(e=>{const a=P[e.from],b=P[e.to];
      const hl=S.q&&(vis.find(n=>n.id===e.from&&matches(n))||vis.find(n=>n.id===e.to&&matches(n)));
      const cls="link"+(hl?" hl":(S.q?" dim":""));
      return `<line class="${cls}" x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" data-e="${esc(e.type)}|${esc(e.from)}|${esc(e.to)}"></line>`;}).join("");
    $("#elabels").innerHTML=links.map(e=>{const a=P[e.from],b=P[e.to];
      return `<text class="elabel" x="${(a.x+b.x)/2}" y="${(a.y+b.y)/2}">${esc(e.type)}</text>`;}).join("");
    $("#nodes").innerHTML=vis.map(n=>{const p=P[n.id];const m=matches(n);
      const cls="node"+(m?" hl":(S.q?" dim":""));
      const r=n.type==="Project"?13:9;
      return `<g class="${cls}" data-n="${esc(n.id)}" transform="translate(${p.x},${p.y})">
        <circle r="${r}" fill="${COLOR(n.type)}"></circle>
        <text x="${r+3}" y="4">${esc((n.label||n.id).slice(0,22))}</text></g>`;}).join("");
    wire();
  }
  function wire(){
    $("#nodes").querySelectorAll(".node").forEach(g=>{
      const id=g.dataset.n;
      g.onclick=()=>showNode(vis.find(n=>n.id===id),links);
      g.onmousedown=ev=>{ev.preventDefault();const n=vis.find(n=>n.id===id);n._drag=1;
        const mv=e=>{const pt=toSvg(e);S.pos[id].x=pt.x;S.pos[id].y=pt.y;draw(vis,links);};
        const up=()=>{n._drag=0;document.removeEventListener("mousemove",mv);document.removeEventListener("mouseup",up);};
        document.addEventListener("mousemove",mv);document.addEventListener("mouseup",up);};
    });
    $("#links").querySelectorAll(".link").forEach(l=>l.onclick=()=>{
      const [t,f,to]=l.dataset.e.split("|");showEdge(t,f,to);});
  }
  function toSvg(e){const r=svg.getBoundingClientRect();return {x:e.clientX-r.left,y:e.clientY-r.top};}
  step();
}
function showNode(n,links){if(!n)return;
  const conn=(links||S.data.edges).filter(e=>e.from===n.id||e.to===n.id);
  const rows=Object.entries(n.fields||{}).filter(([k])=>k!=="embedding")
    .map(([k,v])=>`<div class="k">${esc(k)}</div><div class="v">${esc(v)}</div>`).join("");
  const cs=conn.map(e=>{const other=e.from===n.id?e.to:e.from,dir=e.from===n.id?"→":"←";
    return `<div class="v">${dir} <b>${esc(e.type)}</b> ${esc(other)}</div>`;}).join("")||'<div class="muted">none</div>';
  $("#side").innerHTML=`<span class="pill" style="background:${COLOR(n.type)}">${esc(n.type)}</span>
    <h3>${esc(n.label||n.id)}</h3><div class="muted">${esc(n.id)} ${n.global?"· global":""}</div>
    ${rows}<div class="k">connections (${conn.length})</div>${cs}`;
}
function showEdge(type,from,to){
  const fn=(S.data.nodes||[]).find(n=>n.id===from),tn=(S.data.nodes||[]).find(n=>n.id===to);
  $("#side").innerHTML=`<span class="pill" style="background:var(--acc)">edge</span><h3>${esc(type)}</h3>
    <div class="k">from</div><div class="v">${esc(from)} <span class="muted">(${esc(fn?fn.type:"?")})</span></div>
    <div class="k">to</div><div class="v">${esc(to)} <span class="muted">(${esc(tn?tn.type:"?")})</span></div>
    <div class="k">meaning</div><div class="v">${esc(EDGE_DOC[type]||"relationship")}</div>`;
}
const EDGE_DOC={DecidedIn:"decision belongs to a project",ConstrainsProject:"rule constrains a project",
  ConstrainsComponent:"rule constrains a component",AppliesTo:"convention/preference applies to target",
  PartOf:"component is part of a project",Supersedes:"decision replaces an earlier decision"};
/* ---------- table view ---------- */
let SORT={};
function renderTable(){
  const vis=visibleNodes();const byType={};TYPES.forEach(t=>byType[t]=[]);
  vis.forEach(n=>byType[n.type].push(n));
  let hasFilter=($("#tf")&&$("#tf").value)||"";
  let hh=`<div style="position:sticky;top:0;background:var(--bg);padding:10px 0;z-index:2">
    <input id="tf" placeholder="filter rows in tables…" value="${esc(hasFilter)}" style="min-width:280px"></div>`;
  const out=TYPES.filter(t=>byType[t].length).map(t=>{
    const cols=["id"].concat(t==="Decision"?["title","status","rationale"]:t==="Rule"?["severity","statement"]:
      t==="Preference"?["scope","statement"]:t==="Convention"?["name","example"]:t==="Component"?["name","kind","location"]:
      t==="Project"?["name","summary"]:t==="Task"?["title","state"]:["label"]);
    let rows=byType[t].map(n=>({id:n.id,...n.fields,_n:n}));
    if(hasFilter){const q=hasFilter.toLowerCase();rows=rows.filter(r=>cols.some(c=>String(r[c]==null?"":r[c]).toLowerCase().includes(q)));}
    const s=SORT[t];if(s){rows.sort((a,b)=>{const av=String(a[s.c]==null?"":a[s.c]),bv=String(b[s.c]==null?"":b[s.c]);return s.d*av.localeCompare(bv);});}
    const th=cols.map(c=>`<th class="sort ${s&&s.c===c?(s.d>0?"asc":"desc"):""}" data-t="${t}" data-c="${c}">${c}</th>`).join("");
    const body=rows.map(r=>`<tr class="${S.q&&matches(r._n)?"match":""}">`+cols.map(c=>`<td>${esc(r[c])}</td>`).join("")+"</tr>").join("")||`<tr><td colspan=9 class=muted>no rows</td></tr>`;
    return `<section><h2><span class="dot" style="background:${COLOR(t)}"></span>${t} <span class="count">${rows.length}</span></h2>
      <div style="overflow-x:auto"><table><thead><tr>${th}</tr></thead><tbody>${body}</tbody></table></div></section>`;
  }).join("");
  $("#table").innerHTML=hh+(out||'<p class="muted">no nodes for this tab.</p>');
  const tf=$("#tf");if(tf){tf.oninput=()=>renderTable();tf.focus();tf.setSelectionRange(tf.value.length,tf.value.length);}
  $("#table").querySelectorAll("th.sort").forEach(th=>th.onclick=()=>{
    const t=th.dataset.t,c=th.dataset.c,cur=SORT[t];SORT[t]=cur&&cur.c===c?{c,d:-cur.d}:{c,d:1};renderTable();});
}
/* ---------- wire header ---------- */
$("#v-graph").onclick=()=>{S.view="graph";render();};
$("#v-table").onclick=()=>{S.view="table";render();};
$("#search").oninput=e=>{S.q=e.target.value;if(S.view==="graph")renderGraph();else renderTable();};
$("#branch").onchange=e=>{S.branch=e.target.value;S.pos=null;load();};
window.addEventListener("resize",()=>{if(S.view==="graph")renderGraph();});
loadBranches().then(load);
</script></body></html>"""
