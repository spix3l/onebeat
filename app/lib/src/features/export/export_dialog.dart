// ExportDialog — audio export modal view (UI-C-06 / UI-D-06).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart' show ExportFormat;
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'export_flow_vm.dart';

class ExportDialog extends StatelessWidget {
  const ExportDialog({
    required this.vm,
    required this.onClose,
    this.onFormatChanged,
    this.onSampleRateChanged,
    this.onChooseFolder,
    this.onStartExport,
    this.onCancelExport,
    this.onOpenFolder,
    this.onRetry,
    super.key,
  });

  final ExportFlowVm vm;
  final VoidCallback onClose;
  final ValueChanged<ExportFormat>? onFormatChanged;
  final ValueChanged<int>? onSampleRateChanged;
  final VoidCallback? onChooseFolder;
  final VoidCallback? onStartExport;
  final VoidCallback? onCancelExport;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.canvasScrim,
      alignment: Alignment.center,
      child: Container(
        width: tokens.size.modalWidthLarge,
        decoration: BoxDecoration(
          color: tokens.color.surfacePanel,
          borderRadius: tokens.radius.panelBorder,
          border: Border.all(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ExportDialogHeader(
              title: switch (vm) {
                ExportSettingsVm(projectName: final String name) => 'Export audio · $name',
                ExportProgressVm() => 'Exporting audio...',
                ExportDoneVm() => 'Export complete',
                ExportFailedVm() => 'Export failed',
              },
              onClose: onClose,
            ),
            switch (vm) {
              final ExportSettingsVm settings => _ExportSettingsBody(
                vm: settings,
                onFormatChanged: onFormatChanged,
                onSampleRateChanged: onSampleRateChanged,
                onChooseFolder: onChooseFolder,
                onClose: onClose,
                onStartExport: onStartExport,
              ),
              final ExportProgressVm progress => _ExportProgressBody(
                vm: progress,
                onCancel: onCancelExport,
              ),
              final ExportDoneVm done => _ExportDoneBody(
                vm: done,
                onClose: onClose,
                onOpenFolder: onOpenFolder,
              ),
              final ExportFailedVm failed => _ExportFailedBody(
                vm: failed,
                onClose: onClose,
                onRetry: onRetry,
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _ExportDialogHeader extends StatelessWidget {
  const _ExportDialogHeader({
    required this.title,
    required this.onClose,
  });

  final String title;
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
          Text(title, style: tokens.type.dialogTitle),
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

class _ExportSettingsBody extends StatelessWidget {
  const _ExportSettingsBody({
    required this.vm,
    this.onFormatChanged,
    this.onSampleRateChanged,
    this.onChooseFolder,
    this.onClose,
    this.onStartExport,
  });

  final ExportSettingsVm vm;
  final ValueChanged<ExportFormat>? onFormatChanged;
  final ValueChanged<int>? onSampleRateChanged;
  final VoidCallback? onChooseFolder;
  final VoidCallback? onClose;
  final VoidCallback? onStartExport;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('FORMAT', style: tokens.type.label),
              SizedBox(height: tokens.spacing.xs),
              Wrap(
                spacing: tokens.spacing.xs,
                runSpacing: tokens.spacing.xs,
                children: <Widget>[
                  for (final ExportFormat format in ExportSettingsVm.formats)
                    _ChoiceChip(
                      label: format.label,
                      selected: vm.format == format,
                      onTap: onFormatChanged == null ? null : () => onFormatChanged!(format),
                    ),
                ],
              ),
              SizedBox(height: tokens.spacing.md),
              Text('SAMPLE RATE', style: tokens.type.label),
              SizedBox(height: tokens.spacing.xs),
              Wrap(
                spacing: tokens.spacing.xs,
                runSpacing: tokens.spacing.xs,
                children: <Widget>[
                  for (final int rate in ExportSettingsVm.sampleRates)
                    _ChoiceChip(
                      label: sampleRateLabel(rate),
                      selected: vm.sampleRate == rate,
                      onTap: onSampleRateChanged == null ? null : () => onSampleRateChanged!(rate),
                    ),
                ],
              ),
              SizedBox(height: tokens.spacing.md),
              Text('DESTINATION', style: tokens.type.label),
              SizedBox(height: tokens.spacing.xs),
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
                    ObKitGlyph(
                      kind: ObKitGlyphKind.folder,
                      color: tokens.color.textMuted,
                      size: ObKitGlyphSize.inline,
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            vm.destinationDirectory,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.type.numericSmall,
                          ),
                          SizedBox(height: tokens.spacing.xxs),
                          Text(
                            vm.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.type.numericSmall.copyWith(color: tokens.color.textMuted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: tokens.spacing.sm),
                    ObButton(label: 'Choose Folder…', onTap: onChooseFolder),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Footer
        Container(
          height: tokens.size.dialogHeaderHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Spacer(),
              ObButton(label: 'Cancel', onTap: onClose),
              SizedBox(width: tokens.spacing.sm),
              ObButton(
                label: 'Export',
                tone: ObButtonTone.primary,
                onTap: onStartExport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportProgressBody extends StatelessWidget {
  const _ExportProgressBody({
    required this.vm,
    this.onCancel,
  });

  final ExportProgressVm vm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(vm.statusText, style: tokens.type.title),
          SizedBox(height: tokens.spacing.lg),
          Container(
            height: tokens.spacing.md,
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: vm.progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.color.accent,
                  borderRadius: tokens.radius.controlBorder,
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Text('${(vm.progress * 100).toInt()}% complete', style: tokens.type.numeric),
          SizedBox(height: tokens.spacing.xl),
          ObButton(label: 'Cancel Render', onTap: onCancel),
        ],
      ),
    );
  }
}

class _ExportDoneBody extends StatelessWidget {
  const _ExportDoneBody({
    required this.vm,
    required this.onClose,
    this.onOpenFolder,
  });

  final ExportDoneVm vm;
  final VoidCallback onClose;
  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ObKitGlyph(
            kind: ObKitGlyphKind.check,
            color: tokens.color.accentBright,
            size: ObKitGlyphSize.feature,
          ),
          SizedBox(height: tokens.spacing.md),
          Text('Audio Exported Successfully', style: tokens.type.title),
          SizedBox(height: tokens.spacing.xs),
          Text(vm.summaryText, style: tokens.type.bodySecondary),
          SizedBox(height: tokens.spacing.md),
          Text(vm.filePath, style: tokens.type.numericSmall.copyWith(color: tokens.color.textMuted)),
          SizedBox(height: tokens.spacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (onOpenFolder != null) ...<Widget>[
                ObButton(label: 'Open in Finder', onTap: onOpenFolder),
                SizedBox(width: tokens.spacing.md),
              ],
              ObButton(label: 'Done', tone: ObButtonTone.primary, onTap: onClose),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportFailedBody extends StatelessWidget {
  const _ExportFailedBody({
    required this.vm,
    required this.onClose,
    this.onRetry,
  });

  final ExportFailedVm vm;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ObKitGlyph(
            kind: ObKitGlyphKind.warning,
            color: tokens.color.danger,
            size: ObKitGlyphSize.feature,
          ),
          SizedBox(height: tokens.spacing.md),
          Text('Export Error', style: tokens.type.title.copyWith(color: tokens.color.danger)),
          SizedBox(height: tokens.spacing.sm),
          Text(vm.errorMessage, style: tokens.type.body),
          SizedBox(height: tokens.spacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ObButton(label: 'Close', onTap: onClose),
              if (onRetry != null) ...<Widget>[
                SizedBox(width: tokens.spacing.md),
                ObButton(label: 'Retry', tone: ObButtonTone.primary, onTap: onRetry),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
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
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: selected ? tokens.color.accent : tokens.color.line,
              width: selected ? tokens.border.emphasis : tokens.border.hairline,
            ),
          ),
          child: Text(
            label,
            style: tokens.type.numericSmall.copyWith(
              color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
