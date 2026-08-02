import 'dart:io';

import 'package:dio/dio.dart';

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
/// run quietly — the future completes normally, the partial stays for
/// Resume, and [promote] never runs. If the transfer had already
/// completed, the promotion underway is allowed to finish — the artifact
/// is whole, installing it loses nothing.
Future<void> resumableDownload({
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
  } on DioException catch (err) {
    // The caller's own cancel ends the run quietly: the kept partial is
    // the whole story, and promote never runs.
    if (err.type == DioExceptionType.cancel) return;
    rethrow;
  }
}
