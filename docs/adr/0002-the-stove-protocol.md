# ADR-0002: The stove protocol — encrypted asks to a home server

**Status:** Accepted (v0.1)

## Context

Both apps already speak "OpenAI-compatible endpoint" for a self-hosted
server, so a phone can reach a big model on a home desktop today — over
plain HTTP that anyone on the Wi-Fi can read or impersonate. StillLife's
LAN sync learned this lesson once (started plaintext, went encrypted
fail-closed); Peckish's LAN sync shipped encrypted from day one on the
pattern that ADR was written for. Household inference deserves the same
floor: prompts are family matters.

## Decision

A minimal HTTP protocol on the LAN (default port **4663** — HOME on a
phone keypad), three endpoints:

- `GET /stove/status` — cleartext, secret-free: `{domovoi, protocol,
  model}`. Safe to probe; used for "is the stove lit?".
- `GET /stove/challenge` — a single-use, 60-second-TTL random challenge.
- `POST /stove/ask` — body and response are AEAD frames
  (`nonce(12) ‖ ciphertext ‖ mac(16)`, ChaCha20-Poly1305). The AAD binds
  `domovoi-stove/v1 | endpoint | challenge`: a frame can never be
  replayed across endpoints, protocol versions, or asks, and the answer
  is bound to the same challenge so it cannot be spliced from another
  exchange.

Fail-closed law: any verification or decode failure — wrong key, spent
challenge, tampered frame — yields the same constant-shaped `403
refused`. The server is not an oracle. The challenge is consumed before
any upstream work, so a replay cannot even burn GPU time.

Behind the seal, the stove proxies the prompt to a local
OpenAI-compatible upstream (Ollama, llamafile) and returns the text.
The upstream never sees the network; the network never sees a prompt.

## Consequences

One new wire format to maintain, versioned in the AAD so peers fail
closed on mismatch rather than mis-decrypting. Discovery is deliberately
manual (type host:port once, like Peckish sync pairing) — mDNS is a
non-goal until typing an IP proves to be the actual friction.
