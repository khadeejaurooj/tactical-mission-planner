import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/mission_view_model.dart';
import 'dialogs.dart';

/// Shows the active mission exactly as it is stored and exchanged: as JSON.
class JsonPanel extends StatelessWidget {
  const JsonPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MissionViewModel>();
    final theme = Theme.of(context);
    final json = vm.exportActiveMissionJson();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: json));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mission JSON copied to clipboard.')),
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import'),
                onPressed: () => showImportDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
