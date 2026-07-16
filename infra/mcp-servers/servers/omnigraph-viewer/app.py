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


def _graphs():
    """All graph IDs the cluster exposes (for the project/graph selector)."""
    try:
        r = requests.get(f"{OMNIGRAPH_URL}/graphs", headers=_headers, timeout=TIMEOUT)
        r.raise_for_status()
        ids = [g.get("graph_id") or g.get("graphId") for g in r.json().get("graphs", [])]
        return [g for g in ids if g] or [GRAPH_ID]
    except Exception:  # noqa: BLE001
        return [GRAPH_ID]


def _resolve_graph(graph):
    """Only serve a graph the cluster actually exposes; fall back to the default."""
    return graph if graph in _graphs() else GRAPH_ID


def _branches(graph):
    try:
        r = requests.get(f"{OMNIGRAPH_URL}/graphs/{graph}/branches", headers=_headers, timeout=TIMEOUT)
        r.raise_for_status()
        return r.json().get("branches", ["main"])
    except Exception:  # noqa: BLE001
        return ["main"]


def _export(branch, graph):
    """POST export -> list of NDJSON records (nodes + edges) for a branch."""
    url = f"{OMNIGRAPH_URL}/graphs/{graph}/export"
    params = {"branch": branch} if branch and branch != "main" else None
    r = requests.post(url, json={}, params=params, headers=_headers, timeout=TIMEOUT)
    r.raise_for_status()
    out = []
    for line in r.text.splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


def _build_graph(branch, graph):
    records = _export(branch, graph)
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
    graph = _resolve_graph(request.args.get("graph", GRAPH_ID))
    branch = request.args.get("branch", "main")
    if branch not in _branches(graph):
        branch = "main"
    try:
        data = _build_graph(branch, graph)
        data["graph"] = graph
        return jsonify(data)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": str(exc), "nodes": [], "edges": [], "projects": [], "branch": branch, "graph": graph}), 200


@app.get("/api/branches")
def api_branches():
    return jsonify({"branches": _branches(_resolve_graph(request.args.get("graph", GRAPH_ID)))})


@app.get("/api/graphs")
def api_graphs():
    return jsonify({"graphs": _graphs(), "current": GRAPH_ID})


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
.node circle{paint-order:stroke}   /* stroke = project-cluster ring (set per-node); fill drawn on top */
.node text{font-size:11px;fill:var(--fg);pointer-events:none}
.node.dim{opacity:.12}
.node.hl circle{stroke:var(--acc);stroke-width:3px}
.elabel{font-size:9px;fill:var(--mut);pointer-events:none}
.clabel{font-size:15px;font-weight:700;text-anchor:middle;opacity:.85;pointer-events:none;text-transform:uppercase;letter-spacing:.5px}
#side{width:320px;border-left:1px solid var(--bd);background:var(--panel);overflow:auto;padding:14px}
#side h3{margin:.1em 0 .4em;font-size:14px}
#side .k{color:var(--mut);font-size:12px;margin-top:8px}
#side .v{white-space:pre-wrap;word-break:break-word}
#side .pill{display:inline-block;font-size:11px;padding:1px 8px;border-radius:999px;color:#fff}
#side .muted{color:var(--mut)}
#hint{position:absolute;right:10px;top:10px;background:var(--panel);border:1px solid var(--bd);border-radius:8px;padding:4px 9px;font-size:11px;color:var(--mut);pointer-events:none}
#svg{cursor:grab}#svg.panning{cursor:grabbing}
.hit{stroke:transparent;stroke-width:12px;fill:none;cursor:pointer}
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
  <h1>Omnigraph Memory</h1>
  <button id="v-graph" class="on">Graph</button>
  <button id="v-table">Table</button>
  <input id="search" placeholder="search nodes / edges…">
  <span class="sp"></span>
  <label class="muted" style="color:var(--mut)">graph</label>
  <select id="graph" title="each project is an isolated graph"></select>
  <label class="muted" style="color:var(--mut)">branch</label>
  <select id="branch"></select>
</header>
<div class="tabs" id="tabs"></div>
<main>
  <div id="stage">
    <svg id="svg"><g id="viewport"><g id="hulls"></g><g id="clabels"></g><g id="links"></g><g id="elabels"></g><g id="nodes"></g></g></svg>
    <div id="hint">scroll = zoom · drag empty space = pan · drag node = move</div>
    <div id="legend"></div>
  </div>
  <div id="table" class="hidden"></div>
  <div id="side"><p class="muted">Click a node or edge for details.</p></div>
