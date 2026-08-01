# ADR-0001: A pure-Dart control plane — no Flutter, no flutter_gemma

**Status:** Accepted (v0.1)

## Context

Two apps (Peckish, Reckon) grew the same on-device-AI machinery
independently: a brain seam, a model catalog with trust rules, a
resumable downloader, BYOK clients. Extracting the shared spine ran into
two hard facts. First, `sanctuary_auth_core` depends on Flutter
(`flutter_secure_storage`, Riverpod providers), so nothing that must run
on a desktop CLI — the household stove — can consume it. Second, the apps
pin incompatible flutter_gemma versions (Peckish `1.0.0-rc.1`, Reckon
`^0.13.2`, each after its own painful pin saga); a shared package that
depends on flutter_gemma would force an alignment neither app wants.

## Decision

`domovoi` (repo: **DomovoiDiscernment**) is pure Dart on the eloEngine
template. It carries its own key derivation and AEAD using the *same
primitive libraries* sanctuary uses (`package:cryptography`,
`package:bip39_mnemonic`) — primitives are never hand-rolled, and the
only cross-contract with sanctuary is standard BIP39 seed derivation
(PBKDF2-HMAC-SHA512, 2048 iterations, salt "mnemonic"), which is
spec-fixed, not implementation-fixed. The on-device inference adapter
(flutter_gemma) stays app-side, implementing domovoi's `Brain` interface;
each app keeps its own pin. Model catalogs are app data; domovoi ships
the laws (`ModelTrust`), not the list.

## Consequences

The whole package — including the entire stove protocol, client ↔
server ↔ fake upstream — tests in-process under plain `dart test`, with
no device, emulator, or network. The cost is a thin adapter per app
(each already had one) and a BIP39/HKDF implementation that must be
vector-locked in tests rather than shared as code.
