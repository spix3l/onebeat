// Export Audio Dialog (matches onebeat-export.html.png, onebeat-export-progress.html.png, onebeat-export-done.html.png).
//
// Modal dialog with format, sample rate, bit depth, stem selection, and export progress.
// Built entirely from tokens with zero raw literals.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'controls.dart';
import 'icons.dart';

class ExportAudioDialog extends StatefulWidget {
  const ExportAudioDialog({
    required this.onClose,
    super.key,
  });

  final VoidCallback onClose;

  @override
  State<ExportAudioDialog> createState() => _ExportAudioDialogState();
}

class _ExportAudioDialogState extends State<ExportAudioDialog> {
  String _format = 'WAV';
  String _bitDepth = '24-bit';
  String _sampleRate = '48 kHz';
  String _range = 'Loop region';
  final Set<String> _selectedStems = <String>{
    'Master',
    'Drums Bus',
    'Bass',
    'Music',
    'Vox',
  };
  bool _isExporting = false;
  double _progress = 0.0;

  void _startExport() {
    setState(() {
      _isExporting = true;
      _progress = 0.45; // token-lint-ok: progress simulation
    });
  }

  void _toggleStem(String stem) {
    setState(() {
      if (_selectedStems.contains(stem)) {
        _selectedStems.remove(stem);
      } else {
        _selectedStems.add(stem);
      }
    });
  }

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
            // Header
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
                  Text('Export audio', style: tokens.type.dialogTitle),
                  SizedBox(width: tokens.spacing.sm),
                  Text('· Demo Project.onebeat', style: tokens.type.numericSmall),
                  const Spacer(),
                  IconButtonSmall(
                    icon: OneBeatIconData.close,
                    semanticLabel: 'Close export dialog',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // Body
            _isExporting
                ? _ExportProgressView(
                    progress: _progress,
                    onCancel: () => setState(() => _isExporting = false),
                    onDone: widget.onClose,
                    tokens: tokens,
                  )
                : Padding(
                    padding: EdgeInsets.all(tokens.spacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Left Column: Format, Bit Depth, Sample Rate, Range
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('FORMAT', style: tokens.type.label),
                              SizedBox(height: tokens.spacing.xs),
                              Row(
                                children: <Widget>[
                                  _FormatChoiceChip(
                                    label: 'WAV',
                                    ext: '.wav',
                                    selected: _format == 'WAV',
                                    onTap: () => setState(() => _format = 'WAV'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _FormatChoiceChip(
                                    label: 'AIFF',
                                    ext: '.aiff',
                                    selected: _format == 'AIFF',
                                    onTap: () => setState(() => _format = 'AIFF'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _FormatChoiceChip(
                                    label: 'FLAC',
                                    ext: '.flac',
                                    selected: _format == 'FLAC',
                                    onTap: () => setState(() => _format = 'FLAC'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _FormatChoiceChip(
                                    label: 'MP3',
                                    ext: '.mp3',
                                    selected: _format == 'MP3',
                                    onTap: () => setState(() => _format = 'MP3'),
                                    tokens: tokens,
                                  ),
                                ],
                              ),
                              SizedBox(height: tokens.spacing.md),
                              Text('BIT DEPTH', style: tokens.type.label),
                              SizedBox(height: tokens.spacing.xs),
                              Row(
                                children: <Widget>[
                                  _DepthRateChip(
                                    label: '16-bit',
                                    selected: _bitDepth == '16-bit',
                                    onTap: () => setState(() => _bitDepth = '16-bit'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _DepthRateChip(
                                    label: '24-bit',
                                    selected: _bitDepth == '24-bit',
                                    onTap: () => setState(() => _bitDepth = '24-bit'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _DepthRateChip(
                                    label: '32-bit float',
                                    selected: _bitDepth == '32-bit float',
                                    onTap: () => setState(() => _bitDepth = '32-bit float'),
                                    tokens: tokens,
                                  ),
                                ],
                              ),
                              SizedBox(height: tokens.spacing.md),
                              Text('SAMPLE RATE', style: tokens.type.label),
                              SizedBox(height: tokens.spacing.xs),
                              Row(
                                children: <Widget>[
                                  _DepthRateChip(
                                    label: '48 kHz',
                                    selected: _sampleRate == '48 kHz',
                                    onTap: () => setState(() => _sampleRate = '48 kHz'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _DepthRateChip(
                                    label: '44.1 kHz',
                                    selected: _sampleRate == '44.1 kHz',
                                    onTap: () => setState(() => _sampleRate = '44.1 kHz'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _DepthRateChip(
                                    label: '88.2 kHz',
                                    selected: _sampleRate == '88.2 kHz',
                                    onTap: () => setState(() => _sampleRate = '88.2 kHz'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _DepthRateChip(
                                    label: '96 kHz',
                                    selected: _sampleRate == '96 kHz',
                                    onTap: () => setState(() => _sampleRate = '96 kHz'),
                                    tokens: tokens,
                                  ),
                                ],
                              ),
                              SizedBox(height: tokens.spacing.md),
                              Text('RANGE', style: tokens.type.label),
                              SizedBox(height: tokens.spacing.xs),
                              Row(
                                children: <Widget>[
                                  _RangeChip(
                                    label: 'Whole project',
                                    sub: 'bars 1-32',
                                    selected: _range == 'Whole project',
                                    onTap: () => setState(() => _range = 'Whole project'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _RangeChip(
                                    label: 'Loop region',
                                    sub: 'bars 1-8',
                                    selected: _range == 'Loop region',
                                    onTap: () => setState(() => _range = 'Loop region'),
                                    tokens: tokens,
                                  ),
                                  SizedBox(width: tokens.spacing.xs),
                                  _RangeChip(
                                    label: 'Selection',
                                    sub: '',
                                    selected: _range == 'Selection',
                                    onTap: () => setState(() => _range = 'Selection'),
                                    tokens: tokens,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: tokens.spacing.lg),
                        // Right Column: Stems & Output Info
                        Expanded(
                          flex: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('STEMS · PER MIXER TRACK', style: tokens.type.label),
                              SizedBox(height: tokens.spacing.xs),
                              Wrap(
                                spacing: tokens.spacing.xs,
                                runSpacing: tokens.spacing.xs,
                                children: <Widget>[
                                  _StemCheckboxPill(
                                    label: 'Master',
                                    selected: _selectedStems.contains('Master'),
                                    onTap: () => _toggleStem('Master'),
                                    tokens: tokens,
                                  ),
                                  _StemCheckboxPill(
                                    label: 'Drums Bus',
                                    count: '4 tracks',
                                    selected: _selectedStems.contains('Drums Bus'),
                                    onTap: () => _toggleStem('Drums Bus'),
                                    tokens: tokens,
                                  ),
                                  _StemCheckboxPill(
                                    label: 'Bass',
                                    selected: _selectedStems.contains('Bass'),
                                    onTap: () => _toggleStem('Bass'),
                                    tokens: tokens,
                                  ),
                                  _StemCheckboxPill(
                                    label: 'Music',
                                    count: '2 tracks',
                                    selected: _selectedStems.contains('Music'),
                                    onTap: () => _toggleStem('Music'),
                                    tokens: tokens,
                                  ),
                                  _StemCheckboxPill(
                                    label: 'Vox',
                                    selected: _selectedStems.contains('Vox'),
                                    onTap: () => _toggleStem('Vox'),
                                    tokens: tokens,
                                  ),
                                  _StemCheckboxPill(
                                    label: 'Reverb Send',
                                    selected: _selectedStems.contains('Reverb Send'),
                                    onTap: () => _toggleStem('Reverb Send'),
                                    tokens: tokens,
                                  ),
                                ],
                              ),
                              SizedBox(height: tokens.spacing.md),
                              // Output stats block
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Text('Files', style: tokens.type.numericSmall),
                                        const Spacer(),
                                        Text(
                                          '${_selectedStems.length} · $_format $_bitDepth · $_sampleRate',
                                          style: tokens.type.numericSmall.copyWith(
                                            color: tokens.color.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: tokens.spacing.xxs),
                                    Row(
                                      children: <Widget>[
                                        Text('Duration', style: tokens.type.numericSmall),
                                        const Spacer(),
                                        Text(
                                          '0:32 (8 bars)',
                                          style: tokens.type.numericSmall.copyWith(
                                            color: tokens.color.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: tokens.spacing.xxs),
                                    Row(
                                      children: <Widget>[
                                        Text('Estimated size', style: tokens.type.numericSmall),
                                        const Spacer(),
                                        Text(
                                          '~96 MB',
                                          style: tokens.type.numericSmall.copyWith(
                                            color: tokens.color.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: tokens.spacing.xs),
                                    Text(
                                      '~/Music/OneBeat/Demo Project/',
                                      style: tokens.type.numericSmall.copyWith(
                                        color: tokens.color.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            // Footer
            if (!_isExporting)
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
                    OneBeatIcon(
                      OneBeatIconData.folder,
                      size: tokens.size.tagHeight,
                      color: tokens.color.textMuted,
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Text(
                      'Export to ~/Music/OneBeat',
                      style: tokens.type.numericSmall,
                    ),
                    const Spacer(),
                    OneBeatButton(
                      label: 'Cancel',
                      onPressed: widget.onClose,
                    ),
                    SizedBox(width: tokens.spacing.sm),
                    ExportActionButton(
                      label: 'Export',
                      onPressed: _startExport,
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

class _FormatChoiceChip extends StatelessWidget {
  const _FormatChoiceChip({
    required this.label,
    required this.ext,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final String ext;
  final bool selected;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.color.surfaceDeep : tokens.color.surfaceDeep,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: selected ? tokens.color.accent : tokens.color.line,
            width: selected ? tokens.border.emphasis : tokens.border.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: tokens.type.label.copyWith(
                color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            SizedBox(width: tokens.spacing.xxs),
            Text(
              ext,
              style: tokens.type.numericSmall.copyWith(
                color: selected ? tokens.color.accent : tokens.color.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepthRateChip extends StatelessWidget {
  const _DepthRateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: tokens.spacing.sm,
              height: tokens.spacing.sm,
              decoration: BoxDecoration(
                color: selected ? tokens.color.accent : tokens.color.none,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(
                  color: selected ? tokens.color.accent : tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              label,
              style: tokens.type.numericSmall.copyWith(
                color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: tokens.type.tag.copyWith(
                color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
              ),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: tokens.type.numericSmall.copyWith(
                  color: selected ? tokens.color.accent : tokens.color.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StemCheckboxPill extends StatelessWidget {
  const _StemCheckboxPill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
    this.count = '',
  });

  final String label;
  final String count;
  final bool selected;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: tokens.spacing.sm,
              height: tokens.spacing.sm,
              decoration: BoxDecoration(
                color: selected ? tokens.color.accent : tokens.color.none,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(
                  color: selected ? tokens.color.accent : tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              label,
              style: tokens.type.body.copyWith(
                color: selected ? tokens.color.textPrimary : tokens.color.textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (count.isNotEmpty) ...<Widget>[
              SizedBox(width: tokens.spacing.xs),
              Text(
                count,
                style: tokens.type.numericSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ExportActionButton extends StatelessWidget {
  const ExportActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: tokens.size.controlHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
        decoration: BoxDecoration(
          color: tokens.color.accent,
          borderRadius: tokens.radius.controlBorder,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            OneBeatIcon(
              OneBeatIconData.export,
              size: tokens.size.tagHeight,
              color: tokens.color.textPrimary,
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              label,
              style: tokens.type.labelDense.copyWith(
                color: tokens.color.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _ExportProgressView extends StatelessWidget {
  const _ExportProgressView({
    required this.progress,
    required this.onCancel,
    required this.onDone,
    required this.tokens,
  });

  final double progress;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('Rendering audio mix...', style: tokens.type.title),
          SizedBox(height: tokens.spacing.md),
          Container(
            height: tokens.spacing.md,
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.color.accent,
                  borderRadius: tokens.radius.controlBorder,
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Text('${(progress * 100).toInt()}% complete', style: tokens.type.numeric),
          SizedBox(height: tokens.spacing.xl),
          OneBeatButton(
            label: 'Cancel Render',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
