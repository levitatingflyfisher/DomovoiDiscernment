// Direct src imports: the barrel exports the STOVE area, which is built by
// another owner and may not exist while CORE is under test.
import 'package:domovoi/src/model/model_spec.dart';
import 'package:domovoi/src/model/model_trust.dart';
import 'package:test/test.dart';

/// A spec that satisfies every trust law; each test breaks exactly one.
ModelSpec spec({
  String downloadUrl =
      'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/'
          'resolve/main/model.task',
  String fileName = 'model.task',
  bool requiresToken = false,
}) =>
    ModelSpec(
      id: 'test-model',
      displayName: 'Test Model',
      fileName: fileName,
      downloadUrl: downloadUrl,
      sizeBytes: 1,
      modelType: 'qwen',
      description: 'd',
    );

void main() {
  group('ModelTrust.check', () {
    test('a spec satisfying every law is trusted (empty list)', () {
      expect(ModelTrust.check(spec()), isEmpty);
    });

    test('rejects a non-https URL', () {
      final violations = ModelTrust.check(spec(
        downloadUrl:
            'http://huggingface.co/litert-community/M/resolve/main/m.task',
      ));
      expect(violations, hasLength(1));
      expect(violations.single, contains('https'));
    });

    test('rejects a host other than huggingface.co', () {
      final violations = ModelTrust.check(spec(
        downloadUrl:
            'https://example.com/litert-community/M/resolve/main/m.task',
      ));
      expect(violations, hasLength(1));
      expect(violations.single, contains('huggingface.co'));
    });

    test('rejects an org outside the allowlist', () {
      final violations = ModelTrust.check(spec(
        downloadUrl: 'https://huggingface.co/google/M/resolve/main/m.task',
      ));
      expect(violations, hasLength(1));
      expect(violations.single, contains('litert-community'));
    });

    test('rejects a URL with no org path segment (reject by default)', () {
      final violations =
          ModelTrust.check(spec(downloadUrl: 'https://huggingface.co/'));
      expect(violations, hasLength(1));
      expect(violations.single, contains('litert-community'));
    });

    test('rejects an unparseable URL', () {
      final violations = ModelTrust.check(spec(downloadUrl: '::not a url::'));
      expect(violations, isNotEmpty);
    });

    test('rejects a gated model (requiresToken true)', () {
      const gated = ModelSpec(
        id: 'gated',
        displayName: 'Gated',
        fileName: 'model.task',
        downloadUrl: 'https://huggingface.co/litert-community/M/'
            'resolve/main/model.task',
        sizeBytes: 1,
        modelType: 'qwen',
        description: 'd',
        requiresToken: true,
      );
      final violations = ModelTrust.check(gated);
      expect(violations, hasLength(1));
      expect(violations.single, contains('ungated'));
    });

    test('rejects a fileName that does not end in .task', () {
      final violations = ModelTrust.check(spec(fileName: 'model.bin'));
      expect(violations, hasLength(1));
      expect(violations.single, contains('.task'));
    });

    test('reports one violation per broken law, not just the first', () {
      const broken = ModelSpec(
        id: 'broken',
        displayName: 'Broken',
        fileName: 'model.gguf',
        downloadUrl: 'http://example.com/google/M/resolve/main/model.gguf',
        sizeBytes: 1,
        modelType: 'qwen',
        description: 'd',
        requiresToken: true,
      );
      final violations = ModelTrust.check(broken);
      // https+host law, org law, token law, fileName law.
      expect(violations, hasLength(4));
    });
  });
}
