import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// How a [resumableDownload] run ended.
///
/// A cancelled run also finishes without error — quietly stopping is not a
/// failure — so "no exception" alone never meant "installed". The two are
/// named apart here because a caller that cannot tell them apart will
/// eventually announce a half-file as a finished install.
enum TransferOutcome {
  /// The last byte arrived and `promote` ran: the artifact is installed.
  completed,

  /// The cancel token fired before the last byte. The partial is kept for
  /// Resume and `promote` never ran.
  cancelled,
}

/// The one resumable-transfer engine behind every big household download
/// (model bundles, data slices — native builds only; web surfaces keep
/// their own inert variants and never compile this file).
///
/// Transfers [url] into [partFile], reporting `(receivedBytes, totalBytes)`
/// through [onProgress] (total is `null` when the server omits
/// Content-Length).
///
/// Resumable: an interrupted attempt's partial is continued with an HTTP
/// Range request instead of restarting from zero (what kept happening
/// when a phone slept mid-download). The partial is deliberately KEPT on
/// error so the next attempt picks up where this one stopped. A 416
/// (partial larger than the resource) discards and restarts; a host that
/// ignores Range (200 instead of 206) also discards — appending onto
/// stale bytes would corrupt the file.
///
/// After the last byte, [promote] runs the caller's own post-transfer
/// step (the model file's atomic rename; a slice's sha check + gunzip +
/// rename) before the future completes — so a caller that hears success
/// knows the artifact is fully installed. Completion IS the caller's
/// atomic .part → final rename inside [promote], never a size judgment.
/// An error anywhere (transfer or promotion) reaches the caller as the
/// future's error.
///
/// [cancelToken] is the pause button: cancelling it mid-transfer ends the
/// run quietly — the future completes normally with
/// [TransferOutcome.cancelled], the partial stays for Resume, and
/// [promote] never runs. If the transfer had already completed, the
/// promotion underway is allowed to finish and the run is
/// [TransferOutcome.completed] — the artifact is whole, installing it
/// loses nothing.
Future<TransferOutcome> resumableDownload({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
  CancelToken? cancelToken,
  void Function(int received, int? total)? onProgress,
}) async {
  try {
    final resumeFrom = partFile.existsSync() ? await partFile.length() : 0;
    final reqHeaders = <String, dynamic>{
      if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
    };

    Response<dynamic> response;
    var restarted = false;
    try {
      response = await dio.download(
        url,
        partFile.path,
        options: Options(headers: reqHeaders),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // dio reports progress relative to THIS request; offset it so
          // the caller tracks the whole file when resuming.
          onProgress?.call(
            resumeFrom + received,
            total < 0 ? null : resumeFrom + total,
          );
        },
        // Keep the partial on error so a later attempt can resume.
        deleteOnError: false,
        fileAccessMode:
            resumeFrom > 0 ? FileAccessMode.append : FileAccessMode.write,
      );
    } on DioException catch (err) {
      if (resumeFrom > 0 &&
          err.response?.statusCode ==
              HttpStatus.requestedRangeNotSatisfiable) {
        if (partFile.existsSync()) await partFile.delete();
        response = await dio.download(
          url,
          partFile.path,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) =>
              onProgress?.call(received, total < 0 ? null : total),
          deleteOnError: false,
        );
        restarted = true;
      } else {
        rethrow;
      }
    }

    if (!restarted &&
        resumeFrom > 0 &&
        response.statusCode == HttpStatus.ok) {
      if (partFile.existsSync()) await partFile.delete();
      await dio.download(
        url,
        partFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) =>
            onProgress?.call(received, total < 0 ? null : total),
        deleteOnError: false,
      );
    }

    await promote();
    return TransferOutcome.completed;
  } on DioException catch (err) {
    // The caller's own cancel ends the run quietly: the kept partial is
    // the whole story, and promote never runs.
    if (err.type == DioExceptionType.cancel) return TransferOutcome.cancelled;
    rethrow;
  }
}

/// [resumableDownload] in the dialect the download screens already speak:
/// progress as `(receivedBytes, totalBytes)` events, `-1` for a total the
/// server never sent, and the listener leaving as the pause button.
///
/// The engine's laws are unchanged — this only changes who does the
/// asking. Every argument means what it means above.
///
/// **Cold.** Nothing hits the wire until something subscribes. An eager
/// start would leave a stream nobody listened to downloading *and
/// promoting* an artifact with no reachable cancel — a transfer running
/// on behalf of no one. Cancelling the subscription is therefore always
/// enough to stop the work, because the subscription is what started it.
/// (One listener, once: the transfer is a real thing happening, not a
/// value to be replayed.)
///
/// **Cancellation is not silence.** [onOutcome] fires exactly once, just
/// BEFORE the stream closes, so a consumer that merely awaits the stream
/// can read the outcome immediately after and know whether it may say
/// "installed". It reports [TransferOutcome.completed] or
/// [TransferOutcome.cancelled] only; a transfer or promotion error rides
/// the stream's error channel instead. Pass [cancelToken] to hold the
/// pause button somewhere other than the subscription — the stream then
/// closes normally on cancel, and [onOutcome] is the only thing that
/// tells you it was not a finish.
///
/// Note that `await subscription.cancel()` returns once the token is
/// cancelled, not once the transfer has wound down; a promotion already
/// underway is still allowed to finish.
Stream<(int, int)> resumableDownloadStream({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
  CancelToken? cancelToken,
  void Function(TransferOutcome outcome)? onOutcome,
}) {
  final token = cancelToken ?? CancelToken();
  late final StreamController<(int, int)> controller;
  controller = StreamController<(int, int)>(
    onListen: () {
      unawaited(resumableDownload(
        dio: dio,
        url: url,
        partFile: partFile,
        promote: promote,
        cancelToken: token,
        onProgress: (received, total) {
          // The listener can leave mid-byte; the engine finds out one
          // chunk later, and a closed controller refuses events.
          if (!controller.isClosed) controller.add((received, total ?? -1));
        },
      ).then((outcome) {
        onOutcome?.call(outcome);
        return controller.close();
      }, onError: (Object err, StackTrace stack) {
        if (!controller.isClosed) controller.addError(err, stack);
        return controller.close();
      }));
    },
    // A transfer that already finished shrugs this off: cancel() is a
    // no-op once there is nothing left in flight.
    onCancel: () {
      if (!token.isCancelled) token.cancel();
    },
  );
  return controller.stream;
}
