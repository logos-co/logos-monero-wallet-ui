import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Monero wallet: balances, receive, a reviewed send, activity. It holds no password — a
// locked wallet asks the keys app through monero.wallet.unlock. Every string this view did
// not author is PlainText (LogosText is AutoText). EMPTY JSON means "not read yet" → em-dash.
Item {
    id: root
    objectName: "moneroWalletRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("monero_wallet_ui")
    property bool ready: false
    property string intentNote: ""

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "monero_wallet_ui") root.ready = isReady && root.backend !== null
        }
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("monero_wallet_ui")

    function j(t, fb) { try { return JSON.parse(t && t.length ? t : fb) } catch (e) { return JSON.parse(fb) } }
    readonly property var status: ready ? j(backend.statusJson, "{}") : ({})
    readonly property var node: ready ? j(backend.nodeHealthJson, "{}") : ({})
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

    // Ask another app for a capability. The result is ADVISORY: wallet_status is what settles
    // whether a wallet is open; this only explains a trip that did not happen.
    function askFor(intent, params, whenUnavailable) {
        root.intentNote = ""
        logos.request(intent, params, function (res) {
            if (res.ok || res.error === "cancelled") return
            root.intentNote = res.error === "unavailable" ? whenUnavailable
                : "That request did not go through (" + res.error + ")."
        })
    }
    function askToUnlock() {
        var w = status.wallet && status.wallet !== "" ? status.wallet : ""
        if (w === "") { askFor("monero.accounts.manage", ({}), "No app on this device manages Monero wallets."); return }
        askFor("monero.wallet.unlock", ({ wallet: w }), "Open this wallet in the Monero Keys app.")
    }

    property int page: 0
    function selectTab(i) { root.page = i }
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

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10

        // Persistent chrome: network, node, sync, view-only.
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

        LogosText { objectName: "errorLine"; visible: root.ready && backend.lastError !== ""; text: root.ready ? backend.lastError : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true; color: "#d9534f" }
        LogosText { objectName: "intentNote"; visible: root.intentNote !== ""; text: root.intentNote; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true }

        // Locked state: one button that asks the keys app.
        ColumnLayout {
            visible: root.ready && !root.walletOpen
            Layout.fillWidth: true
            LogosText { objectName: "lockedText"; text: status.state === "opening" ? "Opening…" : (status.state === "closing" ? "Closing…" : "No wallet is open.") }
            RowLayout {
                LogosButton { objectName: "unlockButton"; text: "Open a wallet…"; enabled: status.state !== "opening"; onClicked: root.askToUnlock() }
                LogosButton { text: "Manage wallets…"; onClicked: root.askFor("monero.accounts.manage", ({}), "No app on this device manages Monero wallets.") }
            }
        }

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
                    LogosButton { text: "New subaddress"; onClicked: { backend.createSubaddress(subLabel.text); subLabel.text = "" } }
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

            // Settings
            ColumnLayout {
                spacing: 6
                LogosText { textFormat: Text.PlainText; text: "Network: " + (status.activeNetwork || "") + " — set in the Monero Keys app while no wallet is open." }
                LogosText { textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
                            text: node.reachable === true ? ("Node reachable · height " + node.height + " · " + (node.route === "proxied" ? "through the proxy" : "direct") ) : "Node: " + (node.error || "unknown") }
                LogosText { textFormat: Text.PlainText; text: "Engine: monero_c " + (status.libraryVersion || "") + " (LGPL-3.0, dynamically linked)" }
                LogosButton { text: "Manage wallets…"; onClicked: root.askFor("monero.accounts.manage", ({}), "No app on this device manages Monero wallets.") }
                LogosButton { objectName: "closeButton"; text: "Close wallet"; onClicked: backend.closeWallet() }
            }
        }
    }
}
