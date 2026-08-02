import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domovoi/src/brain.dart';
import 'package:domovoi/src/keys.dart';
import 'package:domovoi/src/stove/stove_client.dart';
import 'package:domovoi/src/stove/stove_codec.dart';
import 'package:domovoi/src/stove/stove_server.dart';
import 'package:test/test.dart';

// The whole household tier, in-process: fake OpenAI-compat upstream ↔
// StoveServer ↔ StoveClient. Everything binds 127.0.0.1 on ephemeral ports;
// nothing touches the real network.
void main() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';
  const wrongPhrase =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';
  const answerText = 'Simmer, covered, forty minutes.';

  late HttpServer upstream;
  late StoveServer server;
  late Uint8List seed;
  late Uint8List key;

  setUpAll(() async {
    seed = await DomovoiKeys.seedFromPhrase(phrase);
    key = await DomovoiKeys.stoveKey(seed);

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
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

    server = StoveServer(
      0,
      key,
      Uri.parse('http://127.0.0.1:${upstream.port}/v1'),
      'test-model',
    );
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    await upstream.close(force: true);
  });

  test('client and server sharing the household phrase complete an ask',
      () async {
    final client = StoveClient(
      host: '127.0.0.1',
      port: server.port,
      secret: () async => seed,
    );
    expect(await client.complete('hello'), answerText);
  });

  test('a client with the wrong secret is refused', () async {
    final client = StoveClient(
      host: '127.0.0.1',
      port: server.port,
      secret: () async => DomovoiKeys.seedFromPhrase(wrongPhrase),
    );
    await expectLater(
      client.complete('hello'),
      throwsA(isA<AskException>().having(
        (e) => e.message,
        'message',
        contains('refused'),
      )),
    );
  });

  test('a replayed ask frame is refused', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));

    Future<HttpClientResponse> postAsk(String challenge, List<int> frame) async {
      final req = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/stove/ask'),
      );
      req.headers.contentType = ContentType.binary;
      req.headers.set(kStoveChallengeHeader, challenge);
      req.add(frame);
      return req.close();
    }

    final challengeReq = await http.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/stove/challenge'),
    );
    final challengeRes = await challengeReq.close();
    final challenge = (jsonDecode(await utf8.decodeStream(challengeRes))
        as Map<String, dynamic>)['challenge'] as String;

    final frame = await StoveCodec().seal(
      Uint8List.fromList(utf8.encode(jsonEncode({'prompt': 'hello'}))),
      key,
      endpoint: StoveCodec.endpointAsk,
      challenge: challenge,
    );

    final first = await postAsk(challenge, frame);
    await first.drain<void>();
    expect(first.statusCode, 200);

    final replay = await postAsk(challenge, frame);
    expect(replay.statusCode, 403);
    expect(await utf8.decodeStream(replay), 'refused');
  });

  test('the status endpoint reveals no key-derived bytes', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final req = await http.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/stove/status'),
    );
    final body = await utf8.decodeStream(await req.close());

    expect(jsonDecode(body), {
      'domovoi': 1,
      'protocol': 1,
      'model': 'test-model',
    });

    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    for (final material in [seed, key]) {
      expect(body, isNot(contains(hex(material))));
      expect(body.toUpperCase(), isNot(contains(hex(material).toUpperCase())));
      expect(body, isNot(contains(base64.encode(material))));
    }
  });
}
