class SensorState {
  SensorState({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.azimuth,
    required this.elevation,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final double azimuth;
  final double elevation;
  final DateTime timestamp;
}
