// The stove CLI. Thin by law: argument handling and the startup
// announcement live here; every protocol behavior lives in StoveServer,
// where it is tested.
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:domovoi/src/keys.dart';
import 'package:domovoi/src/stove/stove_server.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'phrase-file',
      help: 'Path to a file holding the household phrase. The phrase is '
          'never accepted on the command line — process lists leak.',
    )
    ..addOption(
      'secret-hex',
      help: 'Household secret as raw hex — test use. It leaks through '
          'process lists and shell history; prefer --phrase-file.',
    )
    ..addOption(
      'upstream',
      defaultsTo: 'http://127.0.0.1:11434/v1',
      help: 'OpenAI-compatible base URL (Ollama, llamafile).',
    )
    ..addOption(
      'model',
      defaultsTo: 'llama3.2',
      help: 'Model name passed through to the upstream.',
    )
    ..addOption(
      'port',
      defaultsTo: '$kStovePort',
      help: 'Port to serve on ($kStovePort = HOME on a phone keypad).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    _die('${e.message}\n\n${parser.usage}');
  }
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final secret = await _resolveSecret(
    phraseFile: args['phrase-file'] as String?,
    secretHex: args['secret-hex'] as String?,
  );
  final key = await DomovoiKeys.stoveKey(secret);

  final upstream = Uri.tryParse(args['upstream'] as String);
  if (upstream == null || !upstream.hasScheme) {
    _die('--upstream must be a URL (got "${args['upstream']}").');
  }
  final port = int.tryParse(args['port'] as String);
  if (port == null || port < 0 || port > 65535) {
    _die('--port must be a port number (got "${args['port']}").');
  }

  final model = args['model'] as String;
  final server = StoveServer(port, key, upstream, model);
  await server.start();

  stdout
    ..writeln(
      'The stove is lit. It serves "$model" (via $upstream) to any device on '
      'this network that holds the household phrase — the phrase is the '
      'whole pairing; asks and answers travel only as encrypted frames, and '
      'nothing leaves this machine.',
    )
    ..writeln('listening on port ${server.port}');
}

/// Reads the household secret: a BIP39 phrase from [phraseFile], or raw
/// [secretHex]. Exactly one source must be given; with neither, the stove
/// refuses to start (never a default, never argv for the phrase).
Future<Uint8List> _resolveSecret({
  String? phraseFile,
  String? secretHex,
}) async {
  if (phraseFile == null && secretHex == null) {
    _die('No secret source. Pass --phrase-file or --secret-hex; '
        'the stove never starts unkeyed.');
  }
  if (phraseFile != null && secretHex != null) {
    _die('Pass --phrase-file or --secret-hex, not both.');
  }
  if (phraseFile != null) {
    // The phrase IS the household key. A file any other account can read has
    // already given it away, so refuse rather than serve a leaked household.
    if (!Platform.isWindows) {
      final mode = (await File(phraseFile).stat()).mode;
      if (mode & 0x3F != 0) {
        _die('The phrase file is readable by other accounts on this '
            'machine. Run: chmod 600 $phraseFile');
      }
    }
    final String phrase;
    try {
      phrase = (await File(phraseFile).readAsString()).trim();
    } on FileSystemException catch (e) {
      _die('Could not read the phrase file: ${e.path}');
    }
    try {
      return await DomovoiKeys.seedFromPhrase(phrase);
    } catch (_) {
      // Never echo the phrase (or why it failed) — it is the household key.
      _die('The phrase file does not hold a valid household phrase.');
    }
  }
  final hex = secretHex!;
  if (hex.isEmpty || hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    _die('--secret-hex must be non-empty hex bytes.');
  }
  // The frame key is HKDF(secret) with no other input, so the secret's own
  // entropy is the whole defense against a keyless peer on the LAN.
  if (hex.length < kMinStoveSecretBytes * 2) {
    _die('--secret-hex must be at least $kMinStoveSecretBytes bytes '
        '(${kMinStoveSecretBytes * 2} hex characters).');
  }
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

Never _die(String message) {
  stderr.writeln(message);
  exit(64); // EX_USAGE
}
