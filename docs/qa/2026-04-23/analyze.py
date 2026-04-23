#!/usr/bin/env python3
"""Diff each scenario snapshot against its baseline to reconstruct tool calls.

For each scenario end state:
  - messages ordered by timestamp
  - new meal / workout / metric rows (= update_meal_log / record_workout_set / update_metric)
  - identity profile diff (= update_identity_fact)
  - pattern additions (memory maintainer, not a tool call)
  - active state snapshot (memory maintainer)
"""
import sqlite3, json, sys, pathlib, datetime, difflib

QA = pathlib.Path("/tmp/ledger_qa")

# Scenario metadata
SCENARIOS = [
    ("B_end", "fresh_baseline", "Scenario B — Priya, vague-frame"),
    ("C_end", "fresh_baseline", "Scenario C — Alex, skeptical"),
    ("D_end", "seed_baseline", "Scenario D — Normal day (Omar)"),
    ("E_end", "seed_baseline", "Scenario E — Bad day (Omar)"),
    ("F_end", "seed_baseline", "Scenario F — AI-questioning (Omar)"),
    ("G_end", "seed_baseline", "Scenario G — Contradictions (Omar)"),
    ("H_end", "seed_baseline", "Scenario H — Friend pull (Omar)"),
]

def load_messages(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZTIMESTAMP, ZROLE, ZCONTENT FROM ZSTOREDMESSAGE ORDER BY ZTIMESTAMP ASC").fetchall()
    conn.close()
    return rows

def load_meals(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZDATE, ZDESCRIPTIONTEXT, ZCALORIES, ZPROTEIN FROM ZSTOREDMEAL ORDER BY ZDATE").fetchall()
    conn.close()
    return rows

def load_workouts(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZDATE, ZEXERCISE, ZSUMMARY, ZNOTES FROM ZSTOREDWORKOUTSET ORDER BY ZDATE").fetchall()
    conn.close()
    return rows

def load_metrics(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZDATE, ZTYPE, ZVALUE, ZCONTEXT FROM ZSTOREDMETRIC ORDER BY ZDATE").fetchall()
    conn.close()
    return rows

def load_identity(db):
    conn = sqlite3.connect(db)
    row = conn.execute("SELECT ZMARKDOWNCONTENT FROM ZIDENTITYPROFILE WHERE ZSCOPE='default'").fetchone()
    conn.close()
    return row[0] if row else ""

def load_patterns(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZKEY, ZDESCRIPTIONTEXT, ZCONFIDENCE, ZFIRSTOBSERVED FROM ZPATTERN ORDER BY ZFIRSTOBSERVED").fetchall()
    conn.close()
    return rows

def load_active(db):
    conn = sqlite3.connect(db)
    rows = conn.execute("SELECT ZSCOPE, ZMARKDOWNCONTENT FROM ZACTIVESTATESNAPSHOT").fetchall()
    conn.close()
    return rows

def fmt_ts(ts):
    if ts is None: return "—"
    # SwiftData timestamps are Cocoa reference date: seconds since 2001-01-01 UTC
    epoch = datetime.datetime(2001,1,1, tzinfo=datetime.timezone.utc).timestamp()
    t = datetime.datetime.fromtimestamp(ts + epoch, tz=datetime.timezone.utc)
    return t.strftime("%Y-%m-%d %H:%M:%S") + "Z"

def diff_set(baseline, current, key=lambda r: r):
    base_set = {key(r) for r in baseline}
    return [r for r in current if key(r) not in base_set]

def ident_diff(a, b):
    return "\n".join(difflib.unified_diff(
        (a or "").splitlines(), (b or "").splitlines(),
        fromfile="baseline", tofile="end", lineterm=""
    ))

def analyze(label, title, base_label):
    end_db = str(QA / f"{label}.store")
    base_db = str(QA / f"{base_label}.store")

    msgs = load_messages(end_db)
    new_meals = diff_set(load_meals(base_db), load_meals(end_db), key=lambda r: (r[0], r[1]))
    new_wos = diff_set(load_workouts(base_db), load_workouts(end_db), key=lambda r: (r[0], r[1], r[2]))
    new_metrics = diff_set(load_metrics(base_db), load_metrics(end_db), key=lambda r: (r[0], r[1], r[2]))
    new_patterns = diff_set(load_patterns(base_db), load_patterns(end_db), key=lambda r: r[0])
    id_a = load_identity(base_db)
    id_b = load_identity(end_db)
    active_b = load_active(end_db)

    out = []
    out.append(f"## {title}\n")

    out.append("### Conversation\n")
    for ts, role, content in msgs:
        out.append(f"**[{fmt_ts(ts)}] {role}**")
        out.append("")
        out.append(content.strip())
        out.append("")

    out.append("### Tool calls (inferred from new persisted rows)\n")
    if not (new_meals or new_wos or new_metrics):
        out.append("_(no `update_meal_log`, `record_workout_set`, or `update_metric` calls this scenario)_\n")
    for ts, desc, cal, pro in new_meals:
        out.append(f"- **update_meal_log** @ {fmt_ts(ts)} — `{desc}` ({cal} kcal, {pro}g protein)")
    for ts, ex, summ, notes in new_wos:
        n = f" — {notes}" if notes else ""
        out.append(f"- **record_workout_set** @ {fmt_ts(ts)} — `{ex}`: {summ}{n}")
    for ts, t, v, ctx in new_metrics:
        c = f" ({ctx})" if ctx else ""
        out.append(f"- **update_metric** @ {fmt_ts(ts)} — {t}={v}{c}")
    out.append("")

    out.append("### Identity profile diff (`update_identity_fact` effects)\n")
    d = ident_diff(id_a, id_b)
    if d.strip():
        out.append("```diff")
        out.append(d)
        out.append("```")
    else:
        out.append("_(no identity changes)_")
    out.append("")

    if new_patterns:
        out.append("### Patterns added (memory maintainer, not a direct tool call)\n")
        for k, desc, cf, ts in new_patterns:
            out.append(f"- **{k}** ({cf}) — {desc}")
        out.append("")

    if active_b:
        out.append("### Active-state snapshot (end of scenario)\n")
        for scope, md in active_b:
            out.append(f"**[{scope}]**")
            out.append("")
            out.append(md.strip())
            out.append("")
    return "\n".join(out)

def main():
    out = ["# Ledger scenarios — full transcripts and tool-call traces\n"]
    out.append("Generated 2026-04-23 from sqlite snapshots at `/tmp/ledger_qa/*.store`.\n")
    out.append("Each scenario's end state was diffed against its baseline (`fresh_baseline` for A/B/C, `seed_baseline` for D–H) to reconstruct the silent tool calls the coach made during the run.\n")
    out.append("Coach tools: `update_meal_log`, `record_workout_set`, `update_metric`, `update_identity_fact`, `search_archive`. Only the first four leave persisted rows we can diff; `search_archive` is a read-only lookup and is not visible in this view.\n")
    for label, base, title in SCENARIOS:
        end_store = QA / f"{label}.store"
        if not end_store.exists():
            print(f"skip: missing {end_store}", file=sys.stderr)
            continue
        out.append(analyze(label, title, base))
        out.append("\n---\n")
    (QA / "TRANSCRIPTS.md").write_text("\n".join(out))
    print(f"wrote {QA/'TRANSCRIPTS.md'} ({(QA/'TRANSCRIPTS.md').stat().st_size} bytes)")

if __name__ == "__main__":
    main()
