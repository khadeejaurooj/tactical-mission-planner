import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/waypoint.dart';
import '../../viewmodels/mission_view_model.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
}

Future<void> showEditWaypointDialog(BuildContext context, Waypoint waypoint) async {
  final vm = context.read<MissionViewModel>();
  final name = TextEditingController(text: waypoint.name);
  final notes = TextEditingController(text: waypoint.notes);
  final radius = TextEditingController(text: waypoint.radiusMeters.round().toString());
  final isHazard = waypoint.type == WaypointType.hazard;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Edit ${waypoint.type.label.toLowerCase()}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            if (isHazard) ...[
              const SizedBox(height: 12),
              TextField(
                controller: radius,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Hazard radius (meters)'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ),
  );

  if (saved == true) {
    vm.updateWaypoint(
      waypoint.id,
      name: name.text,
      notes: notes.text,
      radiusMeters: isHazard ? double.tryParse(radius.text) : null,
    );
  }
}

Future<void> showHelpDialog(BuildContext context) {
  const steps = <(IconData, String, String)>[
    (Icons.touch_app, 'Plan a route', 'Drag Start, Waypoint, Objective and End from the "Add to map" panel onto the map. Tap a marker, then drag it to move it. Drag the handle in the Plan list to reorder stops.'),
    (Icons.warning_amber_rounded, 'Mark hazards', 'Drop a Hazard to mark a restricted zone. Edit it in the list to change its radius.'),
    (Icons.moving, 'Run the simulation', 'Press "Run simulation" to move a simulated asset along the route. The Telemetry tab shows speed, heading, distance and ETA, and you get an alert when it enters a hazard zone.'),
    (Icons.gps_fixed, 'Track live GPS', 'Press the GPS button in the top bar to show and record your real position on the map.'),
    (Icons.data_object, 'Save and share as JSON', 'Missions are saved on this device automatically. Use the JSON tab to copy a mission, or Import to load one.'),
  ];

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How to use'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (icon, title, text) in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(text),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
    ),
  );
}

/// Paste-in JSON import with inline validation errors.
Future<void> showImportDialog(BuildContext context) async {
  final vm = context.read<MissionViewModel>();
  final controller = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Import mission JSON'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                minLines: 10,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Paste a mission, a list of missions or {"missions": [...]}',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                final count = vm.importMissionsJson(controller.text);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Imported $count mission${count == 1 ? '' : 's'}.')),
                );
              } on FormatException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showExportDialog(BuildContext context, String json, {required String title}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        height: 360,
        child: SingleChildScrollView(
          child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied to clipboard.')));
            }
          },
          child: const Text('Copy'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
