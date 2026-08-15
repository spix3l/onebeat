// PreferencesDialog — settings modal view (UI-C-08 / UI-D-07).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'preferences_vm.dart';

class PreferencesDialog extends StatelessWidget {
  const PreferencesDialog({
    required this.vm,
    required this.onClose,
    this.onTabChanged,
    this.onBufferChanged,
    this.onAddFolder,
    this.onRemoveFolder,
    this.onRescanPlugins,
    super.key,
  });

  final PreferencesVm vm;
  final VoidCallback onClose;
  final ValueChanged<int>? onTabChanged;
  final ValueChanged<int>? onBufferChanged;
  final VoidCallback? onAddFolder;
  final ValueChanged<String>? onRemoveFolder;
  final VoidCallback? onRescanPlugins;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.canvasScrim,
      alignment: Alignment.center,
      child: Container(
        width: tokens.size.modalWidthLarge,
        height: tokens.size.knobLarge * 8.0,
        decoration: BoxDecoration(
          color: tokens.color.surfacePanel,
          borderRadius: tokens.radius.panelBorder,
          border: Border.all(
            color: tokens.color.line,
            width: tokens.border.emphasis,
          ),
        ),
        child: Column(
          children: <Widget>[
            _PrefHeader(onClose: onClose),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _PrefSidebar(
                    activeTab: vm.activeTab,
                    onTabChanged: onTabChanged,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(tokens.spacing.lg),
                      child: switch (vm.activeTab) {
                        0 => _AudioTabContent(
                          vm: vm.audio,
                          onBufferChanged: onBufferChanged,
                        ),
                        1 => _PluginsTabContent(
                          folders: vm.folders,
                          isScanning: vm.isScanning,
                          onAddFolder: onAddFolder,
                          onRemoveFolder: onRemoveFolder,
                          onRescanPlugins: onRescanPlugins,
                        ),
                        _ => _ShortcutsTabContent(shortcuts: vm.shortcuts),
                      },
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

class _PrefHeader extends StatelessWidget {
  const _PrefHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
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
          GestureDetector(
            onTap: onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ObKitGlyph(
                kind: ObKitGlyphKind.close,
                color: tokens.color.textMuted,
                size: ObKitGlyphSize.inline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrefSidebar extends StatelessWidget {
  const _PrefSidebar({
    required this.activeTab,
    this.onTabChanged,
  });

  final int activeTab;
  final ValueChanged<int>? onTabChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      width: tokens.size.patternSelectorWidth * 0.75,
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
            icon: ObKitGlyphKind.waveform,
            selected: activeTab == 0,
            onTap: onTabChanged == null ? null : () => onTabChanged!(0),
          ),
          _PrefTabItem(
            label: 'Sound & Plugins',
            icon: ObKitGlyphKind.folder,
            selected: activeTab == 1,
            onTap: onTabChanged == null ? null : () => onTabChanged!(1),
          ),
          _PrefTabItem(
            label: 'Keys & Shortcuts',
            icon: ObKitGlyphKind.keyboard,
            selected: activeTab == 2,
            onTap: onTabChanged == null ? null : () => onTabChanged!(2),
          ),
        ],
      ),
    );
  }
}

class _PrefTabItem extends StatelessWidget {
  const _PrefTabItem({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final ObKitGlyphKind icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          margin: EdgeInsets.only(bottom: tokens.spacing.xs),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? color.surfaceOverlay : null,
            borderRadius: tokens.radius.controlBorder,
            border: selected ? Border.all(color: color.accent, width: tokens.border.hairline) : null,
          ),
          child: Row(
            children: <Widget>[
              ObKitGlyph(
                kind: icon,
                color: selected ? color.textPrimary : color.textMuted,
                size: ObKitGlyphSize.inline,
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: tokens.type.body.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? color.accent : color.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioTabContent extends StatelessWidget {
  const _AudioTabContent({
    required this.vm,
    this.onBufferChanged,
  });

  final AudioPrefsVm vm;
  final ValueChanged<int>? onBufferChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

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
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Text(vm.deviceName, style: tokens.type.body),
        ),
        SizedBox(height: tokens.spacing.lg),
        Text('BUFFER SIZE (LATENCY)', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Wrap(
          spacing: tokens.spacing.xs,
          runSpacing: tokens.spacing.xs,
          children: <Widget>[
            for (final int buffer in vm.bufferOptions)
              _BufferChoicePill(
                buffer: buffer,
                selected: buffer == vm.selectedBuffer,
                onTap: onBufferChanged == null ? null : () => onBufferChanged!(buffer),
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.md),
        Container(
          padding: EdgeInsets.all(tokens.spacing.md),
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: tokens.spacing.sm,
                height: tokens.spacing.sm,
                decoration: BoxDecoration(
                  color: tokens.color.meterLow,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  vm.latencyText,
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
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Text(vm.sampleRateText, style: tokens.type.body),
        ),
      ],
    );
  }
}

class _BufferChoicePill extends StatelessWidget {
  const _BufferChoicePill({
    required this.buffer,
    required this.selected,
    this.onTap,
  });

  final int buffer;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? tokens.color.surfaceOverlay : tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: selected ? tokens.color.accent : tokens.color.line,
              width: selected ? tokens.border.emphasis : tokens.border.hairline,
            ),
          ),
          child: Text(
            '$buffer',
            style: tokens.type.numeric.copyWith(
              color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PluginsTabContent extends StatelessWidget {
  const _PluginsTabContent({
    required this.folders,
    required this.isScanning,
    this.onAddFolder,
    this.onRemoveFolder,
    this.onRescanPlugins,
  });

  final List<PrefFolderVm> folders;
  final bool isScanning;
  final VoidCallback? onAddFolder;
  final ValueChanged<String>? onRemoveFolder;
  final VoidCallback? onRescanPlugins;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SAMPLE & PRESET FOLDERS', style: tokens.type.label),
        SizedBox(height: tokens.spacing.sm),
        for (final PrefFolderVm folder in folders)
          _FolderRow(
            folder: folder,
            onRemove: onRemoveFolder == null ? null : () => onRemoveFolder!(folder.path),
          ),
        SizedBox(height: tokens.spacing.md),
        Row(
          children: <Widget>[
            ObButton(label: '+ Add Folder...', onTap: onAddFolder),
            SizedBox(width: tokens.spacing.sm),
            ObButton(
              label: isScanning ? 'Scanning...' : 'Rescan Plugins Now',
              tone: ObButtonTone.accentOutline,
              onTap: onRescanPlugins,
            ),
          ],
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    this.onRemove,
  });

  final PrefFolderVm folder;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: tokens.spacing.xs),
      padding: EdgeInsets.all(tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          ObKitGlyph(
            kind: ObKitGlyphKind.folder,
            color: tokens.color.textMuted,
            size: ObKitGlyphSize.inline,
          ),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(folder.path, style: tokens.type.body),
                Text(folder.detail, style: tokens.type.numericSmall),
              ],
            ),
          ),
          if (folder.removable)
            GestureDetector(
              onTap: onRemove,
              child: MouseRegion(
                cursor: onRemove != null ? SystemMouseCursors.click : MouseCursor.defer,
                child: ObKitGlyph(
                  kind: ObKitGlyphKind.close,
                  color: tokens.color.textMuted,
                  size: ObKitGlyphSize.inline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutsTabContent extends StatelessWidget {
  const _ShortcutsTabContent({required this.shortcuts});

  final List<PrefShortcutVm> shortcuts;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('KEYBOARD SHORTCUTS', style: tokens.type.label),
        SizedBox(height: tokens.spacing.sm),
        for (final PrefShortcutVm shortcut in shortcuts)
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
                Expanded(child: Text(shortcut.label, style: tokens.type.body)),
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
                    shortcut.shortcut,
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
