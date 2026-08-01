# Vision

## The one idea

**Households own more compute than a phone.** The fleet solved on-device AI
the hard way — pinned local models, trust-lawed downloads, BYOK for people
who want a frontier model — and hit the same wall in every app: the phone
strains to run a 1.5B model while the desktop upstairs could serve 70B, and
there is no privacy-preserving bridge between them. Every existing bridge
is a cloud account: relay services, vendor "home" hubs, remote-access
products that route a family's prompts through someone else's server to
reach hardware the family already owns. Domovoi is that bridge with the
cloud removed — the encrypted stove protocol pairs a phone to the household
machine with nothing but a shared phrase, and one `Brain` seam lets an app
treat phone, stove, and explicitly-keyed cloud as the same question asked
in three places.

The name is the contract: the domovoi serves the house that feeds him, and
he never leaves it.

## The laws

1. **Domovoi never routes.** Apps choose the backend; there is no fallback
   chain, no smart selection. Every degradation from a private tier to a
   less private one is a user decision, every time
   ([ADR-0004](docs/adr/0004-apps-choose-domovoi-never-routes.md)).
2. **Fail closed, no oracle.** Any stove-ask failure — bad challenge, bad
   frame, wrong key, upstream trouble — is the same constant-shaped
   `403 refused`. The server explains nothing to a stranger.
3. **The secret is the pairing.** Same household phrase on both ends →
   same key; nothing else can open or forge a frame. No accounts, no
   certificates, no discovery service
   ([ADR-0003](docs/adr/0003-the-secret-is-the-pairing.md)).
4. **Primitives are never hand-rolled.** BIP39, PBKDF2, HKDF, and
   ChaCha20-Poly1305 come from the same audited packages sanctuary uses;
   domovoi composes them and vector-locks the composition in tests.
5. **Trust laws reject by default.** A non-allowlisted org, a gated model,
   or a non-`.task` artifact never reaches a download URL.

## Honest scorecard

| Claim | Status |
|---|---|
| The package: Brain seam, ModelTrust, resumable downloads, keys, codec, client, server, CLI | **Shipped** — pure Dart, 70 tests |
| Stove protocol: client ↔ server ↔ upstream | **Shipped** — proven in-process (round-trip suite: shared phrase completes an ask, wrong secret refused, replay refused, status leaks nothing) |
| The shipped `stove` binary, over a real socket, refusing a wrong phrase | **Shipped** — the CLI served a real upstream on 2026-08-02: the right phrase got its answer, a valid-but-different BIP39 phrase got "The stove refused this ask" |
| A real local model answering through the protocol | **Shipped** — 2026-08-02, Ollama serving `qwen3:1.7b` on a 5.9 GiB-VRAM box: a Peckish-shaped meal-parsing prompt came back as JSON in **44 s cold, 8 s warm** (the 36 s difference is model load, not the wire). Worth knowing before an app promises a wait |
| Real phone → real desktop over Wi-Fi | **NOT yet run** — both halves are proven on one machine; the Wi-Fi hop is the remaining unknown |
| App adoption (Peckish `stove` backend, Reckon `stove` provider, both on the shared download engine) | **In flight** — same release as this package, separate repos |
| Streaming answers | **Not built** — `complete()` returns whole text; a non-goal until a household asks for it |
| Per-device revocation | **Not built, deliberately** — anyone with the phrase has the household's full trust; the household is the trust boundary, not the individual (ADR-0003) |
| mDNS / zero-conf discovery | **Deliberately not built** — host:port is typed once, like Peckish sync pairing; revisit only if typing an IP proves to be the actual friction |
