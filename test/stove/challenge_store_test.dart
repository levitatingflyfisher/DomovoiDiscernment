import 'dart:convert';

import 'package:domovoi/src/stove/challenge_store.dart';
import 'package:test/test.dart';

void main() {
  group('ChallengeStore', () {
    test('issues a base64 16-byte challenge', () {
      final store = ChallengeStore();
      final token = store.issue()!;
      expect(base64.decode(token).length, 16);
    });

    test('issued challenges are distinct', () {
      final store = ChallengeStore();
      expect(store.issue(), isNot(store.issue()));
    });

    test('consume is single-use', () {
      final store = ChallengeStore();
      final token = store.issue()!;
      expect(store.consume(token), isTrue);
      expect(store.consume(token), isFalse);
    });

    test('an unknown challenge is rejected', () {
      final store = ChallengeStore();
      store.issue();
      expect(store.consume(base64.encode(List.filled(16, 42))), isFalse);
      expect(store.consume('not base64 at all'), isFalse);
    });

    test('an expired challenge is rejected (fake clock)', () {
      var now = DateTime.utc(2026, 1, 1);
      final store = ChallengeStore(clock: () => now);
      final token = store.issue()!;
      now = now.add(const Duration(seconds: 61));
      expect(store.consume(token), isFalse);
    });

    test('a challenge within the 60s TTL is accepted (fake clock)', () {
      var now = DateTime.utc(2026, 1, 1);
      final store = ChallengeStore(clock: () => now);
      final token = store.issue()!;
      now = now.add(const Duration(seconds: 59));
      expect(store.consume(token), isTrue);
    });

    test('outstanding challenges are bounded', () {
      final store = ChallengeStore(maxOutstanding: 4);
      for (var i = 0; i < 10; i++) {
        store.issue();
      }
      expect(store.outstandingCount, lessThanOrEqualTo(4));
    });
  });
  // A keyless LAN flooder must not be able to evict a challenge an honest
  // client is already holding: that turns a memory bound into a replay-free
  // but useless stove. At the cap we stop issuing instead of dropping live
  // tokens — availability of NEW challenges degrades, in-flight asks survive.
  test('at capacity, issuing refuses instead of evicting a live challenge',
      () {
    final store = ChallengeStore(maxOutstanding: 3);
    final mine = store.issue()!;
    store.issue();
    store.issue();

    expect(store.issue(), isNull, reason: 'full store stops issuing');
    expect(store.consume(mine), isTrue,
        reason: 'the honest holder keeps its challenge');
  });

  test('expiry frees capacity again', () {
    var now = DateTime(2026);
    final store = ChallengeStore(
      maxOutstanding: 2,
      clock: () => now,
      ttl: const Duration(seconds: 60),
    );
    store.issue();
    store.issue();
    expect(store.issue(), isNull);

    now = now.add(const Duration(seconds: 61));
    expect(store.issue(), isNotNull);
  });

}
