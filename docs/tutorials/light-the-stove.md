# Light the stove

Zero to a served household model in ten minutes. You need: a machine that
stays home (a desktop, a mini-PC, the computer upstairs), this repo checked
out on it, and a Dart SDK.

## 1. Install an upstream (2 minutes)

The stove does no inference itself — it proxies encrypted asks to a local
OpenAI-compatible server. Ollama is the easy one:

```sh
curl -fsSL https://ollama.com/install.sh | sh
```

(llamafile works too; anything serving `/v1/chat/completions` on this
machine does.)

## 2. Pull a model (depends on your connection)

Pick something the machine can hold. A desktop with 16 GB of RAM runs
models a phone never could:

```sh
ollama pull llama3.2        # small and quick, good first light
# or: ollama pull qwen2.5:14b, llama3.3:70b, ... — your hardware, your call
```

Check it answers locally:

```sh
curl -s http://127.0.0.1:11434/v1/models
```

## 3. Write the household phrase to a file (1 minute)

The phrase is the pairing — the same BIP39 phrase your household already
uses for its OpenHearth backups, or a fresh one. It goes in a file, never
on the command line (process lists leak):

```sh
printf '%s\n' 'your twelve word household phrase goes here ...' > ~/household
chmod 600 ~/household
```

The stove refuses to start unkeyed, and refuses a phrase whose BIP39
checksum does not validate — a typo fails loudly here, not silently at
first ask.

## 4. Light it

From the DomovoiDiscernment checkout:

```sh
dart pub get
dart run domovoi:stove --phrase-file ~/household --model llama3.2
```

You get one calm paragraph — what it serves, to whom (anyone holding the
household phrase), and what leaves the machine (nothing) — then:

```
listening on port 4663
```

4663 is HOME on a phone keypad.

## 5. Verify from another device (1 minute)

From your phone's browser or any machine on the same Wi-Fi:

```sh
curl -s http://<stove-host>:4663/stove/status
# {"domovoi":1,"protocol":1,"model":"llama3.2"}
```

Cleartext and secret-free by design — this endpoint only says a stove
lives here and what it serves. Everything else on the wire is an
encrypted frame.

## 6. Point an app at it

In Peckish or Reckon, choose the **stove** backend in the app's AI
settings, enter `<stove-host>:4663`, and confirm the household phrase.
Same phrase on both ends → same key → the ask completes; a mismatched
phrase gets a calm refusal, and nothing more. The full ceremony
(including rotation) is in
[how-to/pair-an-app.md](../how-to/pair-an-app.md).

That's it. Prompts now travel your own Wi-Fi as sealed frames, the model
runs on hardware you own, and the exact network story is written down in
[what-leaves-the-machine.md](../reference/what-leaves-the-machine.md).
