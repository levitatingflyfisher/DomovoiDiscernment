# ADR-0003: The secret is the pairing — household seed as identity

**Status:** Accepted (v0.1)

## Context

The stove needs to know who may ask, and phones need to know they are
talking to their own stove — mutual authentication with no accounts, no
certificate authority, no cloud rendezvous. The fleet already holds the
answer: sanctuary's household seed phrase is the family's identity, and
Peckish LAN sync proved the reduced form — "the secret IS the pairing:
every device that knows it derives the same frame key, and nothing else
can open (or forge) a single frame."

## Decision

The stove key is `HKDF-SHA256(secret, info='openhearth.domovoi.stove.v1')`.
The secret is the household's BIP39 seed: apps obtain it from their
sanctuary spine (or a stored household secret they already hold); the
desktop derives it by reading the same phrase from a file
(`--phrase-file` — never argv, which process lists leak). Same phrase on
both ends → same key → the channel authenticates both directions by
construction. The distinct HKDF info string cryptographically isolates
the stove key from every sanctuary purpose sharing the same seed, so
lending the seed to the stove lends *nothing else*.

## Consequences

Pairing UX is "type the household phrase once at the stove" — the same
ceremony families already perform for backup. Rotating the household
phrase rotates the stove key with it. The deliberate limitation: anyone
with the phrase has the household's full trust — there is no per-device
revocation in v1, which matches the fleet's threat model (the household
is the trust boundary, not the individual).
