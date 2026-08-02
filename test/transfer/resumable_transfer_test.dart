import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
// Direct src import: the barrel exports the STOVE area, which is built by
// another owner and may not exist while CORE is under test.
import 'package:domovoi/src/transfer/resumable_transfer.dart';
import 'package:test/test.dart';

/// Deterministic body — every byte position provable after any resume.
final body = List<int>.generate(4096, (i) => i % 251);

void main() {
  late Directory tmp;
  late File partFile;
  late Dio dio;
  late int promoteCalls;
  HttpServer? server;

  Future<void> promote() async => promoteCalls++;

  String urlOf(HttpServer s) => 'http://127.0.0.1:${s.port}/model.task';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('domovoi_transfer_');
    partFile = File('${tmp.path}/model.task.part');
    dio = Dio();
    promoteCalls = 0;
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    dio.close(force: true);
    await tmp.delete(recursive: true);
  });

  group('resumableDownload', () {
    test('fresh download sends no Range, promotes exactly once', () async {
      final rangeHeaders = <String?>[];
      final progress = <(int, int?)>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(rangeHeaders, [null]);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
      expect(progress.last, (body.length, body.length));
    });

    test('resume sends Range from the .part byte offset and completes',
        () async {
      const already = 1000;
      await partFile.writeAsBytes(body.sublist(0, already));
      final rangeHeaders = <String?>[];
      final progress = <(int, int?)>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        final rest = body.sublist(already);
        req.response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = rest.length
          ..headers.set(HttpHeaders.contentRangeHeader,
              'bytes $already-${body.length - 1}/${body.length}')
          ..add(rest);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(rangeHeaders, ['bytes=$already-']);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
      // Progress is offset to track the WHOLE file, not just this request.
      expect(progress.last, (body.length, body.length));
      expect(progress.first.$1, greaterThanOrEqualTo(already));
    });

    test('cancel mid-flight is quiet, leaves the .part, never promotes',
        () async {
      final gate = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          // dart:io buffers ~8KB by default; the first chunk must actually
          // reach the wire or the client never sees mid-flight progress.
          ..bufferOutput = false
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body.sublist(0, 1024));
        await req.response.flush();
        try {
          await gate.future;
          await req.response.close();
        } catch (_) {}
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final cancelToken = CancelToken();
      final future = resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!cancelToken.isCancelled) cancelToken.cancel();
        },
      );

      // Quiet: completes normally, no error surfaces.
      await future;
      expect(promoteCalls, 0);
      expect(partFile.existsSync(), isTrue);
      expect(partFile.lengthSync(), lessThan(body.length));
    });

    test('a 200 answering a resume discards the partial and restarts clean',
        () async {
      // Stale bytes that must NOT survive: a host that ignores Range would
      // otherwise have them appended under the real payload.
      await partFile.writeAsBytes(List<int>.filled(1000, 0xFF));
      final rangeHeaders = <String?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
      );

      expect(rangeHeaders, ['bytes=1000-', null]);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
    });

    test('a 416 answering a resume discards the partial and restarts clean',
        () async {
      await partFile.writeAsBytes(List<int>.filled(5000, 0xFF));
      final rangeHeaders = <String?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        rangeHeaders.add(range);
        if (range != null) {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
      );

      expect(rangeHeaders, ['bytes=5000-', null]);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
    });

    test('a server omitting Content-Length reports null totals', () async {
      final totals = <int?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        // No contentLength set: dart:io answers chunked, dio sees -1.
        req.response
          ..statusCode = HttpStatus.ok
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => totals.add(total),
      );

      expect(totals, isNotEmpty);
      expect(totals, everyElement(isNull));
      expect(await partFile.readAsBytes(), body);
      expect(promoteCalls, 1);
    });

    test('a transfer error surfaces, keeps the .part, never promotes',
        () async {
      final stale = List<int>.filled(1000, 0x42);
      await partFile.writeAsBytes(stale);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      });

      await expectLater(
        resumableDownload(
          dio: dio,
          url: urlOf(server!),
          partFile: partFile,
          promote: promote,
        ),
        throwsA(isA<DioException>()),
      );
      expect(promoteCalls, 0);
      // The partial is deliberately KEPT so the next attempt resumes.
      expect(await partFile.readAsBytes(), stale);
    });

    test('a promotion error surfaces to the caller', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await expectLater(
        resumableDownload(
          dio: dio,
          url: urlOf(server!),
          partFile: partFile,
          promote: () async => throw StateError('sha mismatch'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
