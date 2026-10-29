import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/geo_utils.dart';
import '../../viewmodels/mission_view_model.dart';

class MissionsDrawer extends StatelessWidget {
  const MissionsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Missions', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Saved on this device as JSON.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final mission in vm.missions)
                    ListTile(
                      selected: mission.id == vm.activeMission?.id,
                      leading: const Icon(Icons.route),
                      title: Text(mission.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${mission.waypoints.length} points  •  ${GeoUtils.formatDistance(mission.routeDistanceMeters)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete mission',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, vm, mission.id, mission.name),
                      ),
                      onTap: () {
                        vm.selectMission(mission.id);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New mission'),
                  onPressed: () {
                    vm.createMission();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, MissionViewModel vm, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete mission?'),
        content: Text('"$name" will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) vm.deleteMission(id);
  }
}
