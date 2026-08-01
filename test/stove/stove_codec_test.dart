import 'dart:convert';
import 'dart:typed_data';

import 'package:domovoi/src/stove/stove_codec.dart';
import 'package:test/test.dart';

void main() {
  final codec = StoveCodec();
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final otherKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  final challenge = base64.encode(List.filled(16, 7));
  final otherChallenge = base64.encode(List.filled(16, 8));
  final plaintext = Uint8List.fromList(utf8.encode('{"prompt":"hello"}'));

  group('StoveCodec', () {
    test('seal/open round-trips for the same endpoint and challenge',
        () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      expect(frame.length, plaintext.length + StoveCodec.frameOverhead);
      final opened = await codec.open(
        frame,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      expect(utf8.decode(opened), '{"prompt":"hello"}');
    });

    test('a tampered byte fails to open', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      // Flip one ciphertext byte (past the nonce).
      frame[12] ^= 0x01;
      await expectLater(
        codec.open(
          frame,
          key,
          endpoint: StoveCodec.endpointAsk,
          challenge: challenge,
        ),
        throwsA(isA<StoveCodecException>()),
      );
    });

    test("a frame sealed for 'ask' does not open as 'answer'", () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      await expectLater(
        codec.open(
          frame,
          key,
          endpoint: StoveCodec.endpointAnswer,
          challenge: challenge,
        ),
        throwsA(isA<StoveCodecException>()),
      );
    });

    test('a different challenge fails to open', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      await expectLater(
        codec.open(
          frame,
          key,
          endpoint: StoveCodec.endpointAsk,
          challenge: otherChallenge,
        ),
        throwsA(isA<StoveCodecException>()),
      );
    });

    test('the wrong key fails to open', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );
      await expectLater(
        codec.open(
          frame,
          otherKey,
          endpoint: StoveCodec.endpointAsk,
          challenge: challenge,
        ),
        throwsA(isA<StoveCodecException>()),
      );
    });

    test('a frame too short to hold nonce + mac fails structurally', () async {
      await expectLater(
        codec.open(
          Uint8List(StoveCodec.frameOverhead - 1),
          key,
          endpoint: StoveCodec.endpointAsk,
          challenge: challenge,
        ),
        throwsA(isA<StoveCodecException>()),
      );
    });
  });
}
