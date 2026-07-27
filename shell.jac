"""Client UI: the knowledge MAP (clickable node-graph) + a conversation panel.

Left: an SVG graph of Turn nodes connected by their Child edges - branches
fan out spatially, the current node and its lineage are highlighted, click any
node to stand there. Right: the conversation at the node you're standing on
(its exact ancestor lineage) plus the ask box. Hand-rolled SVG, all Jac.
"""
sv import from .study { get_tree, ask_from, propose_from, link_nodes, TurnView, AskReply }

glob EXAMPLES: list[str] = [
    "Explain backpropagation like I've seen the equations but don't get it",
    "What actually is an eigenvector, intuitively?",
    "Why does attention in transformers work?",
    "What is entropy in information theory, really?",
];

# layout constants (px)
glob COLW: float = 190.0;
glob ROWH: float = 120.0;
glob MX: float = 110.0;
glob TOPY: float = 54.0;

def:pub StudyShell() -> JsxElement {
    has tree: list[TurnView] = [];
    has cursor: int = 0;
    has draft: str = "";
    has loading: bool = False;
    has link_src: int = -1;

    async can with entry {
        tree = await get_tree();
    }

    def lineage_ids() -> list[int] {
        by_id: dict[int, TurnView] = {};
        for v in tree {
            by_id[v.id] = v;
        }
        ids: list[int] = [0];
        cur: int = cursor;
        while cur != 0 and cur in by_id {
            ids.append(cur);
            cur = by_id[cur].parent;
        }
        return ids;
    }

    def path_to_cursor() -> list[TurnView] {
        by_id: dict[int, TurnView] = {};
        for v in tree {
            by_id[v.id] = v;
        }
        chain: list[TurnView] = [];
        cur: int = cursor;
        while cur != 0 and cur in by_id {
            nd = by_id[cur];
            chain = [nd] + chain;
            cur = nd.parent;
        }
        return chain;
    }

    async def submit_ask() {
        q = draft.strip();
        if q == "" or loading {
            return;
        }
        loading = True;
        draft = "";
        reply = await ask_from(cursor, q);
        tree = await get_tree();
        cursor = reply.id;
        loading = False;
    }

    async def do_propose() {
        if loading {
            return;
        }
        loading = True;
        _made = await propose_from(cursor);
        tree = await get_tree();
        loading = False;
    }

    async def on_node(nid: int) {
        if link_src >= 0 and nid != link_src {
            _ok = await link_nodes(link_src, nid);
            link_src = -1;
            tree = await get_tree();
        } else {
            cursor = nid;
        }
    }

    def start_link(e: MouseEvent) {
        link_src = cursor;
    }

    def cancel_link(e: MouseEvent) {
        link_src = -1;
    }

    def on_input(e: ChangeEvent) {
        draft = e.target.value;
    }

    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            submit_ask();
        }
    }

    def pick_example(text: str) {
        draft = text;
    }

    pos = layout(tree);
    pids = lineage_ids();

    return <div className="app">
        <header className="topbar">
            <div className="brand">Branch</div>
            <div className="tagline">Chat gives you a transcript. This gives you a map — the answer depends on where you're standing.</div>
        </header>
        <div className="body">
            <section className="graph">
                {if link_src >= 0 {
                    <div className="linkbar">Linking from node {str(link_src)} — click any node to connect it.
                        <button className="ghost" onClick={cancel_link}>cancel</button>
                    </div>
                }}
                {if len(tree) == 0 {
                    <div className="empty">Your map is empty. Ask a question on the right to plant the first node — then jump back to it and ask something different to watch it branch.</div>
                } else {
                    <div className="canvas">
                        <svg width={graph_w(tree, pos)} height={graph_h(tree, pos)}>
                            {for v in tree {
                                <path key={"e" + str(v.id)}
                                      className={edge_class(v.id, v.parent, pids)}
                                      d={edge_path(pos, v.parent, v.id)}
                                      fill="none" />
                            }}
                            <g className={root_class(pids)}
                               transform={node_tf(pos, 0)}
                               onClick={lambda (e: MouseEvent) { on_node(0); }}>
                                <circle r={18} />
                                <text className="gid" x={0} y={4} textAnchor="middle">root</text>
                            </g>
                            {for v in tree {
                                <g key={"n" + str(v.id)}
                                   className={node_class(v.id, cursor, pids, v.answer)}
                                   transform={node_tf(pos, v.id)}
                                   onClick={lambda (e: MouseEvent) { on_node(v.id); }}>
                                    <title>{v.question}</title>
                                    <rect x={-84} y={-26} width={168} height={52} rx={10} />
                                    <text className="gnum" x={-72} y={-10}>{"#" + str(v.id)}</text>
                                    <text className="gq" x={-72} y={10}>{trunc(v.question, 22)}</text>
                                </g>
                            }}
                        </svg>
                    </div>
                }}
            </section>
            <aside className="side">
                <div className="side-head">
                    {"Standing at root" if cursor == 0 else "Standing at node " + str(cursor)}
                </div>
                <div className="thread">
                    {if cursor == 0 and len(tree) > 0 {
                        <div className="standing">Pick a node on the map, or ask a new root-level question below.</div>
                    }}
                    {for v in path_to_cursor() {
                        <div key={str(v.id)} className={turn_class(v.id, cursor)}>
                            <div className="turn-q">{v.question}</div>
                            {if v.answer == "" {
                                <div className="turn-a muted">not yet explored — ask below to pursue this</div>
                            } else {
                                <div className="turn-a">{v.answer}</div>
                            }}
                        </div>
                    }}
                    {if loading {
                        <div className="thinking">thinking…</div>
                    }}
                </div>
                {if len(tree) == 0 {
                    <div className="examples">
                        {for ex in EXAMPLES {
                            <button key={ex} className="chip" onClick={lambda (e: MouseEvent) { pick_example(ex); }}>{ex}</button>
                        }}
                    </div>
                }}
                <div className="composer">
                    <textarea className="input"
                              value={draft}
                              placeholder={compose_hint(cursor)}
                              onChange={on_input}
                              onKeyDown={on_key} />
                    <div className="actions">
                        <button className="ghost" onClick={lambda (e: MouseEvent) { do_propose(); }}>suggest forks</button>
                        <button className="ghost" onClick={start_link}>link from here</button>
                        <button className="primary" onClick={lambda (e: MouseEvent) { submit_ask(); }}>ask</button>
                    </div>
                </div>
            </aside>
        </div>
    </div>;
}

