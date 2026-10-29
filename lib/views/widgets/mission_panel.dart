import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'json_panel.dart';
import 'telemetry_panel.dart';
import 'waypoint_list.dart';

class MissionPanel extends StatelessWidget {
  const MissionPanel({super.key, required this.mapController});

  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Material(
        color: scheme.surface,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.route), text: 'Plan'),
                Tab(icon: Icon(Icons.speed), text: 'Telemetry'),
                Tab(icon: Icon(Icons.data_object), text: 'JSON'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  WaypointList(mapController: mapController),
                  const TelemetryPanel(),
                  const JsonPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
