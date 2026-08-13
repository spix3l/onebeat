// Frame-timing overlay, toggled with F8 (OB-1-11 §5).
//
// It stays in the app for every future UI ticket: the 120 Hz claim has to be
// checkable at any moment, not only in the one PR that made it.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'engine_controller.dart';
import 'frame_stats.dart';

class FrameTimingOverlay extends StatelessWidget {
  const FrameTimingOverlay({required this.controller, super.key});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        if (!controller.showPerformanceOverlay) {
          return const SizedBox.shrink();
        }
        return Positioned(
          right: tokens.spacing.lg,
          top: tokens.spacing.lg,
          child: AnimatedBuilder(
            animation: controller.frameStats,
            builder: (BuildContext context, Widget? child) {
              final FrameStats stats = controller.frameStats;
              return Container(
                padding: EdgeInsets.all(tokens.spacing.md),
                decoration: BoxDecoration(
                  color: tokens.color.surfaceRaised,
                  borderRadius: tokens.radius.panelBorder,
                  border: Border.all(
                    color: tokens.color.line,
                    width: tokens.border.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('FRAME TIMING  (F8)', style: tokens.type.label),
                    SizedBox(height: tokens.spacing.sm),
                    _row(tokens, 'budget', '${stats.budgetMillis.toStringAsFixed(2)} ms'),
                    _row(tokens, 'build', '${stats.averageBuildMillis.toStringAsFixed(2)} ms'),
                    _row(tokens, 'raster', '${stats.averageRasterMillis.toStringAsFixed(2)} ms'),
                    _row(tokens, 'worst', '${stats.worstFrameMillis.toStringAsFixed(2)} ms'),
                    _row(tokens, 'frames', '${stats.totalFrames}'),
                    _row(
                      tokens,
                      'dropped',
                      '${stats.droppedFrames}',
                      warn: stats.droppedFrames > 0,
                    ),
                    SizedBox(height: tokens.spacing.sm),
                    _row(tokens, 'xruns', '${controller.snapshot.xrunCount}',
                        warn: controller.snapshot.xrunCount > 0),
                    _row(tokens, 'voices', '${controller.snapshot.activeVoices}'),
                    _row(tokens, 'events', '${controller.snapshot.scheduleEventCount}'),
                    if (kDebugMode) ...<Widget>[
                      SizedBox(height: tokens.spacing.sm),
                      Text(
                        'debug build — measure in profile mode',
                        style: tokens.type.label.copyWith(color: tokens.color.warning),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _row(OneBeatTokens tokens, String label, String value, {bool warn = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: tokens.size.overlayLabelWidth,
            child: Text(label, style: tokens.type.label),
          ),
          Text(
            value,
            style: tokens.type.numericSmall.copyWith(
              color: warn ? tokens.color.danger : tokens.color.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
