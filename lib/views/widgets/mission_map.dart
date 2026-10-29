import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/mission.dart';
import '../../models/waypoint.dart';
import '../../services/geo_utils.dart';
import '../../viewmodels/mission_view_model.dart';

/// Pointer position inside the 44px drag feedback, so a drop lands exactly
/// under the finger / cursor.
const Offset _feedbackAnchor = Offset(22, 22);

/// Turns the standard OpenStreetMap tiles into a dark map: invert, then rotate
/// the hue back (the usual "dark mode for raster maps" trick), slightly dimmed.
/// It needs no API key, unlike most hosted dark basemaps.
const ColorFilter _darkMapFilter = ColorFilter.matrix(<double>[
  0.5166, -1.287, -0.1296, 0, 229.5, //
  -0.3834, -0.387, -0.1296, 0, 229.5, //
  -0.3834, -1.287, 0.7704, 0, 229.5, //
  0, 0, 0, 1, 0,
]);

class MissionMap extends StatefulWidget {
  const MissionMap({super.key, required this.controller});

  final MapController controller;

  @override
  State<MissionMap> createState() => _MissionMapState();
}

class _MissionMapState extends State<MissionMap> {
  static const LatLng _fallbackCenter = LatLng(33.6844, 73.0479);
  static const EdgeInsets _fitPaddingWide = EdgeInsets.fromLTRB(120, 80, 90, 240);
  static const EdgeInsets _fitPaddingNarrow = EdgeInsets.fromLTRB(44, 112, 44, 170);

  final GlobalKey _mapKey = GlobalKey();
  bool _ready = false;
  String? _fittedMissionId;
  double _zoom = 14;

  LatLng _toLatLng(Offset globalPosition) {
    final box = _mapKey.currentContext!.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    return widget.controller.camera.screenOffsetToLatLng(local);
  }

  CameraFit? _fitFor(List<LatLng> points, {required bool narrow}) {
    if (points.length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: narrow ? _fitPaddingNarrow : _fitPaddingWide,
      maxZoom: 17,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    final mission = vm.activeMission!;
    final points = [for (final w in mission.waypoints) w.position];

    final primary = Theme.of(context).colorScheme.primary;
    final alerts = [...vm.simHazardAlerts, ...vm.liveHazardAlerts];
    final dark = vm.mapStyle == MapStyle.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;

        if (_ready && _fittedMissionId != mission.id) {
          _fittedMissionId = mission.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final fit = _fitFor(points, narrow: narrow);
            if (fit != null) {
              widget.controller.fitCamera(fit);
            } else if (points.length == 1) {
              widget.controller.move(points.first, 16);
            }
          });
        }

