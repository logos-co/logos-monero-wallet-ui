#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_monero_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Monero wallet backend. Every backend-module call is made here over the generated typed
// client; the QML half renders and collects the password.
//
// Two clocks and one lifecycle: m_readPoll refreshes steady state as a backstop behind the
// backend's events, m_jobPoll follows a wallet lifecycle job (open/create/restore/close/change
// password) to settlement, and m_sendPoll follows a send. Secrets are SLOT arguments and SLOT
// return values — never published as properties, never logged.
class MoneroWalletUiBackend : public MoneroWalletUiSimpleSource,
                              public LogosUiPluginContext
{
public:
    void refresh() override;
    void refreshHistory() override;
    void clearAndRefresh() override;

    // Wallet management.
    void setActiveNetwork(QString network) override;
    void openWallet(QString name, QString password) override;
    void createWallet(QString name, QString password, QString label) override;
    void restoreFromSeed(QString name, QString password, QString seed, int restoreHeight, QString label) override;
    void restoreFromKeys(QString name, QString password, QString address, QString viewKey, QString spendKey,
                         int restoreHeight, QString label) override;
    void changePassword(QString oldPassword, QString newPassword) override;
    QString revealSeed(QString password) override;
    QString revealViewKey(QString password) override;
    void closeWallet() override;
    void saveNodeConfig(QString configJson) override;

    // Receiving.
    void createSubaddress(QString label) override;
    void selectSubaddress(int index) override;
    void setReceiveAmount(QString amountXmr) override;
    void setSubaddressLabel(int index, QString label) override;

    // Spending.
    void prepareSend(QString sendJson) override;
    void confirmSend() override;
    void cancelSend() override;
    void dismissSend() override;
    bool addressValid(QString address) override;
    QString formatXmr(QString atomic) override;

protected:
    void onContextReady() override;

private:
    void say(const QString &line);
    bool ok(const QString &reply, const QString &context);
    void loadStatus();
    void loadRegistry();
    void loadNodeConfig();
    void publishReceiveSelection();
    void loadBalances();
    void loadReceive();
    void track(const QString &reply, const QString &kind);
    void pollJob();
    void pollSend();
    QString qrModulesJson(const QString &text) const;

    QTimer m_readPoll;
    QTimer m_jobPoll;
    QTimer m_sendPoll;
    QString m_pendingKind;
    QString m_lastQrFor;
    QString m_receiveAmount;
};