</main>
<script>
const S={data:null,graph:"__GRAPH__",branch:"main",tab:"all",view:"graph",q:"",types:new Set(),sim:null};
const TYPES=["Project","Decision","Rule","Preference","Convention","Component","Task"];
const COLOR=t=>getComputedStyle(document.documentElement).getPropertyValue("--"+t).trim()||"#888";
// ---- project clustering: group nodes by their primary project so clusters are obvious ----
const CPAL=["#f6c453","#6ea8fe","#e5675f","#57c98a","#b98cf0","#4bc4d6","#f78fb3","#7bd389","#ffa94d","#a0a7b4"];
function clusterOf(n){                                   // which cluster a node lives in
  if(n.type==="Project")return n.id;                     // a Project node anchors its own cluster
  if(n.projects&&n.projects.length)return n.projects[0]; // primary project
  if(n.global)return "__global";
  return "__misc";
}
function clusterName(cid){
  if(cid==="__global")return "global";
  if(cid==="__misc")return "unassigned";
  const p=(S.data.projects||[]).find(x=>x.id===cid);
  return p?p.name:cid;
}
// a project keeps the SAME color everywhere: index into a stable global cluster order
function clusterColor(cid){
  const order=(S.data.projects||[]).map(p=>p.id).concat("__global","__misc");
  const i=order.indexOf(cid);return CPAL[(i<0?0:i)%CPAL.length];
}
// build cluster colors/anchors for the currently visible nodes (anchors spread on a ring)
function buildClusters(vis,W,H){
  const ids=[...new Set(vis.map(clusterOf))].sort();     // deterministic layout order
  const info={},n=ids.length,R=Math.min(W,H)*0.34;
  ids.forEach((cid,i)=>{
    const a=n>1?(-Math.PI/2+i*2*Math.PI/n):0;            // spread anchors on a ring
    info[cid]={color:clusterColor(cid),name:clusterName(cid),
      anchor:n>1?{x:W/2+R*Math.cos(a),y:H/2+R*Math.sin(a)}:{x:W/2,y:H/2}};
  });
  return {ids,info,multi:n>1};
}
const $=s=>document.querySelector(s);
const esc=s=>(s==null?"":String(s)).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));

