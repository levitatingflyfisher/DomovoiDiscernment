import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// The CLI is thin by design (all protocol logic lives in StoveServer, tested
// elsewhere); these tests pin its contract: secret sourcing rules and the
// calm startup announcement.
void main() {
  final repoRoot = Directory.current.path;

  Future<ProcessResult> runStove(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/stove.dart', ...args],
        workingDirectory: repoRoot,
      );

  test('refuses to start with no secret source', () async {
    final result = await runStove([]);
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('--phrase-file or --secret-hex'));
  });

  test('refuses a malformed --secret-hex', () async {
    final result = await runStove(['--secret-hex', 'not-hex']);
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('hex'));
  });

  test('refuses a missing phrase file', () async {
    final result = await runStove(['--phrase-file', '/nonexistent/phrase']);
    expect(result.exitCode, isNot(0));
  });

  test('starts with --secret-hex, prints the calm paragraph, and serves '
      '/stove/status', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/stove.dart',
        '--secret-hex',
        'aa' * 32,
        '--port',
        '0',
        '--model',
        'cli-test-model',
      ],
      workingDirectory: repoRoot,
    );
    addTearDown(process.kill);

    // The startup paragraph ends with the bound port on its own line:
    // "listening on port <n>".
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    var paragraph = '';
    var port = 0;
    await for (final line in lines) {
      paragraph = '$paragraph$line\n';
      final match = RegExp(r'listening on port (\d+)').firstMatch(line);
      if (match != null) {
        port = int.parse(match.group(1)!);
        break;
      }
    }
    expect(port, greaterThan(0));
    expect(paragraph, contains('household phrase'));
    expect(paragraph, contains('cli-test-model'));
    // The announcement never prints key material.
    expect(paragraph, isNot(contains('aa' * 32)));

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final req =
        await http.getUrl(Uri.parse('http://127.0.0.1:$port/stove/status'));
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(
      jsonDecode(await utf8.decodeStream(res)),
      containsPair('model', 'cli-test-model'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
