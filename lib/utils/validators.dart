class Validators {
  static bool isNonEmptyString(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static bool isValidCoordinate(double value) {
    return value.isFinite;
  }
}
