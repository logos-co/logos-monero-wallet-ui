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
        // What setLocalSends answers: "" stores the route, as the node does.
        property string sendsReply: ""
        function setLocalSends(v) {
            note("setLocalSends", [v])
            if (sendsReply !== "") return sendsReply
            var h = JSON.parse(nodeHealthJson || "{}")
            if (h.sends) { h.sends.localSends = v; h.sends.localSendsChosen = true }
            nodeHealthJson = JSON.stringify(h)
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
        // A dialog's footer buttons live in its action lists.
        ;[obj.leftActions, obj.rightActions].forEach(function (l) { if (l) for (var a = 0; a < l.length; a++) kids.push(l[a]) })
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
        // A dialog's footer buttons live in its action lists.
        ;[obj.leftActions, obj.rightActions].forEach(function (l) { if (l) for (var a = 0; a < l.length; a++) kids.push(l[a]) })
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
            expect("a fresh install: the Wallets screen, with a notice", shown("walletsPage") + " " + shown("nodeSetupNotice"), "true true")
            expect("...naming the network", prop("nodeSetupNotice", "title"), "Set up Node for stagenet")
            expect("...no first-run screen", shown("torUsePage"), "<no torUsePage>")
            expect("the network, picked in the header", prop("networkPicker", "displayText") + " " + prop("networkPicker", "enabled"), "stagenet true")
            expect("...not on the Wallets screen", shown("networkBox"), "<no networkBox>")
            expect("create and restore wait for it", ["newWalletButton", "restoreSeedOpen", "restoreKeysOpen"].map(function (n) { return prop(n, "enabled") }),
                   [false, false, false])
            click("nodeSetupButton")
        },
        function (v) {
            expect("Open Node opens the sheet", shown("nodeSheet"), true)
            expect("...saying it isn't saved", shown("nodeSetupSheetNotice") + " " + prop("nodeSetupSheetNotice", "title"), "true Not saved for stagenet yet")
            expect("...for this network", prop("nodeNetworkLine", "text"), "For stagenet. Each network has its own setting.")
            expect("...in the shared words", prop("torUseIntro", "text"), v.torUseIntro)
            expect("public sources picked for you, preselected", prop("sourcePublic", "checked") + " " + prop("publicPicked", "checked"), "true true")
            expect("three options", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "text") }),
                   ["Only what identifies you", "Everything", "Nothing"])
            expect("...each with what happens, pros and cons", ["identifying", "all", "none"].every(function (m) {
                return shown("torUse_info_" + m) === true && ["happens_", "pros_", "cons_"].every(function (k) {
                    return find(view.item, "torUse_" + k + m, 0) !== null && shown("torUse_" + k + m) === false }) }), true)
            var idInfo = find(view.item, "torUse_info_identifying", 0)
            idInfo.clicked()
            expect("its i opens them", [idInfo.opened, idInfo.title, shown("torUse_cons_identifying")], [true, "Only what identifies you", true])
            idInfo.close()
            expect("...in the plan's words", prop("torUse_cons_identifying", "text").indexOf("You can send only once the wallet has moved to Tor.") > 0, true)
            expect("fresh: identifying checked", checks("torUse_"), [true, false, false])
            expect("...and Recommended", shown("torUse_recommended_identifying"), true)
            expect("the button saves", prop("saveNodeButton", "text"), "Save")
            click("saveNodeButton")
        },
        function (v) {
            expect("Save stores the checked mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
            expect("...then the node on screen", saved(), { mode: "remote", source: "default", proxy: "" })
            expect("...and closes the sheet; the notice goes", shown("nodeSheet") + " " + shown("nodeSetupNotice"), "false false")
            expect("create is offered", prop("newWalletButton", "enabled"), true)
            v.torUseAnswered = false
            tor({ torUse: "all", torUseChosen: false, existing: true })
        },
        function (v) {
            expect("existing: the notice once more", shown("nodeSetupNotice"), true)
            click("nodeSettingsButton")
        },
        function (v) {
            expect("...its routing checked", checks("torUse_"), [false, true, false])
            fake.torUseReply = "Close your open accounts to change this."
            click("saveNodeButton")
        },
        function (v) {
            expect("Save unchanged keeps all-Tor", fake.last("setTorUse"), ["setTorUse", "all"])
            expect("a refusal shows in the sheet", prop("nodeSetupNote", "text"), "Close your open accounts to change this.")
            expect("...which stays open", shown("nodeSheet"), true)
            fake.torUseReply = ""
            click("torUse_none")
        },
        function (v) {
            expect("picking an option saves it", fake.last("setTorUse"), ["setTorUse", "none"])
            expect("...so the button is Done", [prop("saveNodeButton", "text"), v.nodeSetupNeeded], ["Done", false])
            v.closeSheets()
            v.torUseAnswered = false
        },
        function (v) {
            expect("...and the notice never shows again", shown("nodeSetupNotice"), false)
            v.torUseAnswered = true
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "stagenet"], active: "mainnet" })
            tor({ torUse: "identifying", torUseChosen: false, network: "mainnet" })
        },
        function (v) {
            expect("another network asks for itself", shown("nodeSetupNotice") + " " + prop("nodeSetupNotice", "title"), "true Set up Node for mainnet")
            expect("...the header shows it", prop("networkPicker", "displayText"), "mainnet")
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "stagenet"], active: "stagenet" })
            tor({ torUse: "none", torUseChosen: true, network: "stagenet" })
        },
        function (v) {
            expect("back on stagenet: chosen there", shown("nodeSetupNotice") + " " + prop("networkPicker", "displayText"), "false stagenet")
            fake.torUseJson = ""
        },
        function (v) {
            expect("an older backend: no notice", shown("nodeSetupNotice") + " " + shown("walletsPage"), "false true")
            expect("no wallet open: said once, under the title", [shown("syncChip"), prop("statusLine", "text")], [false, "No wallet open"])
            expect("...and no choice in the node sheet", v.torUse, "")
            tor({ torUse: "identifying", torUseChosen: false })
            fake.statusJson = JSON.stringify({ state: "opening" })
        },
        function (v) {
            expect("opening: no notice", v.nodeSetupNeeded, false)
            fake.statusJson = JSON.stringify({ state: "no_wallet" })
            tor({ torUse: "identifying", torUseChosen: false, existing: false })
        },
        function (v) {
            click("nodeSetupButton")
        },
        function (v) {
            click("sourceOwn")
        },
        function (v) {
            expect("your own node: its one note, behind its i", shown("ownNodeInfo") && !shown("ownNodeNote")
                   && prop("ownNodeNote", "text").indexOf("<b>Costs:</b>") > 0, true)
            expect("...with no node in Logos, at an address", prop("ownInLogos", "enabled") + " " + prop("ownAtAddress", "checked"), "false true")
            expect("...public sources folded away", shown("publicSourcesOption") + " " + shown("torUseSettings"), "false false")
            expect("...Save waits for an address", prop("saveNodeButton", "enabled"), false)
            find(view.item, "ownAddressField", 0).text = "http://192.168.1.20:18081"
        },
        function (v) {
            click("saveNodeButton")
        },
        function (v) {
            expect("your own node still stores the checked mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
            expect("...and the node at that address", saved().own + " " + saved().url, "true http://192.168.1.20:18081")
            expect("...then the sheet closes", shown("nodeSheet"), false)
            expect("an older node module: no Sending payments", shown("localSendsPane"), false)
            v.closeSheets()
            tor({ torUse: "identifying", torUseChosen: true })
            fake.nodeConfigJson = JSON.stringify({ url: "http://192.168.1.20:18081", own: true, mode: "remote", network: "stagenet" })
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 10, route: "direct", mode: "remote",
                sends: { localSends: "servers", localSendsChosen: false, localSendsRecommended: "servers",
                         sendNode: { url: "http://plowsof.onion:38089", operator: null } } })
            v.openSheet("node")
        },
        function (v) {
            expect("your node stored: Sending payments under it, a public node over Tor, recommended",
                   [shown("localSendsPane"), prop("localSends_servers", "checked"), shown("localSendsRecommended_servers"), shown("localSendsRecommended_node")],
                   [true, true, true, false])
            expect("...through the network's onion node", prop("localSendsServersLine", "text"), "Through a public node, at its onion address.")
            expect("...the note names both routes", prop("ownNodeNote", "text").indexOf("as Sending payments says") > 0, true)
            expect("...your node's note: its own IP", prop("localSendsNote_node", "text").indexOf("from its own IP address") > 0, true)
            click("localSends_node")
        },
        function (v) {
            expect("your node, stored at once", [fake.last("setLocalSends"), prop("localSends_node", "checked"), shown("localSendsServersLine")],
                   [["setLocalSends", "node"], true, false])
            fake.sendsReply = "Close your open accounts to change this."
            click("localSends_servers")
        },
        function (v) {
            expect("a refusal shows under the choice", [prop("localSendsNote", "text"), prop("localSends_node", "checked")],
                   ["Close your open accounts to change this.", true])
            fake.sendsReply = ""
            fake.localNodeJson = JSON.stringify({ available: true, rpcUrl: "http://127.0.0.1:38081" })
            click("ownInLogos")
        },
        function (v) {
            expect("another node in the form: no Sending payments until it is saved", [prop("ownInLogos", "checked"), shown("localSendsPane")], [true, false])
            fake.localNodeJson = "{}"
            v.closeSheets()
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
            expect("...for this network", prop("nodeNetworkLine", "text"), "For stagenet. Each network has its own setting.")
            expect("...and what every mode shares", shown("torUseEveryMode"), true)
            expect("...no lock line", shown("torUseLocked"), false)
            expect("the sheet reads top to bottom", inOrder(["sourceOwn", "sourcePublic", "publicPicked", "publicChosen", "torUse_all",
                                                              "torUse_identifying", "torUse_none", "publicBuiltInTor"]), "in order")
            expect("Which Tor under Use Tor for, with the Tor chip", shown("publicBuiltInTor") + " " + prop("publicBuiltInTor", "checked")
                   + " " + prop("publicTorChip", "text") + " " + shown("publicManageTor"), "true true Connecting to Tor… 40% true")
            var notes = findAll(find(view.item, "nodeSheet", 0), function (o) { return typeof o.text === "string" && o.text.indexOf("Benefits:") >= 0 })
            expect("one description of your own node", notes.length, 1)
            find(view.item, "publicManageTor", 0).activated("")
            var asked = logos.requests[logos.requests.length - 1]
            expect("Manage Tor raises tor.manage", asked ? asked.intent : "<none>", "tor.manage")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", prop("publicTorNote", "text"), "The Tor app is not installed.")
            expect("picked for you, it stores the module's own node", v.nodeDraft(), { mode: "remote", source: "default", proxy: "" })
            expect("...the button is Done", prop("saveNodeButton", "text") + " " + prop("saveNodeButton", "enabled"), "Done true")
            click("saveNodeButton")
        },
        function (v) {
            expect("Done, nothing changed: no save, and the sheet closes", [saved().url, shown("nodeSheet")], ["http://192.168.1.20:18081", false])
            v.openSheet("node")
        },
        function (v) {
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
            var c = v.nodeDraft()
            expect("Done stores your node direct", [c.mode, c.own, c.url, c.reachThroughTor, c.onionUrl, c.proxy, c.trusted, "password" in c],
                   ["remote", true, "https://my.node.example:18081", false, "", "", false, false])
            click("ownTorSwitch")
            click("ownOwnTor")
        },
        function (v) {
            expect("your own Tor needs its address", shown("ownProxyField") + " " + prop("saveNodeButton", "enabled"), "true false")
            setText("ownProxyField", "socks5://127.0.0.1:9050")
        },
        function (v) {
            var c = v.nodeDraft()
            expect("...or over your own Tor", [c.reachThroughTor, c.proxy], [true, "socks5://127.0.0.1:9050"])
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
            expect("...then the sheet closes", shown("nodeSheet"), false)
            fake.nodeConfigJson = JSON.stringify({ url: "https://my.node.example:18081", own: true, reachThroughTor: false, mode: "remote",
                                                   source: "external", network: "stagenet", username: "u", hasPassword: true })
            v.openSheet("node")
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
            v.openSheet("node")
        },
        function (v) {
            expect("a stored chosen node opens as stored", prop("publicChosen", "checked") + " " + prop("nodeHostField", "text"), "true https://chosen.example:18089")
            var c = v.nodeDraft()
            expect("...its login stays with its address", [c.username, "password" in c], ["u", false])
            setText("nodeHostField", "http://10.0.0.2:18089")
        },
        function (v) {
            expect("a chosen address on your network says what it becomes", shown("chosenLanNote"), true)
            expect("...and a new address drops the login", [v.nodeDraft().username, v.nodeDraft().password], ["", ""])
            setText("nodeOnionField", "http://x.onion:18089")
        },
        function (v) {
            expect("...but not with an address over Tor", shown("chosenLanNote"), false)
            setText("nodeOnionField", "")
        },
        function (v) {
            expect("What this means, for a node you choose", shown("torUse_info_all") && prop("torUse_happens_all", "text").indexOf("your address over Tor") > 0, true)
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
            expect("catching up says so", prop("torRouteLine", "text"), "Catching up directly. Sends wait until the wallet has moved to Tor.")
            expect("...and so does the chip, not the Tor node's check", prop("nodeChip", "text"), "catching up directly")
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
            expect("...the chip names the Tor node", prop("nodeChip", "text"), "node over Tor 900ms")
            expect("...sends open", shown("sendWaitNote") + " " + prop("reviewButton", "enabled"), "false true")
            expect("a node that isn't holding payments: no notice", shown("nodeHoldsSendsNotice"), false)
            fake.sendStatusJson = JSON.stringify({ state: "sent", txids: "ab12" })
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 10, mode: "local",
                local: { state: "running", txProxy: "on", txProxyWaiting: true,
                         txProxyReason: "No Tor peer yet. Payments wait in the node until one connects." },
                sends: { localSends: "node", localSendsChosen: false, localSendsRecommended: "node",
                         sendNode: { url: "http://plowsof.onion:38089", operator: null } } })
        },
        function (v) {
            expect("your node holding payments: the notice, with the node's reason", [shown("nodeHoldsSendsNotice"),
                   prop("nodeHoldsSendsNotice", "message")], [true, "No Tor peer yet. Payments wait in the node until one connects. "
                   + "In Activity they show as pending, and they don't go out over the ordinary network."])
            expect("...a send says it waits", prop("sendSentLine", "text"), "Handed to your node, which holds it until it reaches Tor. txid: ab12")
            click("nodeHoldsSendsButton")
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 10, mode: "local",
                local: { state: "running", txProxy: "on", txProxyWaiting: true }, sends: { localSends: "servers", sendNode: {} } })
        },
        function (v) {
            var asked = logos.requests[logos.requests.length - 1]
            expect("...the button opens the Monero Node app", asked ? asked.intent : "<none>", "monero.node.configure")
            expect("sends through a public node: no notice", shown("nodeHoldsSendsNotice"), false)
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 10, mode: "local", local: { state: "running", txProxy: "on", txProxyWaiting: false } })
        },
        function (v) {
            expect("your node on Tor: no notice, and a send is broadcast", [shown("nodeHoldsSendsNotice"), prop("sendSentLine", "text")],
                   [false, "Broadcast. txid: ab12"])
            fake.sendStatusJson = "{}"
            fake.nodeHealthJson = JSON.stringify({ reachable: true, height: 2000, route: "proxied", rttMs: 900, mode: "remote" })
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
            expect("an open wallet: no notice", v.nodeSetupNeeded, false)
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
        },
        function (v) {
            // A short window: the Node sheet scrolls, and its bar must leave the form's right edge clear.
            fake.statusJson = JSON.stringify({ state: "no_wallet" })
            scene.height = 560
        },
        function (v) {
            v.openSheet("node")
        },
        function (v) {
            var sv = find(view.item, "nodeScroll", 0), form = find(view.item, "walletsNodePage", 0)
            expect("a short window: the Node sheet scrolls", sv ? sv.effectiveScrollBarWidth > 0 : "<no nodeScroll>", true)
            expect("...and its bar leaves the form clear",
                   sv && form ? Math.round(form.mapToItem(sv, form.width, 0).x) <= sv.width - sv.effectiveScrollBarWidth : "<none>", true)
            v.closeSheets()
            scene.height = 900
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
