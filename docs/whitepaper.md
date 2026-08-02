# DomovoiDiscernment — White Paper

*Family cognition for family matters: a control plane that lets household
apps use household compute, with no account in between.*

**Status:** strategic overview. For the laws and the honest scorecard see
[VISION.md](../VISION.md); for the wire mechanics,
[reference/stove-protocol.md](reference/stove-protocol.md); for the formal
spec, the [yellow paper](spec/yellow-paper.md). This document is candid
about what is built and what is not — see §6.

---

## Abstract

Local-first apps solved on-device AI: pinned small models, trust-lawed
downloads, opt-in BYOK. But the device in your pocket is the *weakest*
computer the household owns. The desktop upstairs can serve models fifty
times larger, and today the only ways a phone reaches it are a cloud
account or a plaintext LAN endpoint. Domovoi is the missing bridge: a
pure-Dart control plane with one `Brain` seam for apps, model trust laws,
a hardened download engine, and the *stove protocol* — encrypted asks to a
home server, keyed by nothing more than the household's shared phrase. The
governing constraint is in the name: the domovoi serves the house that
feeds him, and he never leaves it.

## 1. The gap

A family running local-first apps hits the same ceiling in every one of
them. The phone strains under a 1.5B-parameter model — thermals, memory,
battery — while a 70B-capable machine sits idle on the same Wi-Fi. Between
those two facts there is, today, no privacy-preserving bridge:

- **Cloud assistants** bridge it by replacing it: your prompt goes to a
  data center, under an account, with retention governed by policy rather
  than architecture.
- **Remote-access and relay products** reach your own hardware *through
  someone else's server* — an account and a middleman to use a machine you
  already own.
- **Bare Ollama-on-LAN** — the enthusiast answer both consuming apps
  already support as "OpenAI-compatible endpoint" — sends family prompts
  in cleartext HTTP that anyone on the Wi-Fi can read, and answers to
  anyone who can reach the port. No pairing story at all.

The household's most private questions deserve the household's strongest
computer, and no product on this list can deliver both halves at once.

## 2. The idea

A **control plane**, deliberately minimal. Domovoi standardizes three
things and refuses to do more:

1. **The seam.** `Brain.complete(prompt) → answer` is the one interface
   between an app's features and whatever thinks. On-device adapter,
   stove client, and BYOK client are interchangeable behind it.
2. **The acquisition laws.** Model catalogs stay app data; domovoi ships
   the validator (`ModelTrust`: https + allowlisted org + ungated +
   `.task`) and the download engine whose completion is an atomic rename,
   never a size guess.
3. **The stove protocol.** A home server that proxies encrypted asks to a
   local OpenAI-compatible upstream. ChaCha20-Poly1305 frames, a key
   HKDF-derived from the household phrase, single-use challenges, and one
   constant-shaped refusal for every failure.

The pairing is the radical simplification: *the secret is the pairing.*
Same phrase on both ends → same key. No accounts, no certificate
authority, no discovery service, no rendezvous server — nothing to
operate, and therefore nothing to trust.

## 3. Positioning

**Versus cloud assistants.** The comparison is structural, not
performative. A cloud assistant requires an account and holds your prompts
under a retention policy; domovoi has no server-side anything. The privacy
claim is not "we promise not to look" but "there is nowhere to look."
The trade is real too: a data center will beat a desktop on raw model
size. Domovoi's bet is that a 70B model on hardware you own covers family
matters, and that apps keep BYOK for the rest — explicitly, per the user's
own key.

**Versus bare Ollama on the LAN.** Domovoi *uses* Ollama; the difference
is the floor under it. Plaintext becomes sealed frames; an open port
becomes possession-based membership; "anyone on the Wi-Fi" becomes "anyone
holding the household phrase." StillLife's LAN sync learned this lesson
once (started plaintext, went encrypted fail-closed); household inference
starts at the encrypted floor.

**Versus home-assistant ecosystems.** Hub platforms are hub-centric: the
hub owns the devices, the automations, and the interaction model, and
apps integrate *into* it. Domovoi is app-centric: Peckish and Reckon stay
whole applications with their own features and privacy screens, and the
stove is just a place their asks may run. There is no domovoi app, no
dashboard, no ecosystem to join — a library and a 120-line CLI.

## 4. The household as trust boundary

Consumer security models default to the individual: per-user accounts,
per-device certificates, revocation lists. The fleet's position, carried
into domovoi, is that inside a home these are the wrong primitives. The
household already has a shared secret culture (the backup phrase on paper
in a drawer), already shares physical access to the machines, and already
operates on mutual trust. So the stove trusts *the household*: one phrase,
one key, full membership for whoever holds it, and rotation — not
revocation — when membership changes. That is a smaller, more honest
security claim than per-device PKI, and it is the one a family can
actually operate. The deliberate costs are named in the
[yellow paper](spec/yellow-paper.md) §7: no per-device revocation, no
forward secrecy against a future phrase compromise. The threat model is
the stranger on the Wi-Fi, not the spouse.

## 5. Why a control plane — not a harness, not an agent

A harness runs a loop: it plans, invokes tools, retries, escalates. An
agent decides: it chooses actions on your behalf. Domovoi is neither, as a
matter of law rather than scope. It runs no loop and holds no policy —
there is no fallback chain, no "try the phone, quietly fall back to the
stove," no telemetry-informed routing
([ADR-0004](adr/0004-apps-choose-domovoi-never-routes.md)). Every
placement of a prompt is an app-surfaced, user-made decision, which is
what keeps every app's "what leaves your device" screen *statically* true:
the answer never depends on runtime conditions. The moment a control plane
starts routing, it starts deciding where private data goes; domovoi's
refusal to route is its core privacy feature, not a missing one.

## 6. Honest status

The package is real: 70 tests, pure Dart, and the entire protocol —
client ↔ server ↔ a stand-in upstream — proves itself in-process under
plain `dart test` — no device, no emulator, no network — including replay
refusal, wrong-key refusal, and the fail-closed shape of every
rejection. It has also
answered for real: the shipped binary in front of Ollama serving
`qwen3:1.7b` parsed a meal into JSON in 44 s cold and 8 s warm. What has
*not* happened yet: a real phone asking across a real kitchen's Wi-Fi,
and the two consuming apps' adoption lands in this same release rather
than being shipped history. Streaming, per-device revocation, and mDNS discovery are not
built — the first by scope, the second by conviction, the third until
typing an IP once proves to be actual friction. The full scorecard is in
[VISION.md](../VISION.md).
