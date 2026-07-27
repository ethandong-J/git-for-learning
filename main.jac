"""Git-for-Learning: a REPL where the conversation is a tree, not a transcript."""
import os;
import sys;
import from jaclang.byllm.lib { Model, MockLLM }

node Turn {
    has id: int;
    has question: str;
    has answer: str;
}

obj AskResult {
    has answer: str;
    has new_id: int;
}

glob next_id: int = 0;
glob node_by_id: dict[int, Turn] = {};
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
]}) if use_mock else Model(model_name=model_name);

def continue_dialogue(transcript: str, question: str) -> str by llm();
sem continue_dialogue = """
Continue this tutoring dialogue. Answer the new question using ONLY the
prior conversation as context. Be concise (under 120 words).
""";
sem continue_dialogue.transcript = "The prior Q/A turns on this branch, oldest first.";
sem continue_dialogue.question = "The new follow-up question to answer.";

def build_transcript(history: list[tuple[str, str]]) -> str {
    chronological = history[::-1];
    lines: list[str] = [];
    for (q, a) in chronological {
        lines.append(f"Q: {q}\nA: {a}");
    }
    return "\n".join(lines);
}

def print_tree(nd: any, depth: int) {
    children = [nd --> [?:Turn]];
    for child in children {
        marker = "*" if child.id == cursor else " ";
        indent = "  " * depth;
        preview = child.question[:50];
        print(f"{marker}{indent}[{child.id}] {preview}");
        print_tree(child, depth + 1);
    }
}

walker Ask {
    has question: str;
    has origin: Turn | None = None;
    has history: list[tuple[str, str]] = [];
    has reports: list[AskResult] = [];

    can climb with Turn entry {
        if self.origin is None {
            self.origin = here;
        }
        self.history.append((here.question, here.answer));
        visit [<--];
    }

    can answer with Root entry {
        transcript = build_transcript(self.history);
        answer_text = continue_dialogue(transcript, self.question);

        next_id += 1;
        new_turn = Turn(id=next_id, question=self.question, answer=answer_text);
        node_by_id[next_id] = new_turn;

        if self.origin is None {
            root ++> new_turn;
        } else {
            self.origin ++> new_turn;
        }

        cursor = next_id;
        report AskResult(answer=answer_text, new_id=next_id);
    }
}

def do_ask(question: str) {
    target = node_by_id[cursor] if cursor != 0 else root;
    result = target spawn Ask(question=question);
    if result.reports {
        r = result.reports[0];
        print(f"[{r.new_id}] {r.answer}");
    } else {
        print("error: no response");
    }
}

def do_goto(n: int) {
    if n == 0 {
        cursor = 0;
        print("cursor -> 0 (root)");
    } elif n in node_by_id {
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

with entry:__main__ {
    print("Git-for-Learning REPL. Commands: ask <text> | goto <n> | tree | quit");
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
        } elif line.startswith("ask ") {
            do_ask(line[4:]);
        } elif line.startswith("goto ") {
            do_goto(int(line[5:].strip()));
        } else {
            print(f"unknown command: {line}");
        }
    }
}
