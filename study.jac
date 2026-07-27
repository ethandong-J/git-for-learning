"""Backend: the object-spatial knowledge graph + RPC endpoints for the web UI.

The conversation is a graph on `root`: Turn nodes joined by Child edges (the
tree of follow-ups) and Ref edges (cross-branch links). Walkers traverse it;
def:pub functions wrap them as the client's typed RPC surface. Anonymous
callers share one guest graph - fine for a single-user local demo, no auth.
"""
import os;
import from jaclang.byllm.lib { Model, MockLLM }

node Turn {
    has id: int;
    has question: str;
    has answer: str;
}

edge Child {}
edge Ref {}

# What crosses the wire to the client - hydrated as typed instances.
obj TurnView {
    has id: int;
    has question: str;
    has answer: str;
    has parent: int;
    has depth: int;
}

obj AskReply {
    has id: int;
    has answer: str;
}

glob model_name: str = os.getenv("GFL_MODEL", "");
glob use_mock: bool = (os.getenv("GFL_MOCK", "0") == "1") or model_name == "" or model_name == "mockllm";

glob llm: any = MockLLM(model_name="mockllm", config={"outputs": [
    "Backpropagation computes how much each weight contributed to the error by applying the chain rule backwards through the network, layer by layer.",
    "The chain rule lets you multiply local derivatives along a path: dLoss/dw = dLoss/dout * dout/dnet * dnet/dw. Each layer just passes its gradient back.",
    "Gradients vanish when many small derivatives (<1) multiply together across deep layers, shrinking the signal toward zero so early layers barely learn.",
    "Both threads are the same mechanism from two angles: the chain rule is WHY backprop works, vanishing gradients are what happens when that chain-rule product decays.",
    "A computational graph is the network written as nodes (operations) and edges (data flow); backprop is just reverse-mode differentiation walking that graph.",
    "(mock) That builds directly on the point above — here is the concise intuition you asked for.",
    "(mock) Good follow-up. In short: it follows from what we just established, one step further.",
    "(mock) Think of it as the same idea viewed from a slightly different angle.",
]}) if use_mock else Model(model_name=model_name);

# propose_followups returns list[str]; give it its own mock so canned outputs
# are always lists (a shared string-mock would be iterated char-by-char).
glob llm_propose: any = MockLLM(model_name="mockllm", config={"outputs": [
    ["Where does the chain rule actually enter here?", "Why do gradients vanish in deep networks?", "What is a computational graph?"],
    ["Can you show a tiny numeric example?", "How does this differ from forward-mode?", "What breaks if we skip this step?"],
    ["What's the one-sentence intuition?", "When does this approach fail?", "How is this used in practice?"],
]}) if use_mock else Model(model_name=model_name);

def continue_dialogue(transcript: str, question: str) -> str by llm();
sem continue_dialogue = """
You are a patient tutor helping someone who is stuck on a concept. Answer the
new question using ONLY the prior conversation as context, building on exactly
what was already said. Be concrete and concise (under 120 words). Prefer an
intuition or a small example over restating a definition.
""";
sem continue_dialogue.transcript = "The prior Q/A turns on this branch, oldest first.";
sem continue_dialogue.question = "The new follow-up question to answer.";

