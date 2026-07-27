"""Fullstack entry for Branch.

Server endpoints are registered by importing them here; the client `app()`
mounts the study shell. Run with: jac start --dev main.jac
"""
import from study { get_tree, ask_from, propose_from, link_nodes, TurnView, AskReply }

import "./app.css";
import from .shell { StudyShell }

def:pub app() -> JsxElement {
    return <StudyShell />;
}
