# What leaves the machine

The honest network map — the same contract the fleet's apps put behind
"What leaves your device," written down for the stove and for the apps
that ask it.

## The stove (the desktop running `dart run domovoi:stove`)

**Nothing leaves the LAN.** The stove makes exactly one kind of outbound
connection: to its upstream, which defaults to loopback
(`http://127.0.0.1:11434/v1` — Ollama on the same machine). Prompts go
OS-internal to the model and never touch a network interface. There is no
telemetry, no update check, no phone-home, no logging of prompt content.

If you point `--upstream` somewhere other than loopback, prompts go there
in cleartext HTTP — that is your explicit choice, and the tool will not
make it for you. The shipped default keeps inference on the machine.

**What a device on your Wi-Fi can observe:**

| Traffic | Visible to the LAN? | Contains |
|---|---|---|
| `GET /stove/status` | Yes, cleartext | `{domovoi, protocol, model}` — that a stove exists and the model's name. No secret-derived bytes (test-bound: `test/stove/stove_roundtrip_test.dart`, "the status endpoint reveals no key-derived bytes") |
| `GET /stove/challenge` | Yes, cleartext | 16 random bytes, base64. Worthless without the key |
| `POST /stove/ask` + reply | Frames only | Ciphertext, sizes, and timing. Never a prompt, an answer, or any key material |

So a passive observer learns: a stove is lit, which model it serves, when
asks happen, and roughly how big they are. It never learns what was asked
or answered. Traffic analysis (sizes and timing) is the residual — named
here rather than papered over.

**What an active attacker gets:** the constant `403 refused`. Forged
frames, replayed frames, and wrong-key frames are indistinguishable
failures, refused before any inference runs.

## The client apps (Peckish, Reckon)

For a stove ask, an app sends exactly two requests, both to the
`host:port` the household typed in — never to a third party:

1. `GET /stove/challenge` (cleartext, contentless).
2. `POST /stove/ask` (a sealed frame; the prompt is inside the
   ciphertext).

The household phrase and every derived key stay on the device. There is no
account, no token, and no domovoi-operated server anywhere — there is
nothing for this package to send telemetry *to*.

The one other network path in this package is `resumableDownload`, which
apps use for model acquisition. It contacts only the URL the app's catalog
names, and `ModelTrust` refuses any catalog entry that is not an https
URL on `huggingface.co` under an allowlisted org, ungated. Downloads run
only when the user acts — the fleet's standing rule.

## Summary

- Prompts and answers: device ↔ stove, sealed; stove ↔ model, loopback.
- The Internet: involved only for a user-initiated model download, from an
  allowlisted host.
- Accounts, telemetry, rendezvous servers: none exist in the design, so
  none can leak.
