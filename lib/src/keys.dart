import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:cryptography/cryptography.dart';

/// Key derivation for the stove protocol.
///
/// Provisioning law: the secret IS the pairing. The same household phrase on
/// both ends yields the same key; nothing else can open or forge a frame.
/// No key ever crosses the wire.
///
/// Both steps route through audited primitive libraries (`bip39_mnemonic`,
/// `cryptography`) — nothing is hand-rolled here.
abstract final class DomovoiKeys {
  /// HKDF `info` label for the stove frame key. A distinct domain keeps this
  /// key cryptographically isolated from every sanctuary purpose sharing the
  /// same seed. FROZEN — changing it strands every paired household.
  static const String stoveKeyDomain = 'openhearth.domovoi.stove.v1';

  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Derives the 512-bit BIP39 seed from a household [phrase].
  ///
  /// Standard BIP39 (PBKDF2-HMAC-SHA512, 2048 iterations, salt "mnemonic",
  /// empty passphrase) — byte-identical to sanctuary's `OpenHearthMnemonic`,
  /// so the stove CLI and the apps agree on the seed without sharing code.
  ///
  /// Throws (a `bip39_mnemonic` exception) on an invalid phrase — a bad
  /// checksum must fail loudly at provisioning, never silently mis-key.
  static Future<Uint8List> seedFromPhrase(String phrase) async {
    final mnemonic = Mnemonic.fromSentence(phrase, Language.english);
    return Uint8List.fromList(mnemonic.seed);
  }

  /// Derives the 32-byte stove frame key from [secret] (normally the BIP39
  /// seed) via HKDF-SHA256 with info [stoveKeyDomain] and no salt — the
  /// entropy is already concentrated in the seed.
  ///
  /// Throws [ArgumentError] if [secret] is empty.
  static Future<Uint8List> stoveKey(List<int> secret) async {
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be empty');
    }
    // Defensive copy: `cryptography` retains the reference, so callers may
    // zeroize their copy after this returns.
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(Uint8List.fromList(secret)),
      nonce: const <int>[],
      info: utf8.encode(stoveKeyDomain),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }
}
