sealed class MatchingFailure implements Exception {
  const MatchingFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class NoCandidatesFound extends MatchingFailure {
  const NoCandidatesFound(super.message, {super.cause});
}

final class ProductMatchingRepositoryFailure extends MatchingFailure {
  const ProductMatchingRepositoryFailure(super.message, {super.cause});
}

final class InvalidProductMatchRequest extends MatchingFailure {
  const InvalidProductMatchRequest(super.message, {super.cause});
}

final class ProductMatchingFailed extends MatchingFailure {
  const ProductMatchingFailed(super.message, {super.cause});
}
