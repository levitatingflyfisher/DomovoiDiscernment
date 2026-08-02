/// The one seam between an app's feature pipeline and whatever thinks.
///
/// Implementations run on the device (an app-side flutter_gemma adapter),
/// on the household stove ([StoveClient]), or at a cloud the user
/// explicitly keyed (app-side BYOK clients). Callers never know which —
/// that is the point.
abstract class Brain {
  /// One prompt in, the model's whole text answer out.
  ///
  /// Implementations throw [AskException] for anything the user might need
  /// to read; callers wrap failures calmly and never retry blind.
  Future<String> complete(String prompt);
}

/// A calm, displayable failure from a [Brain].
class AskException implements Exception {
  AskException(this.message, {this.cause});

  /// Human-readable, in the interface's voice — no stack traces, no jargon.
  final String message;

  /// The underlying error, kept for logs and tests, never for the user.
  final Object? cause;

  @override
  String toString() => 'AskException: $message';
}