const qg=()=>"graph="+encodeURIComponent(S.graph);
async function load(){
  const r=await fetch("/api/graph?"+qg()+"&branch="+encodeURIComponent(S.branch));
  S.data=await r.json();
  if(S.data.error){$("#side").innerHTML='<p class="err">'+esc(S.data.error)+'</p>';}
  S.types=new Set(TYPES);
  buildTabs();buildLegend();render();
}
async function loadGraphs(){
  const r=await fetch("/api/graphs");const j=await r.json();const g=j.graphs||[S.graph];
  if(!g.includes(S.graph))S.graph=j.current||g[0];
  $("#graph").innerHTML=g.map(x=>`<option ${x===S.graph?"selected":""}>${esc(x)}</option>`).join("");
}
async function loadBranches(){
  const r=await fetch("/api/branches?"+qg());const b=(await r.json()).branches||["main"];
  $("#branch").innerHTML=b.map(x=>`<option ${x===S.branch?"selected":""}>${esc(x)}</option>`).join("");
}
function buildTabs(){
  const t=[{id:"all",name:"All"},{id:"global",name:"Global",c:clusterColor("__global")}]
    .concat((S.data.projects||[]).map(p=>({id:p.id,name:p.name,c:clusterColor(p.id)})));   // tab dot = cluster color
  $("#tabs").innerHTML=t.map(x=>`<div class="tab ${x.id===S.tab?"on":""}" data-id="${esc(x.id)}">${x.c?`<span class=dot style="background:${x.c}"></span>`:""}${esc(x.name)}</div>`).join("");
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
/* ---------- force-directed graph: build DOM once, update positions per tick ---------- */
const NS="http://www.w3.org/2000/svg";
function svgPt(e){const r=$("#svg").getBoundingClientRect();return {x:e.clientX-r.left,y:e.clientY-r.top};}
function screenToGraph(sx,sy){return {x:(sx-S.vp.tx)/S.vp.k,y:(sy-S.vp.ty)/S.vp.k};}
function vpApply(){$("#viewport").setAttribute("transform",`translate(${S.vp.tx},${S.vp.ty}) scale(${S.vp.k})`);}
function edgeKey(e){return e.type+"|"+e.from+"|"+e.to;}
function ptSeg(px,py,ax,ay,bx,by){const dx=bx-ax,dy=by-ay,L=dx*dx+dy*dy||1;
  let t=((px-ax)*dx+(py-ay)*dy)/L;t=Math.max(0,Math.min(1,t));return Math.hypot(px-(ax+t*dx),py-(ay+t*dy));}
function nearestEdge(g){let best=null,bd=1e9;for(const e of (S.curLinks||[])){const a=S.pos[e.from],b=S.pos[e.to];
  if(!a||!b)continue;const d=ptSeg(g.x,g.y,a.x,a.y,b.x,b.y);if(d<bd){bd=d;best=e;}}return bd<25?best:null;}
function renderGraph(){
  const svg=$("#svg"),W=svg.clientWidth||800,H=svg.clientHeight||600;
  const vis=visibleNodes(),ids=new Set(vis.map(n=>n.id));
  const links=(S.data.edges||[]).filter(e=>ids.has(e.from)&&ids.has(e.to));
  S.curVis=vis;S.curLinks=links;
  S.cl=buildClusters(vis,W,H);                            // cluster colors + anchors for this view
  const prev=S.pos||{};S.pos={};
  vis.forEach(n=>{const p=prev[n.id],a=S.cl.info[clusterOf(n)].anchor;   // seed new nodes near their cluster
    S.pos[n.id]={x:p?p.x:a.x+(Math.random()-.5)*120,y:p?p.y:a.y+(Math.random()-.5)*120,vx:0,vy:0};});
  if(!S.vp)S.vp={tx:0,ty:0,k:1};
  if(S.sim)cancelAnimationFrame(S.sim);

  // build DOM once (persists across sim ticks so clicks/drag always work)
  const linkG=$("#links"),elG=$("#elabels"),nodeG=$("#nodes");
  linkG.innerHTML="";elG.innerHTML="";nodeG.innerHTML="";
  const linkEls=links.map(e=>{
    const ln=document.createElementNS(NS,"line");ln.setAttribute("class","link");
    const hit=document.createElementNS(NS,"line");hit.setAttribute("class","hit");
    hit.addEventListener("click",ev=>{ev.stopPropagation();
      const sp=svgPt(ev);onEdgeClick(nearestEdge(screenToGraph(sp.x,sp.y))||e);});
    const tx=document.createElementNS(NS,"text");tx.setAttribute("class","elabel");tx.textContent=e.type;
    linkG.append(ln,hit);elG.append(tx);return {e,ln,hit,tx};
  });
  const nodeEls=vis.map(n=>{
    const g=document.createElementNS(NS,"g");g.setAttribute("class","node");
    const r=n.type==="Project"?13:9;
    const c=document.createElementNS(NS,"circle");c.setAttribute("r",r);c.setAttribute("fill",COLOR(n.type));
    c.setAttribute("stroke",S.cl.info[clusterOf(n)].color);c.setAttribute("stroke-width",n.type==="Project"?3.5:2.5);  // project-cluster ring
    const t=document.createElementNS(NS,"text");t.setAttribute("x",r+3);t.setAttribute("y",4);t.textContent=(n.label||n.id).slice(0,22);
    g.append(c,t);nodeG.append(g);
    g.addEventListener("mousedown",ev=>{ev.stopPropagation();ev.preventDefault();
      const start=svgPt(ev);let moved=false;n._drag=1;
      const mv=e2=>{const sp=svgPt(e2);if(Math.hypot(sp.x-start.x,sp.y-start.y)>4)moved=true;
        const gp=screenToGraph(sp.x,sp.y);S.pos[n.id].x=gp.x;S.pos[n.id].y=gp.y;paint();};
      const up=()=>{n._drag=0;document.removeEventListener("mousemove",mv);document.removeEventListener("mouseup",up);
        if(!moved)onNodeClick(n);};   // moved little => it was a click, not a drag
      document.addEventListener("mousemove",mv);document.addEventListener("mouseup",up);});
    return {n,g};
  });
  S.els={linkEls,nodeEls};

  // zoom (wheel) + pan (drag empty space) — attach to the persistent svg
  svg.onwheel=ev=>{ev.preventDefault();const sp=svgPt(ev),g=screenToGraph(sp.x,sp.y);
    const f=ev.deltaY<0?1.1:1/1.1;S.vp.k=Math.max(.2,Math.min(4,S.vp.k*f));
    S.vp.tx=sp.x-g.x*S.vp.k;S.vp.ty=sp.y-g.y*S.vp.k;vpApply();};
  svg.onmousedown=ev=>{if(ev.target.closest(".node")||ev.target.classList.contains("hit"))return;
    ev.preventDefault();svg.classList.add("panning");
    const s={x:ev.clientX,y:ev.clientY,tx:S.vp.tx,ty:S.vp.ty};
    const mv=e2=>{S.vp.tx=s.tx+(e2.clientX-s.x);S.vp.ty=s.ty+(e2.clientY-s.y);vpApply();};
    const up=()=>{svg.classList.remove("panning");document.removeEventListener("mousemove",mv);document.removeEventListener("mouseup",up);};
    document.addEventListener("mousemove",mv);document.addEventListener("mouseup",up);};

  vpApply();applyHighlight();
  let ticks=0;
  (function tick(){
    const P=S.pos;
    for(let i=0;i<vis.length;i++)for(let j=i+1;j<vis.length;j++){
      const pa=P[vis[i].id],pb=P[vis[j].id];let dx=pa.x-pb.x,dy=pa.y-pb.y,d=Math.hypot(dx,dy)||1,f=3000/(d*d);
      pa.vx+=dx/d*f;pa.vy+=dy/d*f;pb.vx-=dx/d*f;pb.vy-=dy/d*f;}
    for(const e of links){const pa=P[e.from],pb=P[e.to];if(!pa||!pb)continue;
      let dx=pb.x-pa.x,dy=pb.y-pa.y,d=Math.hypot(dx,dy)||1,f=(d-90)*0.01;
      pa.vx+=dx/d*f;pa.vy+=dy/d*f;pb.vx-=dx/d*f;pb.vy-=dy/d*f;}
    for(const n of vis){const p=P[n.id];if(n._drag){p.vx=p.vy=0;continue;}
      const a=S.cl.multi?S.cl.info[clusterOf(n)].anchor:{x:W/2,y:H/2};   // pull toward cluster anchor
      p.vx+=(a.x-p.x)*0.012;p.vy+=(a.y-p.y)*0.012;p.x+=p.vx*=.85;p.y+=p.vy*=.85;}
    paint();
    if(++ticks<400)S.sim=requestAnimationFrame(tick);
  })();
}
function paint(){
  if(!S.els)return;const P=S.pos;
  for(const {e,ln,hit,tx} of S.els.linkEls){const a=P[e.from],b=P[e.to];if(!a||!b)continue;
    for(const L of [ln,hit]){L.setAttribute("x1",a.x);L.setAttribute("y1",a.y);L.setAttribute("x2",b.x);L.setAttribute("y2",b.y);}
    tx.setAttribute("x",(a.x+b.x)/2);tx.setAttribute("y",(a.y+b.y)/2);}
  for(const {n,g} of S.els.nodeEls){const p=P[n.id];g.setAttribute("transform",`translate(${p.x},${p.y})`);}
  paintHulls();
}
// translucent tinted circle + name behind each project cluster, so groups read at a glance
function paintHulls(){
  const hg=$("#hulls"),lg=$("#clabels");if(!hg||!S.cl)return;
  hg.innerHTML="";lg.innerHTML="";
  if(!S.cl.multi)return;                                  // single cluster => no hull needed
  const by={};for(const {n} of S.els.nodeEls){const p=S.pos[n.id];if(!p)continue;(by[clusterOf(n)]=by[clusterOf(n)]||[]).push(p);}
  for(const cid of S.cl.ids){const pts=by[cid];if(!pts||!pts.length)continue;
    let cx=0,cy=0;for(const p of pts){cx+=p.x;cy+=p.y;}cx/=pts.length;cy/=pts.length;
    let rad=0;for(const p of pts)rad=Math.max(rad,Math.hypot(p.x-cx,p.y-cy));rad+=34;
    const col=S.cl.info[cid].color;
    const ci=document.createElementNS(NS,"circle");ci.setAttribute("cx",cx);ci.setAttribute("cy",cy);ci.setAttribute("r",rad);
    ci.setAttribute("fill",col);ci.setAttribute("fill-opacity",".06");ci.setAttribute("stroke",col);
    ci.setAttribute("stroke-opacity",".55");ci.setAttribute("stroke-width","1.5");ci.setAttribute("stroke-dasharray","6 5");hg.append(ci);
    const tx=document.createElementNS(NS,"text");tx.setAttribute("x",cx);tx.setAttribute("y",cy-rad-7);
    tx.setAttribute("class","clabel");tx.setAttribute("fill",col);tx.textContent=S.cl.info[cid].name;lg.append(tx);}
}
function onNodeClick(n){if(S.q)toggleRemoved(n.id);showNode(n,S.curLinks);}
function onEdgeClick(e){if(S.q)toggleRemoved(edgeKey(e));showEdge(e.type,e.from,e.to);}
function toggleRemoved(key){if(!S.removed)S.removed=new Set();S.removed.has(key)?S.removed.delete(key):S.removed.add(key);applyHighlight();}
function applyHighlight(){
  if(!S.els)return;const q=S.q,rm=S.removed||new Set();
  for(const {n,g} of S.els.nodeEls){const isM=q&&matches(n);const hl=isM&&!rm.has(n.id);
    g.classList.toggle("hl",!!hl);g.classList.toggle("dim",!!(q&&!isM));
    if(hl)g.parentNode.appendChild(g);}   // raise matched nodes above the rest
  for(const {e,ln,hit,tx} of S.els.linkEls){
    const fn=S.data.nodes.find(x=>x.id===e.from),tn=S.data.nodes.find(x=>x.id===e.to);
    const isM=q&&((fn&&matches(fn))||(tn&&matches(tn)));const hl=isM&&!rm.has(edgeKey(e));
    ln.classList.toggle("hl",!!hl);ln.classList.toggle("dim",!!(q&&!isM));
    if(hl){ln.parentNode.appendChild(ln);hit.parentNode.appendChild(hit);tx.parentNode.appendChild(tx);}}
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
function whyMatch(node){ // when searching, show WHERE the term hit (or "" if it doesn't)
  if(!S.q||!node)return "";const q=S.q.toLowerCase();
  for(const [k,v] of Object.entries(node.fields||{})){
    if(k==="embedding")continue;const s=String(v).toLowerCase();const i=s.indexOf(q);
    if(i>=0)return `${node.id}.${k}: …${esc(String(v).slice(Math.max(0,i-15),i+q.length+25))}…`;}
  return "";
}
function showEdge(type,from,to){
  const fn=(S.data.nodes||[]).find(n=>n.id===from),tn=(S.data.nodes||[]).find(n=>n.id===to);
  const why=whyMatch(fn)||whyMatch(tn);
  const note=S.q?`<div class="k">search "${esc(S.q)}"</div><div class="v">${why?("highlighted because "+why):"<span class=muted>not matched — highlighted edges connect a node that matches</span>"}</div>`:"";
  $("#side").innerHTML=`<span class="pill" style="background:var(--acc)">edge</span><h3>${esc(type)}</h3>
    <div class="k">from</div><div class="v">${esc(from)} <span class="muted">(${esc(fn?fn.type:"?")})</span></div>
    <div class="k">to</div><div class="v">${esc(to)} <span class="muted">(${esc(tn?tn.type:"?")})</span></div>
    <div class="k">meaning</div><div class="v">${esc(EDGE_DOC[type]||"relationship")}</div>${note}`;
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
$("#search").oninput=e=>{S.q=e.target.value;S.removed=new Set();if(S.view==="graph")applyHighlight();else renderTable();};
$("#branch").onchange=e=>{S.branch=e.target.value;S.pos=null;S.vp=null;load();};
// switching graph = switching project (isolated store): reset view, reload its branches + data
$("#graph").onchange=async e=>{S.graph=e.target.value;S.branch="main";S.tab="all";S.pos=null;S.vp=null;await loadBranches();load();};
window.addEventListener("resize",()=>{if(S.view==="graph")renderGraph();});
loadGraphs().then(loadBranches).then(load);
</script></body></html>"""
