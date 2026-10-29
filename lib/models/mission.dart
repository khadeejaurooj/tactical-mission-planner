import 'package:latlong2/latlong.dart';

import '../services/geo_utils.dart';
import 'waypoint.dart';

/// A planned mission: an ordered list of waypoints plus metadata.
///
/// The route is every waypoint that is not a hazard, in list order.
class Mission {
  const Mission({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.waypoints = const [],
  });

  static const int schemaVersion = 1;

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Waypoint> waypoints;

  List<Waypoint> get routePoints =>
      waypoints.where((w) => w.type.isOnRoute).toList(growable: false);

  List<Waypoint> get hazards =>
      waypoints.where((w) => w.type == WaypointType.hazard).toList(growable: false);

  List<LatLng> get routeLatLngs =>
      routePoints.map((w) => w.position).toList(growable: false);

  double get routeDistanceMeters => GeoUtils.pathLength(routeLatLngs);

  Mission copyWith({
    String? name,
    String? description,
    List<Waypoint>? waypoints,
    DateTime? updatedAt,
  }) {
    return Mission(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      waypoints: waypoints ?? this.waypoints,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
      };

  factory Mission.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['name'] is! String) {
      throw const FormatException('Mission needs "id" and "name".');
    }
    final rawWaypoints = json['waypoints'];
    if (rawWaypoints != null && rawWaypoints is! List) {
      throw const FormatException('"waypoints" must be a list.');
    }
    final now = DateTime.now();
    return Mission(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? now,
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ?? now,
      waypoints: [
        for (final item in (rawWaypoints as List? ?? const []))
          Waypoint.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }
}
