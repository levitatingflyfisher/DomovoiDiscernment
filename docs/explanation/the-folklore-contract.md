# The folklore contract — why a domovoi

Every AI product ships a mascot. This one ships a job description.

## The domovoi

In Slavic folklore the domovoi is the household spirit: a small, gruff,
whiskered presence who lives behind the stove. He is not summoned and not
subscribed to; he simply belongs to the house. Feed him — a bowl of kasha,
a little respect — and he keeps the fires banked, warns of trouble, and
watches over the family's affairs as one of the family. Two properties
define him, and both are load-bearing here:

1. **He serves the house that feeds him.** His loyalty runs to the
   household — not to a village, a lord, or any distant authority.
2. **He never leaves the house.** A domovoi is *of* the dwelling. When
   folklore describes a family moving, the ritual is coaxing him along in
   an ember scuttle from the old stove — even relocation is framed as
   carrying the hearth, because outside the house he has no existence.

That is the contract this package enforces in code rather than in a
privacy policy: cognition that belongs to the dwelling, is fed by the
household's own hardware, and has no self that exists outside the walls.

## The anti-mascot: Zao Jun

Chinese folklore supplies the perfect counterexample. Zao Jun, the Kitchen
God, also lives at the family hearth and also watches the household all
year. But once a year he travels to heaven and **files a report** on the
family's conduct, on which their fortunes are adjusted; families famously
smear his lips with honey before the journey so he'll say sweet things.

That is the telemetry model, a few millennia early: a resident presence
whose observations are collected locally and remitted to a remote
authority for judgment, with the household reduced to hoping the report is
kind. Every cloud assistant is a Zao Jun — it sits in your kitchen and
answers warmly, but its loyalty terminates elsewhere, and what it heard
travels up. The honey-smearing has modern equivalents too: settings pages
that ask retention to be gentle rather than architecture that makes
reporting impossible.

The domovoi is the deliberate opposite. There is no heaven to report to.
The architecture has no channel on which a report could travel — nothing
to disable, because there is nothing to enable.

## How the folklore maps to the architecture

| Folklore | Architecture |
|---|---|
| Lives behind the stove | The home server *is* the stove; the protocol is named for the dwelling place, port 4663 = HOME |
| Serves the house that feeds him | Inference runs on the household's own hardware; the upstream is loopback |
| Never leaves the house | Nothing crosses the LAN boundary; no cloud rendezvous, no relay, no account ([what-leaves-the-machine](../reference/what-leaves-the-machine.md)) |
| Knows the household, not individuals | One household phrase is the whole identity; the household is the trust boundary — no per-member accounts, no per-device certificates ([ADR-0003](../adr/0003-the-secret-is-the-pairing.md)) |
| Gruff with strangers | Fail closed, no oracle: a stranger's ask gets the same flat `403 refused` as a forgery, with no explanation |
| Does not run the household | Domovoi never routes and never decides — apps choose where thinking runs; every privacy trade is the family's explicit call ([ADR-0004](../adr/0004-apps-choose-domovoi-never-routes.md)) |
| Moves only as a carried ember | Re-keying is a household ceremony: the phrase moves by hand, never over a wire |

## Discernment

The repo's full name adds the second word: *DomovoiDiscernment*. The
discernment is the family's, not the model's — deciding which matters are
family matters, which tier of the house may hear them, and when a question
is worth sending beyond the walls at all. Domovoi supplies the walls, the
sealed frames, and the honest map. The judgment stays where it belongs.
