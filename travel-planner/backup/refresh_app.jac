"""Standalone preview of the same Roam validation panel, without other feature UIs."""
import "../styles.css";
import from backup.validation_frontend { ValidationLab }

def:pub app -> JsxElement {
    <main className="workspace">
        <header className="topbar"><span>ROAM · BACKUP REFRESH DEMO</span></header>
        <ValidationLab/>
    </main>
}
