/// Domovoi — Discernment: family cognition for family matters.
///
/// A model-agnostic control plane for household AI. Apps ask through one
/// seam ([Brain]); the house answers — on the device, on the household
/// stove (a home server reached over the encrypted stove protocol), or at
/// a cloud the user explicitly keyed. Domovoi governs where the thinking
/// runs, never what is thought.
///
/// Public API:
///   - [Brain] / [AskException] — the one seam apps implement or consume
///   - [ModelSpec] / [ModelTrust] — model catalog entry + the trust laws
///   - [resumableDownload] / [TransferOutcome] — cancel-aware,
///     resume-from-byte download engine, and how a run ended
///   - [resumableDownloadStream] — the same engine as progress events
///   - [DomovoiKeys] — BIP39 seed + HKDF stove-key derivation
///   - [StoveCodec] — AEAD frame codec for the stove protocol
///   - [StoveClient] — a [Brain] that asks the household stove
///   - [StoveServer] — the home-server side (see also `bin/stove.dart`)
///   - [ChallengeStore] — single-use TTL replay protection
library;

export 'src/brain.dart';
export 'src/model/model_spec.dart';
export 'src/model/model_trust.dart';
export 'src/transfer/resumable_transfer.dart';
export 'src/keys.dart';
export 'src/stove/stove_codec.dart';
export 'src/stove/stove_client.dart';
export 'src/stove/stove_server.dart';
export 'src/stove/challenge_store.dart';
