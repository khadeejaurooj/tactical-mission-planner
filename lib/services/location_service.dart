import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One GPS reading.
class LocationFix {
  const LocationFix(this.position, this.accuracyMeters, this.speedMps, this.timestamp);

  final LatLng position;
  final double accuracyMeters;
  final double speedMps;
  final DateTime timestamp;
}

/// Source of live device positions. Abstract so the view model can be tested
/// without a GPS.
abstract class LocationService {
  /// Checks permissions and returns a stream of fixes.
  /// Throws [LocationException] with a readable message if that is not possible.
  Future<Stream<LocationFix>> start();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<Stream<LocationFix>> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Location services are turned off on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is blocked. Enable it in the system settings.',
      );
    }

    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3);
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => LocationFix(
        LatLng(p.latitude, p.longitude),
        p.accuracy,
        p.speed < 0 ? 0 : p.speed,
        p.timestamp,
      ),
    );
  }
}
