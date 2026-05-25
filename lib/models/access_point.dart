class AccessPoint {
  AccessPoint({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.altitude,
  });

  final int? id;
  final String name;
  final double latitude;
  final double longitude;
  final double altitude;

  AccessPoint copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    double? altitude,
  }) {
    return AccessPoint(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
    };
  }

  factory AccessPoint.fromMap(Map<String, dynamic> map) {
    return AccessPoint(
      id: map['id'] as int?,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num).toDouble(),
    );
  }
}
