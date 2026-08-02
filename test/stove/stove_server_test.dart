import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domovoi/src/keys.dart';
import 'package:domovoi/src/stove/challenge_store.dart';
import 'package:domovoi/src/stove/stove_codec.dart';
import 'package:domovoi/src/stove/stove_server.dart';
import 'package:test/test.dart';

/// In-process OpenAI-compat upstream. Records the last request body so tests
/// can assert what the stove sends; never leaves 127.0.0.1.
class FakeUpstream {
  HttpServer? _server;
  Map<String, dynamic>? lastRequestBody;
  String? lastPath;
  int statusCode = 200;
  String answerText = 'the stove answers';

  Uri get uri => Uri.parse('http://127.0.0.1:${_server!.port}/v1');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      lastPath = req.uri.path;
      lastRequestBody =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      req.response.statusCode = statusCode;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': answerText},
          },
        ],
      }));
      await req.response.close();
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  _failClosedRegression();
  final key = Uint8List.fromList(List.generate(32, (i) => i * 3 % 256));
  final wrongKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final codec = StoveCodec();

  late FakeUpstream upstream;
  late StoveServer server;
  late HttpClient http;

  Uri stoveUri(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<(int, String)> get(String path) async {
    final req = await http.getUrl(stoveUri(path));
    final res = await req.close();
    return (res.statusCode, await utf8.decodeStream(res));
  }

  Future<(int, Uint8List)> postAsk(List<int> body, {String? challenge}) async {
    final req = await http.postUrl(stoveUri('/stove/ask'));
    req.headers.contentType = ContentType.binary;
    if (challenge != null) {
      req.headers.set(kStoveChallengeHeader, challenge);
    }
    req.add(body);
    final res = await req.close();
    final bytes = BytesBuilder(copy: false);
    await res.forEach(bytes.add);
    return (res.statusCode, bytes.takeBytes());
  }

  Future<String> freshChallenge() async {
    final (status, body) = await get('/stove/challenge');
    expect(status, 200);
    return (jsonDecode(body) as Map<String, dynamic>)['challenge'] as String;
  }

  Future<Uint8List> sealAsk(
    String challenge, {
    Uint8List? underKey,
    String prompt = 'hello',
    int? maxTokens,
  }) =>
      codec.seal(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'prompt': prompt,
          if (maxTokens != null) 'maxTokens': maxTokens,
        }))),
        underKey ?? key,
        endpoint: StoveCodec.endpointAsk,
        challenge: challenge,
      );

  setUp(() async {
    upstream = FakeUpstream();
    await upstream.start();
    server = StoveServer(0, key, upstream.uri, 'test-model');
    await server.start();
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await server.stop();
    await upstream.stop();
  });

  group('GET /stove/status', () {
    test('returns cleartext {domovoi, protocol, model}', () async {
      final (status, body) = await get('/stove/status');
      expect(status, 200);
      expect(jsonDecode(body), {
        'domovoi': 1,
        'protocol': 1,
        'model': 'test-model',
      });
    });
  });

  group('GET /stove/challenge', () {
    test('returns a base64 16-byte single-use challenge with its TTL',
        () async {
      final (status, body) = await get('/stove/challenge');
      expect(status, 200);
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(base64.decode(json['challenge'] as String).length, 16);
      expect(json['ttlSeconds'], 60);
    });
  });

  group('POST /stove/ask', () {
    test('proxies the prompt upstream and returns a sealed answer', () async {
      final challenge = await freshChallenge();
      final (status, body) = await postAsk(
        await sealAsk(challenge, prompt: 'what simmers?'),
        challenge: challenge,
      );
      expect(status, 200);

      expect(upstream.lastPath, '/v1/chat/completions');
      expect(upstream.lastRequestBody, {
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'what simmers?'},
        ],
      });

      final opened = await codec.open(
        body,
        key,
        endpoint: StoveCodec.endpointAnswer,
        challenge: challenge,
      );
      expect(jsonDecode(utf8.decode(opened)), {'text': 'the stove answers'});
    });

    test('passes maxTokens through as max_tokens when present', () async {
      final challenge = await freshChallenge();
      final (status, _) = await postAsk(
        await sealAsk(challenge, maxTokens: 128),
        challenge: challenge,
      );
      expect(status, 200);
      expect(upstream.lastRequestBody!['max_tokens'], 128);
    });

    test('refuses identically on missing challenge, unknown challenge, '
        'garbage frame, and wrong key (no oracle)', () async {
      final results = <(int, String)>[];

      // Missing challenge header.
      var r = await postAsk(await sealAsk(await freshChallenge()));
      results.add((r.$1, utf8.decode(r.$2)));

      // Unknown (never-issued) challenge.
      final bogus = base64.encode(List.filled(16, 9));
      r = await postAsk(await sealAsk(bogus), challenge: bogus);
      results.add((r.$1, utf8.decode(r.$2)));

      // Valid challenge, garbage frame.
      r = await postAsk([1, 2, 3], challenge: await freshChallenge());
      results.add((r.$1, utf8.decode(r.$2)));

      // Valid challenge, frame sealed under the wrong key.
      final challenge = await freshChallenge();
      r = await postAsk(
        await sealAsk(challenge, underKey: wrongKey),
        challenge: challenge,
      );
      results.add((r.$1, utf8.decode(r.$2)));

      for (final (status, body) in results) {
        expect(status, 403);
        expect(body, 'refused');
      }
      // No upstream work happened for any refusal.
      expect(upstream.lastRequestBody, isNull);
    });

    test('consumes the challenge before verification: a failed ask burns it',
        () async {
      final challenge = await freshChallenge();
      await postAsk([1, 2, 3], challenge: challenge);
      // The same challenge with a well-formed frame is now refused.
      final (status, body) = await postAsk(
        await sealAsk(challenge),
        challenge: challenge,
      );
      expect(status, 403);
      expect(utf8.decode(body), 'refused');
    });

    test('a replayed ask frame is refused', () async {
      final challenge = await freshChallenge();
      final frame = await sealAsk(challenge);
      final (first, _) = await postAsk(frame, challenge: challenge);
      expect(first, 200);
      final (replay, body) = await postAsk(frame, challenge: challenge);
      expect(replay, 403);
      expect(utf8.decode(body), 'refused');
    });

    test('an upstream failure is refused, not echoed', () async {
      upstream.statusCode = 500;
      final challenge = await freshChallenge();
      final (status, body) = await postAsk(
        await sealAsk(challenge),
        challenge: challenge,
      );
      expect(status, 403);
      expect(utf8.decode(body), 'refused');
    });
  });

  test('unknown routes are 404', () async {
    final (status, _) = await get('/stove/secrets');
    expect(status, 404);
  });

  test('an injected ChallengeStore is honored', () async {
    await server.stop();
    var now = DateTime.utc(2026, 1, 1);
    final store = ChallengeStore(clock: () => now);
    server = StoveServer(0, key, upstream.uri, 'test-model', challenges: store);
    await server.start();

    final challenge = await freshChallenge();
    now = now.add(const Duration(seconds: 61));
    final (status, body) = await postAsk(
      await sealAsk(challenge),
      challenge: challenge,
    );
    expect(status, 403);
    expect(utf8.decode(body), 'refused');
  });
}

