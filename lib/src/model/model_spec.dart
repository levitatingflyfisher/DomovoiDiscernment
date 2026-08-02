/// One acquirable on-device model — pure data, no plugin import (the
/// Reckon rule: the spec layer must compile everywhere, including web).
///
/// Domovoi ships no catalog and no lookup: which models exist, their
/// order, and the default are app decisions. Apps hold their own
/// `List<ModelSpec>` and run each entry through `ModelTrust.check`.
class ModelSpec {
  /// All fields are required except [requiresToken], which defaults to
  /// false — ungated is the default posture.
  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.modelType,
    required this.description,
    this.requiresToken = false,
  });

  /// Stable identifier apps persist in settings; never shown to users.
  final String id;

  /// The name users see in a model picker.
  final String displayName;

  /// On-disk artifact name; trust law: must end in `.task`.
  final String fileName;

  /// Where the artifact lives; trust laws pin scheme, host, and org.
  final String downloadUrl;

  /// Approximate — progress bars only. NEVER used to judge whether a file
  /// on disk is complete (the Reckon scar: size-guessing deleted real
  /// models); completion is the atomic .part → final rename.
  final int sizeBytes;

  /// Mapped onto the runtime plugin's model type by name, app-side.
  final String modelType;

  /// One calm sentence for the picker: size, license, offline posture.
  final String description;

  /// Whether the host gates the download behind an account token.
  /// Trust law: must be false — only ungated models are acquirable.
  final bool requiresToken;
}
