# The stove protocol — wire reference

Plain HTTP on the LAN; everything that matters travels as an AEAD frame.
The formal spec (key schedule, grammars, threat model, invariants) is the
[yellow paper](../spec/yellow-paper.md); the decision record is
[ADR-0002](../adr/0002-the-stove-protocol.md). This page is the numbers.

## Defaults

| Item | Value | Source |
|---|---|---|
| Port | **4663** — HOME on a phone keypad | `kStovePort` |
| Upstream | `http://127.0.0.1:11434/v1` (Ollama's default) | `bin/stove.dart --upstream` |
| Model | `llama3.2` (passed through to the upstream) | `bin/stove.dart --model` |
| Challenge TTL | 60 seconds | `ChallengeStore.ttl` |
| Outstanding challenges | 256 max; at the cap issuance refuses (`503`) — live tokens are never evicted | `ChallengeStore.maxOutstanding` |
| Max ask frame | 1 MiB (1 048 576 bytes) | `StoveServer.maxFrameBytes` |
| Frame overhead | 28 bytes (12 nonce + 16 mac) | `StoveCodec.frameOverhead` |
| Protocol version | 1 (embedded in the AAD) | `StoveCodec.protocolVersion` |

## Endpoints

### `GET /stove/status`

Cleartext capability probe. Reveals no secret-derived material — only that
a stove lives here and what it serves.

```json
{"domovoi": 1, "protocol": 1, "model": "llama3.2"}
```

### `GET /stove/challenge`

Issues a fresh single-use challenge: 16 random bytes, base64-encoded,
valid for `ttlSeconds`.

```json
{"challenge": "<base64 16 bytes>", "ttlSeconds": 60}
```

### `POST /stove/ask`

- **Request header**: `x-stove-challenge: <challenge>` — the token from
  `/stove/challenge`, echoed in cleartext. Cleartext by design: the server
  consumes it *before* opening the frame, and the AAD binding is what
  makes echoing it unforgeable.
- **Request body** (`application/octet-stream`): an `ask` frame whose
  plaintext is JSON `{"prompt": "...", "maxTokens": 123}` (`maxTokens`
  optional, forwarded upstream as `max_tokens`).
- **Response body** (`application/octet-stream`): an `answer` frame whose
  plaintext is JSON `{"text": "..."}` — sealed to the *same* challenge, so
  an answer can never be spliced from another exchange.

## Frame grammar

```text
frame = nonce(12) ‖ ciphertext ‖ mac(16)
```

ChaCha20-Poly1305 (IETF), 32-byte key, via `package:cryptography` — nothing
hand-rolled. The associated data binds every frame to the protocol
version, the endpoint, and the single-use challenge:

```text
AAD = "domovoi-stove/v1" | <endpoint> | <challenge>     (UTF-8, '|' literal)
endpoint ∈ { "ask", "answer" }
```

A frame therefore cannot replay across endpoints, protocol versions, or
asks. The base64 challenge alphabet cannot contain `|`, so the AAD parses
unambiguously (see the yellow paper §4).

## Status codes

| Code | Meaning |
|---|---|
| `200` | Success: status/challenge JSON, or a sealed `answer` frame |
| `403` body `refused` | The constant-shaped refusal. Every `/stove/ask` failure — missing, unknown, expired, or reused challenge; oversize body; structurally invalid frame; wrong key; tampered bytes; unparseable plaintext; upstream error; a body that misses the read deadline; a repeated challenge header; any unhandled throw inside a handler — looks exactly like this. Fail closed, no oracle. |
| `503` body `busy` | `/stove/challenge` only: 256 challenges are already outstanding. Retry — this reveals nothing secret. |
| `404` | Unknown route or method |

## Size caps

- Ask frames above **1 MiB** are refused mid-read (a prompt is small; a
  hostile flood must not buy unbounded memory).
- A frame shorter than **28 bytes** cannot hold nonce + mac and is
  structurally invalid.
- The challenge map holds at most **256** outstanding tokens. At the cap
  the stove stops issuing (`503 busy`) rather than evicting: a flood can
  pause new challenges, but can never drop the challenge an honest client
  is holding between its fetch and its ask.
- A `/stove/ask` body must arrive within **30 seconds**; a trickled body
  is refused rather than pinning the handler open.
