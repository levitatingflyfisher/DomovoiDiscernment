# ADR-0004: Apps choose; domovoi never routes

**Status:** Accepted (v0.1)

## Context

A control plane invites policy: "try the phone, fall back to the stove,
fall back to the cloud." Every step of such a chain moves data somewhere
the user didn't explicitly send it — a silent fallback from on-device to
network is exactly the kind of decision the fleet refuses to make on the
user's behalf (the privacy screens promise "network only when you act").

## Decision

Domovoi ships mechanisms, not policy. `Brain` is one seam; each
implementation is explicit about where it runs; the app's own settings
surface is where a household picks the backend, exactly as both apps do
today for BYOK. There is no fallback chain, no "smart" routing, no
telemetry-informed selection — not as v1 scoping, but as a law: a
degradation from a private tier to a less private one is a user
decision, every time.

## Consequences

Apps keep a small amount of selection UI they might otherwise delete.
In exchange, "what leaves your device" screens stay statically true —
the answer never depends on runtime conditions. If a future version
wants convenience chaining (phone→stove within the same privacy class),
it gets its own ADR and an explicit opt-in.
