#include "monero_wallet_ui_backend.h"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>

#include "logos_sdk.h"
#include "qrcodegen.hpp"

namespace {
QJsonObject parse(const QString &s) { return QJsonDocument::fromJson(s.toUtf8()).object(); }
QString compact(const QJsonValue &v) {
    if (v.isArray()) return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject()) return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}
QString stripOk(const QString &reply) { QJsonObject o = parse(reply); o.remove("ok"); return compact(o); }
constexpr int kReadPollMs = 3000;
constexpr int kJobPollMs = 750;
constexpr int kSendPollMs = 700;
}

void MoneroWalletUiBackend::say(const QString &line) {
    setLastError(lastError().isEmpty() ? line : lastError() + QLatin1Char('\n') + line);
}

bool MoneroWalletUiBackend::ok(const QString &reply, const QString &context) {
    const QJsonObject o = parse(reply);
    if (o.value("ok").toBool()) return true;
    QString e = o.value("error").toString();
    if (e.isEmpty()) e = QStringLiteral("the wallet backend refused the request");
    say(context.isEmpty() ? e : QStringLiteral("%1: %2").arg(context, e));
    return false;
}

// Clear before a user-initiated action, so its outcome is what the error line shows.
void MoneroWalletUiBackend::clearAndRefresh() {
    setLastError({});
    refresh();
}

void MoneroWalletUiBackend::onContextReady() {
    QObject::connect(&m_readPoll, &QTimer::timeout, [this] { loadStatus(); loadBalances(); });
    QObject::connect(&m_jobPoll, &QTimer::timeout, [this] { pollJob(); });
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });
    // Subscribe first, then reconcile; never call out synchronously from an event callback
    // (it runs on the IPC read stack and would block the thread delivering its own reply).
    auto &b = modules().monero_wallet_backend;
    b.onWallet_state_changed([this](QString) { QTimer::singleShot(0, [this] { refresh(); }); });
    b.onSync_progress([this](QString) { QTimer::singleShot(0, [this] { loadStatus(); }); });
    b.onBalance_changed([this](QString) { QTimer::singleShot(0, [this] { loadBalances(); }); });
    b.onSend_status_changed([this](QString, QString) { QTimer::singleShot(0, [this] { pollSend(); }); });
    m_readPoll.start(kReadPollMs);
    refresh();
}

void MoneroWalletUiBackend::loadStatus() {
    auto &b = modules().monero_wallet_backend;
    const QString s = b.wallet_status();
    if (ok(s, "status")) setStatusJson(stripOk(s));
    const QString h = b.node_health();
    if (!h.isEmpty()) setNodeHealthJson(stripOk(h));
}

// The daemon this network points at. The RPC password is redacted by the backend to a
// hasPassword flag before it reaches here, so nothing secret lands in a PROP.
void MoneroWalletUiBackend::loadNodeConfig() {
    const QString c = modules().monero_wallet_backend.node_config();
    if (!c.isEmpty() && parse(c).value("ok").toBool()) setNodeConfigJson(stripOk(c));
}

void MoneroWalletUiBackend::saveNodeConfig(QString configJson) {
    setLastError({});
    if (!ok(modules().monero_wallet_backend.set_node_config(configJson), "node")) return;
    loadNodeConfig();
    loadStatus();
}

// The wallet registry and the network list: what the Wallets screen renders while nothing is open.
void MoneroWalletUiBackend::loadRegistry() {
    auto &b = modules().monero_wallet_backend;
    const QString n = b.list_networks();
    if (ok(n, "networks")) { QJsonObject o = parse(n); o.remove("ok"); setNetworksJson(compact(o)); }
    const QString w = b.list_wallets();
    setWalletsJson(ok(w, "wallets") ? compact(parse(w).value("wallets")) : QStringLiteral("[]"));
}

void MoneroWalletUiBackend::loadBalances() {
    const QJsonObject st = parse(statusJson());
    const QString state = st.value("state").toString();
    if (state != "ready" && state != "syncing") { setBalancesJson({}); return; }
    const QString r = modules().monero_wallet_backend.balances(0);
    setBalancesJson(ok(r, "balances") ? stripOk(r) : QString());
}

void MoneroWalletUiBackend::loadReceive() {
    const QJsonObject st = parse(statusJson());
    const QString state = st.value("state").toString();
    if (state != "ready" && state != "syncing") {
        setReceiveJson({}); setQrModulesJson({}); setReceiveUri({}); m_lastQrFor.clear();
        return;
    }
    const QString r = modules().monero_wallet_backend.receive_info(0);
    if (!ok(r, "receive")) { setReceiveJson({}); return; }
    setReceiveJson(stripOk(r));
    publishReceiveSelection();
}

