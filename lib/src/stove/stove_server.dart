import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'challenge_store.dart';
import 'stove_codec.dart';

/// The stove's LAN port — HOME on a phone keypad.
const int kStovePort = 4663;

/// The household stove: an embedded HTTP server that proxies encrypted asks
/// to a local OpenAI-compat upstream (Ollama, llamafile).
///
/// The wire is encrypted: `/stove/ask` bodies are binary AEAD frames (see
/// [StoveCodec]) under a key HKDF-derived from the household phrase. AEAD
/// possession is the pairing proof — no accounts, no certificates, no bearer
/// token to leak. `/stove/status` stays a minimal cleartext probe that
/// reveals no secret-derived material.
///
/// Laws enforced here:
/// - The challenge is consumed BEFORE any verification or upstream work, so
///   a replayed frame is dead on arrival.
/// - ANY `/stove/ask` failure — bad challenge, bad frame, wrong key, upstream
///   trouble — is the same constant-shaped `403 refused`. Fail closed, no
///   oracle.
class StoveServer {
  /// Creates a stove bound to [port] (0 for ephemeral), sealing frames under
  /// the 32-byte [key], proxying prompts to the OpenAI-compat [upstream]
  /// base URI (e.g. `http://127.0.0.1:11434/v1`) as [model].
  StoveServer(
    this._port,
    Uint8List key,
    Uri upstream,
    String model, {
    ChallengeStore? challenges,
  })  : _key = key,
        _upstream = upstream,
        _model = model,
        _challenges = challenges ?? ChallengeStore();

  /// A hostile flood must not buy unbounded memory; a prompt is small.
  static const int maxFrameBytes = 1024 * 1024;

  final int _port;
  final Uint8List _key;
  final Uri _upstream;
  final String _model;
  final ChallengeStore _challenges;
  final Dio _dio = Dio();
  final StoveCodec _codec = StoveCodec();

  HttpServer? _server;

  /// Whether the stove is currently bound.
  bool get isRunning => _server != null;

  /// The bound port — meaningful once [start] has completed.
  int get port => _server?.port ?? _port;

  /// Binds the socket and begins serving. Idempotent.
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _server = server;
    server.listen(_route);
  }

  /// Closes the socket. Idempotent.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _route(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/stove/status') {
        await _handleStatus(request);
      } else if (request.method == 'GET' && path == '/stove/challenge') {
        await _handleChallenge(request);
      } else if (request.method == 'POST' && path == '/stove/ask') {
        await _handleAsk(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      // The socket may already be gone; never let one request kill the loop,
      // and never echo internals to the peer.
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Cleartext capability probe. Law: reveals no secret-derived material —
  /// only that a stove lives here and what model it serves.
  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'domovoi': 1,
      'protocol': StoveCodec.protocolVersion,
      'model': _model,
    }));
    await request.response.close();
  }

  Future<void> _handleChallenge(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'challenge': _challenges.issue(),
      'ttlSeconds': _challenges.ttl.inSeconds,
    }));
    await request.response.close();
  }

  Future<void> _handleAsk(HttpRequest request) async {
    // Challenge first: consumed before the frame is even read fully, so no
    // failure path leaves it reusable and no upstream work precedes it.
    final token = request.headers.value(kStoveChallengeHeader);
    if (token == null || !_challenges.consume(token)) {
      return _refuse(request);
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxFrameBytes) return _refuse(request);
    }

    final String answer;
    try {
      final plaintext = await _codec.open(
        builder.takeBytes(),
        _key,
        endpoint: StoveCodec.endpointAsk,
        challenge: token,
      );
      final ask = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      answer = await _askUpstream(
        ask['prompt'] as String,
        maxTokens: ask['maxTokens'] as int?,
      );
    } catch (_) {
      // Same shape for every cause — codec, JSON, upstream. No oracle.
      return _refuse(request);
    }

    final frame = await _codec.seal(
      Uint8List.fromList(utf8.encode(jsonEncode({'text': answer}))),
      _key,
      endpoint: StoveCodec.endpointAnswer,
      challenge: token,
    );
    request.response.headers.contentType = ContentType.binary;
    request.response.add(frame);
    await request.response.close();
  }

  Future<String> _askUpstream(String prompt, {int? maxTokens}) async {
    final res = await _dio.postUri<Map<String, dynamic>>(
      _upstream.replace(path: '${_upstream.path}/chat/completions'),
      data: {
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        if (maxTokens != null) 'max_tokens': maxTokens,
      },
    );
    final choices = res.data!['choices'] as List<dynamic>;
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    return message['content'] as String;
  }

  Future<void> _refuse(HttpRequest request) async {
    request.response.statusCode = HttpStatus.forbidden;
    request.response.write('refused');
    await request.response.close();
  }
}
