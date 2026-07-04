class NovelException implements Exception {
  NovelException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('NovelException: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

class NovelSourceException extends NovelException {
  NovelSourceException(super.message, {super.cause});
}

class ParseException extends NovelException {
  ParseException(super.message, {super.cause});
}

class HttpException extends NovelException {
  HttpException(super.message, {super.cause});
}

class CacheException extends NovelException {
  CacheException(super.message, {super.cause});
}