// The QR and the copy target follow the SELECTED subaddress and any requested amount, so a
// merchant can show a per-customer address rather than the account's primary one.
void MoneroWalletUiBackend::publishReceiveSelection() {
    const QJsonObject rc = parse(receiveJson());
    const QJsonArray subs = rc.value("subaddresses").toArray();
    int idx = selectedSubaddress();
    if (idx < 0 || idx >= subs.size()) idx = 0;
    QString addr = rc.value("address").toString();
    if (idx < subs.size()) {
        const QString a = subs.at(idx).toObject().value("address").toString();
        if (!a.isEmpty()) addr = a;
    }
    if (addr.isEmpty()) { setReceiveUri({}); setQrModulesJson({}); m_lastQrFor.clear(); return; }

    // BIP-21 shaped, as monero-wallet-gui and the wallets that read these QRs expect.
    QString uri = QStringLiteral("monero:") + addr;
    if (!m_receiveAmount.isEmpty()) uri += QStringLiteral("?tx_amount=") + m_receiveAmount;
    setReceiveUri(uri);
    if (uri != m_lastQrFor) { m_lastQrFor = uri; setQrModulesJson(qrModulesJson(uri)); }
}

// A module matrix rather than an image: the design system ships no QR control, and
// Basecamp's ui_qml sandbox blocks every URL import, data: URIs included, so the view
// draws the modules itself as rectangles. nayuki's qrcodegen (MIT) is vendored.
QString MoneroWalletUiBackend::qrModulesJson(const QString &text) const {
    using qrcodegen::QrCode;
    const QrCode qr = QrCode::encodeText(text.toUtf8().constData(), QrCode::Ecc::MEDIUM);
    const int n = qr.getSize();
    QString bits;
    bits.reserve(n * n);
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x) bits += qr.getModule(x, y) ? QLatin1Char('1') : QLatin1Char('0');
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"size", n}, {"bits", bits}}).toJson(QJsonDocument::Compact));
}

// NB: does NOT clear lastError. It is called from pollJob() right after a job failure is
// recorded, and from event callbacks — clearing here erased the one message the user needed.
// The explicit user-initiated entry points clear it before they act.
void MoneroWalletUiBackend::refresh() {
    setDataLoading(true);
    loadStatus();
    loadRegistry();
    loadNodeConfig();
    loadBalances();
    loadReceive();
    refreshHistory();
    setDataLoading(false);
}

void MoneroWalletUiBackend::refreshHistory() {
    const QJsonObject st = parse(statusJson());
    const QString state = st.value("state").toString();
    if (state != "ready" && state != "syncing") { setHistoryJson({}); return; }
    const QString r = modules().monero_wallet_backend.history();
    setHistoryJson(ok(r, "history") ? stripOk(r) : QString());
}

// ---- wallet management -------------------------------------------------------------------

void MoneroWalletUiBackend::setActiveNetwork(QString network) {
    setLastError({});
    if (ok(modules().monero_wallet_backend.set_active_network(network), "network")) refresh();
}

// A lifecycle call answers a job id; the job settles later. Track exactly one at a time.
void MoneroWalletUiBackend::track(const QString &reply, const QString &kind) {
    if (!ok(reply, kind)) return;
    const QString id = parse(reply).value("jobId").toString();
    if (id.isEmpty()) { say(kind + ": no job id returned"); return; }
    m_pendingKind = kind;
    setPendingJobId(id);
    setBusy(true);
    m_jobPoll.start(kJobPollMs);
}

void MoneroWalletUiBackend::pollJob() {
    const QString id = pendingJobId();
    if (id.isEmpty()) { m_jobPoll.stop(); setBusy(false); return; }
    const QJsonObject st = parse(modules().monero_wallet_backend.job_status(id));
    const QString state = st.value("state").toString();
    if (state != "done" && state != "failed") return;
    m_jobPoll.stop();
    QJsonObject last{{"kind", m_pendingKind}, {"state", state}, {"error", st.value("error").toString()}};
    setLastJobJson(compact(last));
    if (state == "failed") say(m_pendingKind + ": " + st.value("error").toString());
    setPendingJobId({});
    setBusy(false);
    refresh();
}

void MoneroWalletUiBackend::openWallet(QString name, QString password) {
    setLastError({});
    track(modules().monero_wallet_backend.open_wallet(name, password), "open");
}

void MoneroWalletUiBackend::createWallet(QString name, QString password, QString label) {
    setLastError({});
    track(modules().monero_wallet_backend.create_wallet(name, password, label), "create");
}

void MoneroWalletUiBackend::restoreFromSeed(QString name, QString password, QString seed, int restoreHeight, QString label) {
    setLastError({});
    QJsonObject p{{"name", name}, {"password", password}, {"seed", seed},
                  {"restoreHeight", restoreHeight < 0 ? 0 : restoreHeight}, {"label", label}};
    track(modules().monero_wallet_backend.restore_from_seed(compact(p)), "restore");
}

