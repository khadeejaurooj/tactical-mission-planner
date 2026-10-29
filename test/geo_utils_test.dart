import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_mission_planner/services/geo_utils.dart';

void main() {
  const a = LatLng(33.0, 73.0);
  const b = LatLng(33.0, 73.01); // roughly 930 m east of a
  const c = LatLng(33.01, 73.01); // roughly 1.1 km north of b

  group('GeoUtils', () {
    test('meters is symmetric and close to the expected distance', () {
      expect(GeoUtils.meters(a, b), closeTo(GeoUtils.meters(b, a), 0.001));
      expect(GeoUtils.meters(a, b), inInclusiveRange(900, 960));
    });

    test('pathLength sums every segment', () {
      expect(GeoUtils.pathLength([a]), 0);
      expect(GeoUtils.pathLength([a, b, c]), closeTo(GeoUtils.meters(a, b) + GeoUtils.meters(b, c), 0.001));
    });

    test('bearing points east then north', () {
      expect(GeoUtils.bearing(a, b), closeTo(90, 1));
      expect(GeoUtils.bearing(b, c), closeTo(0, 1));
    });

    test('sampleAlong returns the start, a midpoint and the clamped end', () {
      final path = [a, b, c];
      expect(GeoUtils.sampleAlong(const [], 10), isNull);

      final start = GeoUtils.sampleAlong(path, 0)!;
      expect(GeoUtils.meters(start.position, a), lessThan(0.5));
      expect(start.segmentIndex, 0);

      final firstLeg = GeoUtils.meters(a, b);
      final mid = GeoUtils.sampleAlong(path, firstLeg / 2)!;
      expect(GeoUtils.meters(mid.position, a), closeTo(firstLeg / 2, 1));
      expect(mid.bearingDegrees, closeTo(90, 1));

      final secondLeg = GeoUtils.sampleAlong(path, firstLeg + 100)!;
      expect(secondLeg.segmentIndex, 1);
      expect(secondLeg.bearingDegrees, closeTo(0, 1));

      final end = GeoUtils.sampleAlong(path, 1e9)!;
      expect(GeoUtils.meters(end.position, c), lessThan(1));
    });

    test('distanceToVertex', () {
      final path = [a, b, c];
      expect(GeoUtils.distanceToVertex(path, 0), 0);
      expect(GeoUtils.distanceToVertex(path, 1), closeTo(GeoUtils.meters(a, b), 0.001));
      expect(GeoUtils.distanceToVertex(path, 2), closeTo(GeoUtils.pathLength(path), 0.001));
    });

    test('formatters', () {
      expect(GeoUtils.formatDistance(850), '850 m');
      expect(GeoUtils.formatDistance(1500), '1.50 km');
      expect(GeoUtils.formatDuration(const Duration(seconds: 75)), '01:15');
      expect(GeoUtils.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(GeoUtils.formatBearing(0), '0° N');
      expect(GeoUtils.formatBearing(92), '92° E');
      expect(GeoUtils.formatBearing(359), '359° N');
    });
  });
}
