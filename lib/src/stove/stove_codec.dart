import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Header carrying the single-use challenge token on `POST /stove/ask`.
///
/// Cleartext by design: the server must consume the challenge BEFORE opening
/// the frame, so the token travels beside the frame, and the AAD binding
/// (below) is what makes echoing it unforgeable.
const String kStoveChallengeHeader = 'x-stove-challenge';

/// Thrown when a stove frame cannot be sealed or opened: wrong key, tampered
/// bytes, an AAD mismatch (wrong endpoint or challenge), or a structurally
/// invalid frame. Callers must treat every case identically (fail closed).
class StoveCodecException implements Exception {
  /// Describes the failure for logs and tests — never sent over the wire.
  StoveCodecException(this.message, {this.cause});

  /// What failed, in one sentence.
  final String message;

  /// The underlying error, kept for diagnosis, never for the peer.
  final Object? cause;

  @override
  String toString() => 'StoveCodecException: $message';
}

/// Seals and opens the binary AEAD frames of the stove protocol.
///
/// Wire frame (`application/octet-stream`):
///
/// ```text
///   nonce(12) ‖ ciphertext(plaintext.length) ‖ mac(16)
/// ```
///
/// ChaCha20-Poly1305 (IETF) via the pure-Dart `cryptography` package —
/// nothing hand-rolled. The AAD is `domovoi-stove/v1|<endpoint>|<challenge>`:
/// protocol version, endpoint, and single-use challenge all bound, so a frame
/// can never replay across endpoints, versions, or asks — and the answer is
/// challenge-bound too, so it cannot be spliced onto another ask.
class StoveCodec {
  /// Creates a codec; [cipher] is injectable for tests only.
  StoveCodec({Chacha20? cipher}) : _cipher = cipher ?? Chacha20.poly1305Aead();

  /// Wire-protocol version, embedded in the AAD prefix below. Bump on any
  /// wire-format change so peers fail closed.
  static const int protocolVersion = 1;

  /// AAD namespace — binds every frame to this protocol and version.
  static const String _aadPrefix = 'domovoi-stove/v1';

  /// Endpoint tag for the request frame (`POST /stove/ask` body).
  static const String endpointAsk = 'ask';

  /// Endpoint tag for the response frame (the `/stove/ask` reply body).
  static const String endpointAnswer = 'answer';

  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// Fixed per-frame AEAD overhead: 12-byte nonce + 16-byte Poly1305 tag.
  static const int frameOverhead = _nonceLen + _macLen; // 28 bytes

  final Chacha20 _cipher;

  /// AAD bytes for a frame on [endpoint] bound to the base64 [challenge].
  static Uint8List additionalData(String endpoint, String challenge) =>
      Uint8List.fromList(utf8.encode('$_aadPrefix|$endpoint|$challenge'));

  /// Seals [plaintext] into a binary frame under the 32-byte [key], bound to
  /// [endpoint] and the single-use base64 [challenge].
  Future<Uint8List> seal(
    Uint8List plaintext,
    Uint8List key, {
    required String endpoint,
    required String challenge,
  }) async {
    _requireKeyLength(key);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      aad: additionalData(endpoint, challenge),
    );
    final out = Uint8List(box.nonce.length + box.cipherText.length + _macLen);
    out.setAll(0, box.nonce);
    out.setAll(box.nonce.length, box.cipherText);
    out.setAll(box.nonce.length + box.cipherText.length, box.mac.bytes);
    return out;
  }

  /// Opens a binary [frame] produced by [seal].
  ///
  /// Throws [StoveCodecException] on ANY failure — structurally invalid
  /// frame, wrong key, tampered bytes, or AAD mismatch (wrong endpoint or
  /// challenge). Never returns partial plaintext.
  Future<Uint8List> open(
    Uint8List frame,
    Uint8List key, {
    required String endpoint,
    required String challenge,
  }) async {
    _requireKeyLength(key);
    if (frame.length < frameOverhead) {
      throw StoveCodecException(
        'Frame too short: ${frame.length} bytes (minimum $frameOverhead).',
      );
    }
    final box = SecretBox(
      Uint8List.sublistView(frame, _nonceLen, frame.length - _macLen),
      nonce: Uint8List.sublistView(frame, 0, _nonceLen),
      mac: Mac(Uint8List.sublistView(frame, frame.length - _macLen)),
    );
    try {
      final plaintext = await _cipher.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: additionalData(endpoint, challenge),
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError catch (e) {
      throw StoveCodecException('Frame failed authentication.', cause: e);
    }
  }

  static void _requireKeyLength(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes; got ${key.length}');
    }
  }
}
