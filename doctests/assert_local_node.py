#!/usr/bin/env python3
# Local-node mode over the QML inspector on 3768. Run against logos-standalone-app (offscreen) with
# monero_wallet_ui and the wallet modules, plus monerod_module --load'ed for the default run and
# absent for --absent. Creates a throwaway stagenet wallet.
import base64, json, socket, sys, time
from pathlib import Path

OUT = Path.cwd() / "shots"
OUT.mkdir(exist_ok=True)
FAIL = []
WALLET = f"ln{int(time.time())}"  # unique per run: a created wallet persists in the session dir
_id = 0

def call(cmd, params=None, timeout=60):
    global _id
    _id += 1
    s = socket.create_connection(("127.0.0.1", 3768), timeout=timeout)
    s.sendall((json.dumps({"id": _id, "command": cmd, "params": params or {}}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        c = s.recv(1 << 22)
        if not c:
            break
        buf += c
    s.close()
    return json.loads(buf.decode().splitlines()[0]) if buf else {}

def oid(name, prop="objectName"):
    m = call("findByProperty", {"property": prop, "value": name}).get("matches") or []
    return m[0]["id"] if m else None

def props(name, prop="objectName"):
    i = oid(name, prop)
    if i is None:
        return {}
    raw = call("getProperties", {"objectId": i}).get("properties") or []
    return {d["name"]: d.get("value") for d in raw} if isinstance(raw, list) else raw

def ev(expr):
    r = call("evaluate", {"objectId": oid("moneroWalletRoot"), "expression": expr})
    if "error" in r:
        raise RuntimeError(f"eval({expr}): {r['error']}")
    return r.get("result")

def method(name, m, args=None):
    i = oid(name)
    if i is None:
        raise RuntimeError(f"no {name}")
    r = call("callMethod", {"objectId": i, "method": m, "args": args or []})
    if "error" in r:
        raise RuntimeError(f"{name}.{m}: {r['error']}")

def activate(name, index):
    # callMethod cannot match activated(int) from a JSON number; QML emits a signal when called.
    r = call("evaluate", {"objectId": oid(name), "expression": f"activated({index})"})
    if "error" in r:
        raise RuntimeError(f"{name}.activated({index}): {r['error']}")

def set_text(name, text, prop="objectName"):
    call("setProperty", {"objectId": oid(name, prop), "property": "text", "value": text})

def daemon(m, args=None):
    raw = ev(f'logos.callModule("monerod_module", "{m}", {json.dumps(args or [])})')
    try:
        v = json.loads(raw)
    except Exception:
        return raw
    return v.get("value", v) if isinstance(v, dict) else v

def shot(name):
    r = call("screenshot", {}, timeout=90)
    if r.get("image"):
        (OUT / name).write_bytes(base64.b64decode(r["image"]))
        print(f"  screenshot {name}")

def check(label, ok, got=None):
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok else f"   got={got!r}"))
    if not ok:
        FAIL.append(label)

def wait(fn, what, timeout, interval=2):
    end, last = time.time() + timeout, None
    while time.time() < end:
        try:
            v = fn()
            if v:
                return v
        except Exception as e:
            last = e
        time.sleep(interval)
    raise TimeoutError(f"timed out waiting for {what} ({last})")

def present():
    print("1) the Wallets screen is up, on stagenet, in remote mode")
    wait(lambda: oid("moneroWalletRoot") is not None and ev("ready"), "view ready", 180)
    if ev("activeNetwork") != "stagenet":
        ev('backend.setActiveNetwork("stagenet")')
        wait(lambda: ev("activeNetwork") == "stagenet", "stagenet active", 60)
    wait(lambda: ev("nodeCfg.url"), "node config", 60)
    wait(lambda: ev("node.mode"), "node health", 60)
    check("stored mode is remote", ev("nodeCfg.mode") == "remote", ev("nodeCfg.mode"))
    check("health says remote", ev("node.mode") == "remote", ev("node.mode"))
    stored_url = ev("nodeCfg.url")
    print(f"    stored remote url: {stored_url}")

    print("2) start the local node (monerod_module, same app)")
    if (daemon("status") or {}).get("state") != "running":
        print(f"    start -> {str(daemon('start', ['stagenet']))[:160]}")
    wait(lambda: (daemon("status") or {}).get("state") == "running", "daemon running", 60)
    check("daemon running", daemon("status").get("state") == "running", daemon("status"))

    print("3) the node sheet offers local mode")
    method("moneroWalletRoot", "openSheet", ["node"])
    wait(lambda: props("nodeSheet").get("visible") is True, "sheet visible", 20)
    wait(lambda: ev("localNode.available") is True, "local node offered", 30)
    check("the selector is shown", props("nodeModeBox").get("visible") is True, props("nodeModeBox").get("visible"))
    check("form starts in remote", ev("ndMode") == "remote", ev("ndMode"))
    activate("nodeModeBox", 1)
    check("selecting local switches the form", ev("ndMode") == "local", ev("ndMode"))
    check("local pane shown, remote fields hidden",
          props("localNodePane").get("visible") is True and props("nodeHostField").get("visible") is False,
          (props("localNodePane").get("visible"), props("nodeHostField").get("visible")))
    check("address is the loopback node", props("localNodeAddress").get("text") == "Address: http://127.0.0.1:38081",
          props("localNodeAddress").get("text"))
    check("state is running", props("localNodeState").get("text") == "Node on this device: running",
          props("localNodeState").get("text"))
    shot("01-sheet-local.png")

    print("4) save local mode")
    method("saveNodeButton", "clicked")
    wait(lambda: ev("nodeCfg.mode") == "local", "stored mode local", 30)
    check("the remote url is kept on the record", ev("nodeCfg.url") == stored_url, ev("nodeCfg.url"))
    wait(lambda: ev("node.mode") == "local" and ev("node.reachable") is True, "local node reachable", 60)
    line = props("nodeSheetStatus").get("text") or ""
    check("sheet line describes the local node", line.startswith("Local node · height "), line)
    check("chip says local node", (props("nodeChip").get("text") or "").startswith("local node "), props("nodeChip").get("text"))
    note_before = ev("nodeIntentNote")
    method("manageLocalNodeButton", "clicked")
    time.sleep(2)
    print(f"    Manage local node… in the standalone host -> note: {ev('nodeIntentNote')!r} (was {note_before!r})")
    shot("02-sheet-saved.png")
    method("nodeSheet", "close")

    print("5) create a wallet; it opens against the local node")
    method("moneroWalletRoot", "openSheet", ["create"])
    wait(lambda: props("createWalletSheet").get("visible") is True, "create sheet", 20)
    set_text("createNameField", WALLET)
    set_text("createPasswordField", "ln-pw")
    set_text("Repeat password", "ln-pw", prop="placeholderText")
    method("createButton", "clicked")
    wait(lambda: ev("walletOpen") is True and ev("status.wallet") == WALLET, "wallet open", 120)
    wait(lambda: ev("engineConnected") is True, "engine connected", 180)
    dh = ev("status.daemonHeight") or 0
    mh = (daemon("status") or {}).get("height") or 0
    print(f"    engine daemonHeight={dh}  monerod height={mh}")
    check("the engine is connected", ev("engineConnected") is True, ev("status"))
    check("its daemon height is the local node's", dh > 1 and dh <= mh + 5 and mh - dh < 3000, (dh, mh))
    check("chip still says local node", (props("nodeChip").get("text") or "").startswith("local node "),
          props("nodeChip").get("text"))
    shot("03-wallet-open.png")
    method("moneroWalletRoot", "selectTab", [4])
    time.sleep(1)
    check("Settings names the node on this device",
          props("settingsNodeUrl").get("text") == "Address: the node on this device (http://127.0.0.1:38081)",
          props("settingsNodeUrl").get("text"))
    shot("04-settings.png")

    print("6) close it, switch back to remote: the stored remote node is still there")
    method("closeWalletButton", "clicked")
    wait(lambda: ev("walletOpen") is False, "wallet closed", 60)
    method("moneroWalletRoot", "openSheet", ["node"])
    wait(lambda: props("nodeSheet").get("visible") is True, "sheet visible", 20)
    activate("nodeModeBox", 0)
    check("remote fields back, with the stored url", props("nodeHostField").get("text") == stored_url,
          props("nodeHostField").get("text"))
    method("saveNodeButton", "clicked")
    wait(lambda: ev("nodeCfg.mode") == "remote", "stored mode remote", 30)
    check("stored url unchanged", ev("nodeCfg.url") == stored_url, ev("nodeCfg.url"))
    wait(lambda: ev("node.mode") == "remote", "health remote", 30)
    method("nodeSheet", "close")
    print(f"    stop -> {str(daemon('stop'))[:120]}")


def absent():
    print("1) the Wallets screen is up, on stagenet, remote")
    wait(lambda: oid("moneroWalletRoot") is not None and ev("ready"), "view ready", 180)
    if ev("activeNetwork") != "stagenet":
        ev('backend.setActiveNetwork("stagenet")')
        wait(lambda: ev("activeNetwork") == "stagenet", "stagenet active", 60)
    wait(lambda: ev("node.mode"), "node health", 60)
    check("health says remote", ev("node.mode") == "remote", ev("node.mode"))
    check("no local block in remote health", ev("node.local") is None, ev("node.local"))

    print("2) the node sheet does not offer local mode")
    method("moneroWalletRoot", "openSheet", ["node"])
    wait(lambda: props("nodeSheet").get("visible") is True, "sheet visible", 20)
    t0 = time.time()
    wait(lambda: ev("localNode.error"), "local_node answered", 30, interval=0.25)
    print(f"    local_node answered within {time.time() - t0:.1f}s: {ev('localNode.error')!r}")
    check("not available", ev("localNode.available") is False, ev("localNode"))
    check("selector hidden", props("nodeModeBox").get("visible") is False, props("nodeModeBox").get("visible"))
    check("local pane hidden, remote form shown",
          props("localNodePane").get("visible") is False and props("nodeHostField").get("visible") is True,
          (props("localNodePane").get("visible"), props("nodeHostField").get("visible")))
    shot("absent-sheet.png")
    method("nodeSheet", "close")

    print("3) a wallet opens on the remote node")
    method("moneroWalletRoot", "openSheet", ["create"])
    wait(lambda: props("createWalletSheet").get("visible") is True, "create sheet", 20)
    set_text("createNameField", WALLET)
    set_text("createPasswordField", "ln-pw")
    set_text("Repeat password", "ln-pw", prop="placeholderText")
    method("createButton", "clicked")
    wait(lambda: ev("walletOpen") is True and ev("status.wallet") == WALLET, "wallet open", 120)
    wait(lambda: ev("engineConnected") is True, "engine connected", 180)
    dh = ev("status.daemonHeight") or 0
    print(f"    engine daemonHeight={dh}")
    check("connected to the remote chain tip", dh > 2_000_000, dh)
    check("chip names the remote route", (props("nodeChip").get("text") or "").startswith("node direct"), props("nodeChip").get("text"))
    shot("absent-wallet.png")
    method("closeWalletButton", "clicked")
    wait(lambda: ev("walletOpen") is False, "wallet closed", 60)


absent() if "--absent" in sys.argv else present()
print("\n" + (f"{len(FAIL)} FAILED: {FAIL}" if FAIL else "all passed"))
sys.exit(1 if FAIL else 0)
