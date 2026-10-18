sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) { Ok<T>(:final value) => value, _ => null };
  String? get errorOrNull => switch (this) { Err<T>(:final message) => message, _ => null };

  R fold<R>(R Function(T value) onOk, R Function(String message) onErr) =>
      switch (this) { Ok<T>(:final value) => onOk(value), Err<T>(:final message) => onErr(message) };
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final String message;
  const Err(this.message);
}

Future<Result<T>> guard<T>(Future<T> Function() body, {String Function(Object e)? describe}) async {
  try {
    return Ok(await body());
  } catch (e) {
    return Err(describe?.call(e) ?? e.toString());
  }
}
