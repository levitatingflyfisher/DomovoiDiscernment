# AGENTS.md — working on DomovoiDiscernment

`domovoi` is the OpenHearth control plane for household AI: the `Brain`
seam, the model trust laws, the resumable download engine, and the
encrypted stove protocol to a home server. Pure Dart, consumed by Peckish
and Reckon as a sibling path dependency.

## Read first

README → VISION (the one idea + honest scorecard) → this file →
[docs/README.md](docs/README.md) (Diátaxis hub). **DESIGN.md is the
governing build spec**; decisions live in docs/adr/.

## Map

- `lib/domovoi.dart` — export manifest (pre-written; do not reshape).
- `lib/src/brain.dart` — `Brain` + `AskException`, the one seam between an
  app's features and whatever thinks.
- `lib/src/model/` — `ModelSpec` (pure data, no plugin imports) and
  `ModelTrust.check` (the trust laws as one reusable validator).
- `lib/src/transfer/` — `resumableDownload`: Range-resume, cancel-aware,
  promote-once, and it says which of the two ways it ended
  (`TransferOutcome`). `resumableDownloadStream` is the same engine as
  progress events for download screens. Ported from Peckish post-review;
  treat it as hardened.
- `lib/src/keys.dart` — `DomovoiKeys`: BIP39 seed from the household
  phrase, HKDF-SHA256 stove key under the frozen domain string.
- `lib/src/stove/` — `stove_codec.dart` (AEAD frames + AAD binding),
  `challenge_store.dart` (single-use TTL replay protection),
  `stove_client.dart` (a `Brain` over the protocol), `stove_server.dart`
  (the home-server side, proxying to an OpenAI-compat upstream).
- `bin/stove.dart` — the CLI. Thin by law: argument handling and the
  startup paragraph only; every protocol behavior lives in `StoveServer`,
  where it is tested.
- `test/` — mirrors `lib/` (`test/stove/stove_roundtrip_test.dart` is the
  client ↔ server ↔ fake-upstream proof; `test/stove_cli_test.dart` drives
  the real binary as a subprocess).

## Non-negotiables

- **The HKDF domain string is FROZEN.** `openhearth.domovoi.stove.v1`
  (`DomovoiKeys.stoveKeyDomain`) — changing it strands every paired
  household. Same for the BIP39 derivation parameters: they must stay
  byte-identical to sanctuary's.
- **AAD binding.** Every frame's AAD is
  `domovoi-stove/v1|<endpoint>|<challenge>` — protocol version, endpoint,
  and single-use challenge all bound. Never seal or open a frame outside
  `StoveCodec`.
- **The fail-closed 403 law.** ANY `/stove/ask` failure — missing or spent
  challenge, oversize body, bad frame, wrong key, upstream trouble — is
  the same constant-shaped `403 refused`. No branch may leak the cause to
  the peer.
- **Challenge before work.** The server consumes the challenge before
  reading the frame, before verifying, before any upstream call. A replay
  must be dead on arrival and must burn no GPU time.
- **The atomic-rename completion law.** Download completion is the
  caller's `.part` → final rename inside `promote`, never a size judgment.
  `sizeBytes` is a progress hint only.
- **Trust laws reject by default.** New laws add violations; nothing ever
  waves a spec through on a missing field.
- **Pure Dart forever.** No Flutter dependencies, ever — the stove CLI is
  a desktop binary and the whole protocol must keep proving itself under
  plain `dart test` (ADR-0001). App adapters (flutter_gemma, secure
  storage) stay app-side.
- **Secrets never ride argv.** The phrase comes from `--phrase-file`;
  error paths never echo the phrase or why it failed to parse.

## How to work

TDD Iron Law: test first, watch it fail for the right reason, implement,
watch it pass. `dart analyze` clean and full `dart test` before any push.
Atomic commits stating the *why*. The suite is fast (in-process protocol
round-trips, injectable clocks and ciphers) — there is no excuse to skip
it.
