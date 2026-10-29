import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/geo_utils.dart';
import '../../viewmodels/mission_view_model.dart';

class TelemetryPanel extends StatelessWidget {
  const TelemetryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    final theme = Theme.of(context);
    final next = vm.nextWaypoint;
    final speedKmh = MissionViewModel.nominalSpeedMps * vm.timeScale * 3.6;

    final sim = <(String, String)>[
      ('Status', _statusLabel(vm.simStatus)),
      ('Speed', '${speedKmh.toStringAsFixed(0)} km/h'),
      ('Travelled', GeoUtils.formatDistance(vm.distanceTraveledMeters)),
      ('Next stop', next == null ? '--' : '${next.name} (${GeoUtils.formatDistance(vm.distanceToNextMeters)})'),
    ];

    final fix = vm.lastFix;
    final gps = <(String, String)>[
      ('Status', vm.tracking ? (fix == null ? 'Waiting for fix...' : 'Tracking') : 'Off'),
      ('Position', fix == null ? '--' : '${fix.position.latitude.toStringAsFixed(5)}, ${fix.position.longitude.toStringAsFixed(5)}'),
      ('Accuracy', fix == null ? '--' : '±${fix.accuracyMeters.round()} m'),
      ('Speed', fix == null ? '--' : '${(fix.speedMps * 3.6).toStringAsFixed(1)} km/h'),
      ('Track length', GeoUtils.formatDistance(vm.trackDistanceMeters)),
      ('Hazards', vm.liveHazardAlerts.isEmpty ? 'Clear' : vm.liveHazardAlerts.map((h) => h.name).join(', ')),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _Tile(label: 'PROGRESS', value: '${(vm.progress * 100).toStringAsFixed(0)}%', icon: Icons.flag_outlined)),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                label: 'DISTANCE LEFT',
                value: GeoUtils.formatDistance(vm.distanceRemainingMeters),
                icon: Icons.route,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'ETA',
                value: vm.canSimulate ? GeoUtils.formatDuration(vm.eta) : '--',
                icon: Icons.timer_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                label: 'HEADING',
                value: vm.simPosition == null ? '--' : GeoUtils.formatBearing(vm.simHeading),
                icon: Icons.explore_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Section(title: 'Mission simulation', icon: Icons.moving, rows: sim),
        if (vm.simHazardAlerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Hazard alert: ${vm.simHazardAlerts.map((h) => h.name).join(', ')}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 20),
        _Section(title: 'Live GPS tracking', icon: Icons.gps_fixed, rows: gps),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: vm.toggleTracking,
              icon: Icon(vm.tracking ? Icons.stop : Icons.play_arrow),
              label: Text(vm.tracking ? 'Stop tracking' : 'Start tracking'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: vm.track.isEmpty ? null : vm.clearTrack, child: const Text('Clear track')),
          ],
        ),
      ],
    );
  }

  String _statusLabel(SimulationStatus s) => switch (s) {
        SimulationStatus.idle => 'Ready',
        SimulationStatus.running => 'Running',
        SimulationStatus.paused => 'Paused',
        SimulationStatus.finished => 'Arrived',
      };
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
