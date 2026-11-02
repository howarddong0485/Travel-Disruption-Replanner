"""Deterministic graph repair, validation and atomic simulated-state application.
Jac endpoints own connections; LLMs can only choose catalog IDs, never write state.
"""
import copy;
import itertools;
import json;
import sqlite3;
import from datetime { datetime, timedelta, timezone }
import from uuid { uuid4 }
import from events.simulator { simulated_event }
import from replan.backups { backups_for }
import from planning.application { apply_backup }
def install_schema(conn: sqlite3.Connection) -> None {
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS trip_versions (
        trip_id TEXT PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE,
        version INTEGER NOT NULL DEFAULT 1);
    INSERT OR IGNORE INTO trip_versions(trip_id) SELECT id FROM trips;
    CREATE TABLE IF NOT EXISTS replan_rules (
        item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
        duration_minutes INTEGER NOT NULL DEFAULT 60,
        latest_start TEXT NOT NULL DEFAULT '', fixed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS dependencies (
        trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
        prerequisite_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        dependent_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        buffer_minutes INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(prerequisite_id, dependent_id));
    CREATE TABLE IF NOT EXISTS disruption_events (
        id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
        payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending');
    CREATE TABLE IF NOT EXISTS replan_proposals (
        id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
        event_id TEXT NOT NULL REFERENCES disruption_events(id) ON DELETE CASCADE,
        base_version INTEGER NOT NULL, payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'proposed');
    CREATE TRIGGER IF NOT EXISTS replan_trip_insert AFTER INSERT ON trips BEGIN
        INSERT OR IGNORE INTO trip_versions(trip_id) VALUES (NEW.id); END;
    CREATE TRIGGER IF NOT EXISTS replan_trip_update AFTER UPDATE ON trips BEGIN
        UPDATE trip_versions SET version=version+1 WHERE trip_id=NEW.id; END;
    CREATE TRIGGER IF NOT EXISTS replan_item_insert AFTER INSERT ON items BEGIN
        UPDATE trip_versions SET version=version+1 WHERE trip_id=NEW.trip_id; END;
    CREATE TRIGGER IF NOT EXISTS replan_item_update AFTER UPDATE ON items BEGIN
        UPDATE trip_versions SET version=version+1 WHERE trip_id=NEW.trip_id; END;
    CREATE TRIGGER IF NOT EXISTS replan_item_delete AFTER DELETE ON items BEGIN
        UPDATE trip_versions SET version=version+1 WHERE trip_id=OLD.trip_id; END;
    """);
    for table in ('replan_rules', 'dependencies') {
        for operation in ('INSERT', 'UPDATE', 'DELETE') {
            ref = 'OLD' if (operation == 'DELETE') else 'NEW';
            lookup = '(SELECT trip_id FROM items WHERE id={}.item_id)'.format(ref)
                if (table == 'replan_rules')
                else '{}.trip_id'.format(ref);
            conn.execute(
                'CREATE TRIGGER IF NOT EXISTS replan_{}_{} AFTER {} ON {} BEGIN UPDATE trip_versions SET version=version+1 WHERE trip_id={}; END'.format(
                    table, operation.lower(), operation, table, lookup
                )
            );
        }
    }
    conn.commit();
}
def snapshot(conn: any, trip_id: any) -> dict[str, any] {
    trip = conn.execute('SELECT * FROM trips WHERE id=?', (trip_id, )).fetchone();
    if (trip is None) {
        raise ValueError('Trip no longer exists');
    }
    items = [
        `dict(row)
        for row in conn.execute('SELECT * FROM items WHERE trip_id=?', (trip_id, ))
    ];
    rules = {
        row['item_id']: `dict(row)
        for row in conn.execute(
            'SELECT r.* FROM replan_rules r JOIN items i ON r.item_id=i.id WHERE i.trip_id=?',
            (trip_id, )
        )
    };
    for item in items {
        item.update(
            rules.get(
                item['id'], {'duration_minutes': 60, 'latest_start': '', 'fixed': 0}
            )
        );
        # Roam marks transport/stays done when confirmed, not completed.
        item['protected'] = bool(
            (
                item['fixed']
                or (item['done'] and (item['category'] in {'food', 'activity'}))
            )
        );
    }
    edges = [
        `dict(row)
        for row in conn.execute(
            'SELECT * FROM dependencies WHERE trip_id=?', (trip_id, )
        )
    ];
    version = conn.execute(
        'SELECT version FROM trip_versions WHERE trip_id=?', (trip_id, )
    ).fetchone()[0];
    return {
        'trip': `dict(trip),
        'items': items,
        'dependencies': edges,
        'version': version
    };
}
def start(item: dict[str, any]) -> datetime {
    if (not item['date'] or not item['time']) {
        raise ValueError(
            'Set a date and time for {} before replanning'.format(item['title'])
        );
    }
    return datetime.fromisoformat((item['date'] + 'T' + item['time']));
}
def end(item: dict[str, any]) -> datetime {
    return (start(item) + timedelta(minutes=item['duration_minutes']));
}
def set_start(item: dict[str, any], value: datetime) -> None {
    (item['date'], item['time']) = (value.date().isoformat(), value.strftime('%H:%M'));
}
def topological(items: list[dict[str, any]], edges: list[dict[str, any]]) -> tuple[list[str], dict[str, list[str]]] {
    ids = {item['id'] for item in items};
    indegree = {item_id: 0 for item_id in ids};
    children = {item_id: [] for item_id in ids};
    for `edge in edges {
        if (
            (`edge['prerequisite_id'] not in ids) or (`edge['dependent_id'] not in ids)
        ) {
            raise ValueError('Dependency references an item outside this trip');
        }
        children[`edge['prerequisite_id']].append(`edge['dependent_id']);
        indegree[`edge['dependent_id']] += 1;
    }
    queue = sorted(
        item_id
        for item_id in ids
        if (indegree[item_id] == 0)
    );
    ordered = [];
    while queue {
        item_id = queue.pop(0);
        ordered.append(item_id);
        for child in children[item_id] {
            indegree[child] -= 1;
            if (indegree[child] == 0) {
                queue.append(child);
            }
        }
    }
    if (len(ordered) != len(ids)) {
        raise ValueError('Dependencies must not contain a cycle');
    }
    return (ordered, children);
}
def affected_ids(state: dict[str, any], `root: str) -> list[str] {
    (ordered, children) = topological(state['items'], state['dependencies']);
    if (`root not in children) {
        raise ValueError('Choose an item from this trip');
    }
    (reached, queue) = ({`root}, [`root]);
    while queue {
        for child in children[queue.pop(0)] {
            if (child not in reached) {
                reached.add(child);
                queue.append(child);
            }
        }
    }
    return [
        item_id
        for item_id in ordered
        if (item_id in reached)
    ];
}
def save_rules(
    conn: any,
    trip_id: any,
    item_id: any,
    duration_minutes: any,
    latest_start: any,
    fixed: any
) -> dict[str, any] {
    if (
        not isinstance(duration_minutes, int)
        or isinstance(duration_minutes, bool)
        or not (1 <= duration_minutes <= 1440)
    ) {
        raise ValueError('Duration must be 1–1440 minutes');
    }
    conn.execute('BEGIN IMMEDIATE');
    try {
        state = snapshot(conn, trip_id);
        item = next(
            (
                i
                for i in state['items']
                if (i['id'] == item_id)
            ),
            None
        );
        if (
            (item is None)
            or (item['category'] not in {'transport', 'stay', 'food', 'activity'})
        ) {
            raise ValueError('Choose a scheduled travel item');
        }
        if latest_start {
            parsed = datetime.fromisoformat(latest_start);
            if (
                (parsed.tzinfo is not None)
                or (parsed.isoformat(timespec='minutes') != latest_start)
            ) {
                raise ValueError(
                    'Latest start must use destination-local YYYY-MM-DDTHH:MM'
                );
            }
            if (parsed < start(item)) {
                raise ValueError('Latest start cannot precede the current start');
            }
        }
        conn.execute(
            'INSERT INTO replan_rules VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET duration_minutes=excluded.duration_minutes, latest_start=excluded.latest_start, fixed=excluded.fixed',
            (item_id, duration_minutes, latest_start, int(fixed))
        );
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return snapshot(conn, trip_id);
}
def save_dependency(
    conn: any,
    trip_id: any,
    prerequisite_id: any,
    dependent_id: any,
    buffer_minutes: any,
    remove: any = False
) -> dict[str, any] {
    if (
        not isinstance(buffer_minutes, int)
        or isinstance(buffer_minutes, bool)
        or not (0 <= buffer_minutes <= 1440)
    ) {
        raise ValueError('Transfer buffer must be 0–1440 minutes');
    }
    conn.execute('BEGIN IMMEDIATE');
    try {
        state = snapshot(conn, trip_id);
        nodes = {i['id']: i for i in state['items']};
        if (
            (prerequisite_id == dependent_id)
            or `any((i not in nodes) for i in (prerequisite_id, dependent_id))
        ) {
            raise ValueError('Choose two different items from this trip');
        }
        for item_id in (prerequisite_id, dependent_id) {
            start(nodes[item_id]);
            if (
                nodes[item_id]['category']
                not in {'transport', 'stay', 'food', 'activity'}
            ) {
                raise ValueError('Dependencies must link scheduled travel items');
            }
        }
        if remove {
            conn.execute(
                'DELETE FROM dependencies WHERE prerequisite_id=? AND dependent_id=? AND trip_id=?',
                (prerequisite_id, dependent_id, trip_id)
            );
        } else {
            conn.execute(
                'INSERT INTO dependencies VALUES (?,?,?,?) ON CONFLICT(prerequisite_id,dependent_id) DO UPDATE SET buffer_minutes=excluded.buffer_minutes',
                (trip_id, prerequisite_id, dependent_id, buffer_minutes)
            );
            updated = snapshot(conn, trip_id);
            topological(updated['items'], updated['dependencies']);
            if (
                (end(nodes[prerequisite_id]) + timedelta(minutes=buffer_minutes))
                > start(nodes[dependent_id])
            ) {
                raise ValueError(
                    'The original schedule already violates this dependency; adjust times or duration first'
                );
            }
        }
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return snapshot(conn, trip_id);
}
def validate(state: any, nodes: any, changes: any, retained_cents: any) -> any {
    topological(`list(nodes.values()), state['dependencies']);
    original = {i['id']: i for i in state['items']};
    for change in changes {
        item = nodes[change['item_id']];
        before = original[item['id']];
        if before['protected'] {
            raise ValueError(
                'Fixed or completed item conflicts: {}'.format(before['title'])
            );
        }
        if not (
            state['trip']['start_date'] <= item['date'] <= state['trip']['end_date']
        ) {
            raise ValueError(
                'Repair moves {} outside trip dates'.format(item['title'])
            );
        }
        if (end(item).date().isoformat() > state['trip']['end_date']) {
            raise ValueError('Repair ends {} after the trip'.format(item['title']));
        }
        if (
            item['latest_start']
            and (start(item) > datetime.fromisoformat(item['latest_start']))
        ) {
            raise ValueError('Latest-start window missed for {}'.format(item['title']));
        }
    }
    for `edge in state['dependencies'] {
        if (
            (
                end(nodes[`edge['prerequisite_id']])
                + timedelta(minutes=`edge['buffer_minutes'])
            )
            > start(nodes[`edge['dependent_id']])
        ) {
            raise ValueError('Repair violates a downstream timing boundary');
        }
    }
    scheduled = [
        i
        for i in nodes.values()
        if (
            (i['category'] in {'transport', 'stay', 'food', 'activity'})
            and i['date']
            and i['time']
        )
    ];
    scheduled.sort(key=start);
    for item in scheduled {
        if (
            item['latest_start']
            and (start(item) > datetime.fromisoformat(item['latest_start']))
        ) {
            raise ValueError('Latest-start window missed for {}'.format(item['title']));
        }
    }
    for (previous, following) in zip(scheduled, scheduled[1:]) {
        if (end(previous) > start(following)) {
            raise ValueError(
                'Schedule overlap: {} and {}'.format(
                    previous['title'], following['title']
                )
            );
        }
    }
    total = sum(i['cost_cents'] for i in nodes.values()) + retained_cents;
    if (state['trip']['budget_cents'] and (total > state['trip']['budget_cents'])) {
        raise ValueError('Repair exceeds the trip budget');
    }
    return total;
}
def build_combination(
    state: any, event: any, affected: any, choices: any, manual: any = False
) -> any {
    nodes = {i['id']: copy.deepcopy(i) for i in state['items']};
    original = {i['id']: i for i in state['items']};
    (changes, retained, new_cash) = ([], 0, 0);
    for item_id in affected {
        (item, before) = (nodes[item_id], original[item_id]);
        earliest = start(before);
        for `edge in state['dependencies'] {
            if (`edge['dependent_id'] == item_id) {
                earliest = max(
                    earliest,
                    (
                        end(nodes[`edge['prerequisite_id']])
                        + timedelta(minutes=`edge['buffer_minutes'])
                    )
                );
            }
        }
        `root = item_id == event['item_id'];
        if (`root and (event['type'] == 'delayed')) {
            earliest = max(
                earliest, (start(before) + timedelta(minutes=event['delay_minutes']))
            );
        }
        forced_replace = `root and (event['type'] == 'interrupted');
        missed = bool(
            (
                before['latest_start']
                and (earliest > datetime.fromisoformat(before['latest_start']))
            )
        );
        backup = None;
        if (forced_replace or missed or (manual and choices.get(item_id))) {
            if before['protected'] {
                raise ValueError(
                    'Fixed or completed item conflicts: {}'.format(before['title'])
                );
            }
            options = backups_for(before);
            backup = next(
                (
                    b
                    for b in options
                    if (b['id'] == choices.get(item_id))
                ),
                None
            );
            if (backup is None) {
                raise ValueError('Choose a supplied backup ID for each replacement');
            }
            item.update(
                title=backup['title'],
                cost_cents=backup['cost_cents'],
                duration_minutes=backup['duration_minutes'],
                latest_start='',
                reference='',
                done=False,
                paid=False,
                location=before['location']
            );
            earliest += timedelta(minutes=backup['offset_minutes']);
            retained += before['cost_cents'] if before['paid'] else 0;
            new_cash += backup['cost_cents'];
        }
        set_start(item, earliest);
        if (backup or (earliest != start(before))) {
            changes.append(
                {
                    'item_id': item_id,
                    'before': before,
                    'after': item,
                    'backup_id': backup['id'] if backup else '',
                    'reason': 'Interrupted item replaced'
                        if forced_replace
                        else 'Operating window missed; mock backup selected'
                            if (backup and missed)
                            else 'Traveler-selected mock backup'
                                if backup
                                else 'Delayed event'
                                    if `root
                                    else 'Downstream dependency moved'
                }
            );
        }
    }
    total = validate(state, nodes, changes, retained);
    return {
        'changes': changes,
        'projected_total_cents': total,
        'replacement_cash_cents': new_cash,
        'retained_paid_cents': retained,
        'refund_note': 'Refund eligibility unknown; no refunds deducted.',
        'affected_ids': affected,
        'validation': 'Passed schedule, dependency, fixed-item and budget checks',
        'mock': True
    };
}
def prepare(
    conn: any,
    trip_id: any,
    item_id: any,
    kind: any,
    delay_minutes: any = 0,
    event_id: any = ''
) -> dict[str, any] {
    event = simulated_event(trip_id, item_id, kind, delay_minutes, event_id);
    conn.execute('BEGIN IMMEDIATE');
    try {
        state = snapshot(conn, trip_id);
        affected = affected_ids(state, item_id);
        nodes = {i['id']: i for i in state['items']};
        if (
            nodes[item_id]['category'] not in {'transport', 'stay', 'food', 'activity'}
        ) {
            raise ValueError('Choose a travel item, not a packing item or expense');
        }
        for node_id in affected {
            start(nodes[node_id]);
        }
        existing = conn.execute(
            'SELECT * FROM disruption_events WHERE id=?', (event['id'], )
        ).fetchone();
        if existing {
            old = json.loads(existing['payload']);
            if `any(
                (old[k] != event[k])
                for k in ('trip_id', 'item_id', 'type', 'delay_minutes')
            ) {
                raise ValueError('Event ID already belongs to another disruption');
            }
            if (existing['status'] != 'pending') {
                raise ValueError('This event has already been resolved');
            }
            event = old;
        } else {
            conn.execute(
                'INSERT INTO disruption_events(id,trip_id,payload) VALUES (?,?,?)',
                (event['id'], trip_id, json.dumps(event))
            );
        }
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return {
        'state': state,
        'event': event,
        'affected': affected,
        'backups': [b for node_id in affected for b in backups_for(nodes[node_id])]
    };
}
def candidates(
    packet: any, limit: any = 256
) -> tuple[list[dict[str, any]], list[str]] {
    (state, event, affected) = (packet['state'], packet['event'], packet['affected']);
    groups = [
        [
            b
            for b in packet['backups']
            if (b['item_id'] == item_id)
        ] for item_id in affected
    ];
    if (len(affected) > 8) {
        return (
            [],
            [
                'Demo repair scope is limited to eight connected items. Split the itinerary into smaller groups.'
            ]
        );
    }
    (results, errors, signatures) = ([], [], `set());
    count = 1;
    for group in groups {
        count *= max(1, len(group));
    }
    for combination in itertools.islice(
        itertools.product(*[(group or [None]) for group in groups]), limit
    ) {
        choices = {
            b['item_id']: b['id']
            for b in combination
            if b
        };
        try {
            result = build_combination(state, event, affected, choices);
            signature = json.dumps(
                [
                    (
                        c['item_id'],
                        c['after']['title'],
                        c['after']['date'],
                        c['after']['time']
                    ) for c in result['changes']
                ]
            );
            if (signature not in signatures) {
                signatures.add(signature);
                result['candidate_id'] = 'combination-' + str((len(results) + 1));
                results.append(result);
            }
        } except ValueError as exc {
            if (str(exc) not in errors) {
                errors.append(str(exc));
            }
        }
    }
    results.sort(
        key=lambda (p: any) { (p['projected_total_cents'], len(p['changes'])); }
    );
    if (count > limit) {
        errors.append(
            'Searched the first {} mock combinations of {}; more combinations may exist.'.format(
                limit, count
            )
        );
    }
    return (results, errors);
}
def model_packet(packet: any, results: any) -> dict[str, any] {
    return {
        'event': {k: packet['event'][k] for k in ('type', 'delay_minutes')},
        'currency': packet['state']['trip']['currency'],
        'candidates': [
            {
                'id': p['candidate_id'],
                'projected_total_cents': p['projected_total_cents'],
                'replacement_cash_cents': p['replacement_cash_cents'],
                'changes': [
                    {
                        'backup_id': c['backup_id'],
                        'title': c['after']['title'],
                        'date': c['after']['date'],
                        'time': c['after']['time'],
                        'reason': c['reason']
                    } for c in p['changes']
                ]
            } for p in results[:12]
        ]
    };
}
def store_proposals(
    conn: any,
    packet: any,
    results: any,
    selected_ids: any = None,
    explanation: any = '',
    mode: any = 'mock',
    warnings: any = None
) -> dict[str, any] {
    valid_ids = {p['candidate_id'] for p in results[:12]};
    if (selected_ids is not None) {
        if (
            not selected_ids
            or (len(selected_ids) > 3)
            or (len(`set(selected_ids)) != len(selected_ids))
            or `any((i not in valid_ids) for i in selected_ids)
        ) {
            raise ValueError(
                'LLM returned invalid, duplicate or unsupported combination IDs'
            );
        }
        chosen = [
            next(
                p
                for p in results
                if (p['candidate_id'] == i)
            ) for i in selected_ids
        ];
    } else {
        chosen = results[:1];
        if (len(results) > 1) {
            chosen += [results[(len(results) // 2)]];
        }
        if (len(results) > 2) {
            chosen += [results[-1]];
        }
    }
    conn.execute('BEGIN IMMEDIATE');
    try {
        current = snapshot(conn, packet['event']['trip_id']);
        if (current['version'] != packet['state']['version']) {
            raise ValueError(
                'Trip changed while replanning. Generate fresh alternatives.'
            );
        }
        row = conn.execute(
            'SELECT status FROM disruption_events WHERE id=?', (packet['event']['id'], )
        ).fetchone();
        if ((row is None) or (row[0] != 'pending')) {
            raise ValueError('Disruption has already been resolved');
        }
        conn.execute(
            "UPDATE replan_proposals SET status='superseded' WHERE event_id=? AND status='proposed'",
            (packet['event']['id'], )
        );
        for (index, proposal) in enumerate(chosen) {
            proposal.update(
                id=str(uuid4()),
                event_id=packet['event']['id'],
                base_version=current['version'],
                title=('Alternative ' + str((index + 1))),
                explanation=explanation[:1000],
                mode=mode
            );
            conn.execute(
                'INSERT INTO replan_proposals(id,trip_id,event_id,base_version,payload) VALUES (?,?,?,?,?)',
                (
                    proposal['id'],
                    current['trip']['id'],
                    proposal['event_id'],
                    current['version'],
                    json.dumps(proposal)
                )
            );
        }
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return {
        'event_id': packet['event']['id'],
        'proposals': chosen,
        'warnings': (warnings or []),
        'affected': [
            i
            for i in packet['state']['items']
            if (i['id'] in packet['affected'])
        ],
        'backups': packet['backups'],
        'mode': mode
    };
}
def decide(conn: any, trip_id: any, proposal_id: any, accept: any) -> dict[str, any] {
    conn.execute('BEGIN IMMEDIATE');
    try {
        row = conn.execute(
            'SELECT * FROM replan_proposals WHERE id=? AND trip_id=?',
            (proposal_id, trip_id)
        ).fetchone();
        if ((row is None) or (row['status'] != 'proposed')) {
            raise ValueError('Proposal is missing or has already been reviewed');
        }
        event = conn.execute(
            'SELECT * FROM disruption_events WHERE id=?', (row['event_id'], )
        ).fetchone();
        if (event['status'] != 'pending') {
            raise ValueError('Disruption has already been resolved');
        }
        if not accept {
            conn.execute(
                "UPDATE replan_proposals SET status='rejected' WHERE id=?",
                (proposal_id, )
            );
            conn.commit();
            return {
                'status': 'rejected',
                'message': 'Proposal rejected. Your itinerary is unchanged.'
            };
        }
        state = snapshot(conn, trip_id);
        if (state['version'] != row['base_version']) {
            raise ValueError(
                'This proposal is stale. Generate fresh alternatives before accepting.'
            );
        }
        proposal = json.loads(row['payload']);
        if proposal.get('plan_contract') == 'roam.alternative-plan.v1' {
            apply_backup(conn, state, proposal, datetime.now(timezone.utc));
            conn.execute("UPDATE replan_proposals SET status=CASE WHEN id=? THEN 'accepted' ELSE 'superseded' END WHERE event_id=? AND status='proposed'", (proposal_id, row['event_id']));
            conn.execute("UPDATE disruption_events SET status='applied' WHERE id=?", (row['event_id'],));
            conn.commit();
            return {'status': 'accepted', 'message': 'Validated backup applied to the simulated itinerary. No bookings or payments were made.'};
        }
        nodes = {i['id']: i for i in state['items']};
        for change in proposal['changes'] {
            nodes[change['item_id']] = change['after'];
        }
        validate(state, nodes, proposal['changes'], proposal['retained_paid_cents']);
        for change in proposal['changes'] {
            (before, after) = (change['before'], change['after']);
            if (change['backup_id'] and before['paid'] and before['cost_cents']) {
                conn.execute(
                    'INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,0,1)',
                    (
                        str(uuid4()),
                        trip_id,
                        ('Prior payment: ' + before['title']),
                        'expense',
                        '',
                        '',
                        '',
                        '',
                        'Retained original payment after simulated replacement; refund eligibility unknown.',
                        before['cost_cents']
                    )
                );
            }
            conn.execute(
                'UPDATE items SET title=?,date=?,time=?,location=?,reference=?,cost_cents=?,done=?,paid=? WHERE id=? AND trip_id=?',
                (
                    after['title'],
                    after['date'],
                    after['time'],
                    after['location'],
                    after['reference'],
                    after['cost_cents'],
                    int(after['done']),
                    int(after['paid']),
                    after['id'],
                    trip_id
                )
            );
            conn.execute(
                'INSERT INTO replan_rules VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET duration_minutes=excluded.duration_minutes, latest_start=excluded.latest_start',
                (
                    after['id'],
                    after['duration_minutes'],
                    after['latest_start'],
                    int(after['fixed'])
                )
            );
        }
        conn.execute(
            "UPDATE replan_proposals SET status=CASE WHEN id=? THEN 'accepted' ELSE 'superseded' END WHERE event_id=? AND status='proposed'",
            (proposal_id, row['event_id'])
        );
        conn.execute(
            "UPDATE disruption_events SET status='applied' WHERE id=?",
            (row['event_id'], )
        );
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return {
        'status': 'accepted',
        'message': 'Revised mock plan applied. No real bookings were made or canceled.'
    };
}
def seed_demo(conn: any) -> dict[str, any] {
    trip_id = str(uuid4());
    conn.execute('BEGIN IMMEDIATE');
    try {
        conn.execute(
            'INSERT INTO trips VALUES (?,?,?,?,?,?,?,?)',
            (
                trip_id,
                'Backup & replan demo',
                'Boston',
                '2026-11-01',
                '2026-11-03',
                'USD',
                150000,
                'Synthetic Boston trip for generating dinner and rain backups, then repairing a 180-minute flight delay. No real reservations.'
            )
        );
        definitions = [
            (
                'Flight arrival',
                'transport',
                '2026-11-01',
                '15:00',
                30000,
                30,
                '',
                False
            ),
            (
                'Rental-car pickup',
                'transport',
                '2026-11-01',
                '16:00',
                9000,
                30,
                '2026-11-01T17:00',
                False
            ),
            (
                'Hotel check-in',
                'stay',
                '2026-11-01',
                '17:00',
                24000,
                30,
                '2026-11-01T22:00',
                False
            ),
            (
                'Dinner reservation',
                'food',
                '2026-11-01',
                '19:00',
                4500,
                60,
                '2026-11-01T19:30',
                False
            ),
            (
                'Museum visit — keep this',
                'activity',
                '2026-11-02',
                '10:00',
                2000,
                90,
                '2026-11-02T10:00',
                True
            ),
            (
                'Outdoor harbor walk',
                'activity',
                '2026-11-02',
                '14:00',
                1000,
                60,
                '',
                False
            )
        ];
        ids = [];
        for (
            title,
            category,
            date,
            time,
            cost,
            duration,
            latest,
            fixed
        ) in definitions {
            item_id = str(uuid4());
            ids.append(item_id);
            conn.execute(
                'INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,0,0)',
                (
                    item_id,
                    trip_id,
                    title,
                    category,
                    date,
                    time,
                    'Mock Boston',
                    '',
                    'Synthetic demo item',
                    cost
                )
            );
            conn.execute(
                'INSERT INTO replan_rules VALUES (?,?,?,?)',
                (item_id, duration, latest, int(fixed))
            );
        }
        for (source, target, buffer) in [
            (0, 1, 30),
            (1, 2, 30),
            (2, 3, 30),
            (2, 4, 30)
        ] {
            conn.execute(
                'INSERT INTO dependencies VALUES (?,?,?,?)',
                (trip_id, ids[source], ids[target], buffer)
            );
        }
        conn.commit();
    } except Exception {
        conn.rollback();
        raise;
    }
    return {'trip_id': trip_id};
}
def custom_proposal(
    conn: any, trip_id: any, event_id: any, choices: any
) -> dict[str, any] {
    row = conn.execute(
        'SELECT payload,status FROM disruption_events WHERE id=? AND trip_id=?',
        (event_id, trip_id)
    ).fetchone();
    if ((row is None) or (row['status'] != 'pending')) {
        raise ValueError('Choose an unresolved disruption first');
    }
    event = json.loads(row['payload']);
    packet = prepare(
        conn, trip_id, event['item_id'], event['type'], event['delay_minutes'], event_id
    );
    supplied = {b['id']: b['item_id'] for b in packet['backups']};
    if `any(
        (
            (item_id not in packet['affected'])
            or (backup_id and (supplied.get(backup_id) != item_id))
        ) for (item_id, backup_id) in choices.items()
    ) {
        raise ValueError('Select supplied backups belonging to the affected items');
    }
    result = build_combination(
        packet['state'], packet['event'], packet['affected'], choices, manual=True
    );
    result['candidate_id'] = 'custom-combination';
    return store_proposals(
        conn,
        packet,
        [result],
        mode='custom',
        explanation='Your selected backups combined and validated against the full trip.'
    );
}
