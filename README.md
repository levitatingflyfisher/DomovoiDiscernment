# DomovoiDiscernment — Dart package `domovoi` — *family cognition for family matters.*

(The repo and display name is `DomovoiDiscernment`, searchable; the package
stays `domovoi` for short imports — the WeatherGlass/`glass` pattern.
`import 'package:domovoi/domovoi.dart';`)

A model-agnostic **control plane** for household AI. Apps ask; the house
answers — on the phone, on the household stove (a home server on your own
Wi-Fi), or at a cloud the user explicitly keyed. Domovoi governs *where the
thinking runs*, never what is thought. It runs no loop and decides nothing:
not a harness, not an agent — the plumbing that lets a family's apps reach
the family's own compute with no account in between.

## What's in the box

- **`Brain`** — the one seam between an app's features and whatever thinks.
  One method: `Future<String> complete(String prompt)`. Failures surface as
  calm, displayable `AskException`s.
- **`ModelSpec` + `ModelTrust`** — model catalogs stay app data; domovoi
  ships the trust laws (https on huggingface.co only, org allowlist, ungated
  only, `.task` bundles only). The laws reject by default: a spec that
  breaks any of them never reaches a download URL.
- **`resumableDownload`** — the cancel-aware, resume-from-byte transfer
  engine for big household downloads (model bundles). Completion is the
  atomic `.part` → final rename inside the caller's `promote`, never a size
  guess. It returns a `TransferOutcome`, because a cancelled transfer also
  ends without error and nothing may call that an install.
  `resumableDownloadStream` is the same engine wearing the progress-event
  dialect the download screens speak.
- **The stove protocol** — encrypted asks to a home server.
  ChaCha20-Poly1305 frames keyed from the household phrase, single-use
  challenges, fail-closed `403`s. `StoveClient` is a `Brain`; `StoveServer`
  proxies to a local OpenAI-compatible upstream (Ollama, llamafile); and
  `dart run domovoi:stove` is the CLI that lights it.

## Quick start: light the stove

On the household machine — the desktop that owns the GPU:

```sh
# 1. An upstream that speaks OpenAI-compat. Ollama is the easy one.
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2

# 2. The household phrase, in a file only you can read (never on argv).
printf '%s\n' 'your twelve word household phrase goes here ...' > ~/household
chmod 600 ~/household

# 3. Light it (from this repo's checkout, after `dart pub get`).
dart run domovoi:stove --phrase-file ~/household --model llama3.2
```

Then point an app at `<host>:4663` and give it the same phrase. That is the
whole pairing: same phrase on both ends → same key; no accounts, no
certificates, no discovery service. `GET /stove/status` answers in
cleartext (and reveals nothing secret) when you want to check the stove is
lit. The ten-minute walkthrough:
[docs/tutorials/light-the-stove.md](docs/tutorials/light-the-stove.md).

## Who consumes it

- **Peckish** — the resumable download engine behind its model and barcode
  slices, and a `stove` AI backend.
- **Reckon** — the same engine under its model downloads, and a `stove`
  provider beside its BYOK ones.

Both take it as a path dependency (`../DomovoiDiscernment`), the sibling
pattern the fleet already uses for `sanctuary_auth_core`.

## Building and testing

Pure Dart — no Flutter, no device, no emulator ([ADR-0001](docs/adr/0001-pure-dart-control-plane.md)):

```sh
dart pub get
dart test
```

The whole stove protocol — client ↔ server ↔ fake upstream — round-trips
in-process under plain `dart test`.

## Documentation

[VISION.md](VISION.md) (the one idea + honest scorecard) →
[AGENTS.md](AGENTS.md) (the map, for agents) →
[docs/README.md](docs/README.md) (the Diátaxis hub).
[DESIGN.md](DESIGN.md) is the governing build spec; decisions live in
[docs/adr/](docs/adr/README.md).

## License

[MIT](LICENSE).
