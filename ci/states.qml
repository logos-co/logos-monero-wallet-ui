import QtQuick

// Drives the view through the "Use Tor for" states against a fake backend: the first-run screen,
// the choice in the node sheet, the node form's Tor fields, and an open wallet's route.
// Prints STATES-OK, or STATES-FAIL with the cases that disagree.
Item {
    id: scene
    width: 1280; height: 900

    // The host injects `logos`; the view finds this one by name up its context chain.
    property QtObject logos: QtObject {
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        function module(name) { return fake }
        function isViewModuleReady(name) { return true }
        function request(intent, params, cb) {}
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
    function checks(prefix) { return ["identifying", "all", "none"].map(function (m) { return prop(prefix + m, "checked") }) }
    function tor(o) { fake.torUseJson = JSON.stringify(o) }

    readonly property var steps: [
        function (v) {
            tor({ torUse: "identifying", torUseChosen: false, existing: false })
        },
        function (v) {
            expect("a fresh install asks first", shown("torUsePage") + " " + shown("walletsPage"), "true false")
            expect("the intro", prop("torUseIntro", "text").indexOf("How should this wallet use Tor? Tor hides your IP address"), 0)
            expect("three options", ["identifying", "all", "none"].map(function (m) { return prop("torUseStart_" + m, "text") }),
                   ["Only what identifies you", "Everything", "Nothing"])
            expect("...each with what happens, pros and cons", ["identifying", "all", "none"].every(function (m) {
                return ["happens_", "pros_", "cons_"].every(function (k) { return shown("torUseStart_" + k + m) === true }) }), true)
            expect("...in the plan's words", prop("torUseStart_cons_identifying", "text").indexOf("You can send only once the wallet has caught up and moved to Tor.") > 0, true)
            expect("fresh: identifying preselected", checks("torUseStart_"), [true, false, false])
            expect("...and Recommended", shown("torUseStart_recommended_identifying"), true)
            expect("...no Current tag", ["all", "none", "identifying"].some(function (m) { return shown("torUseStart_current_" + m) === true }), false)
            find(view.item, "torUseContinue", 0).clicked()
        },
        function (v) {
            expect("Continue stores the preselected mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
            expect("...and the Wallets screen shows", shown("torUsePage") + " " + shown("walletsPage"), "false true")
            v.torUseAnswered = false
            tor({ torUse: "all", torUseChosen: false, existing: true })
        },
        function (v) {
            expect("existing: the screen shows once more", shown("torUsePage"), true)
            expect("...its routing preselected", checks("torUseStart_"), [false, true, false])
            expect("...tagged Current", shown("torUseStart_current_all"), true)
            expect("...identifying still Recommended", shown("torUseStart_recommended_identifying"), true)
            fake.torUseReply = "Close your open accounts to change this."
            find(view.item, "torUseContinue", 0).clicked()
        },
        function (v) {
            expect("a refusal shows inline", prop("torUseStartNote", "text"), "Close your open accounts to change this.")
            expect("...and the screen stays", shown("torUsePage"), true)
            fake.torUseReply = ""
            find(view.item, "torUseStart_none", 0).clicked()
        },
        function (v) {
            expect("picking moves the choice", checks("torUseStart_"), [false, false, true])
            expect("...Current stays on the node's", shown("torUseStart_current_all") + " " + shown("torUseStart_current_none"), "true false")
            find(view.item, "torUseContinue", 0).clicked()
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
            tor({ torUse: "identifying", torUseChosen: true })
            fake.nodeConfigJson = JSON.stringify({ url: "https://node2.monerodevs.org:38089", onionUrl: "http://abc.onion:38089",
                                                   proxy: "socks5h://127.0.0.1:9050", trusted: false, mode: "remote", network: "stagenet" })
            v.openSheet("node")
        },
        function (v) {
            expect("the node sheet has the choice", shown("torUseSettings"), true)
            expect("...the node's mode checked", checks("torUse_"), [true, false, false])
            expect("...enabled with no account open", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "enabled") }),
                   [true, true, true])
            expect("...no lock line", shown("torUseLocked"), false)
            expect("...the text behind What this means", find(view.item, "torUse_happens_all", 0), null)
            find(view.item, "torUseExplain", 0).activated("")
        },
        function (v) {
            expect("What this means shows it", shown("torUse_happens_all"), true)
            find(view.item, "torUse_all", 0).clicked()
        },
        function (v) {
            expect("picking stores it", fake.last("setTorUse"), ["setTorUse", "all"])
            expect("...and checks it", checks("torUse_"), [false, true, false])
            fake.busy = true
        },
        function (v) {
            expect("a job in flight locks the choice", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "enabled") }),
                   [false, false, false])
            expect("...saying why", shown("torUseLocked") && prop("torUseLocked", "text"), "Close your open accounts to change this.")
            fake.busy = false
            v.resetNodeForm()
        },
        function (v) {
            expect("the form holds both nodes", prop("nodeHostField", "text") + " " + prop("nodeOnionField", "text"),
                   "https://node2.monerodevs.org:38089 http://abc.onion:38089")
            expect("...and your own Tor", prop("nodeWhichTorBox", "currentIndex") + " " + prop("nodeProxyField", "text"), "1 socks5h://127.0.0.1:9050")
            expect("...no require-the-proxy box", find(view.item, "nodeProxyRequiredBox", 0), null)
            find(view.item, "saveNodeButton", 0).clicked()
        },
        function (v) {
            var c = (fake.last("saveNodeConfig") || [])[1] || {}
            expect("Save sends the onion node and your own Tor", [c.url, c.onionUrl, c.proxy, c.proxyRequired],
                   ["https://node2.monerodevs.org:38089", "http://abc.onion:38089", "socks5h://127.0.0.1:9050", undefined])
            find(view.item, "nodeWhichTorBox", 0).currentIndex = 0
        },
        function (v) {
            expect("the built-in Tor hides the address", shown("nodeProxyField"), false)
            find(view.item, "saveNodeButton", 0).clicked()
        },
        function (v) {
            expect("...and saves as the built-in Tor", ((fake.last("saveNodeConfig") || [])[1] || {}).proxy, "")
            find(view.item, "nodeWhichTorBox", 0).currentIndex = 1
            find(view.item, "nodeProxyField", 0).text = ""
        },
        function (v) {
            expect("your own Tor needs its address", prop("saveNodeButton", "enabled"), false)
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
            expect("Settings names the choice", prop("settingsTorUse", "text"), "Only what identifies you")
            expect("...and where to change it", shown("settingsTorUseLocked") && prop("settingsTorUseLocked", "text"),
                   "Close your open accounts to change this.")
            expect("an open wallet: no first-run screen", shown("torUsePage"), false)
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
