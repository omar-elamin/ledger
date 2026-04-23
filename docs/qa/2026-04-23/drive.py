#!/usr/bin/env python3
"""Ledger behaviour-scenario driver.

Commands:
  reset                 uninstall + install + launch, wait for coach opener
  send "<text>"         tap input, type, press Return, wait for next coach msg
  wait                  wait for next coach message (poll sqlite)
  transcript            dump all messages from store
  profile               dump identity + patterns + active state
  snapshot <name>       screenshot + copy sqlite store to /tmp/ledger_qa/<name>
  count                 print (user, coach) message counts
"""
import os, sys, shutil, sqlite3, subprocess, time, pathlib, json

UDID = "38D2A646-8F7C-4383-9D0F-06D461E40267"
BUNDLE = "com.omarelamin.ledger"
APP = "/Users/omarelamin/Library/Developer/Xcode/DerivedData/Ledger-gassypxppraxwlecosdgbvpwltvk/Build/Products/Debug-iphonesimulator/Ledger.app"
QA_DIR = pathlib.Path("/tmp/ledger_qa")
QA_DIR.mkdir(exist_ok=True)

# Input tap coord (inside chat.input TextField)
TAP_X, TAP_Y = 350, 985

def sh(cmd, check=True, capture=True, input=None):
    r = subprocess.run(cmd, shell=isinstance(cmd,str), capture_output=capture, text=True, input=input)
    if check and r.returncode != 0:
        sys.stderr.write(f"FAIL: {cmd}\n{r.stderr}\n"); sys.exit(r.returncode)
    return r

def data_container():
    r = sh(["xcrun","simctl","get_app_container",UDID,BUNDLE,"data"], check=False)
    return r.stdout.strip() if r.returncode==0 else None

def store_path():
    dc = data_container()
    if not dc: return None
    return os.path.join(dc, "Library/Application Support/default.store")

def copy_store():
    s = store_path()
    if not s: return None
    dst = QA_DIR/"live.store"
    for ext in ("", "-wal", "-shm"):
        src = s + ext
        if os.path.exists(src):
            shutil.copy2(src, str(dst)+ext)
    return str(dst)

def counts():
    p = copy_store()
    if not p: return (0,0)
    c = sqlite3.connect(p)
    n_user = c.execute("SELECT COUNT(*) FROM ZSTOREDMESSAGE WHERE ZROLE='user'").fetchone()[0]
    n_coach = c.execute("SELECT COUNT(*) FROM ZSTOREDMESSAGE WHERE ZROLE='coach'").fetchone()[0]
    c.close()
    return n_user, n_coach

def activate():
    sh(["osascript","-e",'tell application "Simulator" to activate'])
    time.sleep(0.2)

def tap_input():
    activate()
    sh(["cliclick", f"c:{TAP_X},{TAP_Y}"])
    time.sleep(0.3)

def type_text(text):
    # Type in small chunks to avoid issues with long strings.
    activate()
    # cliclick handles unicode; use t: prefix. Escape colons and commas with care — our text doesn't have them mostly.
    # cliclick requires the text without enclosing quotes; pass argv directly.
    sh(["cliclick", f"t:{text}"])

def press_return():
    activate()
    sh(["osascript","-e",'tell application "System Events" to key code 36'])  # Return

def wait_for_coach_count(target_coach, timeout=90, stable_secs=1.5):
    """Poll until coach count reaches target_coach, with a stability window after that."""
    deadline = time.time() + timeout
    last_seen = None
    last_change = time.time()
    while time.time() < deadline:
        _, nc = counts()
        if nc >= target_coach:
            # also check content stability (message saved after streaming end)
            p = QA_DIR/"live.store"
            conn = sqlite3.connect(str(p))
            row = conn.execute("SELECT ZCONTENT FROM ZSTOREDMESSAGE WHERE ZROLE='coach' ORDER BY ZTIMESTAMP DESC LIMIT 1").fetchone()
            conn.close()
            content = row[0] if row else ""
            if last_seen == content:
                if time.time() - last_change >= stable_secs:
                    return True
            else:
                last_seen = content
                last_change = time.time()
        time.sleep(0.6)
    return False

