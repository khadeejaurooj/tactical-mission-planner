import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/mission.dart';
import '../models/waypoint.dart';
import '../services/geo_utils.dart';
import '../services/location_service.dart';
import '../services/mission_repository.dart';

enum SimulationStatus { idle, running, paused, finished }

enum MapStyle {
  dark('Dark'),
  standard('Standard');

  const MapStyle(this.label);
  final String label;
}

/// Everything the UI needs, with no Flutter widgets involved (MVVM).
class MissionViewModel extends ChangeNotifier {
  MissionViewModel({
    required MissionRepository repository,
    required Future<Mission> Function() sampleLoader,
    LocationService? locationService,
  })  : _repository = repository,
        _sampleLoader = sampleLoader,
        _location = locationService ?? GeolocatorLocationService();

  final MissionRepository _repository;
  final Future<Mission> Function() _sampleLoader;
  final LocationService _location;
  final Random _random = Random();

  bool _disposed = false;
  bool _loading = true;
  List<Mission> _missions = [];
  String? _activeId;
  String? _selectedWaypointId;

  // ---- map interaction ----
  bool tapToAdd = false;
  WaypointType tapType = WaypointType.waypoint;
  MapStyle _mapStyle = MapStyle.dark;

  MapStyle get mapStyle => _mapStyle;

  void toggleMapStyle() {
    _mapStyle = _mapStyle == MapStyle.dark ? MapStyle.standard : MapStyle.dark;
    _notify();
  }

  // ---- simulation ----
  static const double nominalSpeedMps = 15; // 54 km/h
  Timer? _simTimer;
  SimulationStatus _simStatus = SimulationStatus.idle;
  double _traveled = 0;
  double _timeScale = 1;

  // ---- live GPS tracking ----
  StreamSubscription<LocationFix>? _gpsSub;
  bool _tracking = false;
  String? _trackingError;
  LocationFix? _lastFix;
  final List<LatLng> _track = [];

  // ---------------------------------------------------------------- state

  bool get loading => _loading;
  List<Mission> get missions => List.unmodifiable(_missions);
  Mission? get activeMission {
    for (final m in _missions) {
      if (m.id == _activeId) return m;
    }
    return null;
  }

