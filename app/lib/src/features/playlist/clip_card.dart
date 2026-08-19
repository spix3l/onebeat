// ObClipCard — one block of arrangement (UI-B-08).
//
// The card is the only saturated thing on the playlist canvas, which is the
// whole point: the arrangement is read by colour and shape from across the
// room, and everything around it stays grey so it can be.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

@immutable
class ClipPreviewNoteVm {
  const ClipPreviewNoteVm({
    required this.x,
    required this.width,
    required this.y,
  });

  /// Normalised position in the pattern preview.
  final double x;
  final double width;
  final double y;
}

@immutable
class ClipVm {
  const ClipVm({
    required this.id,
    required this.name,
    required this.duration,
    required this.color,
    required this.startBar,
    required this.lengthBars,
    required this.lane,
    this.selected = false,
    this.isAudio = false,
    this.waveform = const <double>[],
    this.instrumentName = '',
    this.previewNotes = const <ClipPreviewNoteVm>[],
  });

  final int id;
  final String name;

  /// Already formatted (`0:08`). The vm owns time formatting; the card owns
  /// only the look.
  final String duration;

  /// The clip's identity colour, from `ColorTokens.channelColors`.
  final Color color;

  /// Position and length in bars — fractional, because the mockup's clips do
  /// not all start on a bar line.
  final double startBar;
  final double lengthBars;

  /// Which row the clip sits on, zero-based.
  final int lane;

  final bool selected;
  final bool isAudio;
  final List<double> waveform;
  final String instrumentName;
  final List<ClipPreviewNoteVm> previewNotes;
}

enum ClipResizeEdge { start, end }

class ObClipCard extends StatefulWidget {
  const ObClipCard({
    required this.vm,
    this.onTap,
    this.onDoubleTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
    this.onResizeCancel,
    super.key,
  });

  final ClipVm vm;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onPanCancel;
  final void Function(ClipResizeEdge edge, DragStartDetails details)? onResizeStart;
  final GestureDragUpdateCallback? onResizeUpdate;
  final GestureDragEndCallback? onResizeEnd;
  final VoidCallback? onResizeCancel;

  @override
  State<ObClipCard> createState() => _ObClipCardState();
}

class _ObClipCardState extends State<ObClipCard> {
  bool _hover = false;
  bool _resizeEdgeHover = false;
  bool _resizing = false;

  ClipResizeEdge? _resizeEdge(Offset local) {
    final double width = context.size?.width ?? 0;
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double handle = tokens.size.playlistResizeHandleWidth;
    final double edgeWidth = math.min(handle, width / 3);
    if (widget.onResizeStart == null || width <= 0) return null;
    if (local.dx <= edgeWidth) return ClipResizeEdge.start;
    if (local.dx >= width - edgeWidth || local.dx >= width + handle) return ClipResizeEdge.end;
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    // The left edge is an explicit child handle. Use the gesture recogniser's
    // own coordinates for the right-edge fallback so a parent-positioned card
    // cannot turn a body drag into a resize.
    final ClipResizeEdge? edge = _resizeEdge(details.localPosition);
    _resizing = edge == ClipResizeEdge.end;
    if (_resizing) {
      widget.onResizeStart?.call(ClipResizeEdge.end, details);
    } else {
      widget.onPanStart?.call(details);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_resizing) {
      widget.onResizeUpdate?.call(details);
    } else {
      widget.onPanUpdate?.call(details);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_resizing) {
      widget.onResizeEnd?.call(details);
    } else {
      widget.onPanEnd?.call(details);
    }
    _resizing = false;
  }

