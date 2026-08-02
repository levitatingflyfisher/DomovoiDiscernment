import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Tracks the single-use replay challenges the stove issues on
/// `GET /stove/challenge` and consumes on `POST /stove/ask`.
///
/// An ask must echo a challenge the server issued and has not yet seen; the
/// challenge is bound into the frame AAD (see `StoveCodec`), so a replayed
/// frame carries an already-consumed challenge and is rejected before any
/// upstream work — genuine wire-replay protection.
///
/// Pure Dart, injectable clock and randomness for tests.
class ChallengeStore {
  /// Creates a store; production uses the defaults, tests inject [clock]
  /// (and optionally [random]).
  ChallengeStore({
    this.ttl = const Duration(seconds: 60),
    this.maxOutstanding = 256,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  /// How long an issued challenge stays valid before it is discarded.
  final Duration ttl;

  /// Upper bound on outstanding challenges — a flood of `/stove/challenge`
  /// probes cannot grow this map without bound.
  final int maxOutstanding;

  final Random _random;
  final DateTime Function() _clock;
  final Map<String, DateTime> _issued = {};

  /// Issues a fresh 16-byte challenge, records it, and returns it
  /// base64-encoded (the token the client binds into its ask frame's AAD).
  ///
  /// Returns null when [maxOutstanding] live challenges are already
  /// outstanding. Refusing is deliberate: evicting to make room would let a
  /// keyless flooder drop the challenge an honest client is holding between
  /// its fetch and its ask. New challenges pause; in-flight asks survive;
  /// expiry frees the room back.
  String? issue() {
    _evictExpired();
    if (_issued.length >= maxOutstanding) return null;
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    final token = base64.encode(bytes);
    _issued[token] = _clock();
    return token;
  }

  /// Consumes [token] if it is outstanding and unexpired.
  ///
  /// Returns false on an unknown, expired, or already-used token — the
  /// fail-closed / single-use paths. A consumed token can never be consumed
  /// again (the replay defence).
  bool consume(String token) {
    _evictExpired();
    final issuedAt = _issued.remove(token);
    if (issuedAt == null) return false; // unknown or already used
    return _clock().difference(issuedAt) <= ttl;
  }

  /// Number of currently-outstanding (unexpired) challenges — for tests.
  int get outstandingCount {
    _evictExpired();
    return _issued.length;
  }

  void _evictExpired() {
    final now = _clock();
    _issued.removeWhere((_, issuedAt) => now.difference(issuedAt) > ttl);
  }
}
