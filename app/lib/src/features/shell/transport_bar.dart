// ObTransportBar — the ~68px transport bar under the menu bar (UI-B-02).
//
// Full-width chrome on every screen: traffic lights, the app tile and title
// block, the transport cluster (undo/redo/play/stop/loop), the three readout
// boxes, the action search, and the master meter sliver beside the Export
// button. Every value is vm text — nothing here reads real state — and every
// control fires a plain callback that Phase D will wire.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/search_field.dart';
import '../../ui_kit/transport_button.dart';
import 'glyphs.dart';
import 'readouts.dart';

/// What the transport bar shows.
@immutable
class ObTransportBarVm {
  const ObTransportBarVm({
    required this.title,
    required this.subtitle,
    required this.playing,
    required this.looping,
    required this.bpmText,
    required this.sigText,
    required this.positionText,
    required this.meterLeft,
    required this.meterRight,
    required this.searchHint,
  });

  /// Title block lines: `ONEBEAT` caps over the `v0.3 SEQUENCES` micro line.
  final String title;
  final String subtitle;

  /// Play renders accent-active when true.
  final bool playing;

  /// Loop renders latched (accent wash) when true.
  final bool looping;

  /// Readout values, already formatted (`124.00`, `4/4`, `02:01:218`).
  final String bpmText;
  final String sigText;
  final String positionText;

  /// Master meter levels, 0..1.
  final double meterLeft;
  final double meterRight;

  /// Search field hint (`Search actions`).
  final String searchHint;
}

class ObTransportBar extends StatelessWidget {
  const ObTransportBar({
    required this.vm,
    this.onUndo,
    this.onRedo,
    this.onTogglePlay,
    this.onStop,
    this.onToggleLoop,
    this.onSearchTap,
    this.onExport,
    super.key,
  });

  final ObTransportBarVm vm;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onStop;
  final VoidCallback? onToggleLoop;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.transportBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _TitleBlock(vm: vm, tokens: tokens),
          SizedBox(width: tokens.spacing.xl),
          _TransportCluster(
            vm: vm,
            onUndo: onUndo,
            onRedo: onRedo,
            onTogglePlay: onTogglePlay,
            onStop: onStop,
            onToggleLoop: onToggleLoop,
          ),
          SizedBox(width: tokens.spacing.lg),
          ObReadout(value: vm.bpmText, unit: 'BPM'),
          SizedBox(width: tokens.spacing.xs),
          ObReadout(value: vm.sigText, unit: 'SIG'),
          SizedBox(width: tokens.spacing.xs),
          ObReadout(value: vm.positionText, unit: 'BAR · BEAT · TICK'),
          const Spacer(),
          ObSearchField(
            hint: vm.searchHint,
            shortcut: '⌘K',
            onTap: onSearchTap,
          ),
          SizedBox(width: tokens.spacing.md),
          _MasterMeter(vm: vm, tokens: tokens),
          SizedBox(width: tokens.spacing.sm),
          _ExportButton(onTap: onExport),
        ],
      ),
    );
  }
}

/// The rounded accent square and the two-line title beside it.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.vm, required this.tokens});

  final ObTransportBarVm vm;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: tokens.size.appTileSize,
          height: tokens.size.appTileSize,
          decoration: BoxDecoration(
            color: tokens.color.accent,
            borderRadius: tokens.radius.controlBorder,
          ),
          alignment: Alignment.center,
          child: Container(
            width: tokens.spacing.sm,
            height: tokens.spacing.sm,
            decoration: BoxDecoration(
              color: tokens.color.surfaceSunken,
              shape: BoxShape.circle,
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(vm.title, style: tokens.type.brandCaps),
            Text(vm.subtitle, style: tokens.type.microCaps),
          ],
        ),
      ],
    );
  }
}

class _TransportCluster extends StatelessWidget {
  const _TransportCluster({
    required this.vm,
    this.onUndo,
    this.onRedo,
    this.onTogglePlay,
    this.onStop,
    this.onToggleLoop,
  });

