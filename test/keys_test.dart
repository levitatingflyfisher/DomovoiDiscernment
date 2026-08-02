import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:domovoi/src/keys.dart';
import 'package:test/test.dart';

// The standard 12-word test mnemonic (valid checksum). Public knowledge —
// never a real household phrase.
const _phrase =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

const _otherPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

// Law: seedFromPhrase is standard BIP39 with an empty passphrase
// (PBKDF2-HMAC-SHA512, 2048 iters, salt "mnemonic", 512-bit output).
// This golden is the published empty-passphrase vector for the phrase above;
// any drift in derivation breaks it.
const _goldenSeedHex =
    '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1'
    '9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('DomovoiKeys.seedFromPhrase', () {
    test('derives the pinned golden seed for a fixed valid phrase', () async {
      final seed = await DomovoiKeys.seedFromPhrase(_phrase);
      expect(seed.length, 64);
      expect(_hex(seed), _goldenSeedHex);
    });

    test('is deterministic', () async {
      final a = await DomovoiKeys.seedFromPhrase(_phrase);
      final b = await DomovoiKeys.seedFromPhrase(_phrase);
      expect(_hex(a), _hex(b));
    });

    test('rejects an invalid phrase', () async {
      await expectLater(
        DomovoiKeys.seedFromPhrase('not a bip39 phrase at all'),
        throwsA(anything),
      );
    });
  });

  group('DomovoiKeys.stoveKey', () {
    test('outputs 32 bytes and is deterministic', () async {
      final seed = await DomovoiKeys.seedFromPhrase(_phrase);
      final a = await DomovoiKeys.stoveKey(seed);
      final b = await DomovoiKeys.stoveKey(seed);
      expect(a.length, 32);
      expect(_hex(a), _hex(b));
    });

    test('different phrase yields a different key', () async {
      final keyA = await DomovoiKeys.stoveKey(
        await DomovoiKeys.seedFromPhrase(_phrase),
      );
      final keyB = await DomovoiKeys.stoveKey(
        await DomovoiKeys.seedFromPhrase(_otherPhrase),
      );
      expect(_hex(keyA), isNot(_hex(keyB)));
    });

    test('is domain-separated: any other HKDF info yields a different key',
        () async {
      final seed = await DomovoiKeys.seedFromPhrase(_phrase);
      final stove = await DomovoiKeys.stoveKey(seed);

      Future<Uint8List> hkdfWithInfo(String info) async {
        final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
            .deriveKey(
          secretKey: SecretKey(Uint8List.fromList(seed)),
          nonce: const <int>[],
          info: utf8.encode(info),
        );
        return Uint8List.fromList(await derived.extractBytes());
      }

      // The stove domain reproduces the key; any other info string cannot.
      expect(
        _hex(await hkdfWithInfo('openhearth.domovoi.stove.v1')),
        _hex(stove),
      );
      for (final other in [
        'openhearth.domovoi.stove.v2',
        'openhearth.encryption.v1',
        'openhearth.peckish.sync.encryption.v1',
        '',
      ]) {
        expect(_hex(await hkdfWithInfo(other)), isNot(_hex(stove)),
            reason: 'info "$other" must not reproduce the stove key');
      }
    });

    test('rejects an empty secret', () async {
      await expectLater(
        DomovoiKeys.stoveKey(const <int>[]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