  void _onPanCancel() {
    if (_resizing) {
      widget.onResizeCancel?.call();
    } else {
      widget.onPanCancel?.call();
    }
    _resizing = false;
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null || widget.onDoubleTap != null || widget.onPanStart != null;

    return MouseRegion(
      cursor: enabled
          ? (_resizeEdgeHover ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.click)
          : MouseCursor.defer,
      onEnter: enabled
          ? (PointerEnterEvent event) => setState(() {
              _hover = true;
              _resizeEdgeHover = _resizeEdge(event.localPosition) != null;
            })
          : null,
      onHover: enabled
          ? (PointerHoverEvent event) => setState(() {
              _resizeEdgeHover = _resizeEdge(event.localPosition) != null;
            })
          : null,
      onExit: enabled
          ? (_) => setState(() {
              _hover = false;
              _resizeEdgeHover = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onPanStart: enabled ? _onPanStart : null,
        onPanUpdate: enabled ? _onPanUpdate : null,
        onPanEnd: enabled ? _onPanEnd : null,
        onPanCancel: enabled ? _onPanCancel : null,
        child: Container(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            // Keep the saturated identity colour, but let the arrangement
            // grid show through the clip body.
            color: widget.vm.color.withValues(alpha: 0.58), // token-lint-ok: clip identity translucency
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              // Selection brightens the edge rather than the fill: the fill is
              // the clip's identity and must not change when you click it.
              color: widget.vm.selected ? color.clipSelectedOutline : (_hover ? color.textPrimary : color.none),
              width: tokens.border.emphasis,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (widget.vm.isAudio && widget.vm.waveform.isNotEmpty)
                CustomPaint(
                  painter: AudioWaveformPainter(
                    samples: widget.vm.waveform,
                    color: color.clipInkMuted,
                  ),
                ),
              if (!widget.vm.isAudio && widget.vm.previewNotes.isNotEmpty)
                CustomPaint(
                  painter: PatternPreviewPainter(
                    notes: widget.vm.previewNotes,
                    color: color.clipInkMuted,
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.spacing.sm,
                  vertical: tokens.spacing.xs,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.vm.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.clipName,
                    ),
                    Text(
                      widget.vm.isAudio || widget.vm.instrumentName.isEmpty
                          ? widget.vm.duration
                          : '${widget.vm.instrumentName} · ${widget.vm.duration}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.clipDuration,
                    ),
                  ],
                ),
              ),
              if (widget.onResizeStart != null) ...<Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: tokens.size.playlistResizeHandleWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (DragStartDetails details) => widget.onResizeStart!(ClipResizeEdge.start, details),
                    onPanUpdate: widget.onResizeUpdate,
                    onPanEnd: widget.onResizeEnd,
                    onPanCancel: widget.onResizeCancel,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: tokens.size.playlistResizeHandleWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (DragStartDetails details) => widget.onResizeStart!(ClipResizeEdge.end, details),
                    onPanUpdate: widget.onResizeUpdate,
                    onPanEnd: widget.onResizeEnd,
                    onPanCancel: widget.onResizeCancel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a compact piano-roll-like note preview over a pattern clip. It is
/// deliberately a silhouette rather than a second editable roll: the clip
/// remains a placement, while the small note shapes answer "what instrument
/// did I play here?" at a glance.
class PatternPreviewPainter extends CustomPainter {
  PatternPreviewPainter({required this.notes, required this.color});

  final List<ClipPreviewNoteVm> notes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || size.width <= 0 || size.height <= 0) return;
    final Paint paint = Paint()..color = color.withValues(alpha: 0.62); // token-lint-ok: preview translucency
    for (final ClipPreviewNoteVm note in notes) {
      final double left = (note.x.clamp(0.0, 1.0)) * size.width;
      final double width = math.max(1.0, note.width * size.width);
      final double top = (1.0 - note.y.clamp(0.0, 1.0)) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, width, math.max(1.0, size.height * 0.08)),
          Radius.circular(size.height * 0.04),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PatternPreviewPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.notes, notes);
}

/// Draws a compact mirrored peak envelope over an audio clip. The samples are
/// normalised peak values, so this painter does not need to know the source
/// sample rate or duration.
class AudioWaveformPainter extends CustomPainter {
  AudioWaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.width / samples.length * 0.62);
    final double middle = size.height / 2;
    final double halfHeight = size.height * 0.44;
    for (int index = 0; index < samples.length; index++) {
      final double x = samples.length == 1 ? size.width / 2 : index * size.width / (samples.length - 1);
      final double half = halfHeight * samples[index].clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, middle - half),
        Offset(x, middle + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.samples, samples);
}
