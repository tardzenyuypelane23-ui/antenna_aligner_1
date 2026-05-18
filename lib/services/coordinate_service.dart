import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class CoordinateService {
  CoordinateService._internal();
  static final CoordinateService instance = CoordinateService._internal();

  static const double _wgs84A = 6378137.0; // semi-major axis
  static const double _wgs84F = 1 / 298.257223563; // flattening
  static const double _wgs84B = _wgs84A * (1 - _wgs84F); // semi-minor axis
  static const double _wgs84E2 = (_wgs84A * _wgs84A - _wgs84B * _wgs84B) / (_wgs84A * _wgs84A);

  /// Converts Geodetic (Lat, Lon, Alt) to ECEF (Earth-Centered, Earth-Fixed) meters
  Vector3 llaToEcef(double lat, double lon, double alt) {
    final radLat = _degToRad(lat);
    final radLon = _degToRad(lon);

    final n = _wgs84A / sqrt(1 - _wgs84E2 * sin(radLat) * sin(radLat));

    final x = (n + alt) * cos(radLat) * cos(radLon);
    final y = (n + alt) * cos(radLat) * sin(radLon);
    final z = (n * (1 - _wgs84E2) + alt) * sin(radLat);

    return Vector3(x, y, z);
  }

  /// Converts ECEF to Local ENU (East, North, Up) relative to a reference point
  Vector3 ecefToEnu(Vector3 currentEcef, Vector3 refLla, Vector3 refEcef) {
    final radLat = _degToRad(refLla.x);
    final radLon = _degToRad(refLla.y);

    final delta = currentEcef - refEcef;

    final t = -sin(radLon) * delta.x + cos(radLon) * delta.y;
    final n = -sin(radLat) * cos(radLon) * delta.x - sin(radLat) * sin(radLon) * delta.y + cos(radLat) * delta.z;
    final u = cos(radLat) * cos(radLon) * delta.x + cos(radLat) * sin(radLon) * delta.y + sin(radLat) * delta.z;

    return Vector3(t, n, u); // East, North, Up
  }

  double _degToRad(double deg) => deg * pi / 180.0;
  double radToDeg(double rad) => rad * 180.0 / pi;
}