  final ObTransportBarVm vm;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onStop;
  final VoidCallback? onToggleLoop;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Row(
      children: <Widget>[
        ObTransportButton(
          onTap: onUndo,
          child: ObChromeGlyph(
            kind: ObChromeGlyphKind.undo,
            color: color.textSecondary,
          ),
        ),
        SizedBox(width: tokens.spacing.xs),
        ObTransportButton(
          onTap: onRedo,
          child: ObChromeGlyph(
            kind: ObChromeGlyphKind.redo,
            color: color.textSecondary,
          ),
        ),
        SizedBox(width: tokens.spacing.xs),
        // The play control is the one accented thing in the bar — what the
        // eye finds without looking.
        ObTransportButton(
          onTap: onTogglePlay,
          active: vm.playing,
          child: ObChromeGlyph(
            kind: ObChromeGlyphKind.play,
            color: vm.playing ? color.textPrimary : color.textSecondary,
          ),
        ),
        SizedBox(width: tokens.spacing.xs),
        ObTransportButton(
          onTap: onStop,
          child: ObChromeGlyph(
            kind: ObChromeGlyphKind.stop,
            color: color.textSecondary,
          ),
        ),
        SizedBox(width: tokens.spacing.xs),
        ObTransportButton(
          onTap: onToggleLoop,
          toggled: vm.looping,
          child: ObChromeGlyph(
            kind: ObChromeGlyphKind.loop,
            color: vm.looping ? color.accentBright : color.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The vertical L/R master meter slivers: a three-colour stack per channel,
/// filled from the bottom by level.
class _MasterMeter extends StatelessWidget {
  const _MasterMeter({required this.vm, required this.tokens});

  final ObTransportBarVm vm;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: tokens.size.readoutBoxHeight,
      child: Row(
        children: <Widget>[
          _MeterSliver(level: vm.meterLeft, tokens: tokens),
          SizedBox(width: tokens.size.masterMeterSliverGap),
          _MeterSliver(level: vm.meterRight, tokens: tokens),
        ],
      ),
    );
  }
}

class _MeterSliver extends StatelessWidget {
  const _MeterSliver({required this.level, required this.tokens});

  final double level;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.masterMeterSliverWidth,
      height: tokens.size.readoutBoxHeight,
      decoration: BoxDecoration(
        color: tokens.color.meterTrack,
        borderRadius: tokens.radius.meterBorder,
      ),
      child: ClipRRect(
        borderRadius: tokens.radius.meterBorder,
        child: CustomPaint(
          painter: _MeterSliverPainter(
            level: level.clamp(0.0, 1.0),
            color: tokens.color,
          ),
        ),
      ),
    );
  }
}

class _MeterSliverPainter extends CustomPainter {
  _MeterSliverPainter({required this.level, required this.color});

  final double level;
  final ColorTokens color;

  @override
  void paint(Canvas canvas, Size size) {
    // Conventional meter bands: green below −12 dB, amber approaching 0, red
    // at clipping. The bands are part of the meter's meaning, not decoration.
    const double amberFrom = 0.7;
    const double redFrom = 0.85;
    final double fillHeight = size.height * level;
    void band(double fromUnit, double toUnit, Color c) {
      final double from = size.height * fromUnit;
      final double to = size.height * toUnit;
      final double top = size.height - to.clamp(0.0, fillHeight);
      final double bottom = size.height - from.clamp(0.0, fillHeight);
      if (bottom > top) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, bottom - top),
          Paint()..color = c,
        );
      }
    }

    band(0, amberFrom, color.meterLow);
    band(amberFrom, redFrom, color.meterMid);
    band(redFrom, 1, color.meterHigh);
  }

  @override
  bool shouldRepaint(_MeterSliverPainter oldDelegate) =>
      oldDelegate.level != level;
}

class _ExportButton extends StatefulWidget {
  const _ExportButton({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: widget.onTap == null
          ? null
          : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null
          ? null
          : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.exportButtonWidth,
          height: tokens.size.controlHeight,
          decoration: BoxDecoration(
            color: _hover ? tokens.color.accentBright : tokens.color.accent,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: tokens.color.accentDeep,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ObChromeGlyph(
                kind: ObChromeGlyphKind.download,
                color: tokens.color.textPrimary,
                scale: ObGlyphScale.chrome,
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                'Export',
                style: tokens.type.label.copyWith(
                  color: tokens.color.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
