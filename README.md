# logos-monero-wallet-ui

`monero_wallet_ui` — the Monero wallet, as one app: balances, a reviewed send, receive addresses
with a QR, activity, and the wallet management (create · restore · open · close · change password ·
show seed) that Monero GUI keeps under Settings and every Monero wallet ships in the same window.

## Why one app, when the EVM wallet is three

EVM splits its keystore surface off because one vault holds many accounts, several UIs share it,
and **every signature needs the vault password** — so a separate approval surface is a real gate.
None of that transfers to Monero:

- one wallet file is one seed, and the engine holds exactly one open wallet at a time;
- the password is a once-per-session **unlock**, not a per-signature credential, so once a wallet is
  open there is nothing for a signer surface to approve;
- there is no DApp ecosystem asking this wallet to sign.

What actually lets a second app share the open wallet is the **module layer** — `monero_wallet_backend`
and `monero_wallet_core_module` — not the number of UIs. That is untouched.

## Secrets

The wallet password crosses as a **SLOT argument** only; the seed and view key are **SLOT return
values** only, shown once and dropped, and cleared whenever the wallet closes or the user leaves
Settings. Never a `PROP`: a PROP is cached in the replica and broadcast to every connected replica,
so a secret in one leaks by construction.

`scripts/check-rep-passwords.py` in `logos-workspace` owns that rule and lists this repo under
`SECRET_SLOTS` (secret SLOTs permitted, any secret PROP refused). **It does not run against this
repo yet**: the gate reports it as `SKIPPED` until the repo is registered as a workspace submodule,
so treat the rule as agreed and locally tripwired, not as enforced. The doctest carries a
deliberately wider substring check in the meantime. Every password field sets
`passwordMaskDelay = 0`.

The review step governs **broadcast**: the engine signed when it built the preview. Nothing here is
offline signing.

## Intents

The app **provides** both Monero capabilities so another app can reach this wallet:

| intent | shape |
|---|---|
| `monero.wallet.unlock` | `{ wallet }` — opens the password sheet for that wallet, answers when the open settles |
| `monero.accounts.manage` | `handoff: true` — brings wallet management up and leaves the user here |

It **uses** neither: managing wallets is a screen here, not a trip to a second app. A self-provided
intent would dispatch to itself anyway, and the shell raises a chooser for every other case.

## QR

Drawn as plain `Rectangle`s from a module matrix computed with nayuki's `qrcodegen` (MIT, vendored):
the design system has no QR control, Basecamp's `ui_qml` sandbox blocks every URL import (`data:`
URIs included, so an `Image` cannot show one), and a `Canvas` never receives `paint()` inside a
Basecamp plugin view.
