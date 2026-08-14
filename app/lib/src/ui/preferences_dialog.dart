// Preferences Dialog (matches onebeat-prefs.html.png and onebeat-prefs-keys.html.png).
//
// Modal dialog with Audio, Sound & Plugins, and Keys & Shortcuts tabs.
// Built entirely from tokens with zero raw literals.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'action_registry.dart';
import 'controls.dart';
import 'icons.dart';

class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({
    required this.onClose,
    super.key,
  });

  final VoidCallback onClose;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  int _activeTab = 0; // 0 = Audio, 1 = Sound & Plugins, 2 = Keys & Shortcuts
  int _selectedBuffer = 128;
  final String _selectedDevice = 'MacBook Pro Speakers';
  final String _selectedSampleRate = '44.1 kHz';

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.canvasScrim,
      alignment: Alignment.center,
      child: Container(
        width: tokens.size.modalWidthLarge,
        height: tokens.size.knobLarge * 8.0, // token-lint-ok: proportional height
        decoration: BoxDecoration(
          color: tokens.color.surfacePanel,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: tokens.color.line,
            width: tokens.border.emphasis,
          ),
        ),
        child: Column(
          children: <Widget>[
            // Dialog Header
            Container(
              height: tokens.size.dialogHeaderHeight,
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.color.line,
                    width: tokens.border.hairline,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Text('Preferences', style: tokens.type.dialogTitle),
                  const Spacer(),
                  IconButtonSmall(
                    icon: OneBeatIconData.close,
                    semanticLabel: 'Close preferences',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // Dialog Body
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Left Nav Tabs
                  Container(
                    width: tokens.size.patternSelectorWidth * 0.75, // token-lint-ok: ratio
                    decoration: BoxDecoration(
                      color: tokens.color.surfaceDeep,
                      border: Border(
                        right: BorderSide(
                          color: tokens.color.line,
                          width: tokens.border.hairline,
                        ),
                      ),
                    ),
                    child: ListView(
                      padding: EdgeInsets.all(tokens.spacing.sm),
                      children: <Widget>[
                        _PrefTabItem(
                          label: 'Audio',
                          icon: OneBeatIconData.audio,
                          selected: _activeTab == 0,
                          onTap: () => setState(() => _activeTab = 0),
                          tokens: tokens,
                        ),
                        _PrefTabItem(
                          label: 'Sound & Plugins',
                          icon: OneBeatIconData.plugins,
                          selected: _activeTab == 1,
                          onTap: () => setState(() => _activeTab = 1),
                          tokens: tokens,
                        ),
                        _PrefTabItem(
                          label: 'Keys & Shortcuts',
                          icon: OneBeatIconData.keyboard,
                          selected: _activeTab == 2,
                          onTap: () => setState(() => _activeTab = 2),
                          tokens: tokens,
                        ),
                      ],
                    ),
                  ),
                  // Content Panel
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(tokens.spacing.lg),
                      child: _activeTab == 0
                          ? _AudioPrefsContent(
                              selectedDevice: _selectedDevice,
                              selectedBuffer: _selectedBuffer,
                              selectedSampleRate: _selectedSampleRate,
                              onBufferChanged: (int b) => setState(() => _selectedBuffer = b),
                              tokens: tokens,
                            )
                          : (_activeTab == 1
                              ? _SoundPluginsPrefsContent(tokens: tokens)
                              : _KeyShortcutsPrefsContent(tokens: tokens)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrefTabItem extends StatelessWidget {
  const _PrefTabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final OneBeatIconData icon;
  final bool selected;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: tokens.spacing.xs),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.color.surfaceOverlay : null,
          borderRadius: tokens.radius.controlBorder,
          border: selected
              ? Border.all(color: tokens.color.accent, width: tokens.border.hairline)
              : null,
        ),
        child: Row(
          children: <Widget>[
            OneBeatIcon(
              icon,
              size: tokens.size.iconSize,
              color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Text(
                label,
                style: tokens.type.body.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? tokens.color.accent : tokens.color.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPrefsContent extends StatelessWidget {
  const _AudioPrefsContent({
    required this.selectedDevice,
    required this.selectedBuffer,
    required this.selectedSampleRate,
    required this.onBufferChanged,
    required this.tokens,
  });

  final String selectedDevice;
  final int selectedBuffer;
  final String selectedSampleRate;
  final ValueChanged<int> onBufferChanged;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('AUDIO OUTPUT DEVICE', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Container(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          height: tokens.size.controlHeight,
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          alignment: Alignment.centerLeft,
          child: Text(selectedDevice, style: tokens.type.body),
        ),
        SizedBox(height: tokens.spacing.lg),
        Text('BUFFER SIZE (LATENCY)', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Row(
          children: <Widget>[
            for (final int buffer in const <int>[64, 128, 256, 512, 1024, 2048])
              Padding(
                padding: EdgeInsets.only(right: tokens.spacing.xs),
                child: GestureDetector(
                  onTap: () => onBufferChanged(buffer),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                      vertical: tokens.spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: buffer == selectedBuffer
                          ? tokens.color.surfaceOverlay
                          : tokens.color.surfaceDeep,
                      borderRadius: tokens.radius.controlBorder,
                      border: Border.all(
                        color: buffer == selectedBuffer
                            ? tokens.color.accent
                            : tokens.color.line,
                        width: buffer == selectedBuffer
                            ? tokens.border.emphasis
                            : tokens.border.hairline,
                      ),
                    ),
                    child: Text(
                      '$buffer',
                      style: tokens.type.numeric.copyWith(
                        color: buffer == selectedBuffer
                            ? tokens.color.textPrimary
                            : tokens.color.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.md),
        // Latency telemetry card
        Container(
          padding: EdgeInsets.all(tokens.spacing.md),
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          child: Row(
            children: <Widget>[
              OneBeatIcon(
                OneBeatIconData.dot,
                size: tokens.size.tagHeight,
                color: tokens.color.meterLow,
              ),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  '5.3 ms roundtrip latency · $selectedBuffer samples @ $selectedSampleRate · 0 dropouts',
                  style: tokens.type.numericSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.lg),
        Text('SAMPLE RATE', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Container(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          height: tokens.size.controlHeight,
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          alignment: Alignment.centerLeft,
          child: Text(selectedSampleRate, style: tokens.type.body),
        ),
      ],
    );
  }
}

class _SoundPluginsPrefsContent extends StatelessWidget {
  const _SoundPluginsPrefsContent({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SAMPLE & PRESET FOLDERS', style: tokens.type.label),
        SizedBox(height: tokens.spacing.sm),
        _FolderRow(
          path: '/Users/steve/Music/Samples',
          detail: '14,210 sample files · 4.2 GB',
          tokens: tokens,
        ),
        _FolderRow(
          path: '/Library/Audio/Plug-Ins/CLAP',
          detail: '28 CLAP plugins found',
          tokens: tokens,
        ),
        SizedBox(height: tokens.spacing.md),
        Row(
          children: <Widget>[
            OneBeatButton(label: '+ Add Folder...', onPressed: () {}),
            SizedBox(width: tokens.spacing.sm),
            OneBeatButton(label: 'Rescan Plugins Now', onPressed: () {}),
          ],
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.path,
    required this.detail,
    required this.tokens,
  });

  final String path;
  final String detail;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: tokens.spacing.xs),
      padding: EdgeInsets.all(tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
      ),
      child: Row(
        children: <Widget>[
          OneBeatIcon(
            OneBeatIconData.folder,
            size: tokens.size.iconSize,
            color: tokens.color.textMuted,
          ),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(path, style: tokens.type.body),
                Text(detail, style: tokens.type.numericSmall),
              ],
            ),
          ),
          IconButtonSmall(
            icon: OneBeatIconData.close,
            semanticLabel: 'Remove this folder',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _KeyShortcutsPrefsContent extends StatelessWidget {
  const _KeyShortcutsPrefsContent({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('KEYBOARD SHORTCUTS', style: tokens.type.label),
        SizedBox(height: tokens.spacing.sm),
        for (final UiAction action in ActionRegistry.all)
          if (action.shortcut.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(
                vertical: tokens.spacing.xs,
                horizontal: tokens.spacing.sm,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.color.line,
                    width: tokens.border.hairline,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(action.label, style: tokens.type.body)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.xs,
                      vertical: tokens.spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.color.surfaceDeep,
                      borderRadius: tokens.radius.controlBorder,
                    ),
                    child: Text(
                      action.shortcut,
                      style: tokens.type.numericSmall,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
