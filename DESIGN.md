# DomovoiDiscernment — design (v0.1, the governing build spec)

**DomovoiDiscernment — family cognition for family matters.** (Repo and
display name: `DomovoiDiscernment`; the Dart package stays `domovoi` for
short imports — the WeatherGlass/`glass` pattern.)
A model-agnostic **control plane** for household AI. It is not a harness
(it runs no loop) and not an agent (it decides nothing): apps ask, the
house answers, and Domovoi only governs *where the thinking runs* —
on the phone, on the household stove (a home server), or at a cloud the
user explicitly keyed. The folklore is the contract: the domovoi serves
the house that feeds him, and he never leaves it.

## Why pure Dart (the three forcing facts)

1. `sanctuary_auth_core` depends on Flutter → the stove CLI (a desktop
   binary) cannot consume it. Domovoi therefore carries its own key
   derivation using the SAME primitive libraries (`cryptography`,
   `bip39_mnemonic`) — never hand-rolled primitives.
2. Peckish pins `flutter_gemma 1.0.0-rc.1`; Reckon pins `^0.13.2`.
   A shared flutter_gemma dependency would force a pin war → the on-device
   adapter stays app-side, implementing Domovoi's `Brain`.
3. The household tier must be CI-provable: client ↔ server ↔ fake
   upstream round-trips in-process in plain `dart test`.

## Package layout (each area owned by exactly one builder)

```
lib/domovoi.dart          — export manifest (pre-written; do not reshape)
lib/src/brain.dart        — Brain + AskException            (area CORE)
lib/src/model/            — ModelSpec, ModelTrust laws      (area CORE)
lib/src/transfer/         — resumableDownload engine        (area CORE)
lib/src/keys.dart         — DomovoiKeys (HKDF + BIP39 seed) (area STOVE)
lib/src/stove/            — codec, client, server, status   (area STOVE)
bin/stove.dart            — the CLI                          (area STOVE)
test/…                    — mirrors lib/ (same area split)
```

## Area CORE

**`Brain`** — the one seam. Generalizes Peckish's `LocalBrain`
(`OpenHearth/Peckish/lib/features/ai/on_device/local_brain.dart`):

```dart
abstract class Brain {
  Future<String> complete(String prompt);
}
```

Failures throw `AskException(message, {cause})` — calm, displayable.

**`ModelSpec`** — generalizes `PeckishModelSpec`
(`Peckish/lib/features/ai/on_device/model_spec.dart`) minus the app
catalog: id, displayName, fileName, downloadUrl, sizeBytes (progress
hint ONLY — never completeness judgment), modelType, description,
requiresToken. Catalogs stay app-side.

**`ModelTrust.check(spec) → List<String>`** — the trust laws as a
reusable validator (empty list = trusted). Laws, each a named check:
huggingface.co https URLs only; org allowlist (`litert-community` v1);
`requiresToken` must be false (ungated only); `.task` bundle filename.
Apps' existing spec tests can then call one function.

**`resumableDownload`** — port `Peckish/lib/shared/data/resumable_transfer.dart`
essentially verbatim (it is post-review, cancel-aware, hardened):
`({required Dio dio, required String url, required File partFile,
required Future<void> Function() promote, CancelToken? cancelToken,
void Function(int received, int? total)? onProgress})`. Keep the law in
its doc comment: completion is the atomic .part → final rename, never a
size guess. Tests use a local `HttpServer` fixture (range requests,
resume-from-byte, cancel mid-flight leaves .part, promote called once).

## Area STOVE (the household tier — the v1 ambition)

**Provisioning law (from Peckish sync): the secret IS the pairing.**
Same household phrase on both ends → same key; nothing else can open or
forge a frame. No accounts, no certificates, no discovery service.

**`DomovoiKeys`**:
- `seedFromPhrase(String phrase) → Future<Uint8List>` — standard BIP39
  (PBKDF2-HMAC-SHA512, 2048 iters, salt "mnemonic", 512-bit) via
  `bip39_mnemonic`, byte-identical to sanctuary's `OpenHearthMnemonic`.
