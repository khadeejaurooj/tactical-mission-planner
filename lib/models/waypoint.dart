import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// The kinds of points a planner can place on the map.
///
/// [hazard] points are not part of the route: they mark a restricted area
/// (with a radius) that the simulated asset is warned about.
enum WaypointType {
  start('Start', Icons.flag_circle, Color(0xFF2E7D32)),
  waypoint('Waypoint', Icons.place, Color(0xFF1E88E5)),
  objective('Objective', Icons.my_location, Color(0xFFF9A825)),
  hazard('Hazard', Icons.warning_amber_rounded, Color(0xFFE53935)),
  end('End', Icons.sports_score, Color(0xFF8E24AA));

  const WaypointType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  bool get isOnRoute => this != WaypointType.hazard;

  static WaypointType parse(Object? value) {
    for (final type in WaypointType.values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unknown waypoint type: $value');
  }
}

class Waypoint {
  const Waypoint({
    required this.id,
    required this.type,
    required this.name,
    required this.position,
    this.radiusMeters = 0,
    this.notes = '',
  });

  final String id;
  final WaypointType type;
  final String name;
  final LatLng position;

  /// Only meaningful for hazards: the radius of the restricted area.
  final double radiusMeters;
  final String notes;

  Waypoint copyWith({
    WaypointType? type,
    String? name,
    LatLng? position,
    double? radiusMeters,
    String? notes,
  }) {
    return Waypoint(
      id: id,
      type: type ?? this.type,
      name: name ?? this.name,
      position: position ?? this.position,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'lat': position.latitude,
        'lng': position.longitude,
        'radiusMeters': radiusMeters,
        'notes': notes,
      };

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'];
    final lng = json['lng'];
    if (json['id'] is! String || lat is! num || lng is! num) {
      throw const FormatException('Waypoint needs "id", "lat" and "lng".');
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw FormatException('Waypoint "${json['id']}" has invalid coordinates.');
    }
    return Waypoint(
      id: json['id'] as String,
      type: WaypointType.parse(json['type']),
      name: (json['name'] as String?) ?? '',
      position: LatLng(lat.toDouble(), lng.toDouble()),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 0,
      notes: (json['notes'] as String?) ?? '',
    );
  }
}
