import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassService {
  CompassService._internal();
  static final CompassService instance = CompassService._internal();

  static const _channel = MethodChannel('com.example.antenna_aligner/geomagnetic');

  /// Gets the magnetic heading stream from the device sensors.
  Stream<double?> get magneticHeadingStream => FlutterCompass.events!.map((event) => event.heading);

  /// Fetches the reliable magnetic declination from the Android native GeomagneticField class.
  Future<double> getReliableDeclination(double lat, double lon, double alt) async {
    try {
      final double? declination = await _channel.invokeMethod('getDeclination', {
        'lat': lat,
        'lon': lon,
        'alt': alt,
        'time': DateTime.now().millisecondsSinceEpoch,
      });
      return declination ?? 0.0;
    } catch (e) {
      // ignore: avoid_print
      print("COMPASS_ERROR: Failed to get native declination: $e");
      return 0.0;
    }
  }
}
