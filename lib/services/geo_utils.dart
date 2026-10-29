import 'package:latlong2/latlong.dart';

/// A point on a path together with the direction of travel there.
class PathSample {
  const PathSample(this.position, this.bearingDegrees, this.segmentIndex);

  final LatLng position;

  /// Compass bearing, 0 = north, clockwise, in the range 0..360.
  final double bearingDegrees;

  /// Index of the segment (point i -> i+1) the sample lies on.
  final int segmentIndex;
}

/// Small geospatial helpers built on top of latlong2.
class GeoUtils {
  GeoUtils._();

  static const Distance _distance = Distance();

  static double meters(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

  static double bearing(LatLng a, LatLng b) {
    final value = _distance.bearing(a, b);
    return (value % 360 + 360) % 360;
  }

  static double pathLength(List<LatLng> path) {
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += meters(path[i], path[i + 1]);
    }
    return total;
  }

  /// The point [distanceMeters] along [path], clamped to the path ends.
  /// Returns null for an empty path.
  static PathSample? sampleAlong(List<LatLng> path, double distanceMeters) {
    if (path.isEmpty) return null;
    if (path.length == 1) return PathSample(path.first, 0, 0);

    var remaining = distanceMeters < 0 ? 0.0 : distanceMeters;
    for (var i = 0; i < path.length - 1; i++) {
      final segment = meters(path[i], path[i + 1]);
      final heading = bearing(path[i], path[i + 1]);
      if (remaining <= segment || i == path.length - 2) {
        final along = remaining > segment ? segment : remaining;
        final position = segment == 0
            ? path[i]
            : _distance.offset(path[i], along, heading);
        return PathSample(position, heading, i);
      }
      remaining -= segment;
    }
    return PathSample(path.last, 0, path.length - 2);
  }

  /// Distance along [path] to the start of its vertex [index].
  static double distanceToVertex(List<LatLng> path, int index) {
    var total = 0.0;
    for (var i = 0; i < index && i < path.length - 1; i++) {
      total += meters(path[i], path[i + 1]);
    }
    return total;
  }

  static String formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.round()} m';
  }

  static String formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  static String formatBearing(double degrees) {
    const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) % 360 ~/ 45);
    return '${degrees.round()}° ${points[index]}';
  }
}
