import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_mission_planner/models/mission.dart';
import 'package:tactical_mission_planner/models/waypoint.dart';
import 'package:tactical_mission_planner/services/location_service.dart';
import 'package:tactical_mission_planner/services/mission_repository.dart';
import 'package:tactical_mission_planner/viewmodels/mission_view_model.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({this.error});

  final LocationException? error;
  final StreamController<LocationFix> controller = StreamController<LocationFix>.broadcast();

  @override
  Future<Stream<LocationFix>> start() async {
    if (error != null) throw error!;
    return controller.stream;
  }
}

Mission _empty() => Mission(
      id: 'seed',
      name: 'Seed',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Future<MissionViewModel> _vm({
  MissionRepository? repository,
  LocationService? location,
  Mission? seed,
}) async {
  final vm = MissionViewModel(
    repository: repository ?? InMemoryMissionRepository(),
    sampleLoader: () async => seed ?? _empty(),
    locationService: location ?? FakeLocationService(),
  );
  await vm.init();
  return vm;
}

void main() {
  const start = LatLng(33.0, 73.0);
  const middle = LatLng(33.0, 73.005);
  const end = LatLng(33.0, 73.01);

  group('planning', () {
    test('first launch loads the sample mission and saves it', () async {
      final repo = InMemoryMissionRepository();
      final vm = await _vm(repository: repo);
      expect(vm.activeMission!.id, 'seed');
      expect((await repo.loadAll()).single.id, 'seed');
    });

    test('route points are inserted before End, start goes first', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.end, end);
      vm.addWaypoint(WaypointType.waypoint, middle);
      vm.addWaypoint(WaypointType.start, start);

      final names = vm.activeMission!.waypoints.map((w) => w.type).toList();
      expect(names, [WaypointType.start, WaypointType.waypoint, WaypointType.end]);
      expect(vm.canSimulate, isTrue);
    });

    test('dropping a second Start or End moves the existing one', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      vm.addWaypoint(WaypointType.start, middle);

      final starts = vm.activeMission!.waypoints.where((w) => w.type == WaypointType.start);
      expect(starts, hasLength(1));
      expect(starts.single.position, middle);
    });

    test('hazards get a default radius and stay off the route', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      vm.addWaypoint(WaypointType.hazard, middle);
      vm.addWaypoint(WaypointType.end, end);

      expect(vm.activeMission!.hazards.single.radiusMeters, 100);
      expect(vm.activeMission!.routePoints, hasLength(2));
    });

    test('move, edit, reorder and remove', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      vm.addWaypoint(WaypointType.waypoint, middle);
      vm.addWaypoint(WaypointType.end, end);
      final waypointId = vm.activeMission!.waypoints[1].id;

      vm.moveWaypoint(waypointId, const LatLng(33.001, 73.004));
      expect(vm.waypointById(waypointId)!.position.latitude, 33.001);

      vm.updateWaypoint(waypointId, name: '  Renamed  ', notes: 'hi');
      expect(vm.waypointById(waypointId)!.name, 'Renamed');
      expect(vm.waypointById(waypointId)!.notes, 'hi');
      vm.updateWaypoint(waypointId, name: '   ');
      expect(vm.waypointById(waypointId)!.name, 'Renamed', reason: 'blank names are ignored');

      // ReorderableListView convention: moving index 0 to "3" puts it last.
      vm.reorderWaypoints(0, 3);
      expect(vm.activeMission!.waypoints.last.type, WaypointType.start);

      vm.removeWaypoint(waypointId);
      expect(vm.waypointById(waypointId), isNull);
    });

    test('changes are persisted as JSON', () async {
      final repo = InMemoryMissionRepository();
      final vm = await _vm(repository: repo);
      vm.addWaypoint(WaypointType.start, start);
      await vm.flush();

      final saved = await repo.loadAll();
      expect(saved.single.waypoints.single.type, WaypointType.start);
    });

    test('deleting the last mission leaves a blank one', () async {
      final vm = await _vm();
      vm.deleteMission('seed');
      expect(vm.missions, hasLength(1));
      expect(vm.activeMission!.name, 'Mission 1');
    });
  });

  test('the map style toggles between dark and standard', () async {
    final vm = await _vm();
    expect(vm.mapStyle, MapStyle.dark);
    vm.toggleMapStyle();
    expect(vm.mapStyle, MapStyle.standard);
    vm.toggleMapStyle();
    expect(vm.mapStyle, MapStyle.dark);
  });

  group('JSON import / export', () {
    test('export then import creates a copy with a fresh id', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      vm.addWaypoint(WaypointType.end, end);

      final json = vm.exportActiveMissionJson();
      expect(jsonDecode(json)['schemaVersion'], 1);

      expect(vm.importMissionsJson(json), 1);
      expect(vm.missions, hasLength(2));
      expect(vm.missions.map((m) => m.id).toSet(), hasLength(2));
      expect(vm.activeMission!.waypoints, hasLength(2));
    });

    test('accepts a list and a {"missions": []} document', () async {
      final vm = await _vm();
      final one = jsonDecode(vm.exportActiveMissionJson()) as Map<String, dynamic>;
      expect(vm.importMissionsJson(jsonEncode([one, one])), 2);
      expect(vm.importMissionsJson(vm.exportAllMissionsJson()), 3);
    });

    test('rejects bad input with readable errors', () async {
      final vm = await _vm();
      expect(() => vm.importMissionsJson('{not json'), throwsA(isA<FormatException>()));
      expect(() => vm.importMissionsJson('42'), throwsA(isA<FormatException>()));
      expect(() => vm.importMissionsJson('[]'), throwsA(isA<FormatException>()));
      expect(() => vm.importMissionsJson('[1]'), throwsA(isA<FormatException>()));
      expect(
        () => vm.importMissionsJson('{"id":"x","name":"n","waypoints":[{"id":"w","type":"start","lat":999,"lng":0}]}'),
        throwsA(isA<FormatException>()),
      );
      expect(vm.missions, hasLength(1), reason: 'a failed import must not change anything');
    });
  });

  group('simulation', () {
    Future<MissionViewModel> routed() async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      vm.addWaypoint(WaypointType.hazard, middle);
      vm.addWaypoint(WaypointType.end, end);
      return vm;
    }

    test('scrub moves the asset along the route and reports telemetry', () async {
      final vm = await routed();
      vm.scrub(0.5);

      expect(vm.progress, closeTo(0.5, 0.001));
      expect(vm.distanceRemainingMeters, closeTo(vm.routeLengthMeters / 2, 1));
      expect(vm.simHeading, closeTo(90, 1));
      expect(vm.nextWaypoint!.type, WaypointType.end);
      expect(vm.simStatus, SimulationStatus.paused);
    });

    test('the asset triggers a hazard alert inside the radius only', () async {
      final vm = await routed();
      vm.scrub(0.5); // directly on top of the hazard (the route midpoint)
      expect(vm.simHazardAlerts.single.type, WaypointType.hazard);

      vm.scrub(0.0);
      expect(vm.simHazardAlerts, isEmpty);
    });

    test('running to the end finishes, and play after finish restarts', () async {
      final vm = await routed();
      vm.setTimeScale(10);
      vm.startSimulation();
      expect(vm.simStatus, SimulationStatus.running);

      // 10x at 15 m/s = 150 m/s, so a ~710 m route ends within ~5 s.
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while (vm.simStatus != SimulationStatus.finished && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.simStatus, SimulationStatus.finished);
      expect(vm.progress, 1);
      expect(vm.distanceRemainingMeters, 0);

      vm.pauseSimulation(); // no-op once finished
      expect(vm.simStatus, SimulationStatus.finished);

      vm.resetSimulation();
      expect(vm.simStatus, SimulationStatus.idle);
      expect(vm.simPosition, isNull);
      vm.dispose();
    });

    test('editing the route resets the simulation', () async {
      final vm = await routed();
      vm.scrub(0.7);
      vm.moveWaypoint(vm.activeMission!.routePoints.last.id, const LatLng(33.0, 73.02));
      expect(vm.progress, 0);
      expect(vm.simStatus, SimulationStatus.idle);
    });

    test('a route needs two points', () async {
      final vm = await _vm();
      vm.addWaypoint(WaypointType.start, start);
      expect(vm.canSimulate, isFalse);
      vm.startSimulation();
      expect(vm.simStatus, SimulationStatus.idle);
    });
  });

  group('live tracking', () {
    test('records fixes and flags hazards the device is inside', () async {
      final location = FakeLocationService();
      final vm = await _vm(location: location);
      vm.addWaypoint(WaypointType.hazard, middle);

      await vm.toggleTracking();
      expect(vm.tracking, isTrue);

      location.controller.add(LocationFix(start, 5, 1.5, DateTime.now()));
      location.controller.add(LocationFix(middle, 5, 1.5, DateTime.now()));
      await Future<void>.delayed(Duration.zero);

      expect(vm.track, hasLength(2));
      expect(vm.trackDistanceMeters, greaterThan(300));
      expect(vm.liveHazardAlerts, hasLength(1));

      await vm.toggleTracking();
      expect(vm.tracking, isFalse);
      vm.clearTrack();
      expect(vm.track, isEmpty);
    });

    test('a denied permission becomes a readable error, not a crash', () async {
      final vm = await _vm(location: FakeLocationService(error: const LocationException('Location permission was denied.')));
      await vm.toggleTracking();
      expect(vm.tracking, isFalse);
      expect(vm.trackingError, 'Location permission was denied.');
      vm.clearTrackingError();
      expect(vm.trackingError, isNull);
    });
  });
}
