import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GeoPosition {
  GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.altitude,
  });

  final double latitude;
  final double longitude;
  final double altitude;
}

class GeolocatorService {
  GeolocatorService._internal();
  static final GeolocatorService instance = GeolocatorService._internal();

  /// Real-time hardware GNSS stream used by fusionService
  Stream<GeoPosition> get positionUpdates {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).map((pos) => GeoPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
    ));
  }

  /// Checks permissions and gets the first "Fix" from hardware
  Future<GeoPosition> getCurrentPosition() async {
    await requestPermissions();
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return GeoPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
    );
  }

  /// Captures location samples for a specified duration and returns the average for better precision
  Future<GeoPosition> getAveragedPosition({Duration duration = const Duration(seconds: 5)}) async {
    await requestPermissions();
    
    final List<Position> samples = [];
    final completer = Completer<GeoPosition>();
    
    // Listen to the position stream for the specified duration
    final subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen((position) {
      samples.add(position);
    });

    // After the duration, calculate the average
    Timer(duration, () async {
      await subscription.cancel();
      
      if (samples.isEmpty) {
        // Fallback to a single fix if no stream updates were received
        try {
          final singleFix = await getCurrentPosition();
          completer.complete(singleFix);
        } catch (e) {
          completer.completeError("Could not acquire GPS fix for averaging");
        }
        return;
      }

      double sumLat = 0;
      double sumLon = 0;
      double sumAlt = 0;

      for (var pos in samples) {
        sumLat += pos.latitude;
        sumLon += pos.longitude;
        sumAlt += pos.altitude;
      }

      completer.complete(GeoPosition(
        latitude: sumLat / samples.length,
        longitude: sumLon / samples.length,
        altitude: sumAlt / samples.length,
      ));
    });

    return completer.future;
  }


  Future<void> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('GPS Hardware is Disabled');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Permission Denied');
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }
  }
}
