import 'package:commet/config/build_config.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HyprlandShortcutSettingsPage extends StatelessWidget {
  const HyprlandShortcutSettingsPage({super.key});

  // The app_id used when registering shortcuts with Hyprland.
  static String get _appId => BuildConfig.DEBUG
      ? 'chat.tungstn.app.develop'
      : 'chat.tungstn.app';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return tiamat.Panel(
      mode: TileType.surfaceContainerLow,
      header: "Hyprland Global Shortcuts",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          tiamat.Text(
            "Shortcuts are registered with Hyprland automatically when the app starts. "
            "Bind them in your hyprland.conf using the syntax below.",
          ),
          ...SystemWideShortcuts.shortcuts.entries.map((entry) {
            final bindLine =
                'bind = , , global, ${_appId}:${entry.key}';
            return _ShortcutRow(
              id: entry.key,
              description: entry.value.getDisplayName(),
              bindExample: bindLine,
              scheme: scheme,
            );
          }),
          tiamat.Text.labelLow(
            "Replace the first two commas with your desired modifier and key, e.g. "
            "SUPER SHIFT, M.",
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.id,
    required this.description,
    required this.bindExample,
    required this.scheme,
  });

  final String id;
  final String description;
  final String bindExample;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        tiamat.Text.labelEmphasised(description),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  bindExample,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.onSurface,
                      ),
                ),
              ),
            ),
            tiamat.IconButton(
              icon: Icons.copy,
              size: 18,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: bindExample)),
            ),
          ],
        ),
      ],
    );
  }
}
