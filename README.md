# logos-monero-wallet-ui

`monero_wallet_ui` — send and receive Monero on one network at a time: balances, a reviewed
send, receive addresses with a QR, and activity. **Holds no password and no key material** —
its `.rep` is on `scripts/check-rep-passwords.py`'s GOVERNED list and CI asserts the absence.
A locked wallet asks the keys app through `monero.wallet.unlock`.

The review step governs **broadcast**: the engine signed when it built the preview. The QR is
drawn as plain `Rectangle`s from a module matrix computed with nayuki's `qrcodegen` (MIT,
vendored) — the design system has no QR control, Basecamp's `ui_qml` sandbox blocks every URL
import (`data:` URIs included, so an `Image` cannot show it), and a `Canvas` never receives
`paint()` inside a Basecamp plugin view.
