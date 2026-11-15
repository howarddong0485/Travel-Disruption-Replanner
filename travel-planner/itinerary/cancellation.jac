"""Cancellation terms for the bookings an alternative would replace.

Shows the evaluated state, refund, fee and deadline beside the cited policy
excerpt. Free, fee-qualified and no-refund terms stay visually distinct, and
missing terms or an expired source are listed as open questions.
"""

glob BADGES: dict[str, str] = {"free": "Free cancellation", "fee": "Fee applies", "no_refund": "No refund",
    "unknown": "Terms unclear", "no_terms": "No terms saved", "nothing_paid": "Nothing paid", "started": "Already started"};

def money(value: any, currency: str) -> str {
    return currency + " " + (value / 100).toFixed(2);
}

def deadlineText(terms: any) -> str {
    browser: any = window;
    moment = Date.parse(terms["deadline_local"]);
    if not terms["deadline_local"] or browser.Number.isNaN(moment) { return ""; }
    options: dict[str, any] = {"weekday": "short", "month": "short", "day": "numeric", "hour": "numeric", "minute": "2-digit", "timeZoneName": "short"};
    if terms["zone"] { options["timeZone"] = terms["zone"]; }
    try { return new(Date, moment).toLocaleString("en-US", options); }
    except Exception { return terms["deadline_local"]; }
}

"""Where the quoted terms came from, without internal identifiers."""
def sourceText(excerpt: any) -> str {
    source = excerpt["source"];
    if source.startswith("user://") {
        saved = Date.parse(excerpt.get("retrieved_at", ""));
        browser: any = window;
        when = "" if browser.Number.isNaN(saved) else " on " + new(Date, saved).toLocaleDateString("en-US", {"month": "short", "day": "numeric", "year": "numeric"});
        return "Pasted by you" + when;
    }
    if source.startswith("fixture://") or source.startswith("mock://") { return "Sample data"; }
    return "Source: " + source;
}

"""One plain sentence describing what cancelling now means."""
def termsSentence(terms: any) -> str {
    state = terms["state"]; currency = terms["currency"];
    paid = terms["paid_minor"]; refund = terms["refund_minor"]; fee = terms["fee_minor"];
    deadline = deadlineText(terms);
    form = " as credit" if terms["refund_form"] == "credit" else "";
    if state == "free" {
        if not paid { return "Free to cancel" + (" until " + deadline if deadline else "") + ". Nothing has been paid yet."; }
        return "Cancel" + (" by " + deadline if deadline else " now") + " for a full refund of " + money(refund, currency) + form + ".";
    }
    if state == "fee" {
        charge = money(fee, currency) if fee is not None else "a";
        if not paid or refund is None { return "A " + charge + " fee applies if cancelled now" + (" (until " + deadline + ")" if deadline else "") + "."; }
        return "Cancelling now refunds " + money(refund, currency) + form + " after a " + charge + " fee" + (" (until " + deadline + ")" if deadline else "") + ".";
    }
    if state == "no_refund" {
        return "Cancelling now refunds nothing." + (" You would lose " + money(paid, currency) + "." if paid else "");
    }
    if state == "no_terms" { return "No cancellation terms are saved, so the refund is unknown. Check your booking confirmation."; }
    if state == "nothing_paid" { return "Nothing has been paid for this booking."; }
    if state == "started" { return "This booking has already started, so missed-booking terms apply."; }
    return "The saved terms don't say what cancelling now would refund.";
}

"""Short label for an option card: the least favourable state among its bookings."""
def:pub cancellationSummary(entries: any) -> str {
    order = ["no_terms", "unknown", "no_refund", "fee", "started", "free"];
    states = [terms["state"] for terms in entries if terms["state"] != "nothing_paid"];
    for state in order {
        if state in states { return "Original booking: " + BADGES[state].lower(); }
    }
    return "";
}

def:pub CancellationTerms(entries: any, heading: str = "Cancelling the original booking",
    caption: str = "Applying a plan doesn't cancel or book anything. Cancel with the provider yourself.") -> JsxElement {
    return <section className="cancel-terms" aria-label={heading}>
        {(<h4>{heading}</h4>) if heading else None}
        {[<div className="cancel-term" key={terms["item_id"]} data-state={terms["state"]}>
            <div className="cancel-term-head"><strong>{terms["title"]}</strong>
                <span className="cancel-badge" data-state={terms["state"]}>{BADGES.get(terms["state"], "Terms unclear")}</span></div>
            <p>{termsSentence(terms)}</p>
            {[<blockquote className="cancel-excerpt" key={str(index)}><p>{"“" + excerpt["text"] + "”"}</p>
                <cite>{sourceText(excerpt)}</cite></blockquote> for (index, excerpt) in enumerate(terms["excerpts"])]}
            {(<p className="cancel-open">{"Still unknown: " + ", ".join(terms["unknowns"]) + "."}</p>) if len(terms["unknowns"]) > 0 else None}
        </div> for terms in entries]}
        {(<p className="section-caption">{caption}</p>) if caption else None}
    </section>;
}