  String? get selectedWaypointId => _selectedWaypointId;
  SimulationStatus get simStatus => _simStatus;
  double get timeScale => _timeScale;
  bool get tracking => _tracking;
  String? get trackingError => _trackingError;
  LocationFix? get lastFix => _lastFix;
  List<LatLng> get track => List.unmodifiable(_track);
  double get trackDistanceMeters => GeoUtils.pathLength(_track);

  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    _missions = await _repository.loadAll();
    if (_missions.isEmpty) {
      _missions = [await _sampleLoader()];
      await _repository.saveAll(_missions);
    }
    _activeId = _missions.first.id;
    _loading = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_repository.saveAll(_missions));
    }
    _simTimer?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Timer? _saveTimer;

  /// Saves shortly after the last change, so dragging a marker (dozens of
  /// updates per second) results in a single write.
  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_repository.saveAll(_missions));
    });
  }

  /// Writes any pending change immediately.
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _repository.saveAll(_missions);
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 20).toRadixString(36)}';

  // ------------------------------------------------------------- missions

  Mission _blankMission(String name) {
    final now = DateTime.now();
    return Mission(id: _newId('mission'), name: name, createdAt: now, updatedAt: now);
  }

  void createMission([String? name]) {
    final mission = _blankMission(name ?? 'Mission ${_missions.length + 1}');
    _missions = [..._missions, mission];
    selectMission(mission.id);
    _persist();
  }

  void selectMission(String id) {
    if (!_missions.any((m) => m.id == id)) return;
    resetSimulation();
    _activeId = id;
    _selectedWaypointId = null;
    _notify();
  }

  void duplicateActiveMission() {
    final source = activeMission;
    if (source == null) return;
    final now = DateTime.now();
    final copy = Mission(
      id: _newId('mission'),
      name: '${source.name} (copy)',
      description: source.description,
      createdAt: now,
      updatedAt: now,
      waypoints: source.waypoints,
    );
    _missions = [..._missions, copy];
    selectMission(copy.id);
    _persist();
  }

  void deleteMission(String id) {
    _missions = _missions.where((m) => m.id != id).toList();
    if (_missions.isEmpty) _missions = [_blankMission('Mission 1')];
    if (_activeId == id) {
      resetSimulation();
      _activeId = _missions.first.id;
      _selectedWaypointId = null;
    }
    _notify();
    _persist();
  }

  void renameActiveMission(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _updateActive((m) => m.copyWith(name: trimmed));
  }

  void _updateActive(Mission Function(Mission) change, {bool routeChanged = false}) {
    final current = activeMission;
    if (current == null) return;
    final updated = change(current);
    _missions = [for (final m in _missions) m.id == current.id ? updated : m];
    if (routeChanged) resetSimulation(notify: false);
    _notify();
    _persist();
  }

  // ------------------------------------------------------------ waypoints

  /// Tap a palette item to arm tap-to-add for that type; tap it again to stop.
  void setTapMode(WaypointType type) {
    if (tapToAdd && tapType == type) {
      tapToAdd = false;
    } else {
      tapToAdd = true;
      tapType = type;
    }
    _notify();
  }

  Waypoint? waypointById(String id) {
    final mission = activeMission;
    if (mission == null) return null;
    for (final w in mission.waypoints) {
      if (w.id == id) return w;
    }
    return null;
  }

  void selectWaypoint(String? id) {
    _selectedWaypointId = id;
    _notify();
  }

  /// Adds a waypoint of [type] at [position].
  ///
  /// A mission has at most one start and one end: dropping a second one moves
  /// the existing one. Other points are inserted before the end point so the
  /// route always finishes at the end.
  void addWaypoint(WaypointType type, LatLng position) {
    final mission = activeMission;
    if (mission == null) return;

    if (type == WaypointType.start || type == WaypointType.end) {
      final existing = mission.waypoints.where((w) => w.type == type);
      if (existing.isNotEmpty) {
        moveWaypoint(existing.first.id, position);
        selectWaypoint(existing.first.id);
        return;
      }
    }

    final count = mission.waypoints.where((w) => w.type == type).length + 1;
    final waypoint = Waypoint(
      id: _newId('wp'),
      type: type,
      name: type == WaypointType.start || type == WaypointType.end ? type.label : '${type.label} $count',
      position: position,
      radiusMeters: type == WaypointType.hazard ? 100 : 0,
    );

    final list = [...mission.waypoints];
    if (type == WaypointType.start) {
      list.insert(0, waypoint);
    } else if (type == WaypointType.waypoint || type == WaypointType.objective) {
      final endIndex = list.indexWhere((w) => w.type == WaypointType.end);
      list.insert(endIndex == -1 ? list.length : endIndex, waypoint);
    } else {
      list.add(waypoint);
    }

    _selectedWaypointId = waypoint.id;
    _updateActive((m) => m.copyWith(waypoints: list), routeChanged: type.isOnRoute);
  }

  void moveWaypoint(String id, LatLng position) {
    final waypoint = waypointById(id);
    if (waypoint == null) return;
    _replaceWaypoint(waypoint.copyWith(position: position), routeChanged: waypoint.type.isOnRoute);
  }

  void updateWaypoint(String id, {String? name, String? notes, double? radiusMeters}) {
    final waypoint = waypointById(id);
    if (waypoint == null) return;
    _replaceWaypoint(
      waypoint.copyWith(
        name: name?.trim().isEmpty == true ? waypoint.name : name?.trim(),
        notes: notes,
        radiusMeters: radiusMeters == null ? null : max(0, radiusMeters),
      ),
      routeChanged: false,
    );
  }

  void _replaceWaypoint(Waypoint replacement, {required bool routeChanged}) {
    _updateActive(
      (m) => m.copyWith(
        waypoints: [for (final w in m.waypoints) w.id == replacement.id ? replacement : w],
      ),
      routeChanged: routeChanged,
    );
  }

  void removeWaypoint(String id) {
    final waypoint = waypointById(id);
    if (waypoint == null) return;
    if (_selectedWaypointId == id) _selectedWaypointId = null;
    _updateActive(
      (m) => m.copyWith(waypoints: m.waypoints.where((w) => w.id != id).toList()),
      routeChanged: waypoint.type.isOnRoute,
    );
  }

  /// [newIndex] follows the ReorderableListView convention.
  void reorderWaypoints(int oldIndex, int newIndex) {
    final mission = activeMission;
    if (mission == null) return;
    final list = [...mission.waypoints];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, list.length - 1);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _updateActive((m) => m.copyWith(waypoints: list), routeChanged: true);
  }

  void clearWaypoints() {
    _selectedWaypointId = null;
    _updateActive((m) => m.copyWith(waypoints: const []), routeChanged: true);
  }

  // ------------------------------------------------------------ JSON data

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  String exportActiveMissionJson() {
    final mission = activeMission;
    return mission == null ? '{}' : _pretty.convert(mission.toJson());
  }

  String exportAllMissionsJson() => _pretty.convert({
        'schemaVersion': Mission.schemaVersion,
        'missions': _missions.map((m) => m.toJson()).toList(),
      });

  /// Imports one mission, a list of missions or `{ "missions": [...] }`.
  /// Returns the number of missions added. Throws [FormatException] with a
  /// readable message when the JSON is not valid mission data.
  int importMissionsJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException('That is not valid JSON (${e.message}).');
    }

    final List<Object?> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['missions'] is List) {
      items = decoded['missions'] as List;
    } else if (decoded is Map && decoded.containsKey('waypoints')) {
      items = [decoded];
    } else {
      throw const FormatException('Expected a mission, a list of missions or {"missions": [...]}.');
    }
    if (items.isEmpty) throw const FormatException('The file contains no missions.');

    final taken = _missions.map((m) => m.id).toSet();
    final imported = <Mission>[];
    for (final item in items) {
      if (item is! Map) throw const FormatException('Every mission must be a JSON object.');
      final mission = Mission.fromJson(Map<String, dynamic>.from(item));
      final id = taken.contains(mission.id) ? _newId('mission') : mission.id;
      taken.add(id);
      imported.add(Mission(
        id: id,
        name: mission.name,
        description: mission.description,
        createdAt: mission.createdAt,
        updatedAt: mission.updatedAt,
        waypoints: mission.waypoints,
      ));
    }

    _missions = [..._missions, ...imported];
    selectMission(imported.first.id);
    _persist();
    return imported.length;
  }

  // ------------------------------------------------------------ simulation

  List<LatLng> get _route => activeMission?.routeLatLngs ?? const [];
  double get routeLengthMeters => GeoUtils.pathLength(_route);
  bool get canSimulate => _route.length >= 2;
  double get distanceTraveledMeters => _traveled;
  double get distanceRemainingMeters => max(0, routeLengthMeters - _traveled);
  double get progress => routeLengthMeters == 0 ? 0 : (_traveled / routeLengthMeters).clamp(0, 1).toDouble();
  Duration get eta => Duration(seconds: (distanceRemainingMeters / nominalSpeedMps).round());

  PathSample? get _sample => GeoUtils.sampleAlong(_route, _traveled);
  LatLng? get simPosition => _simStatus == SimulationStatus.idle && _traveled == 0 ? null : _sample?.position;

  /// The part of the route already covered by the simulated asset.
  List<LatLng> get progressPath {
    final position = simPosition;
    final sample = _sample;
    if (position == null || sample == null || !canSimulate) return const [];
    return [..._route.sublist(0, sample.segmentIndex + 1), position];
  }
  double get simHeading => _sample?.bearingDegrees ?? 0;

  Waypoint? get nextWaypoint {
    final mission = activeMission;
    final sample = _sample;
    if (mission == null || sample == null || !canSimulate) return null;
    final points = mission.routePoints;
    final index = (sample.segmentIndex + 1).clamp(0, points.length - 1);
    return points[index];
  }

  double get distanceToNextMeters {
    final sample = _sample;
    if (sample == null || !canSimulate) return 0;
    final index = (sample.segmentIndex + 1).clamp(0, _route.length - 1);
    return max(0, GeoUtils.distanceToVertex(_route, index) - _traveled);
  }

  /// Hazards the simulated asset is currently inside of.
  List<Waypoint> get simHazardAlerts => _hazardsAround(simPosition);

  /// Hazards the live GPS position is currently inside of.
  List<Waypoint> get liveHazardAlerts => _hazardsAround(_lastFix?.position);

  List<Waypoint> _hazardsAround(LatLng? position) {
    final mission = activeMission;
    if (mission == null || position == null) return const [];
    return mission.hazards.where((h) => GeoUtils.meters(position, h.position) <= h.radiusMeters).toList();
  }

  void startSimulation() {
    if (!canSimulate) return;
    if (_simStatus == SimulationStatus.finished) _traveled = 0;
    _simStatus = SimulationStatus.running;
    _simTimer?.cancel();
    const tick = Duration(milliseconds: 100);
    _simTimer = Timer.periodic(tick, (_) {
      _traveled += nominalSpeedMps * _timeScale * (tick.inMilliseconds / 1000);
      if (_traveled >= routeLengthMeters) {
        _traveled = routeLengthMeters;
        _simStatus = SimulationStatus.finished;
        _simTimer?.cancel();
      }
      _notify();
    });
    _notify();
  }

  void pauseSimulation() {
    if (_simStatus != SimulationStatus.running) return;
    _simTimer?.cancel();
    _simStatus = SimulationStatus.paused;
    _notify();
  }

  void resetSimulation({bool notify = true}) {
    _simTimer?.cancel();
    _simStatus = SimulationStatus.idle;
    _traveled = 0;
    if (notify) _notify();
  }

  void setTimeScale(double scale) {
    _timeScale = scale;
    _notify();
  }

  /// Jumps the simulation to [fraction] (0..1) of the route.
  void scrub(double fraction) {
    if (!canSimulate) return;
    _traveled = routeLengthMeters * fraction.clamp(0, 1);
    if (_simStatus == SimulationStatus.idle || _simStatus == SimulationStatus.finished) {
      _simStatus = SimulationStatus.paused;
    }
    _notify();
  }

  // ---------------------------------------------------------- live tracking

  Future<void> toggleTracking() async {
    if (_tracking) {
      await _stopTracking();
      return;
    }
    _trackingError = null;
    try {
      final stream = await _location.start();
      _tracking = true;
      _track.clear();
      _gpsSub = stream.listen(
        (fix) {
          _lastFix = fix;
          _track.add(fix.position);
          _notify();
        },
        onError: (Object error) async {
          _trackingError = error.toString();
          await _stopTracking();
        },
      );
    } on LocationException catch (e) {
      _trackingError = e.message;
    } on Object catch (e) {
      _trackingError = 'Could not start tracking: $e';
    }
    _notify();
  }

  Future<void> _stopTracking() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    _tracking = false;
    _notify();
  }

  void clearTrack() {
    _track.clear();
    _lastFix = null;
    _notify();
  }

  void clearTrackingError() {
    _trackingError = null;
    _notify();
  }
}
