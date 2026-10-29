import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../services/geo_utils.dart';
import '../viewmodels/mission_view_model.dart';
import 'widgets/dialogs.dart';
import 'widgets/mission_map.dart';
import 'widgets/mission_panel.dart';
import 'widgets/missions_drawer.dart';

enum _MenuAction { rename, duplicate, mapStyle, importJson, exportAll, clear }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _onMenu(_MenuAction action, MissionViewModel vm) async {
    switch (action) {
      case _MenuAction.rename:
        final name = await promptText(
          context,
          title: 'Rename mission',
          label: 'Mission name',
          initial: vm.activeMission?.name ?? '',
        );
        if (name != null) vm.renameActiveMission(name);
      case _MenuAction.duplicate:
        vm.duplicateActiveMission();
      case _MenuAction.mapStyle:
        vm.toggleMapStyle();
      case _MenuAction.importJson:
        await showImportDialog(context);
      case _MenuAction.exportAll:
        await showExportDialog(context, vm.exportAllMissionsJson(), title: 'All missions (JSON)');
      case _MenuAction.clear:
        vm.clearWaypoints();
    }
  }

  void _surfaceTrackingError(MissionViewModel vm) {
    final error = vm.trackingError;
    if (error == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      vm.clearTrackingError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    if (vm.loading || vm.activeMission == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _surfaceTrackingError(vm);

    final mission = vm.activeMission!;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mission.name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${mission.routePoints.length} stops  •  ${GeoUtils.formatDistance(mission.routeDistanceMeters)}'
              '  •  ${mission.hazards.length} hazard${mission.hazards.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'How to use',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHelpDialog(context),
          ),
          IconButton(
            tooltip: vm.tracking ? 'Stop live GPS tracking' : 'Start live GPS tracking',
            icon: Icon(vm.tracking ? Icons.gps_fixed : Icons.gps_not_fixed),
            color: vm.tracking ? Theme.of(context).colorScheme.primary : null,
            onPressed: vm.toggleTracking,
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: (a) => _onMenu(a, vm),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _MenuAction.rename, child: Text('Rename mission')),
              const PopupMenuItem(value: _MenuAction.duplicate, child: Text('Duplicate mission')),
              PopupMenuItem(
                value: _MenuAction.mapStyle,
                child: Text(
                  vm.mapStyle == MapStyle.dark ? 'Switch to standard map' : 'Switch to dark map',
                ),
              ),
              const PopupMenuItem(value: _MenuAction.importJson, child: Text('Import JSON...')),
              const PopupMenuItem(value: _MenuAction.exportAll, child: Text('Export all missions (JSON)')),
              const PopupMenuItem(value: _MenuAction.clear, child: Text('Clear all waypoints')),
            ],
          ),
        ],
      ),
      drawer: const MissionsDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final map = MissionMap(controller: _mapController);
          final panel = MissionPanel(mapController: _mapController);
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(child: map),
                SizedBox(width: 400, child: panel),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 6, child: map),
              Expanded(flex: 5, child: panel),
            ],
          );
        },
      ),
    );
  }
}
