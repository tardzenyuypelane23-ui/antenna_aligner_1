import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';

class PointingError {
  PointingError({
    required this.currentLocation,
    required this.targetAccessPoint,
    required this.sourceAzimuth,
    required this.sourceElevation,
    required this.targetAzimuth,
    required this.targetElevation,
    required this.deltaAzimuth,
    required this.deltaElevation,
    required this.pose,
    required this.distance,
    required this.timestamp,
  });

  final GeoPosition currentLocation;
  final AccessPoint targetAccessPoint;
  final double sourceAzimuth;
  final double sourceElevation;
  final double targetAzimuth;
  final double targetElevation;
  final double deltaAzimuth;
  final double deltaElevation;
  final EKFState pose;
  final double distance;
  final DateTime timestamp;
}
