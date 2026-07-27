# SPEC — "Git-for-Learning" (hackathon cut)

A terminal REPL for studying with an LLM where the conversation is a **tree, not a transcript**. The user can move to any earlier point and ask a different follow-up, creating a fork. Every answer is generated from the ancestor chain of the node it was asked from — so the same question asked from two different branches gets two different answers. That divergence is the demo.

You (the coding agent) are building this in **Jac** (Jaseci 2.3.x).

## Ground rules for the agent

1. **All application code lives in `.jac` files.** No Python files. This is a hard hackathon requirement.
2. **The compiler is the authority, not this spec.** Pseudocode below is illustrative and may be syntactically stale. Before presenting any file, validate it with the `jac mcp` tools (or `jac run`). Consult `jac guide` / the bundled reference for idiomatic syntax. Jac ≥2.0 syntax only: no `let`; `def` for functions, `can` only for object-spatial abilities; `impl` keyword; `import from byllm.lib { Model }`.
3. **Build Milestone 1 only, run its acceptance test, then STOP and show the human.** Do not start M2 until told. One milestone per session.
4. Terminal only. **Do not build:** any web UI, jac-client, auth, file upload, RAG, resource search, or persistence across process restarts.
5. Keep it small. M1 should be roughly 100–150 lines of Jac in one file, `main.jac`.

## Milestone 1 — core loop (must ship)

### Data model

```jac
node Turn {
    has id: int;
    has question: str;
    has answer: str;
}
```

- The tree hangs off `root`. A child of a Turn is a follow-up asked *from* that Turn.
- Maintain a global auto-incrementing id counter and a global dict mapping `id -> node` for O(1) lookup by id. If globals holding node refs fight the language, fall back to a walker that searches from root by id.
- The REPL tracks a **cursor** (current node id; starts at root). Asking creates a child of the cursor; the new node becomes the cursor.

### LLM call

```jac
import from byllm.lib { Model }
glob llm = Model(model_name=<see Config>);

def continue_dialogue(transcript: str, question: str) -> str by llm();
sem continue_dialogue = """
Continue this tutoring dialogue. Answer the new question using ONLY the
prior conversation as context. Be concise (under 120 words).
""";
```

### Walker `Ask`

Requirement: given a target node and a question, produce an answer using **only that node's ancestor chain** as context.

Suggested shape — spawn on the target node, climb toward root collecting, fire the LLM at root:

```jac
walker Ask {
    has question: str;
    has history: list = [];   # collected (q, a) pairs, leaf-to-root order

    can climb with Turn entry {
        self.history.append((here.question, here.answer));
        visit [<--];          # continue up the ancestor chain
    }
    can answer with `root entry {
        # reverse history into chronological order, join into a transcript
        # string ("Q: ...\nA: ...\n" per turn), call continue_dialogue,
        # create the new Turn, connect it under the original target node,
        # register its id, print the answer.
    }
}
```

Note: the new child must be attached to the **original target node** (where the walker was spawned), not to root — keep a reference to the spawn node in a walker field.

### REPL (in `with entry`)

Plain `input()` loop with commands:

- `ask <text>` — ask from the cursor; print the answer and the new node's id
- `goto <n>` — move cursor to node n (0 = root)
- `tree` — print the whole tree, indented by depth, one line per node: `[id] question (first ~50 chars)`, with the cursor marked `*`
- `quit`

### Acceptance test for M1 (run it; all steps must behave as described)

1. `ask what is a byte` → creates node 1 under root
2. `ask how many bits is that` → node 2, child of 1
3. `goto 1`
4. `ask how does this relate to unicode` → node 3, **second child of 1** — the fork
5. `tree` → shows 2 and 3 as siblings under 1
6. `goto 2` → `ask summarize everything we've covered` → answer reflects the bits thread only
7. `goto 3` → `ask summarize everything we've covered` → answer reflects the unicode thread only
8. The two summaries visibly differ and each contains only its own branch's content. (LLM output is nondeterministic; the criterion is that each answer draws only on its own ancestor chain.)

## Milestone 2 — resume / frontier

- Walker `Frontier`: from root, find all leaf Turns; print them at startup as `open threads: [id] question…` so the user sees where they left off within the session.

## Milestone 3 — reference edges

- `edge Ref {}` and a command `link <a> <b>`.
- Extend `Ask`: for each ancestor, also collect (q, a) from nodes one hop away over `Ref` edges, appended to the transcript under a `Related context:` header. This is what makes the structure a graph rather than a tree — worth having for the pitch if time allows.

## Milestone 4 — proposed forks (stretch, only if M1–M3 are demoed)

- `def propose_followups(transcript: str) -> list[str] by llm();` (exactly 3 items)
- Command `spawn`: creates 3 child Turns of the cursor with `question` set and `answer` empty, printed as options. `goto` one and `ask` to pursue it. **Proposals only — never auto-advance the cursor.**

## Config

- Model name from an env var (e.g. `GFL_MODEL`), defaulting to a cheap hosted model the human has a key for. Ask the human which provider/key they have before hardcoding.
- `--mock` flag (or `GFL_MOCK=1`): use `Model(model_name="mockllm", outputs=[...])` with canned outputs so the stage demo cannot fail on network/rate limits. Wire the canned outputs to match the acceptance script.

## Pitch extras (zero/near-zero code — note for the human, not build tasks)

- Marking `Ask` as `walker:pub` makes it a served HTTP endpoint under `jac start` / `jac serve`; the `--faux` flag prints the generated API without running it — one screenshot = "this REPL is also a backend, no FastAPI written."
- Pitch line: "Chat tools give you a transcript. This gives you a map — and the model's answer depends on where you're standing in it."