        return Stack(
          children: [
            DragTarget<WaypointType>(
              onAcceptWithDetails: (details) =>
                  vm.addWaypoint(details.data, _toLatLng(details.offset + _feedbackAnchor)),
              builder: (context, candidates, _) => DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: candidates.isEmpty ? null : Border.all(color: primary, width: 3),
                ),
                child: FlutterMap(
                  key: _mapKey,
                  mapController: widget.controller,
                  options: MapOptions(
                    backgroundColor: dark ? const Color(0xFF0E1214) : const Color(0xFFDDDDDD),
                    initialCenter: points.isEmpty ? _fallbackCenter : points.first,
                    initialZoom: 14,
                    initialCameraFit: _fitFor(points, narrow: narrow),
                    minZoom: 3,
                    maxZoom: 19,
                    onMapReady: () {
                      _ready = true;
                      _fittedMissionId = mission.id;
                    },
                    onPositionChanged: (camera, _) {
                      if ((camera.zoom - _zoom).abs() > 0.25) setState(() => _zoom = camera.zoom);
                    },
                    onTap: (tap, point) {
                      if (vm.tapToAdd) {
                        vm.addWaypoint(vm.tapType, point);
                      } else {
                        vm.selectWaypoint(null);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.khadeeja.tactical_mission_planner',
                      tileBuilder: dark
                          ? (context, tileWidget, tile) => ColorFiltered(colorFilter: _darkMapFilter, child: tileWidget)
                          : null,
                    ),
                    CircleLayer(circles: _hazardCircles(mission, vm)),
                    PolylineLayer(polylines: _polylines(mission, vm)),
                    MarkerLayer(markers: _markers(vm, mission)),
                    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
              ),
            ),
            if (narrow)
              Positioned(left: 8, right: 8, top: 8, child: _Palette(vm: vm, horizontal: true))
            else
              Positioned(left: 12, top: 12, child: _Palette(vm: vm, horizontal: false)),
            if (alerts.isNotEmpty)
              Positioned(
                top: narrow ? 92 : 12,
                left: narrow ? 8 : 112,
                right: 8,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _AlertBanner(names: alerts.map((h) => h.name).toSet().toList()),
                ),
              ),
            Positioned(
              left: narrow ? 8 : 112,
              right: 8,
              bottom: 28,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _SimulationCard(vm: vm, compact: narrow),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<CircleMarker> _hazardCircles(Mission mission, MissionViewModel vm) {
    return [
      for (final hazard in mission.hazards)
        CircleMarker(
          point: hazard.position,
          radius: hazard.radiusMeters,
          useRadiusInMeter: true,
          color: WaypointType.hazard.color.withValues(alpha: 0.22),
          borderColor: WaypointType.hazard.color,
          borderStrokeWidth: 2,
        ),
      if (vm.lastFix != null && vm.lastFix!.accuracyMeters > 0)
        CircleMarker(
          point: vm.lastFix!.position,
          radius: vm.lastFix!.accuracyMeters,
          useRadiusInMeter: true,
          color: Colors.blue.withValues(alpha: 0.12),
          borderColor: Colors.blue.withValues(alpha: 0.5),
          borderStrokeWidth: 1,
        ),
    ];
  }

  List<Polyline> _polylines(Mission mission, MissionViewModel vm) {
    final route = mission.routeLatLngs;
    return [
      if (route.length >= 2)
        Polyline(
          points: route,
          strokeWidth: 5,
          color: const Color(0xFF1DE9B6),
          borderStrokeWidth: 2,
          borderColor: Colors.black87,
        ),
      if (vm.progressPath.length >= 2)
        Polyline(points: vm.progressPath, strokeWidth: 5, color: Colors.orangeAccent),
      if (vm.track.length >= 2)
        Polyline(points: vm.track, strokeWidth: 4, color: Colors.blueAccent),
    ];
  }

  List<Marker> _markers(MissionViewModel vm, Mission mission) {
    final route = mission.routePoints;
    final simPosition = vm.simPosition;
    final fix = vm.lastFix;
    return [
      for (final w in mission.waypoints)
        Marker(
          point: w.position,
          width: 46,
          height: 46,
          child: _WaypointBadge(
            waypoint: w,
            routeNumber: w.type == WaypointType.waypoint ? route.indexOf(w) + 1 : null,
            selected: vm.selectedWaypointId == w.id,
            showLabel: _zoom >= 13.5 || vm.selectedWaypointId == w.id,
            onTap: () => vm.selectWaypoint(w.id),
            onDragStart: () => vm.selectWaypoint(w.id),
            onDrag: (global) => vm.moveWaypoint(w.id, _toLatLng(global)),
          ),
        ),
      if (simPosition != null)
        Marker(
          point: simPosition,
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: vm.simHeading * math.pi / 180,
            child: const Icon(
              Icons.navigation,
              size: 36,
              color: Colors.cyanAccent,
              shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ),
      if (fix != null)
        Marker(
          point: fix.position,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
    ];
  }
}

class _WaypointBadge extends StatelessWidget {
  const _WaypointBadge({
    required this.waypoint,
    required this.routeNumber,
    required this.selected,
    required this.showLabel,
    required this.onTap,
    required this.onDragStart,
    required this.onDrag,
  });

  final Waypoint waypoint;
  final int? routeNumber;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (details) => onDrag(details.globalPosition),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: selected ? 42 : 36,
              height: selected ? 42 : 36,
              decoration: BoxDecoration(
                color: waypoint.type.color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : Colors.black87, width: selected ? 3 : 2),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black87)],
              ),
              child: Center(
                child: routeNumber != null
                    ? Text(
                        '$routeNumber',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : Icon(waypoint.type.icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
        if (showLabel)
          Positioned(
            top: 44,
            left: -50,
            right: -50,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: waypoint.type.color.withValues(alpha: 0.9)),
                  ),
                  child: Text(
                    waypoint.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The set of things that can be placed on the map. Drag one onto the map,
/// or tap one and then tap the map.
class _Palette extends StatelessWidget {
  const _Palette({required this.vm, required this.horizontal});

  final MissionViewModel vm;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final items = [for (final type in WaypointType.values) _PaletteItem(type: type, vm: vm)];
    final hint = vm.tapToAdd ? 'Tap the map' : 'Drag onto map';
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ADD TO MAP', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(
          hint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: horizontal ? 10 : null,
                color: vm.tapToAdd ? Theme.of(context).colorScheme.primary : null,
              ),
        ),
      ],
    );

    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: horizontal
            ? Row(
                children: [
                  heading,
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: items),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [heading, const SizedBox(height: 6), ...items],
              ),
      ),
    );
  }
}

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.type, required this.vm});

  final WaypointType type;
  final MissionViewModel vm;

  Widget _chip(BuildContext context, {double opacity = 1}) {
    final active = vm.tapToAdd && vm.tapType == type;
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1),
        child: SizedBox(
          width: 54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: type.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: active ? Colors.white : Colors.transparent, width: 3),
                ),
                child: Icon(type.icon, color: Colors.white, size: 22),
              ),
              Text(type.label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Drag ${type.label} onto the map, or tap it and then tap the map',
      child: Draggable<WaypointType>(
        data: type,
        dragAnchorStrategy: (draggable, context, position) => _feedbackAnchor,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: type.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
            ),
            child: Icon(type.icon, color: Colors.white),
          ),
        ),
        childWhenDragging: _chip(context, opacity: 0.35),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => vm.setTapMode(type),
          child: _chip(context),
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WaypointType.hazard.color,
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Inside hazard zone: ${names.join(', ')}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the planned route as a simulated asset. Labelled controls, so it
/// reads as a mission tool rather than a media player.
class _SimulationCard extends StatelessWidget {
  const _SimulationCard({required this.vm, required this.compact});