- `stoveKey(List<int> secret) → Future<Uint8List>` — HKDF-SHA256,
  info `openhearth.domovoi.stove.v1`, 32 bytes. Distinct domain =
  cryptographic isolation from every sanctuary purpose sharing the seed.

**`StoveCodec`** — AEAD frame codec, modeled on Peckish's `SyncCodec`
(`Peckish/lib/features/sync/data/sync_codec.dart`): frame =
`nonce(12) ‖ ciphertext ‖ mac(16)`, ChaCha20-Poly1305. AAD =
`domovoi-stove/v1|<endpoint>|<challenge>` — protocol version, endpoint,
and single-use challenge all bound; a frame can never replay across
endpoints, versions, or asks. Endpoints: `ask` (request), `answer`
(response — the reply is challenge-bound too, so it cannot be spliced).

**Wire protocol** (HTTP on the LAN, default port **4663** — HOME on a
phone keypad):
- `GET /stove/status` → cleartext JSON `{domovoi: 1, protocol: 1,
  model: <name>}`. No secrets; safe to probe.
- `GET /stove/challenge` → `{challenge: <base64 16B>, ttlSeconds: 60}`.
  Single-use, TTL'd (port Peckish's `replay_challenge_store.dart`).
- `POST /stove/ask` → body is an `ask` frame of JSON
  `{prompt, maxTokens?}`; response body is an `answer` frame of
  `{text}`. ANY verify/decode failure → 403 with a constant body
  (fail-closed, no oracle). Challenge consumed before upstream work.

**`StoveClient implements Brain`** — `complete()` = fetch challenge →
seal ask → POST → open answer. Constructor: `({required host, required
port, required Future<List<int>> Function() secret, Dio? dio})`.

**`StoveServer`** — testable class over `dart:io` `HttpServer` (follow
`Peckish/lib/features/sync/data/lan_sync_server_io.dart` for shape):
binds, verifies, decrypts, then proxies the prompt to an OpenAI-compat
upstream (`POST {upstream}/v1/chat/completions`, single user message,
first choice's content out) and seals the answer. Upstream is a plain
`Uri` — Ollama (`http://127.0.0.1:11434/v1`) and llamafile both speak it.

**`bin/stove.dart`** — args: `--phrase-file` (read household phrase from
a file; NEVER the phrase via argv — process lists leak), `--secret-hex`
(tests/advanced), `--upstream` (default Ollama), `--model` (default
upstream model name, passed through), `--port` (4663). Prints a calm
one-paragraph startup: what it serves, to whom (anyone with the
household phrase), and what leaves the machine (nothing).

## App adoption (v1 wiring, separate repos)

- **Peckish**: replace `lib/shared/data/resumable_transfer.dart` with the
  domovoi engine (delete local copy, swap the two call sites + tests);
  add backend kind `stove` to the AI config (host/port; secret defaults
  to the existing LAN-sync household secret — same input secret, distinct
  HKDF domain, pair-once UX) routed through `StoveClient` in
  `GuessService`, following the existing openai-compat pattern.
- **Reckon**: swap `model_download_service_io.dart` internals onto the
  domovoi engine (public API kept; gains real cancel — the missing
  CancelToken class of bug); add a `stove` provider following
  `openai_compat_llm_service.dart` as template, secret via its own
  secure-storage entry.

## Non-goals (v1)

Routing policy/fallback chains (apps choose the backend explicitly);
model catalogs (app data); streaming; multi-turn chat shapes; cloud
clients (apps keep their own BYOK); mDNS discovery (host:port typed once,
like Peckish sync pairing).

## Laws (yellow-paper seeds)

1. Frames fail closed; verification failure is constant-shaped 403.
2. The AAD binds protocol version, endpoint, and challenge; challenges
   are single-use with TTL.
3. Key material: BIP39 seed → HKDF domain `openhearth.domovoi.stove.v1`;
   no key ever crosses the wire.
4. Download completion is the atomic rename, never a size judgment.
5. Trust laws reject by default: non-allowlisted org, gated model, or
   non-`.task` artifact never reaches a download URL.
6. The status endpoint reveals no secret-derived material.