def propose_followups(transcript: str) -> list[str] by llm_propose();
sem propose_followups = """
Propose exactly 3 distinct follow-up questions that would deepen understanding
of this concept - the kind a confused learner should ask next. Concise.
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

# --- Walkers: object-spatial traversal engines ------------------------------

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

# Emit the whole tree in DFS order with depth + parent id for rendering.
walker TreeView {
    has views: list[TurnView] = [];
    has stack: list[tuple[Turn, int, int]] = [];

    can from_root with Root entry {
        children = [here ->:Child:-> [?:Turn]];
        for c in children[::-1] {
            self.stack.append((c, 0, 0));
        }
        while self.stack {
            (nd, parent, depth) = self.stack.pop();
            self.views.append(TurnView(id=nd.id, question=nd.question, answer=nd.answer, parent=parent, depth=depth));
            kids = [nd ->:Child:-> [?:Turn]];
            for k in kids[::-1] {
                self.stack.append((k, nd.id, depth + 1));
            }
        }
    }
}

walker Ask {
    has question: str;
    has assign_id: int;
    has origin: Turn | None = None;
    has history: list[tuple[str, str]] = [];
    has related: list[tuple[str, str]] = [];
    has answer_text: str = "";

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
        new_turn = Turn(id=self.assign_id, question=self.question, answer=self.answer_text);
        parent = root if self.origin is None else self.origin;
        parent +>: Child() :+> new_turn;
    }
}

walker Propose {
    has base_id: int;
    has origin: Turn | None = None;
    has history: list[tuple[str, str]] = [];
    has related: list[tuple[str, str]] = [];
    has created: list[TurnView] = [];

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
        parent_id = 0 if self.origin is None else self.origin.id;
        i = 0;
        for q in questions {
            nid = self.base_id + i;
            new_turn = Turn(id=nid, question=q, answer="");
            parent +>: Child() :+> new_turn;
            self.created.append(TurnView(id=nid, question=q, answer="", parent=parent_id, depth=0));
            i += 1;
        }
    }
}

# --- Helpers ----------------------------------------------------------------

def _next_id() -> int {
    hw = root spawn HighWater();
    return hw.max_id + 1;
}

# --- def:pub RPC endpoints (the client's typed surface) ---------------------

def:pub get_tree() -> list[TurnView] {
    w = root spawn TreeView();
    return w.views;
}

def:pub ask_from(node_id: int, question: str) -> AskReply {
    new_id = _next_id();
    target = root if node_id == 0 else find_node(node_id);
    if target is None {
        return AskReply(id=0, answer="(target node not found)");
    }
    w = target spawn Ask(question=question, assign_id=new_id);
    return AskReply(id=new_id, answer=w.answer_text);
}

def:pub propose_from(node_id: int) -> list[TurnView] {
    base = _next_id();
    target = root if node_id == 0 else find_node(node_id);
    if target is None {
        return [];
    }
    w = target spawn Propose(base_id=base);
    return w.created;
}

def:pub link_nodes(a: int, b: int) -> bool {
    na = find_node(a);
    nb = find_node(b);
    if na is not None and nb is not None {
        na +>: Ref() :+> nb;
        return True;
    }
    return False;
}

def find_node(n: int) -> Turn | None {
    w = root spawn Locate(target_id=n);
    return w.found;
}

# One-call demo seed: a realistic long study session on transformers, written
# directly to the graph (NO LLM calls, zero tokens). Each root answer is dense
# and assumes things the learner doesn't know - so they fork to unpack each.
def:pub seed_demo() -> int {
    turns: list[tuple[str, str, int]] = [
        ("How do transformers actually work?",
         "A transformer processes all tokens at once using self-attention: every token builds a query, key, and value vector, attends to every other token via scaled dot-product attention through a softmax, and this runs in parallel across multiple heads. Positional encodings inject word order, and the whole block is stacked with residual connections and layer norm.",
         0),
        ("What are the query, key, and value vectors?",
         "Each token's embedding is multiplied by three learned weight matrices to produce a query (what this token is looking for), a key (what this token offers), and a value (the information it passes on if attended to). They're just linear projections of the same input into three different roles.",
         1),
        ("Why three separate vectors instead of one?",
         "Splitting roles lets a token ask a different question (query) than the signature it advertises (key), and carry yet different content (value). One shared vector would force 'what I look for', 'how I'm found', and 'what I contribute' to be identical - which collapses the model's expressiveness.",
         2),
        ("What does the dot product between a query and a key actually measure?",
         "It measures alignment: a large dot product means this token's query points in the same direction as that token's key, i.e. they're relevant to each other. That raw relevance score is scaled by 1/sqrt(d) and then turned into attention weights.",
         2),
        ("Why apply softmax to the scores instead of using them directly?",
         "Softmax turns arbitrary real-valued scores into a probability distribution that sums to 1, so each token's attention is a weighted average over all values. It also sharpens the largest scores relative to the rest, letting a token focus while still staying differentiable for training.",
         4),
        ("What is positional encoding, and why is it needed at all?",
         "Self-attention has no built-in notion of order - it sees a set, not a sequence. Positional encodings (fixed sinusoids or learned vectors) are added to token embeddings so that position information is available, letting the model tell 'dog bites man' from 'man bites dog'.",
         1),
        ("What does it mean that attention is 'permutation invariant'?",
         "If you shuffle the input tokens, plain self-attention produces the same set of outputs, just reordered - it can't tell which token came first. That's exactly why positional information must be injected explicitly; the mechanism itself ignores order.",
         6),
        ("What is multi-head attention doing that single attention doesn't?",
         "Multiple heads run attention in parallel, each with its own Q/K/V projections into a different subspace, so one head can track syntax while another tracks coreference, etc. Their outputs are concatenated and mixed - capturing several kinds of relationships at once rather than averaging them into one.",
         1),
    ];
    made: dict[int, Turn] = {};
    i = 1;
    for (qq, aa, par) in turns {
        t = Turn(id=i, question=qq, answer=aa);
        if par == 0 {
            root +>: Child() :+> t;
        } else {
            made[par] +>: Child() :+> t;
        }
        made[i] = t;
        i += 1;
    }
    # cross-branch link: "why three vectors" (node 3) and "multi-head" (node 8)
    # are the same idea - separate representation subspaces.
    if 8 in made and 3 in made {
        made[8] +>: Ref() :+> made[3];
    }
    return len(made);
}
