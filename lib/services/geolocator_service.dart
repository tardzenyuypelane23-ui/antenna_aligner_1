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
