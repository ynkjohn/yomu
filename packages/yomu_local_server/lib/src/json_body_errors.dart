class JsonBodyTooLarge implements Exception {
  const JsonBodyTooLarge();
}

class JsonBodyInvalid implements Exception {
  const JsonBodyInvalid(this.code);
  final String code;
}
