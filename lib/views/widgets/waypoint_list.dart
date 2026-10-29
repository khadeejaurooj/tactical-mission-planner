import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../models/waypoint.dart';
import '../../services/geo_utils.dart';
import '../../viewmodels/mission_view_model.dart';
import 'dialogs.dart';

/// The ordered waypoint list. Drag the handle to reorder: the route follows
/// the list order.
class WaypointList extends StatelessWidget {
  const WaypointList({super.key, required this.mapController});

  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    final mission = vm.activeMission!;
    final theme = Theme.of(context);
    final route = mission.routePoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Stat(
                icon: Icons.place,
                text: '${mission.waypoints.length} point${mission.waypoints.length == 1 ? '' : 's'}',
              ),
              _Stat(icon: Icons.route, text: GeoUtils.formatDistance(mission.routeDistanceMeters)),
              _Stat(
                icon: Icons.warning_amber_rounded,
                text: '${mission.hazards.length} hazard${mission.hazards.length == 1 ? '' : 's'}',
              ),
            ],
          ),
        ),
        Expanded(
          child: mission.waypoints.isEmpty
              ? const _EmptyState()
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: mission.waypoints.length,
                  onReorder: vm.reorderWaypoints,
                  itemBuilder: (context, index) {
                    final w = mission.waypoints[index];
                    final routeIndex = route.indexOf(w);
                    return ListTile(
                      key: ValueKey(w.id),
                      selected: vm.selectedWaypointId == w.id,
                      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      leading: CircleAvatar(
                        backgroundColor: w.type.color,
                        foregroundColor: Colors.white,
                        child: Icon(w.type.icon, size: 20),
                      ),
                      title: Text(w.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _subtitle(w, routeIndex, route),
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => vm.selectWaypoint(w.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Show on map',
                            icon: const Icon(Icons.center_focus_strong, size: 20),
                            onPressed: () {
                              vm.selectWaypoint(w.id);
                              mapController.move(
                                w.position,
                                mapController.camera.zoom < 15 ? 16 : mapController.camera.zoom,
                              );
                            },
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => showEditWaypointDialog(context, w),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => vm.removeWaypoint(w.id),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _subtitle(Waypoint w, int routeIndex, List<Waypoint> route) {
    if (w.type == WaypointType.hazard) return 'Hazard  •  radius ${w.radiusMeters.round()} m';
    final leg = routeIndex > 0 ? GeoUtils.meters(route[routeIndex - 1].position, w.position) : 0.0;
    final base = '${w.type.label}  •  stop ${routeIndex + 1}';
    return leg > 0 ? '$base  •  +${GeoUtils.formatDistance(leg)}' : base;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No waypoints yet.\nDrag Start, Waypoint and End from the palette onto the map to plan a route.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
