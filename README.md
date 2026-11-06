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

Of those two it **uses** neither: managing wallets is a screen here, not a trip to a second app. A self-provided
intent would dispatch to itself anyway, and the shell raises a chooser for every other case.

It **uses** `monero.node.configure`: the node sheet's **Open Monero Node…** hands off to the
app that runs the local node (`monerod_ui`). It also **uses** `tor.manage`: **Manage Tor…**, beside
the Tor that comes with Logos, hands off to the Tor app.

## Networks

The network picker in the header selects the network; it is enabled only while no wallet is open,
opening or closing. The Wallets screen lists wallets for the selected network. Select Stagenet to
open a Stagenet wallet; opening it by name while Mainnet is selected is refused. Unverified wallet
files remain visible until the engine checks their network when opened. The picker and Settings show
the open wallet's network.

## Where the chain comes from

The node sheet (Node, on the Wallets screen) is one decision, read top to bottom, kept per network
by `monero_node_module`, "Use Tor for" included. It has the first-run screen's sections and words,
shared with the Bitcoin and Zcash wallets. Only what the choice uses is shown under it, and the radios are the state:
there is no "Use it" or "Connect to".

- **Your own node** (Most private), with one benefits and costs note:
  - **In Logos:** the node `monerod_module` runs (local mode), with its state and **Open Monero
    Node…**. Offered when it can serve the network. The wallet's connection never leaves the
    computer, so there is no Tor here; the node's peer connections are set in the Monero Node app.
    Start the node before opening a wallet: the engine connects when a wallet opens.
  - **At an address:** a node you run elsewhere, with an optional login. The address decides,
    shown under the field: on your network "Reached directly. Tor can't reach your network.", an
    onion "Always reached through Tor.", anywhere else a **Reach it through Tor** switch, on by
    default. Which Tor shows where Tor is used. Stored with `own: true` and `reachThroughTor`; "Use
    Tor for" does not apply to it. **Trusted daemon** shows only for a loopback address, the only
    place the engine honours it.
- **Public sources**, nodes run by other people:
  - **A node picked for you:** the node module's seeded node, moved by health on mainnet. Saved as
    `source: "default"`, so the node module, not this form, supplies the address.
  - **A node you choose:** a direct address and an optional address over Tor. A login stored for
    that address stays with it; a new address drops it. An address on your own network with no
    address over Tor is saved as your own node.
  - **Use Tor for:** Everything (`all`), Only what identifies you (`identifying`, recommended),
    Nothing (`none`), each with what happens, pros and cons, worded for the choice above. It is
    kept for the active network and stored at once.
  - **Which Tor**, unless Nothing: the Tor that comes with Logos, with its status from
    `node_health` and **Manage Tor…**, or your own Tor's SOCKS address. Tor routes refuse to
    connect without Tor.
- **Save node** stores the choice on screen. A hidden field sends what is stored, never its edits,
  and never blocks Save: In Logos keeps the stored remote half, and an empty own Tor matters only
  while Which Tor shows. The sheet is read-only, with "Close your open accounts to change this.",
  while a wallet is open, opening or closing. Settings shows the stored choice in the sheet's shape, read-only.
- **First run, per network:** while the node says `torUseChosen: false` for the active network, the
  same top choice replaces the Wallets screen, with Public sources preselected and Use Tor for under
  it. It shows the first time each network is used and names that network. A fresh install
  preselects Only what identifies you; an install from before the setting preselects its current
  routing, tagged Current. Your own node stores the recommended mode too (or an existing install's
  routing), so a later switch to public sources has one, then opens the node sheet on your own
  node. A backend without `tor_use` shows no screen.
- **An open wallet** shows its route: catching up directly, waiting for Tor, or over Tor. While it
  catches up or waits, Send says "You can send once the wallet has moved to Tor." and
  Review is off; the backend refuses `prepare_send` with `waiting_for_tor` either way.

`ci/states.qml` drives these states against a fake backend (CI Gate C), with the Qt that
`flake.lock` pins through logos-nix. `doctests/assert_local_node.py` drives In Logos against a
running `monerod_module`, and without it (`--absent`).

## QR

Drawn as plain `Rectangle`s from a module matrix computed with nayuki's `qrcodegen` (MIT, vendored):
the design system has no QR control, Basecamp's `ui_qml` sandbox blocks every URL import (`data:`
URIs included, so an `Image` cannot show one), and a `Canvas` never receives `paint()` inside a
Basecamp plugin view.
