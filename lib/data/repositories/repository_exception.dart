/// Thrown by repository methods when a Supabase call fails.
class RepositoryException implements Exception {
  final String message;
  final Object? cause;

  RepositoryException(this.message, [this.cause]);

  @override
  String toString() => message;
}
