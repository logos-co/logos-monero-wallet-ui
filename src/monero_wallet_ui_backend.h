#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_monero_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The wallet backend. Reads through the generated typed client, republishes as PROPs, and
// drives the send state machine. Never sees a password; the keys app owns that.
class MoneroWalletUiBackend : public MoneroWalletUiSimpleSource,
                              public LogosUiPluginContext
{
public:
    void refresh() override;
    void refreshHistory() override;
    void createSubaddress(QString label) override;
    void prepareSend(QString sendJson) override;
    void confirmSend() override;
    void cancelSend() override;
    bool addressValid(QString address) override;
    QString formatXmr(QString atomic) override;
    void closeWallet() override;

protected:
    void onContextReady() override;

private:
    void say(const QString &line);
    bool ok(const QString &reply, const QString &context);
    void loadStatus();
    void loadBalances();
    void loadReceive();
    void pollSend();
    QString qrSvgDataUri(const QString &text) const;

    QTimer m_poll;
    QTimer m_sendPoll;
    QString m_lastQrFor;
};
