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
constexpr int kPollMs = 3000;
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

void MoneroWalletUiBackend::onContextReady() {
    QObject::connect(&m_poll, &QTimer::timeout, [this] { loadStatus(); loadBalances(); });
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });
    // Subscribe first, then reconcile; never call out synchronously from an event callback.
    auto &b = modules().monero_wallet_backend;
    b.onWallet_state_changed([this](QString) { QTimer::singleShot(0, [this] { refresh(); }); });
    b.onSync_progress([this](QString) { QTimer::singleShot(0, [this] { loadStatus(); }); });
    b.onBalance_changed([this](QString) { QTimer::singleShot(0, [this] { loadBalances(); }); });
    b.onSend_status_changed([this](QString, QString) { QTimer::singleShot(0, [this] { pollSend(); }); });
    m_poll.start(kPollMs);
    refresh();
}

void MoneroWalletUiBackend::loadStatus() {
    auto &b = modules().monero_wallet_backend;
    const QString s = b.wallet_status();
    if (ok(s, "status")) setStatusJson(stripOk(s));
    const QString h = b.node_health();
    if (!h.isEmpty()) setNodeHealthJson(stripOk(h));
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
    if (state != "ready" && state != "syncing") { setReceiveJson({}); setQrModulesJson({}); return; }
    const QString r = modules().monero_wallet_backend.receive_info(0);
    if (!ok(r, "receive")) { setReceiveJson({}); return; }
    setReceiveJson(stripOk(r));
    const QString addr = parse(r).value("address").toString();
    if (!addr.isEmpty() && addr != m_lastQrFor) { m_lastQrFor = addr; setQrModulesJson(qrModulesJson(addr)); }
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

void MoneroWalletUiBackend::refresh() {
    setLastError({});
    setDataLoading(true);
    loadStatus();
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

void MoneroWalletUiBackend::createSubaddress(QString label) {
    setLastError({});
    if (ok(modules().monero_wallet_backend.create_subaddress(0, label), "subaddress")) loadReceive();
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
    if (state == "failed") setSendError(o.value("error").toString());
    if (state == "sent" || state == "failed" || state == "cancelled") {
        m_sendPoll.stop();
        if (state == "sent") { loadBalances(); refreshHistory(); }
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
    modules().monero_wallet_backend.cancel_send(id);
    m_sendPoll.stop();
    setSendRequestId({});
    setSendStatusJson(QStringLiteral("{}"));
}

bool MoneroWalletUiBackend::addressValid(QString address) {
    return modules().monero_wallet_backend.address_valid(address);
}

QString MoneroWalletUiBackend::formatXmr(QString atomic) {
    return modules().monero_wallet_backend.format_xmr(atomic);
}

void MoneroWalletUiBackend::closeWallet() {
    setLastError({});
    ok(modules().monero_wallet_backend.close_wallet(), "close");
}
