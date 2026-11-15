"""Light and dark theme. A saved choice wins; otherwise the system setting decides."""

def:pub preferredTheme -> str {
    browser: any = window;
    try {
        saved = browser.localStorage.getItem("roam.theme");
        if saved == "dark" or saved == "light" { return saved; }
    } except Exception {}
    return "dark" if browser.matchMedia("(prefers-color-scheme: dark)").matches else "light";
}

"""Show a theme. Pass remember=True when the traveler chose it, so it survives a reload."""
def:pub showTheme(theme: str, remember: bool = False) -> str {
    browser: any = window;
    document.documentElement.setAttribute("data-theme", theme);
    if remember {
        try { browser.localStorage.setItem("roam.theme", theme); } except Exception {}
    }
    return theme;
}
