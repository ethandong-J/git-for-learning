"""Git-for-Learning: a REPL where the conversation is a tree, not a transcript."""
import os;
import sys;
import from jaclang.byllm.lib { Model, MockLLM }

# The conversation lives entirely on the object-spatial graph:
#   Turn nodes hang off root; a Child edge is a follow-up (the TREE),
#   a Ref edge cross-links related turns on other branches (the GRAPH).
node Turn {
    has id: int;
    has question: str;
    has answer: str;
}

edge Child {}
edge Ref {}

glob next_id: int = 0;
glob cursor: int = 0;

glob mock_flag: bool = (os.getenv("GFL_MOCK", "0") == "1") or ("--mock" in sys.argv);
glob model_name: str = os.getenv("GFL_MODEL", "");
glob use_mock: bool = mock_flag or model_name == "" or model_name == "mockllm";

glob llm: any = MockLLM(model_name="mockllm", config={"outputs": [
    "A byte is a unit of digital information made up of 8 bits, used to represent a single character of text.",
    "Since a byte is 8 bits, the answer is 8 bits.",
    "Unicode is a character-encoding standard; each character maps to a code point, which is then encoded into bytes (often via UTF-8).",
    "Bits-thread summary: we covered what a byte is (8 bits of digital information) and confirmed a byte equals 8 bits.",
    "Unicode-thread summary: we covered what a byte is and how it relates to Unicode, where code points are encoded into bytes.",
    ["Why do computers use binary instead of decimal?", "What is a nibble?", "How many bytes are in a kilobyte?"],
    "Computers use binary because transistors have two stable states (on/off), making two-valued logic cheap and reliable in hardware.",
    "Both threads trace back to the same byte definition: one explored bit-counting, the other character encoding - bytes are the shared unit underneath.",
]}) if use_mock else Model(model_name=model_name);

def continue_dialogue(transcript: str, question: str) -> str by llm();
sem continue_dialogue = """
Continue this tutoring dialogue. Answer the new question using ONLY the
prior conversation as context. Be concise (under 120 words).
""";
sem continue_dialogue.transcript = "The prior Q/A turns on this branch, oldest first.";
sem continue_dialogue.question = "The new follow-up question to answer.";

def propose_followups(transcript: str) -> list[str] by llm();
sem propose_followups = """
Propose exactly 3 distinct, concise follow-up questions a student might ask
next, based on this tutoring dialogue so far.
""";
sem propose_followups.transcript = "The prior Q/A turns on this branch, oldest first.";

def build_transcript(history: list[tuple[str, str]], related: list[tuple[str, str]]) -> str {
    chronological = history[::-1];
    lines: list[str] = [];
    for (q, a) in chronological {
        lines.append(f"Q: {q}\nA: {a}");
    }
    if related {
        lines.append("Related context:");
        for (q, a) in related {
            lines.append(f"Q: {q}\nA: {a}");
        }
    }
    return "\n".join(lines);
}

def print_tree(nd: any, depth: int) {
    children = [nd ->:Child:-> [?:Turn]];
    for child in children {
        marker = "*" if child.id == cursor else " ";
        indent = "  " * depth;
        preview = child.question[:50];
        print(f"{marker}{indent}[{child.id}] {preview}");
        print_tree(child, depth + 1);
    }
}

# Object-spatial lookup: instead of a Python-side {id: node} dict, a walker
# descends the graph from root and finds the node by id. The lookup itself
# is a graph traversal - computation moves to the data.
walker Locate {
    has target_id: int;
    has found: Turn | None = None;

    can seed with Root entry {
        visit [->:Child:-> [?:Turn]];
    }

    can scan with Turn entry {
        if here.id == self.target_id {
            self.found = here;
            disengage;
        }
        visit [->:Child:-> [?:Turn]];
    }
}

def find_node(n: int) -> Turn | None {
    w = root spawn Locate(target_id=n);
    return w.found;
}

walker Ask {
    has question: str;
    has origin: Turn | None = None;
    has history: list[tuple[str, str]] = [];
    has related: list[tuple[str, str]] = [];
    has answer_text: str = "";
    has new_id: int = 0;

    # Climb UP the ancestor chain, collecting this branch's turns plus any
    # Ref-linked neighbours, then generate the answer once we reach root.
    can climb with Turn entry {
        if self.origin is None {
            self.origin = here;
        }
        self.history.append((here.question, here.answer));
        refs_out = [here ->:Ref:-> [?:Turn]];
        for r in refs_out {
            self.related.append((r.question, r.answer));
        }
        refs_in = [here <-:Ref:<- [?:Turn]];
        for r in refs_in {
            self.related.append((r.question, r.answer));
        }
        visit [<-:Child:<-];
    }

    can answer with Root entry {
        transcript = build_transcript(self.history, self.related);
        self.answer_text = continue_dialogue(transcript, self.question);

        next_id += 1;
        new_turn = Turn(id=next_id, question=self.question, answer=self.answer_text);
        parent = root if self.origin is None else self.origin;
        parent +>: Child() :+> new_turn;

        self.new_id = next_id;
        cursor = next_id;
    }
}

