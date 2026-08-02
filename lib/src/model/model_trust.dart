import 'model_spec.dart';

/// The model trust laws as one reusable validator.
///
/// Laws reject by default: a non-allowlisted org, a gated model, or a
/// non-`.task` artifact never reaches a download URL. Apps run every
/// catalog entry through [check] in their own spec tests.
abstract final class ModelTrust {
  /// Orgs whose artifacts may be downloaded (v1: litert-community only —
  /// Apache-2.0, ungated LiteRT builds published by the runtime's own team).
  static const Set<String> allowedOrgs = {'litert-community'};

  /// Returns one human-readable violation per broken law; empty = trusted.
  static List<String> check(ModelSpec spec) {
    final violations = <String>[];
    final uri = Uri.tryParse(spec.downloadUrl);

    // Law: https on huggingface.co only.
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'huggingface.co') {
      violations.add(
        'downloadUrl must be an https URL on huggingface.co, '
        'got "${spec.downloadUrl}"',
      );
    }

    // Law: the org (first path segment) must be on the allowlist.
    final org = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.first
        : '';
    if (!allowedOrgs.contains(org)) {
      violations.add(
        'downloadUrl org "$org" is not on the allowlist '
        '(${allowedOrgs.join(', ')})',
      );
    }

    // Law: ungated only — no token-walled downloads.
    if (spec.requiresToken) {
      violations.add(
        'requiresToken must be false: only ungated models are trusted',
      );
    }

    // Law: `.task` bundles only.
    if (!spec.fileName.endsWith('.task')) {
      violations.add(
        'fileName must end in ".task", got "${spec.fileName}"',
      );
    }

    return violations;
  }
}
