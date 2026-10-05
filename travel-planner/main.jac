"""Roam travel planner web entry."""
import "./styles.css";
import from .frontend { app as ClientApp }

def:pub app -> JsxElement { <ClientApp/> }
