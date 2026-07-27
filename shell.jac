"""Client UI: the two-panel study app, compiled from Jac to React.

Left: the knowledge tree (every question, branching where you forked, cursor
highlighted). Right: the conversation at the node you're standing on - the
exact ancestor lineage that generated the current answer - plus the ask box.
"""
sv import from .study { get_tree, ask_from, propose_from, link_nodes, TurnView, AskReply }

glob EXAMPLES: list[str] = [
    "Explain backpropagation like I've seen the equations but don't get it",
    "What actually is an eigenvector, intuitively?",
    "Why does attention in transformers work?",
    "What is entropy in information theory, really?",
];

def:pub StudyShell() -> JsxElement {
    has tree: list[TurnView] = [];
    has cursor: int = 0;
    has draft: str = "";
    has loading: bool = False;
    has link_src: int = -1;

    async can with entry {
        tree = await get_tree();
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

    return <div className="app">
        <header className="topbar">
            <div className="brand">Branch</div>
            <div className="tagline">Chat gives you a transcript. This gives you a map — the answer depends on where you're standing.</div>
        </header>
        <div className="body">
            <aside className="sidebar">
                <div className="sidebar-head">
                    <span>Knowledge tree</span>
                    <button className="ghost" onClick={lambda (e: MouseEvent) { on_node(0); }}>root</button>
                </div>
                {if len(tree) == 0 {
                    <div className="empty">No branches yet. Ask something on the right to plant the first node.</div>
                    skip;
                }}
                {for v in tree {
                    <button key={str(v.id)}
                            className={tree_class(v.id, cursor, v.answer)}
                            style={{"paddingLeft": str(12 + v.depth * 18) + "px"}}
                            onClick={lambda (e: MouseEvent) { on_node(v.id); }}>
                        <span className="node-id">{str(v.id)}</span>
                        <span className="node-q">{v.question}</span>
                    </button>
                }}
            </aside>
            <main className="main">
                {if link_src >= 0 {
                    <div className="linkbar">
                        Linking from node {str(link_src)} — click any tree node to connect it.
                        <button className="ghost" onClick={cancel_link}>cancel</button>
                    </div>
                }}
                <div className="thread">
                    {if cursor == 0 {
                        <div className="standing">You are at the root. Ask about a concept you're stuck on.</div>
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
            </main>
        </div>
    </div>;
}

def tree_class(id: int, cursor: int, answer: str) -> str {
    base = "node";
    if id == cursor {
        base = base + " current";
    }
    if answer == "" {
        base = base + " proposed";
    }
    return base;
}

def turn_class(id: int, cursor: int) -> str {
    return "turn current" if id == cursor else "turn";
}

def compose_hint(cursor: int) -> str {
    return "Ask about a concept you're stuck on…" if cursor == 0 else "Ask a follow-up from where you're standing…";
}