walker Propose {
    has origin: Turn | None = None;
    has history: list[tuple[str, str]] = [];
    has related: list[tuple[str, str]] = [];
    has created: list[Turn] = [];

    can climb with Turn entry {
        if self.origin is None {
            self.origin = here;
        }
        self.history.append((here.question, here.answer));
        refs_out = [here ->:Ref:-> [?:Turn]];
        for r in refs_out {
            self.related.append((r.question, r.answer));
        }
        refs_in = [here <-:Ref:<- [?:Turn]];
        for r in refs_in {
            self.related.append((r.question, r.answer));
        }
        visit [<-:Child:<-];
    }

    can propose with Root entry {
        transcript = build_transcript(self.history, self.related);
        questions = propose_followups(transcript);
        parent = root if self.origin is None else self.origin;
        for q in questions {
            next_id += 1;
            new_turn = Turn(id=next_id, question=q, answer="");
            parent +>: Child() :+> new_turn;
            self.created.append(new_turn);
        }
    }
}

# Resume the id counter from the persisted graph so a reopened session
# doesn't mint ids that collide with existing nodes.
walker HighWater {
    has max_id: int = 0;

    can from_root with Root entry {
        visit [->:Child:-> [?:Turn]];
    }

    can scan with Turn entry {
        if here.id > self.max_id {
            self.max_id = here.id;
        }
        visit [->:Child:-> [?:Turn]];
    }
}

# Session frontier: walk the whole tree, collect the leaf Turns (open threads).
walker Frontier {
    has leaves: list[Turn] = [];

    can from_root with Root entry {
        visit [->:Child:-> [?:Turn]];
    }

    can check with Turn entry {
        kids = [here ->:Child:-> [?:Turn]];
        if not kids {
            self.leaves.append(here);
        }
        visit [->:Child:-> [?:Turn]];
    }
}

def report_ask(w: Ask) {
    if w.new_id > 0 {
        print(f"[{w.new_id}] {w.answer_text}");
    } else {
        print("error: no response");
    }
}

def do_ask(question: str) {
    if cursor == 0 {
        report_ask(root spawn Ask(question=question));
    } else {
        target = find_node(cursor);
        if target is None {
            print(f"cursor node {cursor} not found");
            return;
        }
        report_ask(target spawn Ask(question=question));
    }
}

def do_goto(n: int) {
    if n == 0 {
        cursor = 0;
        print("cursor -> 0 (root)");
    } elif find_node(n) is not None {
        cursor = n;
        print(f"cursor -> {n}");
    } else {
        print(f"no such node: {n}");
    }
}

def do_tree {
    print("tree:");
    print_tree(root, 0);
}

def do_link(a: int, b: int) {
    na = find_node(a);
    nb = find_node(b);
    if na is not None and nb is not None {
        na +>: Ref() :+> nb;
        print(f"linked {a} <-> {b}");
    } else {
        print("no such node(s)");
    }
}

def report_propose(w: Propose) {
    if w.created {
        print("proposed follow-ups (goto <id> then ask to pursue):");
        for opt in w.created {
            print(f"  [{opt.id}] {opt.question}");
        }
    } else {
        print("error: no proposals");
    }
}

def do_spawn {
    if cursor == 0 {
        report_propose(root spawn Propose());
    } else {
        target = find_node(cursor);
        if target is None {
            print(f"cursor node {cursor} not found");
            return;
        }
        report_propose(target spawn Propose());
    }
}

def print_frontier {
    w = root spawn Frontier();
    if w.leaves {
        print("open threads:");
        for lf in w.leaves {
            preview = lf.question[:50];
            print(f"  [{lf.id}] {preview}");
        }
    }
}

with entry:__main__ {
    print("Git-for-Learning REPL. Commands: ask <text> | goto <n> | tree | link <a> <b> | spawn | quit");
    hw = root spawn HighWater();
    next_id = hw.max_id;
    print_frontier();
    while True {
        try {
            line = input("> ").strip();
        } except EOFError {
            break;
        }
        if line == "" {
            continue;
        } elif line == "quit" {
            break;
        } elif line == "tree" {
            do_tree();
        } elif line == "spawn" {
            do_spawn();
        } elif line.startswith("ask ") {
            do_ask(line[4:]);
        } elif line.startswith("goto ") {
            do_goto(int(line[5:].strip()));
        } elif line.startswith("link ") {
            parts = line[5:].strip().split();
            if len(parts) == 2 {
                do_link(int(parts[0]), int(parts[1]));
            } else {
                print("usage: link <a> <b>");
            }
        } else {
            print(f"unknown command: {line}");
        }
    }
}
