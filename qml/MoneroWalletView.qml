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

    // A wallet another app asked us to open, answered once the open job settles.
    property string unlockRequestId: ""
    property string shownSecret: ""
    property string secretKind: ""

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
                root.walletsPage = 0
                if (root.walletOpen) root.page = 4      // Settings holds management once open
                logos.respond(requestId, true, ({}), "")   // arriving IS the request; handoff keeps the user here
                return
            }
            if (intent !== "monero.wallet.unlock") return
            var w = params && params.wallet ? String(params.wallet) : ""
            if (w === "") { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (root.walletOpen && root.status.wallet === w) { logos.respond(requestId, true, ({}), ""); return }
            if (root.walletOpen) { logos.respond(requestId, false, ({}), "another wallet is already open"); return }
            root.unlockRequestId = requestId
            root.walletsPage = 1
            openNameField.text = w
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
    readonly property bool viewOnly: !!status.watchOnly

    // When an unlock another app asked for settles, answer the requester; the shell returns them.
    onLastJobChanged: {
        if (root.unlockRequestId === "" || !lastJob.kind) return
        if (lastJob.kind !== "open") return
        var okNow = lastJob.state === "done"
        logos.respond(root.unlockRequestId, okNow, ({}), okNow ? "" : (lastJob.error || "open failed"))
        root.unlockRequestId = ""
    }

    // Two page spaces: the Wallets screen while nothing is open, the wallet's tabs once it is.
    // The harness navigates with these rather than clicking a tab: only the active StackLayout
    // page is in the visible scene, and a text-click on a TabButton is not a reliable switch.
    property int page: 0            // 0 Home, 1 Send, 2 Receive, 3 Activity, 4 Settings
    property int walletsPage: 0     // 0 list, 1 open, 2 create, 3 restore seed, 4 restore keys
    function selectTab(i) { root.page = i }
    function selectWalletsPage(i) { root.walletsPage = i }
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

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10

        // Persistent chrome: network, view-only, sync, node.
        RowLayout {
            Layout.fillWidth: true
            LogosText { text: "Monero"; font.pixelSize: 22 }
            Rectangle {
                objectName: "networkChip"; radius: 10; implicitHeight: 22; implicitWidth: chipText.implicitWidth + 16
                color: (status.activeNetwork || status.network) === "mainnet" ? "#c0392b" : "#2c7a7b"
                LogosText { id: chipText; anchors.centerIn: parent; textFormat: Text.PlainText; text: (status.activeNetwork || status.network || "—").toUpperCase(); color: "white"; font.pixelSize: 11 }
            }
            LogosText { objectName: "viewOnlyBadge"; visible: root.viewOnly; text: "VIEW-ONLY"; color: "#e67e22"; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            LogosText {
                objectName: "syncChip"; textFormat: Text.PlainText; font.pixelSize: 12
                text: !root.ready ? "Connecting…" : (root.walletOpen
                    ? ((status.synchronized ? "Synced " : "Syncing ") + (status.walletHeight || 0) + " / " + (status.daemonHeight || 0) + " (" + (status.syncPercent || 0) + "%)")
                    : "No wallet open")
            }
            LogosText { objectName: "nodeChip"; textFormat: Text.PlainText; font.pixelSize: 12; opacity: 0.8
                        text: node.reachable === true ? ("node " + (node.route || "") + " " + (node.rttMs || 0) + "ms") : (node.reachable === false ? "node unreachable" : "") }
        }

        // One line a driver (and a user) can read the whole wallet state from.
        LogosText {
            objectName: "statusLine"
            textFormat: Text.PlainText
            text: !root.ready ? "" : (root.walletOpen
                ? ("Open: " + status.wallet + " · " + status.state + " · " + (status.syncPercent || 0) + "%")
                : (status.state === "opening" ? "Opening…" : (status.state === "closing" ? "Closing…" : "No wallet open")))
        }

        LogosText { objectName: "errorLine"; visible: root.ready && backend.lastError !== ""; text: root.ready ? backend.lastError : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: "#d9534f" }

        // ================= NO WALLET OPEN: the Wallets screen =================
        ColumnLayout {
            visible: root.ready && !root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                LogosText { text: "Wallets"; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                LogosText { textFormat: Text.PlainText; opacity: 0.8; text: "Network: " + (networks.active || "?") }
                ComboBox {
                    id: netBox
                    objectName: "networkBox"
                    enabled: root.ready && !root.busy
                    model: networks.networks || []
                    currentIndex: Math.max(0, (networks.networks || []).indexOf(networks.active || ""))
                    onActivated: backend.setActiveNetwork(currentText)
                }
            }

            TabBar {
                id: walletTabs
                Layout.fillWidth: true
                currentIndex: root.walletsPage
                onCurrentIndexChanged: root.walletsPage = currentIndex
                TabButton { text: "Wallets" }
                TabButton { text: "Open" }
                TabButton { text: "Create" }
                TabButton { text: "Restore (seed)" }
                TabButton { text: "Restore (keys)" }
            }

            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: root.walletsPage

                // 0: the wallets on this device
                ColumnLayout {
                    LogosText { objectName: "walletsEmpty"; visible: root.wallets.length === 0
                                text: "No wallets on this device yet. Create one, or restore from a seed." }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        model: root.wallets
                        delegate: RowLayout {
                            width: ListView.view.width
                            LogosText { text: modelData.name + (modelData.viewOnly ? "  (view-only)" : ""); textFormat: Text.PlainText }
                            LogosText { text: modelData.network || ""; textFormat: Text.PlainText; opacity: 0.7 }
                            Item { Layout.fillWidth: true }
                            LogosButton { text: "Open"; enabled: !root.busy
                                          onClicked: { openNameField.text = modelData.name; root.walletsPage = 1 } }
                        }
                    }
                    LogosButton { text: "Refresh"; enabled: root.ready; onClicked: backend.refresh() }
                }

                // 1: open one (the password sheet)
                ColumnLayout {
                    spacing: 8
                    LogosText { visible: root.unlockRequestId !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true
                                text: "Another app asked to unlock this wallet." }
                    TextField { id: openNameField; objectName: "openNameField"; placeholderText: "Wallet name"; Layout.fillWidth: true }
                    TextField {
                        id: openPw; objectName: "openPasswordField"; placeholderText: "Wallet password"
                        echoMode: TextInput.Password; Layout.fillWidth: true
                        Component.onCompleted: passwordMaskDelay = 0
                        onAccepted: if (openButton.enabled) openButton.clicked()
                    }
                    LogosButton {
                        id: openButton
                        objectName: "openButton"; text: root.busy ? "Opening…" : "Open"
                        enabled: root.ready && !root.busy && openNameField.text !== ""
                        onClicked: { backend.openWallet(openNameField.text, openPw.text); openPw.text = "" }
                    }
                }

                // 2: create a new wallet
                ColumnLayout {
                    spacing: 8
                    TextField { id: cName; objectName: "createNameField"; placeholderText: "Wallet name"; Layout.fillWidth: true }
                    TextField { id: cLabel; placeholderText: "Label (optional)"; Layout.fillWidth: true }
                    TextField { id: cPw; objectName: "createPasswordField"; placeholderText: "Add a strong password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    TextField { id: cPw2; placeholderText: "Repeat password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    LogosText { visible: cPw.text !== cPw2.text && cPw2.text !== ""; text: "Passwords do not match" }
                    LogosButton {
                        objectName: "createButton"; text: root.busy ? "Creating…" : "Create wallet"
                        enabled: root.ready && !root.busy && cName.text !== "" && cPw.text !== "" && cPw.text === cPw2.text
                        onClicked: { backend.createWallet(cName.text, cPw.text, cLabel.text); cPw.text = ""; cPw2.text = "" }
                    }
                    LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true; opacity: 0.8
                                text: "The wallet opens once it is created. Write down your mnemonic seed and keep it safe — "
                                      + "Settings › Show seed & keys, behind your password." }
                }

                // 3: restore from a mnemonic seed
                ColumnLayout {
                    spacing: 8
                    TextField { id: rName; placeholderText: "Wallet name"; Layout.fillWidth: true }
                    TextArea { id: rSeed; objectName: "seedField"; placeholderText: "25-word mnemonic seed"; Layout.fillWidth: true; Layout.preferredHeight: 90; wrapMode: TextEdit.Wrap }
                    TextField { id: rHeight; placeholderText: "Restore height (block number; 0 scans from genesis — hours)"; Layout.fillWidth: true; validator: IntValidator { bottom: 0 } }
                    TextField { id: rPw; placeholderText: "New wallet password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    LogosButton {
                        objectName: "restoreSeedButton"
                        text: root.busy ? "Restoring…" : "Restore"
                        enabled: root.ready && !root.busy && rName.text !== "" && rSeed.text.trim().split(/\s+/).length === 25 && rPw.text !== ""
                        onClicked: { backend.restoreFromSeed(rName.text, rPw.text, rSeed.text.trim(), parseInt(rHeight.text || "0"), ""); rSeed.text = ""; rPw.text = "" }
                    }
                }

                // 4: restore from keys (view-only when no spend key)
                ColumnLayout {
                    spacing: 8
                    TextField { id: kName; placeholderText: "Wallet name"; Layout.fillWidth: true }
                    TextField { id: kAddr; placeholderText: "Primary address"; Layout.fillWidth: true }
                    TextField { id: kView; placeholderText: "Private view key"; Layout.fillWidth: true }
                    TextField { id: kSpend; placeholderText: "Private spend key (leave empty for a view-only wallet)"; Layout.fillWidth: true }
                    TextField { id: kHeight; placeholderText: "Restore height"; Layout.fillWidth: true; validator: IntValidator { bottom: 0 } }
                    TextField { id: kPw; placeholderText: "New wallet password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    LogosButton {
                        objectName: "restoreKeysButton"
                        text: root.busy ? "Restoring…" : (kSpend.text === "" ? "Restore view-only wallet" : "Restore wallet")
                        enabled: root.ready && !root.busy && kName.text !== "" && kAddr.text !== "" && kView.text !== "" && kPw.text !== ""
                        onClicked: { backend.restoreFromKeys(kName.text, kPw.text, kAddr.text, kView.text, kSpend.text, parseInt(kHeight.text || "0"), ""); kView.text = ""; kSpend.text = ""; kPw.text = "" }
                    }
                }
            }
        }

        // ================= A WALLET IS OPEN =================
        TabBar {
            id: tabs; visible: root.walletOpen; Layout.fillWidth: true
            currentIndex: root.page; onCurrentIndexChanged: root.page = currentIndex
            TabButton { text: "Home" } TabButton { text: "Send" } TabButton { text: "Receive" } TabButton { text: "Activity" } TabButton { text: "Settings" }
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
                LogosText { objectName: "unlockedText"; textFormat: Text.PlainText; opacity: 0.8
                            text: root.balancesRead ? ("Unlocked: " + balances.unlockedXmr + " XMR") : "Unlocked: —" }
                LogosText { visible: root.balancesRead && balances.balance !== balances.unlocked; opacity: 0.7
                            text: "Incoming funds unlock after 10 confirmations (~20 min)." }
                LogosButton { text: "Refresh"; onClicked: backend.refresh() }
            }

            // Send
            ColumnLayout {
                spacing: 8
                LogosText { visible: root.viewOnly; text: "This is a view-only wallet; it cannot spend." }
                TextField { id: sendAddr; objectName: "sendAddressField"; placeholderText: "Destination address"; Layout.fillWidth: true; enabled: !root.viewOnly && !root.sendOpen }
                TextField { id: sendAmt; objectName: "sendAmountField"; placeholderText: "Amount (XMR)"; Layout.fillWidth: true; enabled: !root.viewOnly && !root.sendOpen
                            validator: RegularExpressionValidator { regularExpression: /^[0-9]*\.?[0-9]{0,12}$/ } }
                ComboBox { id: prio; model: ["Default", "Low", "Medium", "High"]; enabled: !root.sendOpen }
                LogosText { objectName: "sendError"; visible: root.ready && backend.sendError !== ""; text: root.ready ? backend.sendError : ""; textFormat: Text.PlainText; color: "#d9534f"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                LogosButton {
                    objectName: "reviewButton"; text: "Review"
                    enabled: root.ready && !root.viewOnly && !root.sendOpen && sendAddr.text !== "" && sendAmt.text !== "" && sendAmt.text !== "."
                    onClicked: backend.prepareSend(JSON.stringify({ address: sendAddr.text, amountXmr: sendAmt.text, priority: prio.currentIndex }))
                }
                // The review sheet. What it governs is BROADCAST: the engine signed at build.
                Rectangle {
                    visible: root.sendOpen
                    Layout.fillWidth: true; implicitHeight: revCol.implicitHeight + 24; radius: 6
                    color: Theme.palette.surface !== undefined ? Theme.palette.surface : "#222"
                    ColumnLayout {
                        id: revCol; anchors.fill: parent; anchors.margins: 12; spacing: 4
                        LogosText { objectName: "sendState"; textFormat: Text.PlainText; text: "Status: " + (send.state || "") }
                        LogosText { visible: send.state === "preparing"; text: "Building the transaction (fetching decoys)…" }
                        LogosText { visible: !!send.preview; textFormat: Text.PlainText; text: "To: " + (send.preview ? send.preview.destination : "") ; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                        LogosText { objectName: "previewAmount"; visible: !!send.preview; textFormat: Text.PlainText; text: "Amount: " + (send.preview ? send.preview.amountXmr : "") + " XMR" }
                        LogosText { objectName: "previewFee"; visible: !!send.preview; textFormat: Text.PlainText; text: "Fee: " + (send.preview ? send.preview.feeXmr : "") + " XMR" }
                        LogosText { objectName: "previewTotal"; visible: !!send.preview; textFormat: Text.PlainText; text: "Total: " + (send.preview ? send.preview.totalXmr : "") + " XMR" }
                        LogosText { visible: send.state === "sent"; textFormat: Text.PlainText; text: "Broadcast. txid: " + (send.txids || ""); wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                        RowLayout {
                            LogosButton { objectName: "confirmSendButton"; text: "Confirm and broadcast"; visible: send.state === "previewed"; onClicked: backend.confirmSend() }
                            LogosButton { text: send.state === "sent" || send.state === "failed" ? "Done" : "Cancel"; visible: send.state !== "committing"; onClicked: { backend.cancelSend(); if (send.state === "sent") { sendAddr.text = ""; sendAmt.text = "" } } }
                        }
                    }
                }
            }

            // Receive
            ColumnLayout {
                spacing: 8
                LogosText { objectName: "receiveAddress"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                            text: root.receiveRead ? receive.address : "—" }
                // Plain rectangles, one per run of dark modules: the sandbox refuses every URL
                // import (data: URIs included) and a Canvas never receives paint() in this host.
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
                RowLayout {
                    TextField { id: subLabel; placeholderText: "Subaddress label"; Layout.fillWidth: true }
                    LogosButton { text: "Create new address"; onClicked: { backend.createSubaddress(subLabel.text); subLabel.text = "" } }
                }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: root.receiveRead ? (receive.subaddresses || []) : []
                    delegate: LogosText { width: ListView.view.width; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; font.pixelSize: 11
                                          text: "#" + modelData.index + (modelData.label ? " " + modelData.label : "") + "  " + modelData.address }
                }
            }

            // Activity
            ColumnLayout {
                LogosText { objectName: "historyEmpty"; visible: root.historyRead && root.history.length === 0; text: "No transactions yet." }
                LogosText { visible: !root.historyRead; text: "—" }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: root.history
                    delegate: RowLayout {
                        width: ListView.view.width
                        LogosText { textFormat: Text.PlainText; text: (modelData.direction === "in" ? "+" : "−") + modelData.amountXmr + " XMR" }
                        LogosText { textFormat: Text.PlainText; opacity: 0.7; text: modelData.pending ? "pending" : (modelData.failed ? "failed" : (modelData.confirmations + " conf" + (modelData.confirmations < 10 ? " (locked)" : ""))) }
                        Item { Layout.fillWidth: true }
                        LogosText { textFormat: Text.PlainText; opacity: 0.6; font.pixelSize: 10; text: (modelData.txid || "").substring(0, 16) + "…" }
                    }
                }
                LogosButton { text: "Refresh"; onClicked: backend.refreshHistory() }
            }

            // Settings — wallet management lives here, as it does in Monero GUI.
            ColumnLayout {
                spacing: 8
                LogosText { text: "Wallet"; font.pixelSize: 16 }
                RowLayout {
                    LogosButton { objectName: "closeButton"; text: "Close this wallet"; enabled: !root.busy; onClicked: { root.hideSecret(); backend.closeWallet() } }
                }

                LogosText { text: "Change wallet password"; opacity: 0.9 }
                RowLayout {
                    TextField { id: oldPw; objectName: "oldPasswordField"; placeholderText: "Current password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    TextField { id: newPw; objectName: "newPasswordField"; placeholderText: "New password"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
                    LogosButton { objectName: "changePasswordButton"; text: "Change"; enabled: !root.busy && oldPw.text !== "" && newPw.text !== ""
                                  onClicked: { backend.changePassword(oldPw.text, newPw.text); oldPw.text = ""; newPw.text = "" } }
                }

                LogosText { text: "Show seed & keys"; opacity: 0.9 }
                RowLayout {
                    TextField { id: revealPw; objectName: "revealPasswordField"; placeholderText: "Password to reveal"; echoMode: TextInput.Password; Layout.fillWidth: true; Component.onCompleted: passwordMaskDelay = 0 }
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
                    color: Theme.palette.surface !== undefined ? Theme.palette.surface : "#222"
                    radius: 6
                    ColumnLayout {
                        id: secretCol; anchors.fill: parent; anchors.margins: 12
                        LogosText { wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: "Your " + root.secretKind + ". DO NOT share it with anyone: it can "
                                          + (root.secretKind === "mnemonic seed" ? "spend" : "see") + " your funds. Store a copy securely; it is not kept here." }
                        TextEdit { objectName: "secretText"; text: root.shownSecret; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; Layout.fillWidth: true; color: Theme.palette.text !== undefined ? Theme.palette.text : "#eee" }
                        LogosButton { text: "Hide"; onClicked: root.hideSecret() }
                    }
                }

                LogosText { text: "Node"; font.pixelSize: 16 }
                LogosText { textFormat: Text.PlainText; text: "Network: " + (status.activeNetwork || "") + " — switch it from the Wallets screen while no wallet is open." }
                LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
                            text: node.reachable === true ? ("Node reachable · height " + node.height + " · " + (node.route === "proxied" ? "through the proxy" : "direct") ) : "Node: " + (node.error || "unknown") }
                LogosText { textFormat: Text.PlainText; text: "Engine: monero_c " + (status.libraryVersion || "") + " (LGPL-3.0, dynamically linked)" }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
