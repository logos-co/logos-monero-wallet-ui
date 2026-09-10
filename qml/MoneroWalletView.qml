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

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "monero_wallet_ui") root.ready = isReady && root.backend !== null
        }
        // We PROVIDE both Monero capabilities. Another app (a receive-only till, a companion)
        // can ask this wallet to unlock or to bring wallet management up; we never ask anyone
        // else, because managing wallets is a screen here rather than a trip to a second app.
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
    // The node form edits ONE network's config, and the network picker sits on the same screen.
    // `nodeFormNetwork` records which network the fields currently hold, so a switch cannot save
    // one network's daemon over another's: the form repopulates when the new config arrives, and
    // Save is refused until it has.
    readonly property string activeNetwork: ready ? (networks.active || "") : ""
    // The network the fields actually hold, taken from the CONFIG rather than from whatever is
    // active now: on a switch the new config arrives a poll later, and claiming the new network
    // while still showing the old one's daemon is the mis-save this exists to prevent.
    property string nodeFormNetwork: ""
    // A save was sent and we are waiting to see it in the stored config. Only a write that landed
    // changes nodeCfg, so this is what tells a successful save from a refused one.
    property bool nodeSavePending: false
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
        ndHost.text = root.nodeCfg.url || ""
        ndUser.text = root.nodeCfg.username || ""
        ndProxy.text = root.nodeCfg.proxy || ""
        ndProxyReq.checked = !!root.nodeCfg.proxyRequired
        ndTrusted.checked = !!root.nodeCfg.trusted
        ndPass.text = ""
        root.clearNodePassword = false
        root.nodeSavePending = false
        root.nodeFormNetwork = root.nodeCfg.network || ""
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
                        text: node.reachable === true ? ("node " + (node.route || "") + " " + (node.rttMs || 0) + "ms") : (node.reachable === false ? "node unreachable" : "") }

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
                text: (status.activeNetwork || status.network || networks.active || "—").toUpperCase()
                color: (status.activeNetwork || status.network || networks.active) === "mainnet"
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
                ? ("Open: " + status.wallet + " · " + status.state + " · " + (status.syncPercent || 0) + "%")
                : (status.state === "opening" ? "Opening…" : (status.state === "closing" ? "Closing…" : "No wallet open")))
        }

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
                LogosButton { objectName: "dismissUnknownButton"; text: "Dismiss"; onClicked: backend.cancelSend() }
            }
        }

        // ================= NO WALLET OPEN: the Wallets screen =================
        // Shaped like the keystore's Accounts screen: a heading, one row of actions, and the
        // list. The forms are modal sheets rather than a second tab strip — a six-tab strip
        // above a two-row list made the list look like one option among six, and left four
        // tabs' worth of empty form on screen whenever the user was not filling one in.
        ColumnLayout {
            visible: root.ready && !root.walletOpen
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
                    onActivated: backend.setActiveNetwork(currentText)
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
                    visible: root.wallets.length === 0
                    color: Theme.palette.textSecondary
                    text: "No wallets yet"
                }

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacing.tiny
                    model: root.wallets
                    delegate: LogosFrame {
                        width: ListView.view.width
                        contentItem: RowLayout {
                            spacing: Theme.spacing.small
                            // A wallet name is user-typed, so PlainText: LogosText is AutoText.
                            LogosText { text: modelData.name; textFormat: Text.PlainText }
                            LogosText { text: modelData.network || ""; textFormat: Text.PlainText
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
                LogosButton {
                    objectName: "reviewButton"; text: "Review"
                    enabled: root.ready && !root.viewOnly && !root.sendOpen && sendAddr.text !== "" && sendAmt.text !== "" && sendAmt.text !== "."
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
                                text: (send.state === "sent" || send.state === "failed" || send.state === "unknown") ? "Done" : "Cancel"
                                visible: send.state !== "committing"
                                onClicked: { backend.cancelSend(); if (send.state === "sent" || send.state === "unknown") { sendAddr.text = ""; sendAmt.text = "" } }
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
                                            text: (modelData.direction === "in" ? "+" : "−") + modelData.amountXmr + " XMR" }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary
                                            text: modelData.pending ? "pending"
                                                  : (modelData.failed ? "failed"
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
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; text: modelData.amountXmr + " XMR" }
                                LogosText { text: "Fee"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.direction === "in" ? "—  (paid by the sender)" : modelData.feeXmr + " XMR" }
                                LogosText { text: "Confirmations"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.pending ? "0 (in the pool)" : String(modelData.confirmations) }
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
                    LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                                text: node.reachable === true
                                      ? ("Reachable · height " + node.height + " · " + (node.route === "proxied" ? "through the proxy" : "direct") + " · " + (node.rttMs || 0) + "ms")
                                      : ("Node: " + (node.error || "unknown")) }
                    LogosText { objectName: "settingsNodeUrl"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; color: Theme.palette.textSecondary
                                text: "Address: " + (root.nodeCfg.url || "—") }
                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: "Network: " + (status.activeNetwork || "") }
                    LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textTertiary
                                text: "Close this wallet to change either one: the engine binds its daemon when a wallet "
                                      + "opens. The node form and the network picker are both on the Wallets screen." }

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

    LogosDialog {
        id: nodeSheet
        objectName: "nodeSheet"
        title: "Remote node"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720)
        onOpened: root.resetNodeForm()
        contentItem: ColumnLayout {
            // Named so a test can assert REACHABILITY, not just that the fields exist:
            // findByProperty walks the whole tree ignoring visibility, so an assertion on
            // the field alone passes even when this screen is hidden behind an open
            // wallet — which is the exact bug this page was moved here to fix.
            objectName: "walletsNodePage"
            spacing: 8
            LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.palette.textSecondary
                        text: node.reachable === true
                              ? ("Reachable · height " + node.height + " · " + (node.route === "proxied" ? "through the proxy" : "direct") + " · " + (node.rttMs || 0) + "ms")
                              : ("Node: " + (node.error || "unknown")) }
            LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                        text: "Network: " + (networks.active || "?") + " — the node is stored per network." }
            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 6
                Layout.fillWidth: true
                enabled: root.ready

                LogosText { text: "Address"; color: Theme.palette.textSecondary }
                LogosTextField { id: ndHost; objectName: "nodeHostField"; Layout.fillWidth: true
                            placeholderText: "http://host:port, e.g. http://node2.monerodevs.org:38089"
                            text: root.nodeCfg.url || "" }
                LogosText { text: "Daemon username"; color: Theme.palette.textSecondary }
                LogosTextField { id: ndUser; objectName: "nodeUserField"; Layout.fillWidth: true
                            placeholderText: "optional"; text: root.nodeCfg.username || "" }
                LogosText { text: "Daemon password"; color: Theme.palette.textSecondary }
                RowLayout {
                    Layout.fillWidth: true
                    LogosTextField { id: ndPass; objectName: "nodePasswordField"; Layout.fillWidth: true
                                echoMode: TextInput.Password
                                Component.onCompleted: textInput.passwordMaskDelay = 0
                                // The armed Clear has to be VISIBLE. It used to be a
                                // root-scoped boolean with nothing on screen saying so.
                                placeholderText: root.clearNodePassword ? "will be CLEARED when you save"
                                                 : (root.nodeCfg.hasPassword ? "unchanged — type to replace" : "optional") }
                    LogosButton { visible: !!root.nodeCfg.hasPassword; text: "Clear stored"
                                  onClicked: { ndPass.text = ""; root.clearNodePassword = true } }
                }
                LogosText { text: "Proxy"; color: Theme.palette.textSecondary }
                LogosTextField { id: ndProxy; objectName: "nodeProxyField"; Layout.fillWidth: true
                            placeholderText: "socks5h://127.0.0.1:9050 (empty for none)"
                            text: root.nodeCfg.proxy || "" }
                LogosText { text: ""; opacity: 0 }
                // LogosCheckbox, not CheckBox: the raw control colours its own label, and
                // under the dark theme that is near-black on near-black. LogosText is the
                // rule everywhere else in this view; these two were the exception.
                LogosCheckbox { id: ndProxyReq; objectName: "nodeProxyRequiredBox"; text: "Require the proxy (refuse to connect without it)"
                                checked: !!root.nodeCfg.proxyRequired }
                LogosText { text: ""; opacity: 0 }
                LogosCheckbox { id: ndTrusted; objectName: "nodeTrustedBox"; text: "Trusted daemon"
                                checked: !!root.nodeCfg.trusted }
            }
            RowLayout {
                LogosButton {
                    objectName: "saveNodeButton"; text: "Save node"
                    // Empty means the form holds no other network's config — a device
                    // with nothing stored yet, which must still be able to save. Only a
                    // form still holding a DIFFERENT network's daemon is refused.
                    // `busy` is a wallet lifecycle job in flight — open, close, create,
                    // restore, change password. The backend refuses a node write for the
                    // whole of one, and offering a button that cannot work is how the
                    // password-wipe above became reachable.
                    enabled: root.ready && !root.busy && ndHost.text !== ""
                             && (root.nodeFormNetwork === "" || root.nodeFormNetwork === root.activeNetwork)
                    onClicked: {
                        var cfg = { url: ndHost.text.trim(),
                                    username: ndUser.text.trim(),
                                    proxy: ndProxy.text.trim(),
                                    proxyRequired: ndProxyReq.checked,
                                    trusted: ndTrusted.checked }
                        // Omitting password KEEPS the stored one; "" clears it.
                        if (ndPass.text !== "") cfg.password = ndPass.text
                        else if (root.clearNodePassword) cfg.password = ""
                        backend.saveNodeConfig(JSON.stringify(cfg))
                        // Do NOT clear the fields here. saveNodeConfig is refused while a
                        // wallet is open or opening, and wiping the typed password before
                        // knowing the write landed is how a retry ends up sending the new
                        // host with no password — silently rebinding the OLD daemon's
                        // credential to it. The form is cleared by resetNodeForm() when
                        // the stored config actually changes, which only a save that
                        // landed can do.
                        root.nodeSavePending = true
                    }
                }
                LogosButton { text: "Revert"; enabled: root.ready; onClicked: root.resetNodeForm() }
            }
        }
    }

}
