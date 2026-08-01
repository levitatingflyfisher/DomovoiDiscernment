// Direct src import: the barrel exports the STOVE area, which is built by
// another owner and may not exist while CORE is under test.
import 'package:domovoi/src/model/model_spec.dart';
import 'package:test/test.dart';

void main() {
  group('ModelSpec', () {
    test('is const-constructible and carries every field', () {
      const spec = ModelSpec(
        id: 'qwen-2.5-0.5b-it',
        displayName: 'Qwen 2.5 0.5B',
        fileName: 'qwen25-0-5b-it-q8.task',
        downloadUrl:
            'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/'
            'resolve/main/'
            'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        sizeBytes: 572000000,
        modelType: 'qwen',
        description: 'Small and quick.',
      );

      expect(spec.id, 'qwen-2.5-0.5b-it');
      expect(spec.displayName, 'Qwen 2.5 0.5B');
      expect(spec.fileName, 'qwen25-0-5b-it-q8.task');
      expect(spec.downloadUrl, contains('huggingface.co/litert-community/'));
      expect(spec.sizeBytes, 572000000);
      expect(spec.modelType, 'qwen');
      expect(spec.description, 'Small and quick.');
    });

    test('requiresToken defaults to false (ungated is the default posture)',
        () {
      const spec = ModelSpec(
        id: 'x',
        displayName: 'X',
        fileName: 'x.task',
        downloadUrl: 'https://huggingface.co/litert-community/X/x.task',
        sizeBytes: 1,
        modelType: 'qwen',
        description: 'd',
      );
      expect(spec.requiresToken, isFalse);
    });

    test('requiresToken can be set explicitly', () {
      const spec = ModelSpec(
        id: 'x',
        displayName: 'X',
        fileName: 'x.task',
        downloadUrl: 'https://huggingface.co/litert-community/X/x.task',
        sizeBytes: 1,
        modelType: 'qwen',
        description: 'd',
        requiresToken: true,
      );
      expect(spec.requiresToken, isTrue);
    });
  });
}
