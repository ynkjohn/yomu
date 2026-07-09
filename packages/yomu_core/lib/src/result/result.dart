/// Lightweight result type for domain boundaries.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(String message, Object? cause) err,
  });
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(String message, Object? cause) err,
  }) =>
      ok(value);
}

final class Err<T> extends Result<T> {
  const Err(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(String message, Object? cause) err,
  }) =>
      err(message, cause);
}
