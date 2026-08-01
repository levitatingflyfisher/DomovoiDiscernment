import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../brain.dart';
import '../keys.dart';
import 'stove_codec.dart';

/// A [Brain] that asks the household stove over the encrypted stove protocol.
///
/// `complete()` = fetch a single-use challenge, seal the ask frame bound to
/// it, POST it, open the challenge-bound answer. The key is derived fresh
/// from [_secret] per ask (HKDF is cheap; the secret's storage stays the
/// app's concern) and never crosses the wire.
///
/// Every failure surfaces as a calm [AskException]; the cause rides along
/// for logs, never for the user.
class StoveClient implements Brain {
  /// Creates a client for the stove at [host]:[port]. [secret] supplies the
  /// household secret bytes (normally the BIP39 seed); [dio] is injectable
  /// for tests.
  StoveClient({
    required String host,
    required int port,
    required Future<List<int>> Function() secret,
    Dio? dio,
  })  : _base = 'http://$host:$port',
        _secret = secret,
        _dio = dio ?? Dio();

  final String _base;
  final Future<List<int>> Function() _secret;
  final Dio _dio;
  final StoveCodec _codec = StoveCodec();

  static const String _unreachable =
      'The stove is not answering. Is it on and on this network?';
  static const String _refused =
      'The stove refused this ask. Do both ends share the household phrase?';
  static const String _badAnswer =
      'The stove sent an answer this app could not read.';

  @override
  Future<String> complete(String prompt) async {
    final key = await DomovoiKeys.stoveKey(await _secret());
    final challenge = await _fetchChallenge();
    final frame = await _codec.seal(
      Uint8List.fromList(utf8.encode(jsonEncode({'prompt': prompt}))),
      key,
      endpoint: StoveCodec.endpointAsk,
      challenge: challenge,
    );
    final answerFrame = await _postAsk(frame, challenge);
    try {
      final plaintext = await _codec.open(
        answerFrame,
        key,
        endpoint: StoveCodec.endpointAnswer,
        challenge: challenge,
      );
      final answer = jsonDecode(utf8.decode(plaintext));
      return (answer as Map<String, dynamic>)['text'] as String;
    } catch (e) {
      // A 200 whose frame will not open or parse — wrong shape, not refusal.
      throw AskException(_badAnswer, cause: e);
    }
  }

  Future<String> _fetchChallenge() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/stove/challenge',
      );
      return res.data!['challenge'] as String;
    } on DioException catch (e) {
      throw AskException(e.response == null ? _unreachable : _refused,
          cause: e);
    } catch (e) {
      throw AskException(_badAnswer, cause: e);
    }
  }

  Future<Uint8List> _postAsk(Uint8List frame, String challenge) async {
    try {
      final res = await _dio.post<List<int>>(
        '$_base/stove/ask',
        data: Stream.fromIterable([frame]),
        options: Options(
          responseType: ResponseType.bytes,
          contentType: 'application/octet-stream',
          headers: {
            kStoveChallengeHeader: challenge,
            Headers.contentLengthHeader: frame.length,
          },
        ),
      );
      return Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      // A response means the stove answered and said no; none means the wire
      // itself failed.
      throw AskException(e.response == null ? _unreachable : _refused,
          cause: e);
    }
  }
}
