import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Monero wallet: one app, as every Monero wallet is one app. With nothing open it shows the
// Wallets screen (open · create · restore); with a wallet open it shows balances, send, receive
// and activity, and keeps close / change password / show seed under Settings, where Monero GUI
// keeps them.
//
// It takes the wallet password — as a SLOT argument only — and shows a seed as a SLOT return
// value only. Never a PROP: a PROP is cached in the replica and broadcast to every connected one.
//
// Every string this view did not author is rendered PlainText: LogosText is AutoText, and a
// wallet name is user input. EMPTY JSON means "not read yet" → em-dash.
Item {
    id: root
    objectName: "moneroWalletRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("monero_wallet_ui")
    property bool ready: false

    // A wallet another app asked us to open, answered once the open job settles. The NAME is
    // kept too: the user can reach the wallet list and open a different wallet in one click, and
    // answering ok for that one would tell the requester it has wallet A when it has wallet B.
    property string unlockRequestId: ""
    property string unlockWallet: ""
    property string shownSecret: ""
    property string secretKind: ""
    // Receive-tab selection and the inline label editor.
    property int labelIndex: -1
    property string labelDraft: ""
    // Which transaction row is expanded, by txid (an index would follow the wrong row when
    // the list re-sorts under a new confirmation).
    property string openTx: ""
    property bool clearNodePassword: false

    // ---- "Use Tor for": the node module's all, identifying or none, asked once before any account ----
    // Most private first; identifying stays the default.
    readonly property var torUseModes: ["all", "identifying", "none"]
    readonly property var torUseInfo: ready ? j(backend.torUseJson, "{}") : ({})
    readonly property string torUse: torUseModes.indexOf(torUseInfo.torUse) >= 0 ? torUseInfo.torUse : ""
    // False only from a node module that keeps the choice and has not been given it yet.
    readonly property bool torUseUnchosen: torUseInfo.torUseChosen === false
    // Continue was answered: the Wallets screen shows before the reads catch up.
    property bool torUseAnswered: false
    // The node refuses a change while a wallet is open, opening or closing.
    readonly property bool torUseLocked: walletOpen || busy || status.state === "opening" || status.state === "closing"
    readonly property bool torChoiceShown: ready && torUseUnchosen && !torUseAnswered && !torUseLocked
    // Picked on the first-run screen; until then the node's current routing, so Continue never weakens it.
    property string torChoice: ""
    readonly property string torChoiceMode: torChoice !== "" ? torChoice : (torUse !== "" ? torUse : "identifying")
    property bool torUseSending: false
    property string torUseStartNote: ""
    property string torUseNote: ""
    // The first-run choice of where the chain comes from; Public sources is preselected.
    property string startSource: "public"
    readonly property string startIntro: "Where should this wallet get Monero's chain? You can change this later under Node, "
                                         + "on the Wallets screen, while no account is open."
    readonly property string torUseIntro: "Tor hides your IP address, which can reveal where you are, from the nodes your wallet "
                                          + "talks to, but it is slower than a direct connection."
    // The one description of your own node, in the node sheet and on the first-run screen.
    readonly property string ownNodeNote: "<b>Benefits:</b> the wallet asks only your node for the chain and sends only through it, so "
                                          + "no one else's node sees your IP address with your sends and the outputs they spend. "
                                          + "<b>Costs:</b> on mainnet about 60 GB of disk pruned or 250 GB unpruned, a first sync that "
                                          + "takes hours to days, and the node must run while you use the wallet."
    readonly property var torUseCopy: ({
        identifying: {
            label: "Only what identifies you",
            happens: "Each time you open the wallet, it catches up from a regular Monero node directly. Once caught up, it "
                     + "switches to a node reachable only over Tor for everything else, sends included.",
            pros: "Catching up is much faster than over Tor. The node that sees your sends, and the outputs they spend, "
                  + "never sees your IP address.",
            cons: "The catch-up node and your internet provider can see that your IP address uses a Monero wallet, when you "
                  + "open it, and the block it starts from. You can send only once the wallet has caught up and moved to Tor."
        },
        all: {
            label: "Everything",
            happens: "Every connection goes through Tor, to a node reachable only over Tor.",
            pros: "No node learns your IP address, and your internet provider can't see that you use Monero.",
            cons: "The slowest choice. Catching up after weeks away, or restoring, can take hours, and it stops while Tor is down."
        },
        none: {
            label: "Nothing",
            happens: "Every connection is direct.",
            pros: "The fastest choice, and it works where Tor is blocked.",
            cons: "The node sees your IP address together with your sends and the outputs they spend. Your internet provider "
                  + "can see that you use Monero."
        }
    })
    // A node you choose: each mode dials your two addresses rather than public nodes.
    readonly property var torUseChosenHappens: ({
        identifying: "Each time you open the wallet, it catches up from your direct address. Once caught up, it switches to your "
                     + "address over Tor for everything else, sends included. Without one, it uses the direct address over Tor throughout.",
        all: "Every connection goes through Tor, to your address over Tor, or to the direct address over Tor without one.",
        none: "Every connection goes to the direct address, without Tor."
    })
    // `then(error)` gets "" once the node stored it.
    function setTorUse(mode, then) {
        root.torUseSending = true
        logos.watch(backend.setTorUse(mode),
                    function (e) { root.torUseSending = false; then(e || "") },
                    function () { root.torUseSending = false; then("The wallet backend did not answer.") })
    }
    // For a driver, like selectNetwork: the first-run pick without a click.
    function chooseTorUse(mode) {
        if (root.torChoiceShown && root.torUseModes.indexOf(mode) >= 0) root.torChoice = mode
    }
    function chooseStartSource(source) {
        if (root.torChoiceShown && (source === "own" || source === "public")) root.startSource = source
    }
    // Your own node still stores a mode, so a later switch to public sources has one: the recommended
    // one, or an existing install's routing. The node sheet then opens on your own node.
    function continueTorUse() {
        root.torUseStartNote = ""
        var own = root.startSource === "own"
        var mode = !own ? root.torChoiceMode : (root.torUseInfo.existing === true && root.torUse !== "" ? root.torUse : "identifying")
        root.setTorUse(mode, function (e) {
            root.torUseStartNote = e
            if (e !== "") return
            root.torUseAnswered = true
            if (own) { root.nodeSheetOwn = true; nodeSheet.open() }
        })
    }
    // What the open wallet is talking to, under "Use Tor for".
    function routeLine() {
        if (status.route === "catch_up") return "Catching up directly. Sends wait until the wallet has caught up and moved to Tor."
        if (status.route === "waiting_for_tor") return "Waiting for Tor. Nothing is fetched or sent until it is ready."
        if (status.route === "tor") return "Over Tor"
        return ""
    }

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "monero_wallet_ui") root.ready = isReady && root.backend !== null
        }
        // We PROVIDE both Monero capabilities. Another app (a receive-only till, a companion)
        // can ask this wallet to unlock or to bring wallet management up. The one we ask for is
        // monero.node.configure: the local node has its own app.
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent === "monero.accounts.manage") {
                if (root.walletOpen) root.selectTab(4)  // Settings holds management once open
                logos.respond(requestId, true, ({}), "")   // arriving IS the request; handoff keeps the user here
                return
            }
            if (intent !== "monero.wallet.unlock") return
            var w = params && params.wallet ? String(params.wallet) : ""
            if (w === "") { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (root.walletOpen && root.status.wallet === w) { logos.respond(requestId, true, ({}), ""); return }
            if (root.walletOpen) { logos.respond(requestId, false, ({}), "another wallet is already open"); return }
            root.unlockRequestId = requestId
            root.unlockWallet = w
            openNameField.text = w
            root.openSheet("open")
        }
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("monero_wallet_ui")

    function j(t, fb) { try { return JSON.parse(t && t.length ? t : fb) } catch (e) { return JSON.parse(fb) } }
    readonly property var status: ready ? j(backend.statusJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "{}") : ({})
    readonly property var wallets: ready ? j(backend.walletsJson, "[]") : []
    readonly property var node: ready ? j(backend.nodeHealthJson, "{}") : ({})
    readonly property var lastJob: ready ? j(backend.lastJobJson, "{}") : ({})
    readonly property bool busy: ready && backend.busy === true
    readonly property bool balancesRead: ready && backend.balancesJson !== ""
    readonly property var balances: balancesRead ? j(backend.balancesJson, "{}") : ({})
    readonly property bool receiveRead: ready && backend.receiveJson !== ""
    readonly property var receive: receiveRead ? j(backend.receiveJson, "{}") : ({})
    readonly property bool historyRead: ready && backend.historyJson !== ""
    readonly property var history: historyRead ? (j(backend.historyJson, "{}").rows || []) : []
    readonly property var send: ready ? j(backend.sendStatusJson, "{}") : ({})
    readonly property bool sendOpen: ready && backend.sendRequestId !== ""
    // Only a live send can be cancelled — the backend refuses cancel on a settled one, so the
    // Done button dismisses instead. An empty state (the record went away under us) dismisses too.
    readonly property bool sendLive: sendOpen && (send.state === "preparing" || send.state === "previewed"
                                                  || send.state === "committing")
    readonly property bool walletOpen: status.state === "ready" || status.state === "syncing"
    // `busy` means the engine held its wallet lock past the read deadline, so that status carries
    // the state machine and NOTHING about the chain — no `connected`, no heights (see
    // WalletRuntime::status). A transaction build holds it for ~15 s, so reading the ABSENCE of
    // `connected` as "disconnected" would raise a false alarm at exactly the moment the user is
    // reviewing a transaction, and pair it with a fabricated 0 / 0.
    readonly property bool engineBusy: ready && status.busy === true
    // The engine's OWN socket to the daemon — not the node module's separate health probe, which
    // is what the node chip shows. wallet2 keeps returning its last known daemon height after the
    // daemon goes away, so this is the difference between "your balance is current" and "this is
    // what we last heard", and the sync chip has to render that difference.
    readonly property bool engineConnected: ready && walletOpen && !engineBusy && status.connected === true
    readonly property bool viewOnly: !!status.watchOnly
    readonly property var nodeCfg: ready ? j(backend.nodeConfigJson, "{}") : ({})
    readonly property var localNode: ready ? j(backend.localNodeJson, "{}") : ({})
    // The mode the node form holds. Local is offered when monerod_module can serve this network,
    // or when it is already stored, so a user whose node module went away can switch back.
    readonly property string ndMode: ndSource === "own" && ndOwnKind === "logos" ? "local" : "remote"
    readonly property bool localOffered: localNode.available === true || nodeCfg.mode === "local"
    property string nodeIntentNote: ""
    // The node form edits ONE network's config, and the network picker sits on the same screen.
    // `nodeFormNetwork` records which network the fields currently hold, so a switch cannot save
    // one network's daemon over another's: the form repopulates when the new config arrives, and
    // Save is refused until it has.
    readonly property string activeNetwork: ready ? (networks.active || "") : ""
    readonly property string displayedNetwork: status.wallet ? (status.network || status.activeNetwork || "") : activeNetwork
    readonly property var walletsOnNetwork: wallets.filter(function(wallet) {
        return !wallet.network || wallet.network === root.activeNetwork
    })
    // The network the fields actually hold, taken from the CONFIG rather than from whatever is
    // active now: on a switch the new config arrives a poll later, and claiming the new network
    // while still showing the old one's daemon is the mis-save this exists to prevent.
    property string nodeFormNetwork: ""
    // A save was sent and we are waiting to see it in the stored config. Only a write that landed
    // changes nodeCfg, so this is what tells a successful save from a refused one.
    property bool nodeSavePending: false
    // The node sheet's draft, as its radios show it: where the chain comes from, then the choice under it.
    property string ndSource: "public"          // own | public
    property string ndOwnKind: "logos"          // logos (In Logos) | address
    property string ndPublicKind: "picked"      // picked | chosen
    property bool ndOwnTor: true                // Reach it through Tor, for your node on the internet
    property string ndWhichTor: "tor"           // tor (comes with Logos) | own
    property string ndProxyText: ""
    // The first-run screen chose your own node: the sheet opens on it.
    property bool nodeSheetOwn: false
    readonly property string ndOwnAddressKind: root.addressKind(ndOwnAddr.text)
    // Which Tor shows only where Tor is used: your own node by its address, public sources unless Nothing.
    readonly property bool ndUsesTor: ndSource === "own"
        ? ndOwnKind === "address" && (ndOwnAddressKind === "onion" || (ndOwnAddressKind === "internet" && ndOwnTor))
        : torUse !== "none"
    // Where the stored record gets the chain.
    readonly property string storedSource: nodeCfg.mode === "local" ? "own-logos" : nodeCfg.own === true ? "own-address"
        : (nodeCfg.source === "default" || !nodeCfg.url) ? "public-picked" : "public-chosen"
    // The built-in Tor as the node module last saw it, on a route through it.
    readonly property var torView: node.tor || null
    property string torNote: ""
    onActiveNetworkChanged: root.resetNodeForm()
    onNodeCfgChanged: {
        if (root.nodeSavePending || root.nodeFormNetwork !== (root.nodeCfg.network || ""))
            root.resetNodeForm()
    }
    readonly property int selectedIndex: ready ? backend.selectedSubaddress : 0
    readonly property string selectedAddress: {
        if (!root.receiveRead) return ""
        var subs = receive.subaddresses || []
        if (root.selectedIndex >= 0 && root.selectedIndex < subs.length) return subs[root.selectedIndex].address
        return receive.address || ""
    }

    // When an unlock another app asked for settles, answer the requester; the shell returns them.
    onLastJobChanged: {
        if (root.unlockRequestId === "" || !lastJob.kind) return
        if (lastJob.kind !== "open") return
        var opened = lastJob.state === "done"
        // Identity, not just success: a different wallet may have been opened from the list.
        var mine = opened && root.status.wallet === root.unlockWallet
        var err = !opened ? (lastJob.error || "open failed") : (mine ? "" : "a different wallet was opened")
        logos.respond(root.unlockRequestId, mine, ({}), err)
        root.unlockRequestId = ""
        root.unlockWallet = ""
    }

    // Two page spaces: the Wallets screen while nothing is open, the wallet's tabs once it is.
    // The harness navigates with these rather than clicking a tab: only the active StackLayout
    // page is in the visible scene, and a text-click on a TabButton is not a reliable switch.
    property int page: 0            // 0 Home, 1 Send, 2 Receive, 3 Activity, 4 Settings
    function selectTab(i) { root.page = i; tabs.currentIndex = i }
    // The wallet forms are sheets, so there is no page index to select any more. One named
    // entry point instead — for a driver, and for the intent handler above.
    function selectNetwork(network) {
        if (root.ready && !root.busy && !root.walletOpen)
            backend.setActiveNetwork(network)
    }

    function openSheet(which) {
        if (which === "open")   { openWalletSheet.open(); return }
        if (which === "create") { createSheet.open();  return }
        if (which === "seed")   { seedSheet.open();    return }
        if (which === "keys")   { keysSheet.open();    return }
        if (which === "node")   { nodeSheet.open();    return }
    }
    // Populate the node form from the active network's stored config, dropping any half-finished
    // edit. `clearNodePassword` is armed by the Clear stored button and, before this, was reset
    // only by Save or Revert — so it survived leaving the page and even a network switch, and the
    // next Save cleared a password the user never meant to touch.
    function resetNodeForm() {
        if (!ndHost) return
        var c = root.nodeCfg
        var local = c.mode === "local"
        var mine = c.own === true
        var picked = c.source === "default" || !c.url
        root.ndSource = local || mine ? "own" : "public"
        root.ndOwnKind = local ? "logos" : (mine ? "address" : (root.localOffered ? "logos" : "address"))
        root.ndPublicKind = picked || mine ? "picked" : "chosen"
        ndOwnAddr.text = mine ? (c.url || "") : ""
        ndUser.text = mine ? (c.username || "") : ""
        ndHost.text = !mine && !picked ? (c.url || "") : ""
        ndOnion.text = !mine && !picked ? (c.onionUrl || "") : ""
        root.ndOwnTor = c.reachThroughTor !== false
        var ownTor = !!c.proxy && c.proxy !== "tor"
        root.ndProxyText = ownTor ? c.proxy : ""
        root.ndWhichTor = ownTor ? "own" : "tor"
        ndTrusted.checked = !!c.trusted
        root.nodeIntentNote = ""
        root.torNote = ""
        ndPass.text = ""
        root.clearNodePassword = false
        root.nodeSavePending = false
        root.nodeFormNetwork = root.nodeCfg.network || ""
    }
    // The node line for the sheet and Settings. In local mode it describes the node on this
    // device, including when it is stopped or serving another network.
    function nodeLine() {
        if (node.mode === "local") {
            var l = node.local || {}
            if (l.state === "unavailable") return "Local node: " + (l.error || "unavailable")
            if (l.state !== "running") return "Local node: " + (l.state || "unknown")
            if (l.network && l.network !== root.activeNetwork)
                return "Local node is running " + l.network + ", not " + root.activeNetwork
            if (node.reachable !== true) return "Local node: " + (node.error || "not answering yet")
            return "Local node · height " + node.height
                + (node.synced ? " · synced" : node.targetHeight > node.height
                   ? " / " + node.targetHeight + " · syncing" : " · waiting for peers")
        }
        return node.reachable === true
            ? ("Reachable · height " + node.height + " · " + (node.route === "proxied" ? "over Tor" : "direct") + " · " + (node.rttMs || 0) + "ms")
            : ("Node: " + (node.error || "unknown"))
    }
    function nodeChip() {
        var local = node.mode === "local"
        if (node.reachable === true)
            return (local ? "local node " : "node " + (node.route === "proxied" ? "over Tor" : (node.route || "")) + " ") + (node.rttMs || 0) + "ms"
        if (node.reachable === false) return local ? "local node " + ((node.local || {}).state || "unavailable") : "node unreachable"
        return ""
    }
    function manageLocalNode() {
        root.nodeIntentNote = ""
        logos.request("monero.node.configure", ({ network: root.activeNetwork }), function (res) {
            if (res.ok) { backend.refreshLocalNode(); return }
            if (res.error === "cancelled") return
            root.nodeIntentNote = res.error === "unavailable"
                ? "The Monero node app is not installed."
                : "That request did not go through (" + res.error + ")."
        })
    }
    // The built-in Tor has its own app.
    function manageTor() {
        root.torNote = ""
        logos.request("tor.manage", ({}), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.torNote = res.error === "unavailable" ? "The Tor app is not installed."
                                                        : "That request did not go through (" + res.error + ")."
        })
    }
    function torChipText() {
        var t = root.torView
        if (!t) return ""
        if (t.state === "ready") return t.socks ? "Connected to Tor" : "Tor's port is off"
        if (t.state === "connecting") return "Connecting to Tor… " + (t.progress || 0) + "%"
        if (t.state === "idle") return "Tor not started"
        return t.state === "blocked" ? "Tor can't connect" : "Tor is not available"
    }
    function torChipColor() {
        var t = root.torView
        if (t && t.state === "ready" && t.socks) return Theme.palette.success
        return t && (t.state === "connecting" || t.state === "idle") ? Theme.palette.warning : Theme.palette.error
    }
    // The host of http(s)://host:port/..., as the node module reads it (tor.rs host_of).
    function hostOf(url) {
        var rest = String(url || "").trim()
        var i = rest.indexOf("://")
        if (i >= 0) rest = rest.slice(i + 3)
        rest = rest.split(/[\/?#]/)[0]
        rest = rest.slice(rest.lastIndexOf("@") + 1)
        if (rest.charAt(0) === "[") return rest.slice(1).split("]")[0].toLowerCase()
        var c = rest.lastIndexOf(":")
        return (c >= 0 ? rest.slice(0, c) : rest).toLowerCase()
    }
    // lan, onion or internet, by the node module's classes (tor.rs is_own_network, is_onion); "" when empty.
    function addressKind(url) {
        var h = root.hostOf(url)
        if (h === "") return ""
        if (/\.onion$/.test(h)) return "onion"
        if (h === "localhost" || /\.(localhost|local|lan|home\.arpa)$/.test(h)) return "lan"
        var privateV4 = function (a, b) { return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) }
        var v4 = h.match(/^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/)
        if (v4) return privateV4(+v4[1], +v4[2]) || (+v4[1] === 169 && +v4[2] === 254) || h === "0.0.0.0" ? "lan" : "internet"
        if (h.indexOf(":") < 0) return "internet"
        if (h === "::1" || h === "::") return "lan"
        var mapped = h.match(/^::ffff:(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/)
        if (mapped) return privateV4(+mapped[1], +mapped[2]) ? "lan" : "internet"
        var s = h.indexOf("::") === 0 ? 0 : parseInt(h.split(":")[0], 16)
        return (s & 0xfe00) === 0xfc00 || (s & 0xffc0) === 0xfe80 ? "lan" : "internet"
    }
    // The engine trusts only a loopback daemon (wallet_runtime isLoopback), so Trusted shows only there.
    function isLoopback(url) {
        var h = root.hostOf(url)
        return h === "127.0.0.1" || h === "localhost" || h === "::1"
    }
    // For the radios and a driver: where the chain comes from, and optionally the choice under it.
    function chooseNodeSource(source, kind) {
        if (source === "own") {
            if (root.ndSource !== "own" && root.nodeCfg.mode !== "local" && root.nodeCfg.own !== true)
                root.ndOwnKind = root.localOffered ? "logos" : "address"
            root.ndSource = "own"
            if ((kind === "logos" && root.localOffered) || kind === "address") root.ndOwnKind = kind
        } else if (source === "public") {
            root.ndSource = "public"
            if (kind === "picked" || kind === "chosen") root.ndPublicKind = kind
        }
    }
    // What Save stores for the choice on screen. A hidden field sends what is stored, never its edits.
    function nodeDraft() {
        var c = root.nodeCfg
        var proxy = !root.ndUsesTor ? (c.proxy || "") : (root.ndWhichTor === "own" ? root.ndProxyText.trim() : "")
        var cfg = null
        if (root.ndSource === "own" && root.ndOwnKind === "logos") {
            // The record keeps its remote half as stored; without "password" the backend keeps that too.
            cfg = { mode: "local", url: c.url || "", onionUrl: c.onionUrl || "", username: c.username || "", proxy: c.proxy || "",
                    trusted: !!c.trusted, own: c.own === true, reachThroughTor: c.reachThroughTor !== false, source: c.source || "external" }
            return cfg
        }
        if (root.ndSource === "own") {
            var url = ndOwnAddr.text.trim()
            cfg = { mode: "remote", own: true, url: url, onionUrl: "", username: ndUser.text.trim(), proxy: proxy,
                    reachThroughTor: root.ndOwnTor, trusted: root.isLoopback(url) && ndTrusted.checked }
            // Omitting password KEEPS the stored one; "" clears it.
            if (ndPass.text !== "") cfg.password = ndPass.text
            else if (root.clearNodePassword) cfg.password = ""
            return cfg
        }
        if (root.ndPublicKind === "picked") return { mode: "remote", source: "default", proxy: proxy }
        var direct = ndHost.text.trim()
        cfg = { mode: "remote", url: direct, onionUrl: ndOnion.text.trim(), proxy: proxy, trusted: false }
        // A login stored for this address stays with it, and only with it.
        if (c.own !== true && c.source !== "default" && direct === (c.url || "")) cfg.username = c.username || ""
        else { cfg.username = ""; cfg.password = "" }
        return cfg
    }
    // Save is offered only for a choice that can be stored. Hidden fields never gate it.
    function nodeDraftReady() {
        if (!root.ready || root.busy || root.torUseLocked) return false
        // Empty means the form holds no other network's config, which must still be able to save.
        if (root.nodeFormNetwork !== "" && root.nodeFormNetwork !== root.activeNetwork) return false
        if (root.ndUsesTor && root.ndWhichTor === "own" && root.ndProxyText.trim() === "") return false
        if (root.ndSource === "own") return root.ndOwnKind === "logos" ? root.localOffered : ndOwnAddr.text.trim() !== ""
        return root.ndPublicKind === "picked" || ndHost.text.trim() !== ""
    }
    // The stored choice, for Settings.
    function sourceLine() {
        var c = root.nodeCfg
        if (root.storedSource === "own-logos") return "Your own node, in Logos"
        if (root.storedSource === "own-address") {
            var k = root.addressKind(c.url)
            return "Your own node at an address, " + (k === "onion" || (k === "internet" && c.reachThroughTor !== false)
                                                     ? "reached through Tor" : "reached directly")
        }
        return root.storedSource === "public-chosen" ? "Public sources: a node you choose" : "Public sources: a node picked for you"
    }
    function localNodeLine() {
        if (root.localNode.available !== true)
            return "The Monero Node app isn't running a node for " + (root.activeNetwork || "this network") + " on this computer."
        return "Node on this device: " + ((root.localNode.status || {}).state || "unknown")
    }
    function parseQr(s) { try { return s ? JSON.parse(s) : null } catch (e) { return null } }
    function qrRuns(qr) {
        const runs = []
        for (let y = 0; y < qr.size; y++) {
            let x = 0
            while (x < qr.size) {
                if (qr.bits.charAt(y * qr.size + x) !== "1") { x++; continue }
                const start = x
                while (x < qr.size && qr.bits.charAt(y * qr.size + x) === "1") x++
                runs.push([start, y, x - start])
            }
        }
        return runs
    }
    function hideSecret() { root.shownSecret = ""; root.secretKind = "" }

    // Copy without a C++ round trip: QML runs in the shell process, and a TextEdit's copy()
    // is the only clipboard the ui_qml sandbox exposes. Kept off-screen and cleared after use
    // so nothing lingers in a visible item.
    TextEdit { id: clipHelper; visible: false; width: 0; height: 0 }

    // One "Use Tor for" option: its label and tags, then what happens, pros and cons while `explained`.
    component TorUseOption: ColumnLayout {
        id: option
        property string prefix: ""
        property string mode: ""
        property bool checked: false
        property bool explained: true
        // The first-run screen tags the node's current routing; Settings shows it checked.
        property bool withCurrent: false
        // For a node you choose rather than one picked for you.
        property bool chosen: false
        signal picked()
        readonly property var copy: option.chosen
            ? Object.assign({}, root.torUseCopy[mode] || ({}), { happens: root.torUseChosenHappens[mode] })
            : (root.torUseCopy[mode] || ({}))
        Layout.fillWidth: true
        spacing: Theme.spacing.tiny
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosRadioButton { objectName: option.prefix + option.mode; checkable: false; checked: option.checked
                               text: option.copy.label || ""; onClicked: option.picked() }
            LogosBadge { objectName: option.prefix + "recommended_" + option.mode; visible: option.mode === "identifying"
                         text: "Recommended"; color: Theme.palette.success }
            LogosBadge { objectName: option.prefix + "current_" + option.mode
                         visible: option.withCurrent && option.mode === root.torUse && option.mode !== "identifying"
                         text: "Current"; color: Theme.palette.textSecondary }
            Item { Layout.fillWidth: true }
        }
        Repeater {
            model: option.explained ? [["What happens", option.copy.happens], ["Pros", option.copy.pros], ["Cons", option.copy.cons]] : []
            LogosText {
                required property var modelData
                required property int index
                objectName: option.prefix + ["happens_", "pros_", "cons_"][index] + option.mode
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.StyledText; color: Theme.palette.textSecondary
                text: "<b>" + modelData[0] + ":</b> " + (modelData[1] || "")
            }
        }
    }
    property string copied: ""
    Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = "" }
    function copyText(what, text) {
        if (!text) return
        clipHelper.text = text
        clipHelper.selectAll()
        clipHelper.copy()
        clipHelper.text = ""
        root.copied = what
        copiedTimer.restart()
    }
    function shortId(s) { return s && s.length > 20 ? s.slice(0, 10) + "…" + s.slice(-8) : (s || "") }
    function whenOf(ts) { return ts ? new Date(ts * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : "—" }
    function xmrOf(atomic) { return root.ready ? backend.formatXmr(String(atomic || "0")) : "" }
    // monero zeroes an outgoing amount when every output came back to the same account, "so that
    // it's less confusing" (wallet2.cpp, process_new_transaction). The raw row then reads
    // −0.000000000000 XMR, which is faithful and unreadable: only the fee actually left.
    function isSelfSend(r) { return !!r && r.direction === "out" && r.amount === "0" }
    // Drop a revealed secret whenever it stops being this wallet's, on this page — not only
    // when the user happens to press Hide or the one Close button. Any holder of either role
    // can close the session out from under this view.
    function closeSheets() {
        openWalletSheet.close(); createSheet.close(); seedSheet.close()
        keysSheet.close(); nodeSheet.close()
    }
    onWalletOpenChanged: { root.hideSecret(); if (root.walletOpen) root.closeSheets() }
    onPageChanged: if (root.page !== 4) root.hideSecret()

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10

        // Persistent chrome: network, view-only, sync, node.
        RowLayout {
            Layout.fillWidth: true
            LogosText { text: "Monero"; font.pixelSize: 22 }
            Item { Layout.fillWidth: true }
            LogosText {
                objectName: "syncChip"; textFormat: Text.PlainText; font.pixelSize: 12
                // `connected` is what makes these heights a live claim rather than a memory.
                // wallet2 keeps returning its last known daemon height after the daemon goes
                // away, so without this the chip went on saying "Synced … 100%" for as long as
                // the app stayed open — and in a wallet that reads as "your balance is current".
                // It is the ENGINE's own socket, which is not the same question as the node
                // chip beside it: that one is the node module's separate health probe, and the
                // two can disagree (a proxy that only the engine is configured for, say).
                text: !root.ready ? "Connecting…" : (root.walletOpen
                    ? (root.engineBusy ? "Working…"
                       : ((root.engineConnected ? (status.synchronized ? "Synced " : "Syncing ") : "Last seen ")
                          + (status.walletHeight || 0) + " / " + (status.daemonHeight || 0) + " (" + (status.syncPercent || 0) + "%)"
                          + (root.engineConnected ? "" : " · not connected")))
                    : "No wallet open")
            }
            LogosText { objectName: "nodeChip"; textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                        text: root.nodeChip() }

            // Badges, not hand-rolled Rectangles, and coloured the way the EVM wallet colours
            // its chain chip: the live network is `success`, every test network `accentOrange`.
            // That is the inverse of what this view did — it painted MAINNET red — and the
            // family's reading is the better one: orange marks the networks where the money is
            // not real, so the unmarked, calm state is the one that costs something.
            LogosBadge {
                objectName: "viewOnlyBadge"
                visible: root.viewOnly
                text: "VIEW-ONLY"
                color: Theme.palette.warning
            }
            LogosBadge {
                objectName: "networkChip"
                text: (root.displayedNetwork || "—").toUpperCase()
                color: root.displayedNetwork === "mainnet"
                       ? Theme.palette.success : Theme.palette.accentOrange
            }
            // Closing is a session action, so it belongs in the session's own chrome rather than
            // four clicks away under Settings. Nothing is destroyed: the wallet file stays, and
            // this is the only way back to the wallet list.
            LogosButton {
                objectName: "closeWalletButton"
                visible: root.walletOpen
                enabled: root.ready && !root.busy
                text: "Close wallet"
                onClicked: { root.hideSecret(); backend.closeWallet() }
            }
        }

        // One line a driver (and a user) can read the whole wallet state from.
        LogosText {
            objectName: "statusLine"
            textFormat: Text.PlainText
            text: !root.ready ? "" : (root.walletOpen
                // No percentage while the engine is busy: the status then carries no heights, and
                // "0%" on a wallet that is 100% synced is the same fabrication the chip beside
                // this line already refuses to make.
                ? ("Open: " + status.wallet + " · " + status.state + " · "
                   + (root.engineBusy ? "—" : ((status.syncPercent || 0) + "%")))
                : (status.state === "opening" ? "Opening…" : (status.state === "closing" ? "Closing…" : "No wallet open")))
        }

        LogosText { objectName: "torRouteLine"; visible: root.walletOpen && text !== ""; text: root.routeLine(); textFormat: Text.PlainText
                    wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary }

        LogosText { objectName: "errorLine"; visible: root.ready && backend.lastError !== ""; text: root.ready ? backend.lastError : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.error }

        // A send whose outcome is unknown is reported HERE, above the tabs, not inside the Send
        // tab: the tab space is hidden whenever the wallet is not open, and the engine dying is
        // both what makes the outcome unknown AND what closes the wallet. Inside the sheet this
        // banner was invisible in exactly the case it exists for.
        // A LogosFrame with warning-coloured text, not a tinted Rectangle: the family paints no
        // coloured banner fills, and there is no token for one — the weight comes from the words
        // and from `palette.warning`, which stays legible on whatever the frame sits on.
        // The frame's contentItem, NOT a child: LogosFrame overrides none, so a plain child
        // would be laid out on top of the frame's own content item rather than inside it.
        LogosFrame {
            objectName: "sendUnknownBanner"
            visible: root.ready && send.state === "unknown"
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Theme.spacing.tiny
                LogosText { text: "A transaction's outcome is unknown"; wrapMode: Text.Wrap; Layout.fillWidth: true
                            color: Theme.palette.warning }
                LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                            text: send.error || "" }
                LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                            text: "Check Activity once the wallet re-syncs, before sending again." }
                LogosButton { objectName: "dismissUnknownButton"; text: "Dismiss"; onClicked: backend.dismissSend() }
            }
        }

        // ================= NO WALLET OPEN: the Wallets screen =================
        // Shaped like the keystore's Accounts screen: a heading, one row of actions, and the
        // list. The forms are modal sheets rather than a second tab strip — a six-tab strip
        // above a two-row list made the list look like one option among six, and left four
        // tabs' worth of empty form on screen whenever the user was not filling one in.
        ColumnLayout {
            objectName: "walletsPage"
            visible: root.ready && !root.walletOpen && !root.torChoiceShown
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                LogosText { text: "Wallets"; font.pixelSize: 22 }
                Item { Layout.fillWidth: true }
                LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                            text: "Network" }
                LogosComboBox {
                    id: netBox
                    objectName: "networkBox"
                    enabled: root.ready && !root.busy
                    model: networks.networks || []
                    currentIndex: Math.max(0, (networks.networks || []).indexOf(networks.active || ""))
                    onActivated: root.selectNetwork(currentText)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosButton { objectName: "newWalletButton";    text: "Create";          enabled: root.ready && !root.busy; onClicked: createSheet.open() }
                LogosButton { objectName: "restoreSeedOpen";    text: "Restore phrase";  enabled: root.ready && !root.busy; onClicked: seedSheet.open() }
                LogosButton { objectName: "restoreKeysOpen";    text: "Restore keys";    enabled: root.ready && !root.busy; onClicked: keysSheet.open() }
                LogosButton { objectName: "nodeSettingsButton"; text: "Node";            enabled: root.ready;              onClicked: nodeSheet.open() }
                Item { Layout.fillWidth: true }
                LogosButton { objectName: "refreshWalletsButton"; text: "Refresh"; enabled: root.ready; onClicked: backend.clearAndRefresh() }
            }

            // One container for both the empty state and the list, so the empty state is
            // centred in the space the list would have filled rather than pinned to the top.
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                LogosText {
                    objectName: "walletsEmpty"
                    anchors.centerIn: parent
                    visible: root.walletsOnNetwork.length === 0
                    color: Theme.palette.textSecondary
                    text: "No wallets on " + (root.activeNetwork || "this network") + " yet"
                }

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacing.tiny
                    model: root.walletsOnNetwork
                    delegate: LogosFrame {
                        width: ListView.view.width
                        contentItem: RowLayout {
                            spacing: Theme.spacing.small
                            // A wallet name is user-typed, so PlainText: LogosText is AutoText.
                            LogosText { text: modelData.name; textFormat: Text.PlainText }
                            LogosText { text: modelData.network || "Network checked when opened"; textFormat: Text.PlainText
                                        color: Theme.palette.textTertiary }
                            LogosBadge {
                                visible: !!modelData.viewOnly
                                text: "VIEW-ONLY"
                                color: Theme.palette.warning
                            }
                            Item { Layout.fillWidth: true }
                            LogosButton {
                                text: "Open"
                                enabled: root.ready && !root.busy
                                onClicked: { openNameField.text = modelData.name; openWalletSheet.open() }
                            }
                        }
                    }
                }
            }
        }

        // ================= FIRST RUN: where the chain comes from, asked once =================
        // The node sheet's top choice, Public sources preselected with Use Tor for under it.
        ScrollView {
            id: torUseScroll
            objectName: "torUsePage"
            visible: root.torChoiceShown
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: torUseScroll.availableWidth
                spacing: Theme.spacing.medium
                LogosText { text: "Where the wallet gets Monero's chain"; font.pixelSize: 22 }
                LogosText { objectName: "startIntro"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                            text: root.startIntro }
                LogosFrame {
                    Layout.fillWidth: true
                    borderColor: root.startSource === "own" ? Theme.palette.primary : Theme.palette.border
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            spacing: Theme.spacing.small
                            LogosRadioButton { objectName: "startOwn"; checkable: false; checked: root.startSource === "own"; text: "Your own node"
                                               enabled: !root.torUseSending; onClicked: root.startSource = "own" }
                            LogosBadge { text: "Most private"; color: Theme.palette.success }
                            Item { Layout.fillWidth: true }
                        }
                        LogosText { objectName: "startOwnNote"; visible: root.startSource === "own"; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    textFormat: Text.StyledText; color: Theme.palette.textSecondary; text: root.ownNodeNote }
                        LogosText { objectName: "startOwnNext"; visible: root.startSource === "own"; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    color: Theme.palette.textSecondary
                                    text: "Continue opens the node settings, where you pick the node in Logos or one at an address." }
                    }
                }
                LogosFrame {
                    Layout.fillWidth: true
                    borderColor: root.startSource === "public" ? Theme.palette.primary : Theme.palette.border
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout {
                            spacing: Theme.spacing.small
                            LogosRadioButton { objectName: "startPublic"; checkable: false; checked: root.startSource === "public"; text: "Public sources"
                                               enabled: !root.torUseSending; onClicked: root.startSource = "public" }
                            LogosText { text: "Nodes run by other people."; color: Theme.palette.textSecondary }
                            Item { Layout.fillWidth: true }
                        }
                        ColumnLayout {
                            objectName: "startPublicOptions"
                            visible: root.startSource === "public"
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacing.xlarge + Theme.spacing.small
                            spacing: Theme.spacing.small
                            LogosText { text: "Use Tor for"; font.weight: Theme.typography.weightBold }
                            LogosText { objectName: "torUseIntro"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                        text: root.torUseIntro }
                            Repeater {
                                model: root.torUseModes
                                LogosFrame {
                                    id: startOption
                                    required property string modelData
                                    Layout.fillWidth: true
                                    borderColor: root.torChoiceMode === modelData ? Theme.palette.primary : Theme.palette.border
                                    contentItem: TorUseOption {
                                        prefix: "torUseStart_"
                                        mode: startOption.modelData
                                        checked: root.torChoiceMode === startOption.modelData
                                        withCurrent: true
                                        enabled: !root.torUseSending
                                        onPicked: root.torChoice = startOption.modelData
                                    }
                                }
                            }
                        }
                    }
                }
                LogosText { objectName: "torUseStartNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                            textFormat: Text.PlainText; color: Theme.palette.error; text: root.torUseStartNote }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    LogosButton {
                        objectName: "torUseContinue"
                        text: root.torUseSending ? "Saving…" : "Continue"
                        variant: LogosButton.Variant.Primary
                        enabled: root.ready && !root.torUseSending
                        onClicked: root.continueTorUse()
                    }
                }
            }
        }

        // ================= A WALLET IS OPEN =================
        LogosTabBar {
            id: tabs; visible: root.walletOpen; Layout.fillWidth: true
            // NOT `currentIndex: root.page`. TabBar assigns currentIndex itself on a click,
            // which breaks a declarative binding for good — after the first click the pane
            // still followed selectTab while the highlight stayed behind. The strip notifies,
            // selectTab assigns both. No loop: assigning an unchanged index emits nothing.
            onCurrentIndexChanged: root.selectTab(currentIndex)
            LogosTabButton { text: "Home" }
            LogosTabButton { text: "Send" }
            LogosTabButton { text: "Receive" }
            LogosTabButton { text: "Activity" }
            LogosTabButton { text: "Settings" }
        }

        StackLayout {
            visible: root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.page

            // Home
            ColumnLayout {
                spacing: 6
                LogosText { textFormat: Text.PlainText; text: "Wallet: " + (status.wallet || "") }
                LogosText { objectName: "balanceText"; font.pixelSize: 28; textFormat: Text.PlainText
                            text: root.balancesRead ? (balances.balanceXmr + " XMR") : "— XMR" }
                LogosText { objectName: "unlockedText"; textFormat: Text.PlainText; color: Theme.palette.textSecondary
                            text: root.balancesRead ? ("Unlocked: " + balances.unlockedXmr + " XMR") : "Unlocked: —" }
                LogosText { visible: root.balancesRead && balances.balance !== balances.unlocked; color: Theme.palette.textTertiary
                            text: "Incoming funds unlock after 10 confirmations (~20 min)." }
                LogosButton { text: "Refresh"; onClicked: backend.clearAndRefresh() }
            }

            // Send
            ColumnLayout {
                spacing: 8
                LogosText { visible: root.viewOnly; text: "This is a view-only wallet; it cannot spend." }
                LogosTextField { id: sendAddr; objectName: "sendAddressField"; placeholderText: "Destination address"; Layout.fillWidth: true; enabled: !root.viewOnly && !root.sendOpen }
                LogosTextField { id: sendAmt; objectName: "sendAmountField"; placeholderText: "Amount (XMR)"; Layout.fillWidth: true; enabled: !root.viewOnly && !root.sendOpen
                            validator: RegularExpressionValidator { regularExpression: /^[0-9]*\.?[0-9]{0,12}$/ } }
                // A segmented row, the way the EVM wallet offers its fee tiers: four options are
                // a choice to see, not a list to open, and `variant` is what makes the current
                // one visible. `prioIndex` is what prepareSend sends, so the mapping stays where
                // it was — index 0..3 = Default/Low/Medium/High.
                RowLayout {
                    id: prio
                    property int prioIndex: 0
                    spacing: Theme.spacing.tiny
                    Repeater {
                        model: ["Default", "Low", "Medium", "High"]
                        LogosButton {
                            objectName: "priority" + modelData
                            text: modelData
                            enabled: !root.sendOpen
                            variant: prio.prioIndex === index ? LogosButton.Variant.Primary
                                                              : LogosButton.Variant.Secondary
                            onClicked: prio.prioIndex = index
                        }
                    }
                }
                LogosText { objectName: "sendError"; visible: root.ready && backend.sendError !== ""; text: root.ready ? backend.sendError : ""; textFormat: Text.PlainText; color: Theme.palette.error; wrapMode: Text.Wrap; Layout.fillWidth: true }
                LogosText { objectName: "sendWaitNote"; visible: status.waitingForTor === true && !root.sendOpen; wrapMode: Text.Wrap; Layout.fillWidth: true
                            color: Theme.palette.textSecondary; text: "You can send once the wallet has caught up and moved to Tor." }
                LogosButton {
                    objectName: "reviewButton"; text: "Review"
                    enabled: root.ready && !root.viewOnly && !root.sendOpen && status.waitingForTor !== true
                             && sendAddr.text !== "" && sendAmt.text !== "" && sendAmt.text !== "."
                    onClicked: backend.prepareSend(JSON.stringify({ address: sendAddr.text, amountXmr: sendAmt.text, priority: prio.prioIndex }))
                }
                // The review sheet. What it governs is BROADCAST: the engine signed at build.
                Rectangle {
                    visible: root.sendOpen
                    Layout.fillWidth: true; implicitHeight: revCol.implicitHeight + 24; radius: 6
                    color: Theme.palette.surface
                    ColumnLayout {
                        id: revCol; anchors.fill: parent; anchors.margins: 12; spacing: 4
                        LogosText { objectName: "sendState"; textFormat: Text.PlainText; text: "Status: " + (send.state || "") }
                        LogosText { visible: send.state === "preparing"; text: "Building the transaction (fetching decoys)…" }
                        LogosText { visible: !!send.preview; textFormat: Text.PlainText; text: "To: " + (send.preview ? send.preview.destination : "") ; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                        LogosText { objectName: "previewAmount"; visible: !!send.preview; textFormat: Text.PlainText; text: "Amount: " + (send.preview ? send.preview.amountXmr : "") + " XMR" }
                        LogosText { objectName: "previewFee"; visible: !!send.preview; textFormat: Text.PlainText; text: "Fee: " + (send.preview ? send.preview.feeXmr : "") + " XMR" }
                        LogosText { objectName: "previewTotal"; visible: !!send.preview; textFormat: Text.PlainText; text: "Total: " + (send.preview ? send.preview.totalXmr : "") + " XMR" }
                        LogosText { visible: send.state === "sent"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                    text: send.txids ? ("Broadcast. txid: " + send.txids)
                                                     : "Broadcast. Its transaction id will appear in Activity once the wallet re-syncs." }
                        RowLayout {
                            LogosButton { objectName: "confirmSendButton"; text: "Confirm and broadcast"; visible: send.state === "previewed"; onClicked: backend.confirmSend() }
                            LogosButton {
                                objectName: "sendDismissButton"
                                text: root.sendLive ? "Cancel" : "Done"
                                visible: send.state !== "committing"
                                // Read the state BEFORE acting: both calls clear it, and the
                                // fields must still be cleared after a send that went out.
                                onClicked: {
                                    var s = send.state
                                    if (root.sendLive) backend.cancelSend(); else backend.dismissSend()
                                    if (s === "sent" || s === "unknown") { sendAddr.text = ""; sendAmt.text = "" }
                                }
                            }
                        }
                    }
                }
            }

            // Receive — the address list is selectable, and the QR, the URI and every copy
            // target follow the selection, the way monero-wallet-gui's Receive page works.
            ColumnLayout {
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    LogosText { objectName: "receiveAddress"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                text: root.receiveRead ? (root.selectedAddress || "—") : "—" }
                    LogosButton { objectName: "copyAddressButton"; text: "Copy address"
                                  enabled: !!root.selectedAddress
                                  onClicked: root.copyText("Address", root.selectedAddress) }
                }
                LogosText { objectName: "copiedNote"; visible: root.copied !== ""; color: Theme.palette.textSecondary
                            textFormat: Text.PlainText; text: root.copied + " copied to the clipboard" }

                RowLayout {
                    spacing: 12
                    // Plain rectangles, one per run of dark modules: the sandbox refuses every URL
                    // import (data: URIs included) and a Canvas never receives paint() in this host.
                    // The only two literal colours left in this file, and they must stay literal:
                    // a QR is a contrast target, not a themed surface, and a palette white on a
                    // palette black is a scanner failure waiting for a theme change.
                    Rectangle {
                        id: qrBox
                        objectName: "qrBox"
                        readonly property var qr: root.ready ? root.parseQr(backend.qrModulesJson) : null
                        readonly property int quiet: 2
                        readonly property int cell: qr ? Math.max(1, Math.floor(220 / (qr.size + quiet * 2))) : 0
                        visible: !!qr
                        color: "#ffffff"
                        Layout.preferredWidth: qr ? cell * (qr.size + quiet * 2) : 0
                        Layout.preferredHeight: Layout.preferredWidth
                        Repeater {
                            model: qrBox.qr ? root.qrRuns(qrBox.qr) : []
                            Rectangle {
                                x: (modelData[0] + qrBox.quiet) * qrBox.cell; y: (modelData[1] + qrBox.quiet) * qrBox.cell
                                width: modelData[2] * qrBox.cell; height: qrBox.cell; color: "#000000"
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 6
                        LogosText { text: "Amount to receive (XMR)"; color: Theme.palette.textSecondary }
                        RowLayout {
                            LogosTextField {
                                id: wantAmt; objectName: "receiveAmountField"; placeholderText: "optional"
                                Layout.preferredWidth: 200
                                validator: RegularExpressionValidator { regularExpression: /^[0-9]*\.?[0-9]{0,12}$/ }
                                onTextChanged: backend.setReceiveAmount(text)
                            }
                            LogosButton { text: "Clear"; visible: wantAmt.text !== ""; onClicked: wantAmt.text = "" }
                        }
                        LogosText { text: "Payment URL"; color: Theme.palette.textSecondary }
                        LogosText { objectName: "receiveUriText"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                                    Layout.preferredWidth: 420; font.pixelSize: 11
                                    text: root.ready ? (backend.receiveUri || "—") : "—" }
                        LogosButton { objectName: "copyUriButton"; text: "Copy payment URL"
                                      enabled: root.ready && backend.receiveUri !== ""
                                      onClicked: root.copyText("Payment URL", backend.receiveUri) }
                    }
                }

                LogosText { text: "Addresses"; font.pixelSize: 15 }
                RowLayout {
                    LogosTextField { id: subLabel; objectName: "newAddressLabelField"; placeholderText: "Label for a new address"; Layout.fillWidth: true }
                    LogosButton { objectName: "createAddressButton"; text: "Create new address"
                                  onClicked: { backend.createSubaddress(subLabel.text); subLabel.text = "" } }
                }
                ListView {
                    objectName: "subaddressList"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: root.receiveRead ? (receive.subaddresses || []) : []
                    delegate: Rectangle {
                        width: ListView.view.width
                        implicitHeight: subRow.implicitHeight + 10
                        color: index === root.selectedIndex ? Theme.palette.surface : "transparent"
                        radius: 4
                        MouseArea { anchors.fill: parent; onClicked: backend.selectSubaddress(index) }
                        RowLayout {
                            id: subRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6; anchors.rightMargin: 6
                            spacing: 8
                            LogosText { textFormat: Text.PlainText; font.pixelSize: 11; color: Theme.palette.textTertiary
                                        text: "#" + modelData.index + (index === root.selectedIndex ? "  ●" : "") }
                            LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                        Layout.preferredWidth: 140; elide: Text.ElideRight
                                        text: modelData.label || "(no label)" }
                            LogosText { textFormat: Text.PlainText; font.pixelSize: 11; Layout.fillWidth: true
                                        elide: Text.ElideMiddle; text: modelData.address }
                            LogosButton { text: "Copy"; onClicked: root.copyText("Address", modelData.address) }
                            LogosButton { text: "Set label"; onClicked: { root.labelIndex = modelData.index; root.labelDraft = modelData.label || ""; } }
                        }
                    }
                }
                // Set Label, as an inline editor rather than a dialog the sandbox would have to host.
                Rectangle {
                    objectName: "labelEditor"
                    visible: root.labelIndex >= 0
                    Layout.fillWidth: true; implicitHeight: labRow.implicitHeight + 20; radius: 6
                    color: Theme.palette.surface
                    RowLayout {
                        id: labRow; anchors.fill: parent; anchors.margins: 10; spacing: 8
                        LogosText { textFormat: Text.PlainText; text: "Label for #" + root.labelIndex }
                        LogosTextField { objectName: "labelField"; text: root.labelDraft; Layout.fillWidth: true
                                    onTextChanged: root.labelDraft = text }
                        LogosButton { objectName: "saveLabelButton"; text: "Save"
                                      onClicked: { backend.setSubaddressLabel(root.labelIndex, root.labelDraft); root.labelIndex = -1 } }
                        LogosButton { text: "Clear label"
                                      onClicked: { backend.setSubaddressLabel(root.labelIndex, ""); root.labelIndex = -1 } }
                        LogosButton { text: "Cancel"; onClicked: root.labelIndex = -1 }
                    }
                }
            }

            // Activity — a row expands into the detail monero-wallet-gui shows on a transaction:
            // date, amount, fee, confirmations, blockheight, payment ID, destinations, txid.
            ColumnLayout {
                LogosText { objectName: "historyEmpty"; visible: root.historyRead && root.history.length === 0; text: "No transactions yet." }
                LogosText { visible: !root.historyRead; text: "—" }
                LogosText { objectName: "copiedNoteActivity"; visible: root.copied !== ""; color: Theme.palette.textSecondary
                            textFormat: Text.PlainText; text: root.copied + " copied to the clipboard" }
                ListView {
                    objectName: "historyList"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    spacing: 2
                    model: root.history
                    delegate: Rectangle {
                        id: txRow
                        width: ListView.view.width
                        implicitHeight: txCol.implicitHeight + 12
                        radius: 4
                        readonly property bool open: root.openTx === modelData.txid
                        color: open ? Theme.palette.surface : "transparent"
                        ColumnLayout {
                            id: txCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                LogosText { textFormat: Text.PlainText
                                            text: root.isSelfSend(modelData)
                                                  ? ("to yourself · fee " + modelData.feeXmr + " XMR")
                                                  : ((modelData.direction === "in" ? "+" : "−") + modelData.amountXmr + " XMR") }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary
                                            text: modelData.failed ? "failed"
                                                  : (modelData.pending ? "pending"
                                                  : (modelData.confirmations + " conf" + (modelData.confirmations < 10 ? " (locked)" : ""))) }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            text: root.whenOf(modelData.timestamp) }
                                Item { Layout.fillWidth: true }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 10
                                            text: root.shortId(modelData.txid) }
                                LogosButton { text: txRow.open ? "Hide" : "Details"
                                              onClicked: root.openTx = (root.openTx === modelData.txid ? "" : modelData.txid) }
                            }
                            GridLayout {
                                visible: txRow.open
                                columns: 2; columnSpacing: 14; rowSpacing: 3
                                Layout.fillWidth: true
                                LogosText { text: "Date"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; text: root.whenOf(modelData.timestamp) }
                                LogosText { text: "Amount"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            text: root.isSelfSend(modelData)
                                                  ? "— (every output came back to this account; only the fee left)"
                                                  : (modelData.amountXmr + " XMR") }
                                LogosText { text: "Fee"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.direction === "in" ? "—  (paid by the sender)" : modelData.feeXmr + " XMR" }
                                LogosText { text: "Confirmations"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.failed ? "— (failed)"
                                                  : (modelData.pending ? "0 (unconfirmed)" : String(modelData.confirmations)) }
                                LogosText { text: "Blockheight"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.height ? String(modelData.height) : "—" }
                                LogosText { text: "Payment ID"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; text: modelData.paymentId || "—" }
                                LogosText { text: "Description"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; text: modelData.description || "—" }
                                LogosText { text: "Sent to"; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            visible: modelData.direction !== "in" }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; wrapMode: Text.WrapAnywhere
                                            Layout.fillWidth: true
                                            visible: modelData.direction !== "in"
                                            // wallet2 records destinations only for transfers this wallet made.
                                            text: (modelData.destinations && modelData.destinations.length)
                                                  ? modelData.destinations.map(function (d) { return d.address }).join("\n")
                                                  : "not recorded by the wallet" }
                                LogosText { text: "Received on"; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            visible: modelData.direction === "in" }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            visible: modelData.direction === "in"
                                            text: modelData.subaddrIndex ? ("subaddress #" + modelData.subaddrIndex) : "—" }
                                LogosText { text: "Transaction ID"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosText { objectName: "txidText"; textFormat: Text.PlainText; font.pixelSize: 11
                                                wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; text: modelData.txid }
                                    LogosButton { objectName: "copyTxidButton"; text: "Copy"
                                                  onClicked: root.copyText("Transaction ID", modelData.txid) }
                                }
                            }
                        }
                    }
                }
                LogosButton { text: "Refresh"; onClicked: backend.refreshHistory() }
            }

            // Settings — wallet management and the remote node, where monero-wallet-gui keeps them.
            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 8
                    // Closing lives in the chrome, always visible while a wallet is open, rather
                    // than four clicks into this tab.
                    LogosText { text: "Wallet"; font.pixelSize: 16 }
                    LogosText { text: "Change wallet password"; color: Theme.palette.textSecondary }
                    RowLayout {
                        LogosTextField { id: oldPw; objectName: "oldPasswordField"; placeholderText: "Current password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
                        LogosTextField { id: newPw; objectName: "newPasswordField"; placeholderText: "New password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
                        LogosButton { objectName: "changePasswordButton"; text: "Change"; enabled: !root.busy && oldPw.text !== "" && newPw.text !== ""
                                      onClicked: { backend.changePassword(oldPw.text, newPw.text); oldPw.text = ""; newPw.text = "" } }
                    }

                    LogosText { text: "Show seed & keys"; color: Theme.palette.textSecondary }
                    RowLayout {
                        LogosTextField { id: revealPw; objectName: "revealPasswordField"; placeholderText: "Password to reveal"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
                        LogosButton {
                            objectName: "revealSeedButton"; text: "Show seed"; enabled: revealPw.text !== "" && !root.viewOnly
                            onClicked: {
                                root.secretKind = "mnemonic seed"
                                logos.watch(backend.revealSeed(revealPw.text), function (v) { root.shownSecret = v || "" }, function () { root.shownSecret = "" })
                                revealPw.text = ""
                            }
                        }
                        LogosButton {
                            objectName: "revealViewKeyButton"; text: "Show view key"; enabled: revealPw.text !== ""
                            onClicked: {
                                root.secretKind = "secret view key"
                                logos.watch(backend.revealViewKey(revealPw.text), function (v) { root.shownSecret = v || "" }, function () { root.shownSecret = "" })
                                revealPw.text = ""
                            }
                        }
                    }
                    Rectangle {
                        visible: root.shownSecret !== ""
                        Layout.fillWidth: true; implicitHeight: secretCol.implicitHeight + 24
                        color: Theme.palette.surface
                        radius: 6
                        ColumnLayout {
                            id: secretCol; anchors.fill: parent; anchors.margins: 12
                            LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true
                                        text: "Your " + root.secretKind + ". DO NOT share it with anyone: it can "
                                              + (root.secretKind === "mnemonic seed" ? "spend" : "see") + " your funds. Store a copy securely; it is not kept here." }
                            TextEdit { objectName: "secretText"; text: root.shownSecret; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; Layout.fillWidth: true; color: Theme.palette.text }
                            RowLayout {
                                LogosButton { text: "Copy"; onClicked: root.copyText(root.secretKind === "mnemonic seed" ? "Seed" : "View key", root.shownSecret) }
                                LogosButton { text: "Hide"; onClicked: root.hideSecret() }
                            }
                        }
                    }

                    // ---- Remote node: READ-ONLY here ----
                    // The form lives on the Wallets screen, not in this tab. It can only be
                    // saved while no wallet is open (wallet2 binds its daemon at open, and the
                    // backend refuses the write), and this tab only exists while one IS open —
                    // so a form here is visible exactly when it cannot be used. It was, and the
                    // node was unchangeable from the app.
                    LogosText { text: "Node"; font.pixelSize: 16 }
                    LogosText { objectName: "settingsNodeSource"; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
                                text: root.sourceLine() }
                    LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                                text: root.nodeLine() }
                    LogosText { objectName: "settingsNodeUrl"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; color: Theme.palette.textSecondary
                                text: "Address: " + (root.nodeCfg.mode === "local"
                                                     ? "the node on this device" + ((node.local || {}).rpcUrl ? " (" + node.local.rpcUrl + ")" : "")
                                                     : (root.nodeCfg.url || "—")) }
                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: "Network: " + root.displayedNetwork }
                    // Use Tor for applies to public sources only; read-only here for the same reason as the node.
                    RowLayout {
                        visible: root.torUse !== "" && root.storedSource.indexOf("public") === 0
                        spacing: Theme.spacing.small
                        LogosText { text: "Use Tor for:"; color: Theme.palette.textSecondary }
                        LogosText { objectName: "settingsTorUse"; textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                    text: (root.torUseCopy[root.torUse] || {}).label || "" }
                    }
                    LogosText { objectName: "settingsTorUseLocked"; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textTertiary
                                text: "Close this wallet to change these, under Node on the Wallets screen: the wallet binds its node when it opens." }

                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary
                                text: "Engine: monero_c " + (status.libraryVersion || "") + " (LGPL-3.0, dynamically linked)" }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ── the wallet forms, as modal sheets ──────────────────────────────────────────────────
    // Declared outside the layout: a Dialog inside a ColumnLayout is laid out like any other
    // item and reserves space even while closed. Every title is a literal — LogosDialog renders
    // `title` as AutoText and a wallet name is user input.
    LogosDialog {
        id: openWalletSheet
        objectName: "openWalletSheet"
        title: "Open a wallet"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        onClosed: openPw.text = ""
        contentItem: ColumnLayout {
            spacing: 8
            LogosText { visible: root.unlockRequestId !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true
                        text: "Another app asked to unlock this wallet." }
            LogosTextField { id: openNameField; objectName: "openNameField"; placeholderText: "Wallet name"; Layout.fillWidth: true }
            LogosTextField {
                id: openPw; objectName: "openPasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                // `accepted` belongs to the inner TextInput: LogosTextField is a Control
                // wrapping one, not a TextField, and assigning onAccepted on the control
                // is a COMPILE error — which takes the whole view down, not just this
                // field. Same reason passwordMaskDelay is set through `textInput`.
                Component.onCompleted: textInput.passwordMaskDelay = 0
                Connections {
                    target: openPw.textInput
                    function onAccepted() { if (openButton.enabled) openButton.clicked() }
                }
            }
            LogosButton {
                id: openButton
                objectName: "openButton"; text: root.busy ? "Opening…" : "Open"
                enabled: root.ready && !root.busy && openNameField.text !== ""
                onClicked: { backend.openWallet(openNameField.text, openPw.text); openPw.text = ""; openWalletSheet.close() }
            }
        }
    }

    LogosDialog {
        id: createSheet
        objectName: "createWalletSheet"
        title: "Create a wallet"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        onOpened: { cName.text = ""; cPw.text = ""; cPw2.text = "" }
        onClosed: { cPw.text = ""; cPw2.text = "" }
        contentItem: ColumnLayout {
            spacing: 8
            LogosTextField { id: cName; objectName: "createNameField"; placeholderText: "Wallet name"; Layout.fillWidth: true }
            LogosTextField { id: cLabel; placeholderText: "Label (optional)"; Layout.fillWidth: true }
            LogosTextField { id: cPw; objectName: "createPasswordField"; placeholderText: "Add a strong password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosTextField { id: cPw2; placeholderText: "Repeat password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosText { visible: cPw.text !== cPw2.text && cPw2.text !== ""; text: "Passwords do not match" }
            LogosButton {
                objectName: "createButton"; text: root.busy ? "Creating…" : "Create wallet"
                enabled: root.ready && !root.busy && cName.text !== "" && cPw.text !== "" && cPw.text === cPw2.text
                onClicked: { backend.createWallet(cName.text, cPw.text, cLabel.text); cPw.text = ""; cPw2.text = ""; createSheet.close() }
            }
            LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                        text: "The wallet opens once it is created. Write down your mnemonic seed and keep it safe — "
                              + "Settings › Show seed & keys, behind your password." }
        }
    }

    LogosDialog {
        id: seedSheet
        objectName: "restoreSeedSheet"
        title: "Restore from a recovery phrase"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        onClosed: { rSeed.text = ""; rPw.text = "" }
        contentItem: ColumnLayout {
            spacing: 8
            LogosTextField { id: rName; placeholderText: "Wallet name"; Layout.fillWidth: true }
            // LogosTextArea sets placeholderTextColor from the theme; the raw TextArea
            // left the 25-word prompt unreadable on the dark background.
            LogosTextArea { id: rSeed; objectName: "seedField"; placeholderText: "25-word mnemonic seed"; Layout.fillWidth: true; Layout.preferredHeight: 90 }
            LogosTextField { id: rHeight; placeholderText: "Restore height (block number; 0 scans from genesis — hours)"; Layout.fillWidth: true; validator: IntValidator { bottom: 0 } }
            LogosTextField { id: rPw; placeholderText: "New wallet password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosButton {
                objectName: "restoreSeedButton"
                text: root.busy ? "Restoring…" : "Restore"
                enabled: root.ready && !root.busy && rName.text !== "" && rSeed.text.trim().split(/\s+/).length === 25 && rPw.text !== ""
                onClicked: { backend.restoreFromSeed(rName.text, rPw.text, rSeed.text.trim(), parseInt(rHeight.text || "0"), ""); rSeed.text = ""; rPw.text = ""; seedSheet.close() }
            }
        }
    }

    LogosDialog {
        id: keysSheet
        objectName: "restoreKeysSheet"
        title: "Restore from keys"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        onClosed: { kView.text = ""; kSpend.text = ""; kPw.text = "" }
        contentItem: ColumnLayout {
            spacing: 8
            LogosTextField { id: kName; placeholderText: "Wallet name"; Layout.fillWidth: true }
            LogosTextField { id: kAddr; placeholderText: "Primary address"; Layout.fillWidth: true }
            LogosTextField { id: kView; placeholderText: "Private view key"; Layout.fillWidth: true }
            LogosTextField { id: kSpend; placeholderText: "Private spend key (leave empty for a view-only wallet)"; Layout.fillWidth: true }
            LogosTextField { id: kHeight; placeholderText: "Restore height"; Layout.fillWidth: true; validator: IntValidator { bottom: 0 } }
            LogosTextField { id: kPw; placeholderText: "New wallet password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosButton {
                objectName: "restoreKeysButton"
                text: root.busy ? "Restoring…" : (kSpend.text === "" ? "Restore view-only wallet" : "Restore wallet")
                enabled: root.ready && !root.busy && kName.text !== "" && kAddr.text !== "" && kView.text !== "" && kPw.text !== ""
                onClicked: { backend.restoreFromKeys(kName.text, kPw.text, kAddr.text, kView.text, kSpend.text, parseInt(kHeight.text || "0"), ""); kView.text = ""; kSpend.text = ""; kPw.text = ""; keysSheet.close() }
            }
        }
    }

    // Which Tor, wherever the choice above it uses Tor: the one that comes with Logos, or your own.
    component WhichTor: ColumnLayout {
        id: which
        property string prefix: ""
        Layout.fillWidth: true
        spacing: Theme.spacing.tiny
        LogosText { text: "Which Tor"; font.weight: Theme.typography.weightBold }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosRadioButton { objectName: which.prefix + "BuiltInTor"; checkable: false; checked: root.ndWhichTor === "tor"
                               text: "The Tor that comes with Logos"; onClicked: root.ndWhichTor = "tor" }
            LogosBadge { objectName: which.prefix + "TorChip"; visible: root.ndWhichTor === "tor" && root.torView !== null
                         text: root.torChipText(); color: root.torChipColor() }
            LogosLink { objectName: which.prefix + "ManageTor"; visible: root.ndWhichTor === "tor"; text: "Manage Tor…"; underline: false
                        onActivated: root.manageTor() }
            Item { Layout.fillWidth: true }
        }
        LogosRadioButton { objectName: which.prefix + "OwnTor"; checkable: false; checked: root.ndWhichTor === "own"
                           text: "Your own Tor"; onClicked: root.ndWhichTor = "own" }
        LogosTextField { objectName: which.prefix + "ProxyField"; visible: root.ndWhichTor === "own"; Layout.fillWidth: true
                         Layout.leftMargin: Theme.spacing.xlarge + Theme.spacing.small
                         placeholderText: "Its SOCKS address, e.g. socks5h://127.0.0.1:9050"
                         text: root.ndProxyText; onTextChanged: root.ndProxyText = text }
        LogosText { objectName: which.prefix + "TorNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                    textFormat: Text.PlainText; color: Theme.palette.error; text: root.torNote }
    }

    LogosDialog {
        id: nodeSheet
        objectName: "nodeSheet"
        title: "Node"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720)
        height: Math.min(parent.height - 40, implicitHeight)
        onOpened: {
            root.resetNodeForm()
            if (root.nodeSheetOwn) { root.nodeSheetOwn = false; root.chooseNodeSource("own") }
            backend.refreshLocalNode()
        }
        // One decision, top to bottom: your own node or public sources, and under each only what it uses.
        // Save stays in view below the scrolling part.
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            ScrollView {
                id: nodeScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: nodeForm.implicitHeight
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    id: nodeForm
                    // Named so a test can assert REACHABILITY: findByProperty ignores visibility, so the
                    // fields alone would pass even with this sheet hidden behind an open wallet.
                    objectName: "walletsNodePage"
                    width: nodeScroll.availableWidth
                    spacing: Theme.spacing.small
                    readonly property int indent: Theme.spacing.xlarge + Theme.spacing.small

                    LogosText { text: "Where the wallet gets Monero's chain"; font.pixelSize: 16; font.weight: Theme.typography.weightBold }
                    LogosText { objectName: "nodeNetworkLine"; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
                                color: Theme.palette.textSecondary; text: "For " + (networks.active || "this network") + ". Each network keeps its own." }
                    LogosText { objectName: "torUseLocked"; visible: root.torUseLocked; Layout.fillWidth: true; wrapMode: Text.Wrap
                                color: Theme.palette.textSecondary; text: "Close your open accounts to change this." }

                    ColumnLayout {
                        Layout.fillWidth: true
                        enabled: root.ready && !root.torUseLocked
                        spacing: Theme.spacing.small

                        RowLayout {
                            spacing: Theme.spacing.small
                            LogosRadioButton { objectName: "sourceOwn"; checkable: false; checked: root.ndSource === "own"; text: "Your own node"
                                               onClicked: root.chooseNodeSource("own") }
                            LogosBadge { text: "Most private"; color: Theme.palette.success }
                            Item { Layout.fillWidth: true }
                        }
                        ColumnLayout {
                            objectName: "ownNodeOption"
                            visible: root.ndSource === "own"
                            Layout.fillWidth: true
                            Layout.leftMargin: nodeForm.indent
                            spacing: Theme.spacing.small
                            LogosText { objectName: "ownNodeNote"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.StyledText
                                        color: Theme.palette.textSecondary; text: root.ownNodeNote }

                            LogosRadioButton { objectName: "ownInLogos"; checkable: false; checked: root.ndOwnKind === "logos"; text: "In Logos"
                                               enabled: root.localOffered; onClicked: root.chooseNodeSource("own", "logos") }
                            ColumnLayout {
                                objectName: "localNodePane"
                                // Shown without a node too: Open Monero Node is how to get one.
                                visible: root.ndOwnKind === "logos" || !root.localOffered
                                Layout.fillWidth: true
                                Layout.leftMargin: nodeForm.indent
                                spacing: Theme.spacing.tiny
                                LogosText { objectName: "localNodeState"; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
                                            color: Theme.palette.textSecondary; text: root.localNodeLine() }
                                LogosText { objectName: "localNodeAddress"; visible: !!root.localNode.rpcUrl; textFormat: Text.PlainText
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; color: Theme.palette.textSecondary
                                            text: "Address: " + (root.localNode.rpcUrl || "") }
                                RowLayout {
                                    LogosButton { objectName: "manageLocalNodeButton"; text: "Open Monero Node…"; onClicked: root.manageLocalNode() }
                                    Item { Layout.fillWidth: true }
                                }
                                LogosText { objectName: "nodeIntentNote"; visible: text !== ""; textFormat: Text.PlainText; wrapMode: Text.Wrap
                                            Layout.fillWidth: true; color: Theme.palette.error; text: root.nodeIntentNote }
                                LogosText { objectName: "ownNodePeers"; visible: root.ndOwnKind === "logos"; Layout.fillWidth: true
                                            wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                                            text: "The wallet's connection never leaves this computer. The node's own connections to its peers "
                                                  + "are set in the Monero Node app, which can send them through a proxy." }
                                // Follows the node while the user starts it elsewhere. Only while it is there to ask:
                                // an absent module costs 1.5 s per read.
                                Timer { interval: 3000; repeat: true
                                        running: nodeSheet.opened && root.ndMode === "local" && root.localNode.available === true
                                        onTriggered: backend.refreshLocalNode() }
                            }

                            LogosRadioButton { objectName: "ownAtAddress"; checkable: false; checked: root.ndOwnKind === "address"; text: "At an address"
                                               onClicked: root.chooseNodeSource("own", "address") }
                            ColumnLayout {
                                objectName: "ownAddressPane"
                                visible: root.ndOwnKind === "address"
                                Layout.fillWidth: true
                                Layout.leftMargin: nodeForm.indent
                                spacing: Theme.spacing.tiny
                                LogosText { text: "A node you run elsewhere."; color: Theme.palette.textSecondary }
                                LogosTextField { id: ndOwnAddr; objectName: "ownAddressField"; Layout.fillWidth: true
                                                 placeholderText: "http(s)://host:port, e.g. http://192.168.1.10:18081" }
                                LogosText { objectName: "ownRouteLine"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                            color: Theme.palette.textSecondary
                                            text: root.ndOwnAddressKind === "lan" ? "Reached directly. Tor can't reach your network."
                                                  : root.ndOwnAddressKind === "onion" ? "Always reached through Tor." : "" }
                                LogosSwitch { objectName: "ownTorSwitch"; visible: root.ndOwnAddressKind === "internet"; text: "Reach it through Tor"
                                              checkable: false; checked: root.ndOwnTor; onClicked: root.ndOwnTor = !root.ndOwnTor }
                                LogosText { objectName: "ownTorSwitchNote"; visible: root.ndOwnAddressKind === "internet"; Layout.fillWidth: true
                                            wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                                            text: "Otherwise its network sees this computer reaching your node." }
                                WhichTor { prefix: "own"; visible: root.ndUsesTor }
                                GridLayout {
                                    columns: 2; columnSpacing: 10; rowSpacing: 6
                                    Layout.fillWidth: true
                                    LogosText { text: "Login"; color: Theme.palette.textSecondary }
                                    LogosTextField { id: ndUser; objectName: "nodeUserField"; Layout.fillWidth: true; placeholderText: "Username (optional)" }
                                    LogosText { text: "Password"; color: Theme.palette.textSecondary }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        LogosTextField { id: ndPass; objectName: "nodePasswordField"; Layout.fillWidth: true
                                                    echoMode: TextInput.Password
                                                    Component.onCompleted: textInput.passwordMaskDelay = 0
                                                    // The armed Clear has to be VISIBLE.
                                                    placeholderText: root.clearNodePassword ? "will be CLEARED when you save"
                                                                     : (root.nodeCfg.hasPassword && root.nodeCfg.own === true ? "unchanged — type to replace" : "optional") }
                                        LogosButton { visible: !!root.nodeCfg.hasPassword && root.nodeCfg.own === true; text: "Clear stored"
                                                      onClicked: { ndPass.text = ""; root.clearNodePassword = true } }
                                    }
                                }
                                // LogosCheckbox, not CheckBox: the raw control colours its own label, and
                                // under the dark theme that is near-black on near-black.
                                LogosCheckbox { id: ndTrusted; objectName: "nodeTrustedBox"; text: "Trusted daemon"
                                                visible: root.isLoopback(ndOwnAddr.text) }
                            }
                        }

                        RowLayout {
                            Layout.topMargin: Theme.spacing.small
                            spacing: Theme.spacing.small
                            LogosRadioButton { objectName: "sourcePublic"; checkable: false; checked: root.ndSource === "public"; text: "Public sources"
                                               onClicked: root.chooseNodeSource("public") }
                            LogosText { text: "Nodes run by other people."; color: Theme.palette.textSecondary }
                            Item { Layout.fillWidth: true }
                        }
                        ColumnLayout {
                            objectName: "publicSourcesOption"
                            visible: root.ndSource === "public"
                            Layout.fillWidth: true
                            Layout.leftMargin: nodeForm.indent
                            spacing: Theme.spacing.small

                            LogosRadioButton { objectName: "publicPicked"; checkable: false; checked: root.ndPublicKind === "picked"
                                               text: "A node picked for you"; onClicked: root.chooseNodeSource("public", "picked") }
                            LogosText { objectName: "publicPickedNote"; visible: root.ndPublicKind === "picked"; Layout.fillWidth: true
                                        Layout.leftMargin: nodeForm.indent; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                        text: "The wallet's default for this network. On mainnet it moves to whichever of three operators' "
                                              + "nodes answers best." }
                            LogosRadioButton { objectName: "publicChosen"; checkable: false; checked: root.ndPublicKind === "chosen"
                                               text: "A node you choose"; onClicked: root.chooseNodeSource("public", "chosen") }
                            GridLayout {
                                objectName: "publicChosenPane"
                                visible: root.ndPublicKind === "chosen"
                                columns: 2; columnSpacing: 10; rowSpacing: 6
                                Layout.fillWidth: true
                                Layout.leftMargin: nodeForm.indent
                                LogosText { text: "Direct address"; color: Theme.palette.textSecondary }
                                LogosTextField { id: ndHost; objectName: "nodeHostField"; Layout.fillWidth: true
                                                 placeholderText: "http(s)://host:port, e.g. https://node2.monerodevs.org:38089" }
                                LogosText { text: "Address over Tor"; color: Theme.palette.textSecondary }
                                LogosTextField { id: ndOnion; objectName: "nodeOnionField"; Layout.fillWidth: true
                                                 placeholderText: "http://….onion:port (optional)" }
                                LogosText { objectName: "chosenLanNote"; visible: root.addressKind(ndHost.text) === "lan"; Layout.columnSpan: 2
                                            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                                            text: "This address is on your network, so it is saved as your own node and reached directly." }
                            }

                            // The first-run choice, changed here only while no account is open. Absent from an older node module.
                            ColumnLayout {
                                id: torUseSettings
                                objectName: "torUseSettings"
                                property bool explained: false
                                visible: root.torUse !== ""
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacing.small
                                spacing: Theme.spacing.tiny
                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosText { text: "Use Tor for"; font.weight: Theme.typography.weightBold }
                                    Item { Layout.fillWidth: true }
                                    LogosLink { objectName: "torUseExplain"; underline: false
                                                text: torUseSettings.explained ? "Hide what this means" : "What this means"
                                                onActivated: torUseSettings.explained = !torUseSettings.explained }
                                }
                                Repeater {
                                    model: root.torUseModes
                                    TorUseOption {
                                        required property string modelData
                                        prefix: "torUse_"
                                        mode: modelData
                                        chosen: root.ndPublicKind === "chosen"
                                        checked: root.torUse === modelData
                                        explained: torUseSettings.explained
                                        enabled: root.ready && !root.torUseLocked && !root.torUseSending
                                        onPicked: {
                                            if (modelData === root.torUse) return
                                            root.torUseNote = ""
                                            root.setTorUse(modelData, function (e) { root.torUseNote = e })
                                        }
                                    }
                                }
                                LogosText { objectName: "torUseScope"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                                            text: "Applies to every network that uses public sources." }
                                LogosText { objectName: "torUseNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                            textFormat: Text.PlainText; color: Theme.palette.error; text: root.torUseNote }
                            }
                            WhichTor { prefix: "public"; visible: root.ndUsesTor }
                        }
                    }
                }
            }
            LogosText { objectName: "nodeSheetStatus"; textFormat: Text.PlainText; wrapMode: Text.Wrap
                        Layout.fillWidth: true; color: Theme.palette.textSecondary; text: root.nodeLine() }
            RowLayout {
                LogosButton {
                    objectName: "saveNodeButton"; text: "Save node"
                    enabled: root.nodeDraftReady()
                    onClicked: {
                        backend.saveNodeConfig(JSON.stringify(root.nodeDraft()))
                        // Do NOT clear the fields here: saveNodeConfig is refused while a wallet is open or
                        // opening. resetNodeForm() runs when the stored config changes, which only a landed save does.
                        root.nodeSavePending = true
                    }
                }
                LogosButton { text: "Revert"; enabled: root.ready; onClicked: root.resetNodeForm() }
            }
        }
    }

}
