"""Roam travel planner web entry."""
import "./styles.css";
import from .frontend { app as ClientApp }

# The sealed loader requires executable bytecode for the root entry as well as
# colocated services. Keep a small read-only server export in this web entry.
def:pub application_info -> dict[str, str] {
    return {"application": "roam", "inventory": "synthetic", "external_actions": "disabled"};
}

def:pub app -> JsxElement { <ClientApp/> }
