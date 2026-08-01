# Pair an app with the stove

There is no pairing *protocol* — no QR codes, no six-digit confirmations,
no certificate exchange. **The secret is the pairing**
([ADR-0003](../adr/0003-the-secret-is-the-pairing.md)): every end that
knows the household phrase derives the same frame key, and nothing else
can open or forge a single frame. Pairing an app is therefore one
ceremony: get the same phrase to both ends, tell the app where the stove
lives.

## The phrase ceremony

1. **At the stove**: the phrase sits in a file the stove reads at startup
   (`--phrase-file ~/household`, `chmod 600`). Never pass the phrase on
   the command line; process lists leak. The stove validates the BIP39
   checksum on start and dies loudly on a typo.
2. **In the app**: open the app's AI settings, choose the **stove**
   backend, and enter the stove's `host:port` (the port is 4663 unless you
   changed it). Then supply the phrase:
   - **Peckish** defaults to the household secret it already holds for LAN
     sync — if the household paired for sync, the stove works with zero new
     ceremony. The same input secret feeds a *different* HKDF domain, so
     the sync key and the stove key stay cryptographically isolated.
   - **Reckon** stores the phrase in its own secure-storage entry, entered
     once in its stove settings.
3. **Confirm**: ask something. A completed answer proves both directions —
   only the right key opens an ask, and only the right key seals an answer
   the app will accept. A wrong phrase gets the app's calm refusal message
   ("Do both ends share the household phrase?").

There is no account created anywhere, and no third machine involved.

## Where the phrase lives

| End | Where | Notes |
|---|---|---|
| Stove (desktop) | A file, e.g. `~/household`, mode 600 | Read once at startup; the derived key lives only in process memory |
| Peckish | Its existing household secret (sanctuary spine / LAN-sync pairing) | Pair-once UX; distinct HKDF domain per purpose |
| Reckon | Its own secure-storage entry | Entered in the stove settings |

The phrase never crosses the wire in any form — not at pairing, not per
ask. Only AEAD frames travel, and possession of the derived key is the
proof of membership.

## Rotating the phrase

Rotate when a device leaves the household or the phrase may have leaked.
Rotation is re-keying, and it is deliberately blunt — there is no
per-device revocation; the household is the trust boundary:

1. Generate a new BIP39 phrase.
2. Write it to the stove's phrase file and restart the stove. From this
   moment the old key opens nothing.
3. Update the phrase in each app (Peckish's household secret, Reckon's
   stove entry). Devices still holding the old phrase get the same
   constant `403 refused` as any stranger — the stove does not explain.

Note the blast radius before you rotate: if the phrase is the household's
sanctuary phrase, rotating it is a *household* event (backups, sync — every
purpose keyed from that seed), not a stove-only event. A stove-only
rotation means giving the stove its own dedicated phrase file with a fresh
phrase and updating only the stove entries in the apps.