def cmd_reset(seed=None):
    print(f"[reset] terminate + uninstall + install + launch (seed={seed})")
    sh(["xcrun","simctl","terminate",UDID,BUNDLE], check=False, capture=True)
    sh(["xcrun","simctl","uninstall",UDID,BUNDLE], check=False, capture=True)
    sh(["xcrun","simctl","install",UDID,APP])
    env = os.environ.copy()
    if seed:
        env["SIMCTL_CHILD_LEDGER_DEV_SEED_PRESET"] = seed
    r = subprocess.run(["xcrun","simctl","launch",UDID,BUNDLE],
                       env=env, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(f"launch failed: {r.stderr}\n"); sys.exit(1)
    activate()
    print("[reset] waiting for opener (coach count >= 1)...")
    if wait_for_coach_count(1, timeout=60):
        print("[reset] opener received.")
    else:
        print("[reset] WARN: no opener after 60s")
    cmd_transcript()

def cmd_send(text):
    nu_before, nc_before = counts()
    print(f"[send] before: user={nu_before} coach={nc_before}")
    tap_input()
    type_text(text)
    time.sleep(0.2)
    press_return()
    print(f"[send] sent: {text}")
    print(f"[send] waiting for coach response (count -> {nc_before+1})...")
    if wait_for_coach_count(nc_before+1, timeout=90):
        nu, nc = counts()
        print(f"[send] ok: user={nu} coach={nc}")
        cmd_last_coach()
    else:
        print("[send] TIMEOUT waiting for coach reply")

def cmd_transcript():
    p = copy_store()
    if not p:
        print("[transcript] no store yet")
        return
    conn = sqlite3.connect(p)
    rows = conn.execute("SELECT ZROLE, ZCONTENT FROM ZSTOREDMESSAGE ORDER BY ZTIMESTAMP ASC").fetchall()
    conn.close()
    for r, c in rows:
        print(f"--- {r} ---")
        print(c)
        print()

def cmd_last_coach():
    p = copy_store()
    conn = sqlite3.connect(p)
    row = conn.execute("SELECT ZCONTENT FROM ZSTOREDMESSAGE WHERE ZROLE='coach' ORDER BY ZTIMESTAMP DESC LIMIT 1").fetchone()
    conn.close()
    print("--- last coach ---")
    print(row[0] if row else "(none)")

def cmd_profile():
    p = copy_store()
    conn = sqlite3.connect(p)
    print("== IDENTITY ==")
    for scope, md in conn.execute("SELECT ZSCOPE, ZMARKDOWNCONTENT FROM ZIDENTITYPROFILE"):
        print(f"[{scope}]\n{md}\n")
    print("== PATTERNS ==")
    for k, d, cf in conn.execute("SELECT ZKEY, ZDESCRIPTIONTEXT, ZCONFIDENCE FROM ZPATTERN"):
        print(f"- {k} ({cf}): {d}")
    print("== ACTIVE STATE ==")
    for scope, md in conn.execute("SELECT ZSCOPE, ZMARKDOWNCONTENT FROM ZACTIVESTATESNAPSHOT"):
        print(f"[{scope}]\n{md}\n")
    print("== LOGGED MEALS ==")
    for d, desc, cal, pro in conn.execute("SELECT ZDATE, ZDESCRIPTIONTEXT, ZCALORIES, ZPROTEIN FROM ZSTOREDMEAL ORDER BY ZDATE"):
        print(f"- {d}: {desc} ({cal}kcal, {pro}g protein)")
    print("== LOGGED METRICS ==")
    for d, tp, v, ctx in conn.execute("SELECT ZDATE, ZTYPE, ZVALUE, ZCONTEXT FROM ZSTOREDMETRIC ORDER BY ZDATE"):
        print(f"- {d} {tp}={v} ({ctx})")
    print("== LOGGED WORKOUTS ==")
    for d, ex, s in conn.execute("SELECT ZDATE, ZEXERCISE, ZSUMMARY FROM ZSTOREDWORKOUTSET ORDER BY ZDATE"):
        print(f"- {d} {ex}: {s}")
    conn.close()

def cmd_snapshot(name):
    # screenshot
    shot = QA_DIR / f"{name}.png"
    sh(["xcrun","simctl","io",UDID,"screenshot",str(shot)])
    # store
    s = store_path()
    if s:
        dst = QA_DIR / f"{name}.store"
        for ext in ("","-wal","-shm"):
            src = s+ext
            if os.path.exists(src):
                shutil.copy2(src, str(dst)+ext)
    print(f"[snapshot] {shot}")

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "reset":
        seed = sys.argv[2] if len(sys.argv) > 2 else None
        cmd_reset(seed=seed)
    elif cmd == "send":
        cmd_send(sys.argv[2])
    elif cmd == "wait":
        _, nc = counts()
        print(f"waiting from coach={nc} ...")
        wait_for_coach_count(nc+1)
        cmd_last_coach()
    elif cmd == "transcript": cmd_transcript()
    elif cmd == "profile": cmd_profile()
    elif cmd == "snapshot": cmd_snapshot(sys.argv[2])
    elif cmd == "count":
        print(counts())
    elif cmd == "last":
        cmd_last_coach()
    else:
        print(__doc__); sys.exit(1)

if __name__ == "__main__":
    main()