# --- layout + rendering helpers ---------------------------------------------

def build_children(tree: list[TurnView]) -> dict[int, list[int]] {
    kids: dict[int, list[int]] = {0: []};
    for v in tree {
        if v.id not in kids {
            kids[v.id] = [];
        }
    }
    for v in tree {
        if v.parent not in kids {
            kids[v.parent] = [];
        }
        kids[v.parent].append(v.id);
    }
    return kids;
}

def _place(nid: int, depth: int, kids: dict[int, list[int]], pos: dict[int, dict[str, float]], counter: list[int]) {
    cs = kids[nid] if nid in kids else [];
    if len(cs) == 0 {
        pos[nid] = {"x": counter[0] * 1.0, "y": depth * 1.0};
        counter[0] = counter[0] + 1;
    } else {
        for c in cs {
            _place(c, depth + 1, kids, pos, counter);
        }
        first = pos[cs[0]]["x"];
        last = pos[cs[len(cs) - 1]]["x"];
        pos[nid] = {"x": (first + last) / 2.0, "y": depth * 1.0};
    }
}

def layout(tree: list[TurnView]) -> dict[int, dict[str, float]] {
    kids = build_children(tree);
    pos: dict[int, dict[str, float]] = {};
    counter: list[int] = [0];
    tops = kids[0] if 0 in kids else [];
    for t in tops {
        _place(t, 1, kids, pos, counter);
    }
    if len(tops) > 0 {
        rx = (pos[tops[0]]["x"] + pos[tops[len(tops) - 1]]["x"]) / 2.0;
        pos[0] = {"x": rx, "y": 0.0};
    } else {
        pos[0] = {"x": 0.0, "y": 0.0};
    }
    return pos;
}

def node_tf(pos: dict[int, dict[str, float]], nid: int) -> str {
    px = MX + (pos[nid]["x"] as float) * COLW;
    py = TOPY + (pos[nid]["y"] as float) * ROWH;
    return "translate(" + str(px) + "," + str(py) + ")";
}

def edge_path(pos: dict[int, dict[str, float]], p: int, c: int) -> str {
    x1 = MX + (pos[p]["x"] as float) * COLW;
    y1 = TOPY + (pos[p]["y"] as float) * ROWH + 24.0;
    x2 = MX + (pos[c]["x"] as float) * COLW;
    y2 = TOPY + (pos[c]["y"] as float) * ROWH - 26.0;
    my = (y1 + y2) / 2.0;
    return "M " + str(x1) + " " + str(y1) + " C " + str(x1) + " " + str(my) + " " + str(x2) + " " + str(my) + " " + str(x2) + " " + str(y2);
}

def graph_w(tree: list[TurnView], pos: dict[int, dict[str, float]]) -> float {
    m = 0.0;
    for v in tree {
        xv = pos[v.id]["x"] as float;
        if xv > m {
            m = xv;
        }
    }
    return MX * 2.0 + m * COLW + 180.0;
}

def graph_h(tree: list[TurnView], pos: dict[int, dict[str, float]]) -> float {
    m = 0.0;
    for v in tree {
        yv = pos[v.id]["y"] as float;
        if yv > m {
            m = yv;
        }
    }
    return TOPY * 2.0 + m * ROWH + 80.0;
}

def trunc(s: str, n: int) -> str {
    return s if len(s) <= n else s[:n] + "…";
}

def node_class(nid: int, cursor: int, pids: list[int], answer: str) -> str {
    base = "gnode";
    if nid == cursor {
        base = base + " current";
    } elif nid in pids {
        base = base + " onpath";
    }
    if answer == "" {
        base = base + " proposed";
    }
    return base;
}

def root_class(pids: list[int]) -> str {
    return "groot onpath" if 0 in pids else "groot";
}

def edge_class(cid: int, parent: int, pids: list[int]) -> str {
    return "gedge onpath" if (cid in pids and parent in pids) else "gedge";
}

def turn_class(nid: int, cursor: int) -> str {
    return "turn current" if nid == cursor else "turn";
}

def compose_hint(cursor: int) -> str {
    return "Ask about a concept you're stuck on…" if cursor == 0 else "Ask a follow-up from where you're standing…";
}
