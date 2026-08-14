// ObReadout — the dark inset value boxes of the transport bar (UI-B-02).
//
// BPM, time signature and the bar·beat·tick clock: values you read far more
// often than you set, drawn as recessed wells with large mono numerals and a
// dim micro-caps unit label beneath. Values arrive as text — the vm owns
// formatting, this widget owns only the look.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

class ObReadout extends StatelessWidget {
  const ObReadout({required this.value, required this.unit, super.key});

  /// The value, already formatted (`124.00`, `4/4`, `02:01:218`).
  final String value;

  /// The micro-caps unit label (`BPM`, `SIG`, `BAR · BEAT · TICK`).
  final String unit;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.readoutBoxHeight,
      // No vertical padding: the border and the 21px numerals claim most of
      // the box, so the column centres itself in what remains.
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        // The one surface darker than the bar it sits on: the readout is an
        // inset, and the near-black border deepens the step.
        color: tokens.color.surfaceSunken,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.meterTrack,
          width: tokens.border.hairline,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(value, maxLines: 1, style: tokens.type.readoutValue),
          SizedBox(height: tokens.spacing.xxs),
          Text(unit, maxLines: 1, style: tokens.type.readoutUnit),
        ],
      ),
    );
  }
}
