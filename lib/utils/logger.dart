class Logger {
  static void info(String message) {
    // Replace with a logging framework if needed.
    // For now this is a minimal debug logger.
    // ignore: avoid_print
    print('[INFO] $message');
  }

  static void error(String message) {
    // ignore: avoid_print
    print('[ERROR] $message');
  }
}
