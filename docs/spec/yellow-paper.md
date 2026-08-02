# DomovoiDiscernment — Yellow Paper

*A formal specification of the stove protocol: key schedule, frame and AAD
grammar, challenge lifecycle, threat model, and the six invariants.*

**Register.** "Yellow paper" is the protocol convention for a rigorous
specification. This document is precise about *intent and current
behavior*; it is **not** a machine-checked proof. Every invariant below is
tested-and-intended: the enforcing test files are named inline, and the
code they exercise was authored by an AI assistant — treat the
implementation as the artifact to be checked against this spec, not as an
oracle. For intuition read [ADR-0002](../adr/0002-the-stove-protocol.md)
and [ADR-0003](../adr/0003-the-secret-is-the-pairing.md) first; the
governing build spec is [DESIGN.md](../../DESIGN.md).

---

## 1. Notation

`‖` is byte concatenation; `|` inside a quoted string is the literal pipe
character. `E_K(m, a)` is ChaCha20-Poly1305 (IETF) sealing of message `m`
under 32-byte key `K` with associated data `a`; `D_K` is the opening
operation, which fails atomically (no partial plaintext). All decisions
are **fail-closed**: any failure on the ask path yields the single
refusal outcome `⊥` = HTTP `403`, body `refused`, regardless of cause.

## 2. Key schedule

Two derivation steps, both through audited primitive libraries
(`package:bip39_mnemonic`, `package:cryptography`) — nothing hand-rolled.
Implementation: `lib/src/keys.dart` (`DomovoiKeys`).

```text
phrase  — a valid BIP39 mnemonic sentence (checksum enforced at parse)
seed    = PBKDF2-HMAC-SHA512(password = phrase, salt = "mnemonic",
                             iterations = 2048, dkLen = 64)     # standard BIP39
K       = HKDF-SHA256(ikm = seed, salt = ∅,
                      info = "openhearth.domovoi.stove.v1", L = 32)
```

