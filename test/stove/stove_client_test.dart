import 'dart:convert';
import 'dart:io';

import 'package:domovoi/src/brain.dart';
import 'package:domovoi/src/stove/stove_client.dart';
import 'package:test/test.dart';

/// A hand-rolled fake stove: issues a real-shaped challenge, then answers
/// `/stove/ask` however the test dictates. Never leaves 127.0.0.1.
class FakeStove {
  FakeStove(this.onAsk);

  final Future<void> Function(HttpRequest request) onAsk;
  HttpServer? _server;

  int get port => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      if (req.uri.path == '/stove/challenge') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'challenge': base64.encode(List.filled(16, 5)),
          'ttlSeconds': 60,
        }));
        await req.response.close();
      } else {
        await onAsk(req);
      }
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  final secret = List<int>.generate(64, (i) => i);

  test('an unreachable stove becomes a calm AskException', () async {
    // Bind-then-close guarantees a dead port.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();

    final client = StoveClient(
      host: '127.0.0.1',
      port: deadPort,
      secret: () async => secret,
    );
    await expectLater(
      client.complete('hello'),
      throwsA(isA<AskException>().having(
        (e) => e.message,
        'message',
        'The stove is not answering. Is it on and on this network?',
      )),
    );
  });

  test('a 403 refusal becomes a calm AskException', () async {
    final stove = FakeStove((req) async {
      req.response.statusCode = HttpStatus.forbidden;
      req.response.write('refused');
      await req.response.close();
    });
    await stove.start();
    addTearDown(stove.stop);

    final client = StoveClient(
      host: '127.0.0.1',
      port: stove.port,
      secret: () async => secret,
    );
    await expectLater(
      client.complete('hello'),
      throwsA(isA<AskException>().having(
        (e) => e.message,
        'message',
        'The stove refused this ask. Do both ends share the household phrase?',
      )),
    );
  });

  test('an unreadable answer becomes a calm AskException', () async {
    final stove = FakeStove((req) async {
      req.response.headers.contentType = ContentType.binary;
      req.response.add([1, 2, 3, 4]);
      await req.response.close();
    });
    await stove.start();
    addTearDown(stove.stop);

    final client = StoveClient(
      host: '127.0.0.1',
      port: stove.port,
      secret: () async => secret,
    );
    await expectLater(
      client.complete('hello'),
      throwsA(isA<AskException>().having(
        (e) => e.message,
        'message',
        'The stove sent an answer this app could not read.',
      )),
    );
  });
}
