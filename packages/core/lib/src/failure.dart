class Failure implements Exception {
  const Failure(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'Failure($code, $message)';
}
