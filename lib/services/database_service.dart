import 'package:antenna_aligner/models/access_point.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  final List<AccessPoint> _accessPoints = <AccessPoint>[];
  int _nextId = 1;

  Future<List<AccessPoint>> getAccessPoints() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List<AccessPoint>.unmodifiable(_accessPoints);
  }

  Future<void> addAccessPoint(AccessPoint accessPoint) async {
    final newPoint = accessPoint.copyWith(id: _nextId++);
    _accessPoints.add(newPoint);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> removeAccessPoint(int id) async {
    _accessPoints.removeWhere((item) => item.id == id);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> updateAccessPoint(AccessPoint accessPoint) async {
    final index = _accessPoints.indexWhere((item) => item.id == accessPoint.id);
    if (index >= 0) {
      _accessPoints[index] = accessPoint;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