// Law 1 (fail closed, constant shape) must hold for EVERY path into the
// handler, including the ones that throw before any check runs. A response
// that leaves statusCode at its 200 default is a fail-OPEN oracle: an
// unkeyed peer can tell "you crashed" from "refused".
void _failClosedRegression() {
  group('fail-closed under malformed requests', () {
    late StoveServer server;
    late Uint8List key;

    setUp(() async {
      key = await DomovoiKeys.stoveKey(utf8.encode('a-household-secret'));
      server = StoveServer(0, key, Uri.parse('http://127.0.0.1:1/v1'), 'm');
      await server.start();
    });
    tearDown(() => server.stop());

    // A raw socket, not HttpClient: the client folds repeated headers into
    // one comma-joined value, which is exactly what hides this bug.
    Future<String> rawStatusLine(List<String> challengeHeaders) async {
      final socket = await Socket.connect('127.0.0.1', server.port);
      final headers = [
        'POST /stove/ask HTTP/1.1',
        'Host: 127.0.0.1:${server.port}',
        for (final h in challengeHeaders) '$kStoveChallengeHeader: $h',
        'Content-Length: 3',
        'Connection: close',
        '',
        '',
      ].join('\r\n');
      socket.write(headers);
      socket.add(const [1, 2, 3]);
      await socket.flush();
      final bytes = await socket.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      final response = utf8.decode(bytes, allowMalformed: true);
      socket.destroy();
      return response.split('\r\n').first;
    }

    test('a duplicated challenge header refuses, never 200', () async {
      expect(await rawStatusLine(['aaaa', 'bbbb']), contains('403'));
    });

    test('a missing challenge header refuses', () async {
      expect(await rawStatusLine(const []), contains('403'));
    });
  });
    test('a saturated challenge store answers 503, never an empty challenge',
        () async {
      final full = StoveServer(
        0,
        Uint8List.fromList(List.generate(32, (i) => i * 3 % 256)),
        Uri.parse('http://127.0.0.1:1/v1'),
        'm',
        challenges: ChallengeStore(maxOutstanding: 1),
      );
      await full.start();
      addTearDown(full.stop);

      final client = HttpClient();
      addTearDown(client.close);
      Future<int> fetch() async {
        final req = await client.get('127.0.0.1', full.port, '/stove/challenge');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      expect(await fetch(), HttpStatus.ok);
      expect(await fetch(), HttpStatus.serviceUnavailable);
    });

    test('a trickled body is cut off, not held open forever', () async {
      final slow = StoveServer(
        0,
        Uint8List.fromList(List.generate(32, (i) => i * 3 % 256)),
        Uri.parse('http://127.0.0.1:1/v1'),
        'm',
        bodyTimeout: const Duration(milliseconds: 200),
      );
      await slow.start();
      addTearDown(slow.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final chReq =
          await client.get('127.0.0.1', slow.port, '/stove/challenge');
      final chRes = await chReq.close();
      final challenge = (jsonDecode(await utf8.decodeStream(chRes))
          as Map<String, dynamic>)['challenge'] as String;

      final socket = await Socket.connect('127.0.0.1', slow.port);
      addTearDown(socket.destroy);
      socket.write([
        'POST /stove/ask HTTP/1.1',
        'Host: 127.0.0.1:${slow.port}',
        '$kStoveChallengeHeader: $challenge',
        'Content-Length: 100',
        '',
        '',
      ].join('\r\n'));
      socket.add(const [1, 2, 3]); // ...and then never the rest.
      await socket.flush();

      final bytes = await socket
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
          .timeout(const Duration(seconds: 5));
      expect(utf8.decode(bytes, allowMalformed: true), contains('403'));
    });

}
