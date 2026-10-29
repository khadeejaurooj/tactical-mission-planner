import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_mission_planner/models/mission.dart';
import 'package:tactical_mission_planner/models/waypoint.dart';

void main() {
  group('Mission JSON', () {
    test('round-trips without losing data', () {
      final mission = Mission(
        id: 'm1',
        name: 'Round trip',
        description: 'desc',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        waypoints: const [
          Waypoint(id: 'a', type: WaypointType.start, name: 'A', position: LatLng(33.1, 73.1)),
          Waypoint(id: 'h', type: WaypointType.hazard, name: 'H', position: LatLng(33.2, 73.2), radiusMeters: 120, notes: 'n'),
        ],
      );

      final decoded = Mission.fromJson(jsonDecode(jsonEncode(mission.toJson())) as Map<String, dynamic>);

      expect(decoded.id, 'm1');
      expect(decoded.name, 'Round trip');
      expect(decoded.createdAt, DateTime.utc(2026, 1, 1));
      expect(decoded.waypoints, hasLength(2));
      expect(decoded.waypoints[1].type, WaypointType.hazard);
      expect(decoded.waypoints[1].radiusMeters, 120);
      expect(decoded.waypoints[1].position.longitude, 73.2);
    });

    test('route excludes hazards', () {
      final mission = Mission(
        id: 'm',
        name: 'n',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        waypoints: const [
          Waypoint(id: '1', type: WaypointType.start, name: 's', position: LatLng(0, 0)),
          Waypoint(id: '2', type: WaypointType.hazard, name: 'h', position: LatLng(1, 1), radiusMeters: 50),
          Waypoint(id: '3', type: WaypointType.end, name: 'e', position: LatLng(0, 0.01)),
        ],
      );
      expect(mission.routePoints.map((w) => w.id), ['1', '3']);
      expect(mission.hazards.map((w) => w.id), ['2']);
    });

    test('rejects invalid data with a FormatException', () {
      expect(() => Waypoint.fromJson({'id': 'x', 'type': 'start', 'lat': 120, 'lng': 0}), throwsFormatException);
      expect(() => Waypoint.fromJson({'id': 'x', 'type': 'teleport', 'lat': 1, 'lng': 1}), throwsFormatException);
      expect(() => Waypoint.fromJson({'type': 'start'}), throwsFormatException);
      expect(() => Mission.fromJson({'name': 'no id'}), throwsFormatException);
      expect(() => Mission.fromJson({'id': 'x', 'name': 'n', 'waypoints': 'nope'}), throwsFormatException);
    });

    test('the bundled sample mission is valid', () {
      final raw = File('assets/sample_mission.json').readAsStringSync();
      final mission = Mission.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(mission.routePoints.length, greaterThanOrEqualTo(2));
      expect(mission.hazards, isNotEmpty);
      expect(mission.routeDistanceMeters, greaterThan(500));
    });
  });
}
