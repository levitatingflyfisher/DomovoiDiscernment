import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
// Direct src import: the barrel exports the STOVE area, which is built by
// another owner and may not exist while CORE is under test.
import 'package:domovoi/src/transfer/resumable_transfer.dart';
import 'package:test/test.dart';

/// Deterministic body — every byte position provable after any resume.
final body = List<int>.generate(4096, (i) => i % 251);

const _chunk = 512;
const _gap = Duration(milliseconds: 15);

/// A loopback host that hands the body over one chunk at a time, so a test
/// can leave mid-transfer. [requests] is the wiretap for "has anything hit
/// the wire yet"; [servedToEnd] catches a transfer still running after its
/// listener walked away.
class _TricklingHost {
  _TricklingHost._(this._server);

  static Future<_TricklingHost> start({bool contentLength = true}) async {
    final host =
        _TricklingHost._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    host._serve(contentLength: contentLength);
    return host;
  }

  final HttpServer _server;

  int requests = 0;
  bool servedToEnd = false;

  String get url => 'http://127.0.0.1:${_server.port}/artifact.bin';

  Future<void> close() => _server.close(force: true);

  void _serve({required bool contentLength}) {
    _server.listen((req) async {
      requests++;
      req.response
        // dart:io buffers ~8KB by default; each chunk must actually reach
        // the wire or the client never sees mid-flight progress.
        ..bufferOutput = false
        ..statusCode = HttpStatus.ok;
      if (contentLength) req.response.contentLength = body.length;
      try {
        for (var i = 0; i < body.length; i += _chunk) {
          await Future<void>.delayed(_gap);
          req.response.add(body.sublist(i, math.min(i + _chunk, body.length)));
          await req.response.flush();
        }
        servedToEnd = true;
        await req.response.close();
      } catch (_) {
        // The client hung up mid-body — that IS the cancel under test.
      }
    });
  }
}

void main() {
  late Directory tmp;
  late File partFile;
  late Dio dio;
  late int promoteCalls;
  _TricklingHost? host;

  Future<void> promote() async => promoteCalls++;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('domovoi_stream_');
    partFile = File('${tmp.path}/artifact.bin.part');
    dio = Dio();
    promoteCalls = 0;
  });

  tearDown(() async {
    await host?.close();
    host = null;
    dio.close(force: true);
    await tmp.delete(recursive: true);
  });

  group('resumableDownloadStream', () {
    test('nothing hits the wire until someone subscribes', () async {
      host = await _TricklingHost.start();
      final stream = resumableDownloadStream(
        dio: dio,
        url: host!.url,
        partFile: partFile,
        promote: promote,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(host!.requests, 0,
          reason: 'a stream nobody listens to must not download — and must '
              'certainly not promote — with no reachable cancel');

      await stream.forEach((_) {});
      expect(host!.requests, 1);
      expect(promoteCalls, 1);
    });

    test('forwards progress and reports the completed outcome', () async {
      host = await _TricklingHost.start();
      final outcomes = <TransferOutcome>[];
      final seen = <(int, int)>[];

      await resumableDownloadStream(
        dio: dio,
        url: host!.url,
        partFile: partFile,
        promote: promote,
        onOutcome: outcomes.add,
      ).forEach(seen.add);

      // The outcome is settled BEFORE the stream closes, so a consumer that
      // simply awaits the stream can trust what it reads next.
      expect(outcomes, [TransferOutcome.completed]);
      expect(seen, isNotEmpty);
      expect(seen.last, (body.length, body.length));
      expect(promoteCalls, 1);
    });

    test('an absent Content-Length reaches the listener as -1, not null',
        () async {
      host = await _TricklingHost.start(contentLength: false);
      final seen = <(int, int)>[];

      await resumableDownloadStream(
        dio: dio,
        url: host!.url,
        partFile: partFile,
        promote: promote,
      ).forEach(seen.add);

      expect(seen, isNotEmpty);
      expect(seen.map((e) => e.$2), everyElement(-1));
    });

    test('a token cancelled mid-flight ends the stream quietly but says so',
        () async {
      host = await _TricklingHost.start();
      final token = CancelToken();
      final outcomes = <TransferOutcome>[];

      // Closing normally is exactly what makes this dangerous: with no
      // outcome to read, a consumer awaiting the stream would call a
      // cancelled half-file "installed".
      await resumableDownloadStream(
        dio: dio,
        url: host!.url,
        partFile: partFile,
        promote: promote,
        cancelToken: token,
        onOutcome: outcomes.add,
      ).forEach((_) {
        if (!token.isCancelled) token.cancel();
      });

      expect(outcomes, [TransferOutcome.cancelled]);
      expect(promoteCalls, 0);
      expect(partFile.existsSync(), isTrue);
    });

    test('cancelling the subscription cancels the transfer', () async {
      host = await _TricklingHost.start();
      final outcomes = <TransferOutcome>[];
      final firstEvent = Completer<void>();

      final sub = resumableDownloadStream(
        dio: dio,
        url: host!.url,
        partFile: partFile,
        promote: promote,
        onOutcome: outcomes.add,
      ).listen((_) {
        if (!firstEvent.isCompleted) firstEvent.complete();
      });

      await firstEvent.future;
      await sub.cancel();

      // The whole body trickles in ~120ms; a detached transfer would have
      // finished the file and promoted it inside this window.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(host!.servedToEnd, isFalse,
          reason: 'the wire must go quiet once the listener leaves');
      expect(promoteCalls, 0);
      expect(partFile.existsSync(), isTrue,
          reason: 'the partial is kept so Resume picks up from the same byte');
      expect(partFile.lengthSync(), lessThan(body.length));
      expect(outcomes, [TransferOutcome.cancelled]);
    });

    test('a transfer error rides the stream, not the outcome seam', () async {
      final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => failing.close(force: true));
      failing.listen((req) async {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      });
      final outcomes = <TransferOutcome>[];

      await expectLater(
        resumableDownloadStream(
          dio: dio,
          url: 'http://127.0.0.1:${failing.port}/artifact.bin',
          partFile: partFile,
          promote: promote,
          onOutcome: outcomes.add,
        ).forEach((_) {}),
        throwsA(isA<DioException>()),
      );

      expect(outcomes, isEmpty,
          reason: 'failure is not an outcome — it is the error channel');
      expect(promoteCalls, 0);
    });
  });
}