void MoneroWalletUiBackend::restoreFromKeys(QString name, QString password, QString address, QString viewKey,
                                            QString spendKey, int restoreHeight, QString label) {
    setLastError({});
    QJsonObject p{{"name", name}, {"password", password}, {"address", address}, {"viewKey", viewKey},
                  {"spendKey", spendKey}, {"restoreHeight", restoreHeight < 0 ? 0 : restoreHeight}, {"label", label}};
    track(modules().monero_wallet_backend.restore_from_keys(compact(p)), "restore");
}

void MoneroWalletUiBackend::changePassword(QString oldPassword, QString newPassword) {
    setLastError({});
    track(modules().monero_wallet_backend.change_password(oldPassword, newPassword), "change password");
}

// Returned, not published: the QML shows it once and drops it.
QString MoneroWalletUiBackend::revealSeed(QString password) {
    setLastError({});
    const QString r = modules().monero_wallet_backend.reveal_seed(password);
    return ok(r, "reveal seed") ? parse(r).value("seed").toString() : QString();
}

QString MoneroWalletUiBackend::revealViewKey(QString password) {
    setLastError({});
    const QString r = modules().monero_wallet_backend.reveal_view_key(password);
    return ok(r, "reveal view key") ? parse(r).value("viewKey").toString() : QString();
}

void MoneroWalletUiBackend::closeWallet() {
    setLastError({});
    track(modules().monero_wallet_backend.close_wallet(), "close");
}

// ---- spending ----------------------------------------------------------------------------

void MoneroWalletUiBackend::createSubaddress(QString label) {
    setLastError({});
    const QString r = modules().monero_wallet_backend.create_subaddress(0, label);
    if (!ok(r, "subaddress")) return;
    loadReceive();
    // Select what was just made: the point of creating one is to hand it out.
    const int idx = parse(r).value("index").toInt(-1);
    if (idx >= 0) { setSelectedSubaddress(idx); publishReceiveSelection(); }
}

void MoneroWalletUiBackend::selectSubaddress(int index) {
    setSelectedSubaddress(index < 0 ? 0 : index);
    publishReceiveSelection();
}

void MoneroWalletUiBackend::setReceiveAmount(QString amountXmr) {
    m_receiveAmount = amountXmr.trimmed();
    publishReceiveSelection();
}

void MoneroWalletUiBackend::setSubaddressLabel(int index, QString label) {
    setLastError({});
    if (ok(modules().monero_wallet_backend.set_subaddress_label(0, index, label), "label")) loadReceive();
}

void MoneroWalletUiBackend::prepareSend(QString sendJson) {
    setSendError({});
    const QString r = modules().monero_wallet_backend.prepare_send(sendJson);
    const QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) { setSendError(o.value("error").toString()); return; }
    setSendRequestId(o.value("requestId").toString());
    setSendStatusJson(QStringLiteral("{\"state\":\"preparing\"}"));
    m_sendPoll.start(kSendPollMs);
}

void MoneroWalletUiBackend::pollSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) { m_sendPoll.stop(); return; }
    const QString r = modules().monero_wallet_backend.send_status(id);
    const QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) { setSendError(o.value("error").toString()); m_sendPoll.stop(); return; }
    setSendStatusJson(stripOk(r));
    const QString state = o.value("state").toString();
    if (state == "failed" || state == "unknown") setSendError(o.value("error").toString());
    if (state == "sent" || state == "failed" || state == "cancelled" || state == "unknown") {
        m_sendPoll.stop();
        // An unknown outcome may or may not have moved money, so refresh the same as a send:
        // Activity is where the answer will show up.
        if (state == "sent" || state == "unknown") { loadBalances(); refreshHistory(); }
    }
}

void MoneroWalletUiBackend::confirmSend() {
    setSendError({});
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    const QString r = modules().monero_wallet_backend.confirm_send(id);
    const QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) setSendError(o.value("error").toString());
    m_sendPoll.start(kSendPollMs);
}

void MoneroWalletUiBackend::cancelSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    const QString r = modules().monero_wallet_backend.cancel_send(id);
    const QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) {
        // The backend refuses to cancel a broadcast already in progress. Wiping the sheet here
        // would tell the user their transaction was cancelled while it was on its way.
        setSendError(o.value("error").toString());
        m_sendPoll.start(kSendPollMs);
        return;
    }
    m_sendPoll.stop();
    setSendRequestId({});
    setSendStatusJson(QStringLiteral("{}"));
    setSendError({});
}

bool MoneroWalletUiBackend::addressValid(QString address) {
    return modules().monero_wallet_backend.address_valid(address);
}

QString MoneroWalletUiBackend::formatXmr(QString atomic) {
    return modules().monero_wallet_backend.format_xmr(atomic);
}