  final MissionViewModel vm;

  /// Phone layout: fewer rows, so the map keeps most of the screen.
  final bool compact;

  String get _statusLabel => switch (vm.simStatus) {
        SimulationStatus.idle => 'Ready',
        SimulationStatus.running => 'Running',
        SimulationStatus.paused => 'Paused',
        SimulationStatus.finished => 'Arrived',
      };

  String get _primaryLabel => switch (vm.simStatus) {
        SimulationStatus.idle => 'Run simulation',
        SimulationStatus.running => 'Pause',
        SimulationStatus.paused => 'Resume',
        SimulationStatus.finished => 'Run again',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = vm.simStatus == SimulationStatus.running;

    if (!vm.canSimulate) {
      return Card(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.touch_app, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Drag a Start and an End onto the map to plan a route, then run the simulation.'),
              ),
            ],
          ),
        ),
      );
    }

    final primaryButton = FilledButton.icon(
      onPressed: running ? vm.pauseSimulation : vm.startSimulation,
      icon: Icon(running ? Icons.pause : Icons.play_arrow),
      label: Text(_primaryLabel),
    );
    final resetButton = OutlinedButton(
      onPressed: vm.simStatus == SimulationStatus.idle ? null : vm.resetSimulation,
      child: const Text('Reset'),
    );

    final speed = compact
        ? PopupMenuButton<double>(
            tooltip: 'Simulation speed',
            initialValue: vm.timeScale,
            onSelected: vm.setTimeScale,
            itemBuilder: (_) => [
              for (final s in const [1.0, 2.0, 5.0, 10.0]) PopupMenuItem(value: s, child: Text('${s.toInt()}x speed')),
            ],
            child: Chip(
              avatar: const Icon(Icons.speed, size: 18),
              label: Text('${vm.timeScale.toInt()}x'),
              visualDensity: VisualDensity.compact,
            ),
          )
        : SegmentedButton<double>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 1, label: Text('1x')),
              ButtonSegment(value: 2, label: Text('2x')),
              ButtonSegment(value: 5, label: Text('5x')),
              ButtonSegment(value: 10, label: Text('10x')),
            ],
            selected: {vm.timeScale},
            onSelectionChanged: (s) => vm.setTimeScale(s.first),
          );

    final covered =
        '${GeoUtils.formatDistance(vm.distanceTraveledMeters)} of ${GeoUtils.formatDistance(vm.routeLengthMeters)} covered';

    return Card(
      elevation: 6,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 14, compact ? 10 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.moving, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Mission simulation', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (compact)
                  Text(
                    '$_statusLabel  •  ${(vm.progress * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: running ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Chip(
                    label: Text(_statusLabel),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: running ? theme.colorScheme.primaryContainer : null,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: vm.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            if (!compact) ...[
              const SizedBox(height: 4),
              Text(
                covered,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            SizedBox(height: compact ? 8 : 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [primaryButton, resetButton, speed],
            ),
          ],
        ),
      ),
    );
  }
}