- The seed step is byte-identical to sanctuary's `OpenHearthMnemonic`
  (spec-fixed, not code-shared); a golden vector pins it in
  `test/keys_test.dart` ("derives the pinned golden seed for a fixed
  valid phrase").
- The HKDF `info` string is **frozen**: changing it strands every paired
  household. Domain separation is what makes lending the seed to the
  stove lend nothing else; `test/keys_test.dart` proves any other info
  string yields a different key ("is domain-separated: any other HKDF
  info yields a different key").
- An invalid phrase throws at provisioning ("rejects an invalid phrase");
  an empty secret is rejected ("rejects an empty secret"). `K` never
  crosses the wire in any form (§8, I3/I6).

## 3. Frame grammar

Implementation: `lib/src/stove/stove_codec.dart` (`StoveCodec`).

```text
frame      = nonce(12) ‖ ciphertext(|m|) ‖ mac(16)          # 28-byte overhead
cipher     = ChaCha20-Poly1305 (IETF), key length exactly 32 bytes
nonce      = 12 random bytes, fresh per seal (cipher-library supplied)
```

Well-formedness: `|frame| ≥ 28`, else structural rejection before any
cryptography (`test/stove/stove_codec_test.dart`, "a frame too short to
hold nonce + mac fails structurally"). Opening verifies the Poly1305 tag
over ciphertext *and* AAD; any failure — tampered byte, wrong key, wrong
AAD — throws one exception type, `StoveCodecException`, with no partial
plaintext ("a tampered byte fails to open", "the wrong key fails to
open").

Plaintext shapes (UTF-8 JSON):

```text
ask     = { "prompt": string, "maxTokens"?: int }
answer  = { "text": string }
```

## 4. AAD grammar

```text
AAD(e, c)  = UTF8( "domovoi-stove/v1" ‖ "|" ‖ e ‖ "|" ‖ c )
e          ∈ { "ask", "answer" }                 # fixed literals
c          = base64( 16 random bytes )           # the challenge token
```

The AAD binds **protocol version** (the `v1` in the prefix —
`StoveCodec.protocolVersion = 1`; any wire change bumps it so peers fail
closed by failing to open), **endpoint**, and **challenge**. Consequences,
each test-bound in `test/stove/stove_codec_test.dart`:

- A frame sealed for one endpoint never opens as the other ("a frame
  sealed for 'ask' does not open as 'answer'") — an attacker cannot
  reflect a client's own ask back as an answer.
- A frame never opens under a different challenge ("a different challenge
  fails to open") — and since the answer is sealed to the *same*
  challenge as its ask, answers cannot be spliced across exchanges.

**Injection-freeness.** The base64 alphabet is `A–Z a–z 0–9 + / =` and
cannot contain `|`; the endpoint tags are fixed pipe-free literals; the
prefix is constant. Hence `(e, c) ↦ AAD(e, c)` is injective — no
challenge value can be crafted to make two distinct (endpoint, challenge)
pairs collide into one AAD.

## 5. Challenge lifecycle

Implementation: `lib/src/stove/challenge_store.dart` (`ChallengeStore`);
tests: `test/stove/challenge_store_test.dart`.

```text
issue():    evict expired; if |outstanding| ≥ 256, return ⊥ (server: 503)
            c ← base64(16 bytes from Random.secure); record (c, now); return c
consume(c): evict expired; remove c from outstanding;
            return recorded ∧ age(c) ≤ TTL          # TTL = 60 s
```

Properties, each with its test: tokens are 16 bytes base64 ("issues a
base64 16-byte challenge") and distinct ("issued challenges are
distinct"); consumption is single-use — a second `consume` of the same
token returns false ("consume is single-use"); unknown and expired tokens
are refused ("an unknown challenge is rejected", "an expired challenge is
rejected (fake clock)"); the outstanding set is bounded at 256, so a
flood of `/stove/challenge` probes cannot grow memory ("outstanding
challenges are bounded").

**Consume-before-work.** The server consumes the token (from the
cleartext `x-stove-challenge` header) *before* reading the request body,
before verification, and before any upstream call — so a failed or
replayed ask burns its challenge and no replay can cost GPU time
(`test/stove/stove_server_test.dart`, "consumes the challenge before
verification: a failed ask burns it"; `stove_roundtrip_test.dart`,
"a replayed ask frame is refused"). The header is cleartext by design:
the AAD binding, not secrecy of the token, is what makes echoing it
unforgeable.

## 6. The ask exchange

Client (`lib/src/stove/stove_client.dart`) and server
(`lib/src/stove/stove_server.dart`); the in-process end-to-end proof is
`test/stove/stove_roundtrip_test.dart` ("client and server sharing the
household phrase complete an ask", "a client with the wrong secret is
refused").

```text
C:  GET /stove/challenge                        → { challenge: c, ttlSeconds: 60 }
C:  K ← HKDF(seed)          # derived fresh per ask; never cached, never sent
C:  POST /stove/ask,  header x-stove-challenge: c,  body E_K(ask, AAD("ask", c))
S:  consume(c) ∨ ⊥;  |body| ≤ 1 MiB ∨ ⊥;  m ← D_K(body, AAD("ask", c)) ∨ ⊥
S:  text ← upstream POST {upstream}/chat/completions (model, [user: prompt]) ∨ ⊥
S:  reply 200,  body E_K({text}, AAD("answer", c))
C:  answer ← D_K(reply, AAD("answer", c))  ∨ AskException
```

`⊥` is always the constant `403 refused`. Upstream errors take the same
path ("an upstream failure is refused, not echoed") — the stove does not
relay upstream diagnostics to the network.

## 7. Threat model

The adversary owns the LAN, not the endpoints. The household phrase, the
devices holding it, and the stove machine itself are trusted (the
household is the trust boundary — ADR-0003).

| Adversary | Capability | Outcome |
|---|---|---|
| **Passive sniffer** | Reads all LAN traffic | Sees status JSON, challenge tokens, and frame ciphertexts; learns the model name, ask timing, and sizes. Never plaintext or key material — confidentiality reduces to ChaCha20-Poly1305 under `K`, which never crosses the wire |
| **Active MITM** | Injects, modifies, reflects, splices | Cannot forge or alter a frame without `K` (Poly1305 over ciphertext + AAD); cannot cross-splice endpoints or exchanges (§4). Can drop or delay traffic — availability is out of scope. Can serve a fake `/stove/status`; status is unauthenticated by design and carries no trust decisions |
| **Replayer** | Re-sends a captured ask frame | The frame's challenge is already consumed → `⊥` before any work (§5) |
| **Challenge flooder** | Hammers `/stove/challenge` and `/stove/ask` | Outstanding tokens capped at 256; at the cap issuance REFUSES (`503 busy`) rather than evicting — a flooder can pause new challenges but can never drop the one an honest client is holding between its fetch and its ask ("at capacity, issuing refuses instead of evicting a live challenge"). Ask bodies capped at 1 MiB and bounded by a 30-second read deadline, so a trickled body cannot pin a handler ("a trickled body is cut off, not held open forever") |
| **Offline brute force** | Captures frames, guesses phrases | Work factor is the phrase's entropy: a BIP39 mnemonic carries ≥ 128 bits (12 words). PBKDF2's 2048 iterations is BIP39 spec compliance, not a hardening claim. The `--secret-hex` escape hatch is floored at 16 bytes and warns that it leaks through process lists and shell history; the phrase path (mode-checked, `chmod 600` enforced) is the supported ceremony |

## 8. The six invariants

From [DESIGN.md](../../DESIGN.md) § Laws, each with its enforcing tests.

- **I1 — Frames fail closed; verification failure is a constant-shaped
  403.** `test/stove/stove_server_test.dart` ("refuses identically on
  missing challenge, unknown challenge, garbage frame, and wrong key (no
  oracle)" — asserts byte-identical refusals; "an upstream failure is
  refused, not echoed").
- **I2 — The AAD binds protocol version, endpoint, and challenge;
  challenges are single-use with TTL.** `test/stove/stove_codec_test.dart`
  (endpoint and challenge cross-open failures, §4);
  `test/stove/challenge_store_test.dart` (single-use, TTL, §5);
  `test/stove/stove_roundtrip_test.dart` ("a replayed ask frame is
  refused" — the whole-protocol replay proof).
- **I3 — Key material: BIP39 seed → HKDF domain
  `openhearth.domovoi.stove.v1`; no key ever crosses the wire.**
  `test/keys_test.dart` (golden seed vector; domain separation; 32-byte
  output). The no-wire-key half is I6's test plus the construction: no
  code path serializes `K` or the seed into any response.
- **I4 — Download completion is the atomic rename, never a size
  judgment.** `test/transfer/resumable_transfer_test.dart` ("fresh
  download sends no Range, promotes exactly once"; "cancel mid-flight is
  quiet, leaves the .part, never promotes"; the 200-on-resume and
  416-on-resume restarts discard rather than corrupt).
- **I5 — Trust laws reject by default.**
  `test/model/model_trust_test.dart` ("rejects an org outside the
  allowlist"; "rejects a gated model (requiresToken true)"; "rejects a
  URL with no org path segment (reject by default)"; "reports one
  violation per broken law, not just the first").
- **I6 — The status endpoint reveals no secret-derived material.**
  `test/stove/stove_roundtrip_test.dart` ("the status endpoint reveals no
  key-derived bytes" — scans the status body against key and seed bytes);
  `test/stove/stove_server_test.dart` ("returns cleartext {domovoi,
  protocol, model}" — the closed shape).

## 9. Explicit non-guarantees

Named so nobody discovers them the hard way:

- **No forward secrecy.** One static household key; an adversary who
  records traffic and later obtains the phrase decrypts the recording.
  Rotation (see [pair-an-app](../how-to/pair-an-app.md)) bounds the
  window; it does not undo it.
- **No per-device identity or revocation.** Possession of the phrase is
  full membership; the remedy for a departed device is rotation.
- **Nonce collisions are probabilistic.** Random 96-bit nonces under one
  static key: reuse would be catastrophic (keystream and tag-key reuse),
  and the birthday bound says stay far below ~2^48 frames per key. A
  household asking a thousand times a day for thirty years is still seven
  orders of magnitude under the bound; stated, not enforced.
- **Availability is not defended.** A LAN adversary can drop, delay, or
  flood; the caps bound memory, not service.
- **`/stove/status` is unauthenticated.** Anyone on the LAN learns a
  stove exists and its model name. It must never grow a field derived
  from secrets — that is I6, and it is test-bound.
