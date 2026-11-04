import QtQuick

// Drives the view through its node and Tor states against a fake backend: the first-run choice, the
// node sheet's own node or public sources, what Save stores for each, and an open wallet's route.
// Prints STATES-OK, or STATES-FAIL with the cases that disagree.
Item {
    id: scene
    width: 1280; height: 900

    // The host injects `logos`; the view finds this one by name up its context chain.
    property QtObject logos: QtObject {
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        property var requests: []
        property var lastCallback: null
        function module(name) { return fake }
        function isViewModuleReady(name) { return true }
        function request(intent, params, cb) { requests = requests.concat([{ intent: intent, params: params }]); lastCallback = cb }
        function respond(id, ok, result, error) {}
        function watch(reply, ok, err) { ok(reply) }
    }

    QtObject {
        id: fake
        property string lastError: ""
        property bool dataLoading: false
        property bool busy: false
        property string statusJson: JSON.stringify({ state: "no_wallet", activeNetwork: "stagenet" })
        property string networksJson: JSON.stringify({ networks: ["mainnet", "stagenet"], active: "stagenet" })
        property string walletsJson: "[]"
        property string nodeHealthJson: "{}"
        property string balancesJson: ""
        property string receiveJson: ""
        property string qrModulesJson: ""
        property int selectedSubaddress: 0
        property string receiveUri: ""
        property string nodeConfigJson: "{}"
        property string localNodeJson: "{}"
        property string historyJson: ""
        property string pendingJobId: ""
        property string lastJobJson: ""
        property string sendRequestId: ""
        property string sendStatusJson: "{}"
        property string sendError: ""
        property string torUseJson: ""
        // What setTorUse answers: "" stores the mode, as the node does.
        property string torUseReply: ""
        property var calls: []
        function note(name, args) { calls = calls.concat([[name].concat(args)]) }
        function last(name) {
            for (var i = calls.length - 1; i >= 0; i--) if (calls[i][0] === name) return calls[i]
            return null
        }
        function setTorUse(m) {
            note("setTorUse", [m])
            if (torUseReply !== "") return torUseReply
            var o = JSON.parse(torUseJson || "{}")
            o.torUse = m
            o.torUseChosen = true
            torUseJson = JSON.stringify(o)
            return ""
        }
        function saveNodeConfig(c) { note("saveNodeConfig", [JSON.parse(c)]) }
        function prepareSend(s) { note("prepareSend", [s]) }
        function refresh() {}
        function refreshHistory() {}
        function clearAndRefresh() {}
        function refreshLocalNode() {}
        function setActiveNetwork(n) { note("setActiveNetwork", [n]) }
        function openWallet(n, p) {}
        function createWallet(n, p, l) {}
        function restoreFromSeed(n, p, s, h, l) {}
        function restoreFromKeys(n, p, a, v, s, h, l) {}
        function changePassword(o, n) {}
        function revealSeed(p) { return "" }
        function revealViewKey(p) { return "" }
        function closeWallet() {}
        function createSubaddress(l) {}
        function selectSubaddress(i) {}
        function setReceiveAmount(a) {}
        function setSubaddressLabel(i, l) {}
        function confirmSend() {}
        function cancelSend() {}
        function dismissSend() {}
        function addressValid(a) { return true }
        function formatXmr(a) { return a }
    }

    property var bad: []
    function expect(name, got, want) {
        if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want))
    }
    // Finds an object by objectName through items, popups and loaders.
    function find(obj, name, depth) {
        if (!obj || (depth || 0) > 80) return null
        if (obj.objectName === name) return obj
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        if (obj.item && kids.indexOf(obj.item) < 0) kids.push(obj.item)
        for (var k = 0; k < kids.length; k++) {
            var r = find(kids[k], name, (depth || 0) + 1)
            if (r) return r
        }
        return null
    }
    function prop(name, p) {
        var o = find(view.item, name, 0)
        return o ? o[p] : "<no " + name + ">"
    }
    function shown(name) { return prop(name, "visible") }
    function findAll(obj, pred, out, depth) {
        out = out || []
        if (!obj || (depth || 0) > 80) return out
        if (pred(obj) && out.indexOf(obj) < 0) out.push(obj)
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        for (var k = 0; k < kids.length; k++) findAll(kids[k], pred, out, (depth || 0) + 1)
        return out
    }
    function click(name) { find(view.item, name, 0).clicked() }
    function setText(name, t) { find(view.item, name, 0).text = t }
    function saved() { return (fake.last("saveNodeConfig") || [])[1] || {} }
    // Visible items in this order, top to bottom.
    function inOrder(names) {
        var ys = names.map(function (n) { var o = find(view.item, n, 0); return o && o.visible ? Math.round(o.mapToItem(null, 0, 0).y) : -1 })
        return ys.every(function (y, i) { return y >= 0 && (i === 0 || y > ys[i - 1]) }) ? "in order" : JSON.stringify(ys)
    }
    function checks(prefix) { return ["identifying", "all", "none"].map(function (m) { return prop(prefix + m, "checked") }) }
    function tor(o) { fake.torUseJson = JSON.stringify(o) }

    readonly property string onion: "http://abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuv.onion:18081"
    readonly property var steps: [
        function (v) {
            tor({ torUse: "identifying", torUseChosen: false, existing: false })
        },
        function (v) {
            expect("a fresh install asks first", shown("torUsePage") + " " + shown("walletsPage"), "true false")
            expect("the question", prop("startIntro", "text").indexOf("Where should this wallet get Monero's chain?"), 0)
            expect("public sources preselected", prop("startPublic", "checked") + " " + prop("startOwn", "checked"), "true false")
            expect("...with Use Tor for under it", shown("startPublicOptions") + " " + shown("startOwnNote"), "true false")
            expect("most private first", inOrder(["startOwn", "startPublic", "torUseStart_all", "torUseStart_identifying", "torUseStart_none"]), "in order")
            expect("three options", ["identifying", "all", "none"].map(function (m) { return prop("torUseStart_" + m, "text") }),
                   ["Only what identifies you", "Everything", "Nothing"])
            expect("...each with what happens, pros and cons", ["identifying", "all", "none"].every(function (m) {
                return ["happens_", "pros_", "cons_"].every(function (k) { return shown("torUseStart_" + k + m) === true }) }), true)
            expect("...in the plan's words", prop("torUseStart_cons_identifying", "text").indexOf("You can send only once the wallet has caught up and moved to Tor.") > 0, true)
            expect("fresh: identifying preselected", checks("torUseStart_"), [true, false, false])
            expect("...and Recommended", shown("torUseStart_recommended_identifying"), true)
            expect("...no Current tag", ["all", "none", "identifying"].some(function (m) { return shown("torUseStart_current_" + m) === true }), false)
            click("torUseContinue")
        },
        function (v) {
            expect("Continue stores the preselected mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
            expect("...and the Wallets screen shows", shown("torUsePage") + " " + shown("walletsPage") + " " + shown("nodeSheet"), "false true false")
            v.torUseAnswered = false
            tor({ torUse: "all", torUseChosen: false, existing: true })
        },
        function (v) {
            expect("existing: the screen shows once more", shown("torUsePage"), true)
            expect("...its routing preselected", checks("torUseStart_"), [false, true, false])
            expect("...tagged Current", shown("torUseStart_current_all"), true)
            expect("...identifying still Recommended", shown("torUseStart_recommended_identifying"), true)
            fake.torUseReply = "Close your open accounts to change this."
            click("torUseContinue")
        },
        function (v) {
            expect("a refusal shows inline", prop("torUseStartNote", "text"), "Close your open accounts to change this.")
            expect("...and the screen stays", shown("torUsePage"), true)
            fake.torUseReply = ""
            click("torUseStart_none")
        },
        function (v) {
            expect("picking moves the choice", checks("torUseStart_"), [false, false, true])
            expect("...Current stays on the node's", shown("torUseStart_current_all") + " " + shown("torUseStart_current_none"), "true false")
            click("torUseContinue")
        },
        function (v) {
            expect("...stores the pick", fake.last("setTorUse"), ["setTorUse", "none"])
            expect("...and clears the refusal", prop("torUseStartNote", "text"), "")
            expect("chosen: the screen is gone", shown("torUsePage"), false)
            v.torUseAnswered = false
        },
        function (v) {
            expect("...and never shows again", shown("torUsePage"), false)
            fake.torUseJson = ""
        },
        function (v) {
            expect("an older backend: no screen", shown("torUsePage") + " " + shown("walletsPage"), "false true")
            expect("...and no choice in the node sheet", v.torUse, "")
            tor({ torUse: "identifying", torUseChosen: false })
            fake.statusJson = JSON.stringify({ state: "opening" })
        },
        function (v) {
            expect("opening: no screen", shown("torUsePage"), false)
            fake.statusJson = JSON.stringify({ state: "no_wallet" })
            tor({ torUse: "identifying", torUseChosen: false, existing: false })
            click("torUseStart_none")
            click("startOwn")
        },
        function (v) {
            expect("first run, your own node: its one note", shown("startOwnNote") && prop("startOwnNote", "text").indexOf("<b>Costs:</b>") > 0, true)
            expect("...what Continue does", shown("startOwnNext"), true)
            expect("...and no Use Tor for", shown("startPublicOptions"), false)
            click("torUseContinue")
        },
        function (v) {
            expect("your own node still stores the recommended mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
            expect("...and the node sheet opens on it", shown("nodeSheet") + " " + prop("sourceOwn", "checked") + " " + shown("ownNodeOption"), "true true true")
            expect("...with no node in Logos, at an address", prop("ownInLogos", "enabled") + " " + prop("ownAtAddress", "checked"), "false true")
            expect("...public sources folded away", shown("publicSourcesOption") + " " + shown("torUseSettings"), "false false")
            v.closeSheets()
            tor({ torUse: "identifying", torUseChosen: true })
            fake.nodeConfigJson = JSON.stringify({ url: "https://node2.monerodevs.org:38089", onionUrl: "http://plowsof.onion:38089",
                                                   trusted: false, mode: "remote", source: "default", network: "stagenet" })
            fake.nodeHealthJson = JSON.stringify({ reachable: false, mode: "remote", tor: { state: "connecting", progress: 40, answered: true } })
            v.openSheet("node")
        },
        function (v) {
            expect("a seeded record: public sources, picked for you", prop("sourcePublic", "checked") + " " + prop("publicPicked", "checked"), "true true")
            expect("...your own node folded", shown("ownNodeOption") + " " + shown("publicChosenPane"), "false false")
            expect("...Use Tor for under it", shown("torUseSettings") + " " + JSON.stringify(checks("torUse_")), "true [true,false,false]")
            expect("...enabled with no account open", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "enabled") }), [true, true, true])
            expect("...for every public network", prop("torUseScope", "text"), "Applies to every network that uses public sources.")
            expect("...no lock line", shown("torUseLocked"), false)
            expect("the sheet reads top to bottom", inOrder(["sourceOwn", "sourcePublic", "publicPicked", "publicChosen", "torUse_all",
                                                              "torUse_identifying", "torUse_none", "publicBuiltInTor", "saveNodeButton"]), "in order")
            expect("Which Tor under Use Tor for, with the Tor chip", shown("publicBuiltInTor") + " " + prop("publicBuiltInTor", "checked")
                   + " " + prop("publicTorChip", "text") + " " + shown("publicManageTor"), "true true Connecting to Tor… 40% true")
            var notes = findAll(find(view.item, "nodeSheet", 0), function (o) { return typeof o.text === "string" && o.text.indexOf("Benefits:") >= 0 })
            expect("one description of your own node", notes.length, 1)
            find(view.item, "publicManageTor", 0).activated("")
            var asked = logos.requests[logos.requests.length - 1]
            expect("Manage Tor raises tor.manage", asked ? asked.intent : "<none>", "tor.manage")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", prop("publicTorNote", "text"), "The Tor app is not installed.")
            click("saveNodeButton")
        },
        function (v) {
            expect("Save, picked for you: the module's own node", saved(), { mode: "remote", source: "default", proxy: "" })
            click("torUse_none")
        },
        function (v) {
            expect("Nothing: no Which Tor", fake.last("setTorUse") + " " + shown("publicBuiltInTor"), "setTorUse,none false")
            click("sourceOwn")
        },
        function (v) {
            expect("your own node: its branch only", shown("ownNodeOption") + " " + shown("publicSourcesOption") + " " + shown("torUseSettings"), "true false false")
            expect("...one note with benefits and costs", prop("ownNodeNote", "text").indexOf("<b>Benefits:</b>") === 0 && prop("ownNodeNote", "text").indexOf("<b>Costs:</b>") > 0, true)
            expect("...no node in Logos to pick", prop("ownInLogos", "enabled") + " " + prop("ownAtAddress", "checked"), "false true")
            expect("...the way to get one", shown("localNodePane") + " " + prop("localNodeState", "text"),
                   "true The Monero Node app isn't running a node for stagenet on this computer.")
            expect("...where the node's own Tor is set", prop("ownNodePeers", "text").indexOf("Monero Node app") > 0, true)
            click("manageLocalNodeButton")
            var asked = logos.requests[logos.requests.length - 1]
            expect("Open Monero Node raises monero.node.configure", asked ? asked.intent + " " + asked.params.network : "<none>",
                   "monero.node.configure stagenet")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", shown("nodeIntentNote") && prop("nodeIntentNote", "text"), "The Monero node app is not installed.")
            v.nodeIntentNote = ""
            expect("no address yet: no route, no Tor", shown("ownRouteLine") + " " + shown("ownTorSwitch") + " " + shown("ownBuiltInTor"), "false false false")
            expect("...and nothing to save", prop("saveNodeButton", "enabled"), false)
            setText("ownAddressField", "http://192.168.1.4:18081")
        },
        function (v) {
            expect("on your network: direct, said once", prop("ownRouteLine", "text") + " " + shown("ownTorSwitch") + " " + shown("ownBuiltInTor"),
                   "Reached directly. Tor can't reach your network. false false")
            expect("...not trusted off loopback", shown("nodeTrustedBox"), false)
            setText("ownAddressField", "http://127.0.0.1:18081")
        },
        function (v) {
            expect("loopback: Trusted is offered", shown("nodeTrustedBox"), true)
            setText("ownAddressField", scene.onion)
        },
        function (v) {
            expect("an onion: always Tor, and which", prop("ownRouteLine", "text") + " " + shown("ownTorSwitch") + " " + shown("ownBuiltInTor"),
                   "Always reached through Tor. false true")
            setText("ownAddressField", "https://my.node.example:18081")
        },
        function (v) {
            expect("the internet: the switch, on", shown("ownTorSwitch") + " " + prop("ownTorSwitch", "checked") + " " + shown("ownRouteLine"), "true true false")
            expect("...what off means", prop("ownTorSwitchNote", "text"), "Otherwise its network sees this computer reaching your node.")
            expect("...Which Tor while on", shown("ownBuiltInTor"), true)
            click("ownTorSwitch")
        },
        function (v) {
            expect("off: no Which Tor", prop("ownTorSwitch", "checked") + " " + shown("ownBuiltInTor"), "false false")
            click("saveNodeButton")
            var c = saved()
            expect("Save, your node direct", [c.mode, c.own, c.url, c.reachThroughTor, c.onionUrl, c.proxy, c.trusted, "password" in c],
                   ["remote", true, "https://my.node.example:18081", false, "", "", false, false])
            click("ownTorSwitch")
            click("ownOwnTor")
        },
        function (v) {
            expect("your own Tor needs its address", shown("ownProxyField") + " " + prop("saveNodeButton", "enabled"), "true false")
            setText("ownProxyField", "socks5://127.0.0.1:9050")
        },
        function (v) {
            click("saveNodeButton")
            var c = saved()
            expect("Save, your node over your own Tor", [c.reachThroughTor, c.proxy], [true, "socks5://127.0.0.1:9050"])
            fake.localNodeJson = JSON.stringify({ available: true, rpcUrl: "http://127.0.0.1:38081", status: { state: "running" } })
        },
        function (v) {
            expect("a node in Logos can be picked", prop("ownInLogos", "enabled"), true)
            click("ownInLogos")
        },
        function (v) {
            expect("In Logos: its state, no address, no Tor", shown("localNodePane") + " " + prop("localNodeState", "text") + " "
                   + prop("localNodeAddress", "text") + " " + shown("ownAddressPane") + " " + shown("ownProxyField"),
                   "true Node on this device: running Address: http://127.0.0.1:38081 false false")
            v.ndProxyText = ""
            expect("a hidden, empty own Tor does not gate Save", prop("saveNodeButton", "enabled"), true)
            click("saveNodeButton")
            var c = saved()
            expect("Save, In Logos: the stored remote half, not the hidden edits",
                   [c.mode, c.url, c.onionUrl, c.source, c.proxy, c.own, "password" in c],
                   ["local", "https://node2.monerodevs.org:38089", "http://plowsof.onion:38089", "default", "", false, false])
            fake.nodeConfigJson = JSON.stringify({ url: "https://my.node.example:18081", own: true, reachThroughTor: false, mode: "remote",
                                                   source: "external", network: "stagenet", username: "u", hasPassword: true })
        },
        function (v) {
            expect("a stored own node opens as stored", [prop("sourceOwn", "checked"), prop("ownAtAddress", "checked"), prop("ownAddressField", "text"),
                   prop("ownTorSwitch", "checked"), prop("nodeUserField", "text")], [true, true, "https://my.node.example:18081", false, "u"])
            click("sourcePublic")
        },
        function (v) {
            expect("switching to public offers the picked node", prop("publicPicked", "checked") + " " + shown("torUseSettings"), "true true")
            click("publicChosen")
            setText("nodeHostField", "https://node.example:18089")
            setText("nodeOnionField", "http://x.onion:18089")
        },
        function (v) {
            click("saveNodeButton")
            var c = saved()
            expect("Save, a node you choose: no login from another node", [c.mode, c.url, c.onionUrl, c.username, c.password, c.own, c.source],
                   ["remote", "https://node.example:18089", "http://x.onion:18089", "", "", undefined, undefined])
            fake.nodeConfigJson = JSON.stringify({ url: "https://chosen.example:18089", username: "u", hasPassword: true, mode: "remote",
                                                   source: "external", network: "stagenet" })
        },
        function (v) {
            expect("a stored chosen node opens as stored", prop("publicChosen", "checked") + " " + prop("nodeHostField", "text"), "true https://chosen.example:18089")
            click("saveNodeButton")
            var c = saved()
            expect("...its login stays with its address", [c.username, "password" in c], ["u", false])
            setText("nodeHostField", "http://10.0.0.2:18089")
        },
        function (v) {
            expect("a chosen address on your network says what it becomes", shown("chosenLanNote"), true)
            click("saveNodeButton")
            expect("...and a new address drops the login", [saved().username, saved().password], ["", ""])
            find(view.item, "torUseExplain", 0).activated("")
        },
        function (v) {
            expect("What this means, for a node you choose", shown("torUse_happens_all") && prop("torUse_happens_all", "text").indexOf("your address over Tor") > 0, true)
            click("torUse_all")
        },
        function (v) {
            expect("picking stores it", fake.last("setTorUse"), ["setTorUse", "all"])
            expect("...and checks it", checks("torUse_"), [false, true, false])
            fake.busy = true
        },
        function (v) {
            expect("a job in flight locks the sheet", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "enabled") })
                   .concat([prop("sourceOwn", "enabled"), prop("saveNodeButton", "enabled")]), [false, false, false, false, false])
            expect("...saying why", shown("torUseLocked") && prop("torUseLocked", "text"), "Close your open accounts to change this.")
            fake.busy = false
            var kinds = {}
            ;["http://127.0.0.1:18081", "http://localhost:18081", "http://192.168.1.4:18089", "http://10.0.0.2:18089", "http://[::1]:18081",
              "http://node.lan:18089", "http://[fd00::4]:18081", "http://169.254.3.3:1", "https://node.monerodevs.org:18089", "http://8.8.8.8:18089",
              "http://abc.onion:18089", "http://[2001:db8::1]:1", "http://172.32.0.1:1", ""].forEach(function (u) { kinds[u] = v.addressKind(u) })
            expect("the node module's address classes", kinds, {
                "http://127.0.0.1:18081": "lan", "http://localhost:18081": "lan", "http://192.168.1.4:18089": "lan", "http://10.0.0.2:18089": "lan",
                "http://[::1]:18081": "lan", "http://node.lan:18089": "lan", "http://[fd00::4]:18081": "lan", "http://169.254.3.3:1": "lan",
                "https://node.monerodevs.org:18089": "internet", "http://8.8.8.8:18089": "internet", "http://abc.onion:18089": "onion",
                "http://[2001:db8::1]:1": "internet", "http://172.32.0.1:1": "internet", "": "" })
            expect("...by host", v.hostOf("http://user:pw@Node.Example:1/x"), "node.example")
            v.closeSheets()
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 2000, route: "proxied", rttMs: 900, mode: "remote" })
        },
        function (v) {
            expect("a Tor route reads over Tor", v.nodeLine(), "Reachable · height 2000 · over Tor · 900ms")
            tor({ torUse: "identifying", torUseChosen: true })
            fake.statusJson = JSON.stringify({ state: "syncing", wallet: "w", network: "stagenet", route: "catch_up", onTor: false,
                                               waitingForTor: true, torUse: "identifying", connected: true })
        },
        function (v) {
            v.selectTab(1)
            find(view.item, "sendAddressField", 0).text = "5abc"
            find(view.item, "sendAmountField", 0).text = "1"
        },
        function (v) {
            expect("catching up says so", prop("torRouteLine", "text"), "Catching up directly. Sends wait until the wallet has caught up and moved to Tor.")
            expect("...sends wait", shown("sendWaitNote") + " " + prop("reviewButton", "enabled"), "true false")
            fake.statusJson = JSON.stringify({ state: "ready", wallet: "w", network: "stagenet", route: "waiting_for_tor", onTor: false,
                                               waitingForTor: true, torUse: "identifying", connected: false })
        },
        function (v) {
            expect("waiting for Tor says so", prop("torRouteLine", "text"), "Waiting for Tor. Nothing is fetched or sent until it is ready.")
            fake.statusJson = JSON.stringify({ state: "ready", wallet: "w", network: "stagenet", route: "tor", onTor: true,
                                               waitingForTor: false, torUse: "identifying", connected: true })
        },
        function (v) {
            expect("on Tor", prop("torRouteLine", "text"), "Over Tor")
            expect("...sends open", shown("sendWaitNote") + " " + prop("reviewButton", "enabled"), "false true")
            fake.statusJson = JSON.stringify({ state: "ready", wallet: "w", network: "stagenet", route: "direct", torUse: "none", connected: true })
        },
        function (v) {
            expect("direct: no route line", shown("torRouteLine"), false)
            v.selectTab(4)
        },
        function (v) {
            expect("Settings shows the sheet's choice", [prop("settingsSourcePublic", "checked"), prop("settingsPublicChosen", "checked"),
                   prop("settingsPublicPicked", "checked"), prop("settingsSourceOwn", "checked")].join(" "), "true true false false")
            expect("...read-only", prop("settingsSourcePublic", "enabled") + " " + prop("settingsTorUse_identifying", "enabled"), "false false")
            expect("...and Use Tor for", shown("settingsTorUsePane") + " " + prop("settingsTorUse_identifying", "checked"), "true true")
            expect("...and Which Tor", shown("settingsBuiltInTor") + " " + prop("settingsBuiltInTor", "checked"), "true true")
            expect("...and where to change them", prop("settingsNodeLocked", "message").indexOf("These settings apply when a wallet opens") === 0, true)
            expect("an open wallet: no first-run screen", shown("torUsePage"), false)
            fake.nodeConfigJson = JSON.stringify({ url: "http://192.168.1.4:18081", own: true, mode: "remote", source: "external", network: "stagenet" })
        },
        function (v) {
            expect("your own node in Settings: no Use Tor for", [prop("settingsSourceOwn", "checked"), prop("settingsOwnAtAddress", "checked"),
                   shown("settingsTorUsePane"), shown("settingsBuiltInTor")].join(" "), "true true false false")
            expect("...reached directly", prop("settingsOwnRoute", "text"), "Reached directly. Tor can't reach your network.")
            fake.nodeConfigJson = JSON.stringify({ url: "https://node.example.com:18081", own: true, reachThroughTor: true, mode: "remote",
                                                   source: "external", network: "stagenet" })
        },
        function (v) {
            expect("your own node on the internet: its Tor switch and Which Tor", [shown("settingsOwnTorSwitch"), prop("settingsOwnTorSwitch", "checked"),
                   shown("settingsOwnBuiltInTor"), prop("settingsOwnBuiltInTor", "checked"), prop("settingsOwnBuiltInTor", "enabled")].join(" "),
                   "true true true true false")
        }
    ]
    property int step: 0
    Timer {
        id: driver
        interval: 30
        repeat: true
        onTriggered: {
            try { scene.steps[scene.step](view.item) } catch (e) { bad.push("step " + scene.step + " threw " + e) }
            scene.step += 1
            if (scene.step >= scene.steps.length) {
                driver.stop()
                console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + scene.steps.length + " steps")
                Qt.quit()
            }
        }
    }

    Loader {
        id: view
        anchors.fill: parent
        source: "../qml/MoneroWalletView.qml"
        onStatusChanged: {
            if (status === Loader.Error) { console.log("STATES-FAIL load"); Qt.quit(); return }
            if (status === Loader.Ready) driver.start()
        }
    }
}
