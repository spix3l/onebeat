// GenericParamEditor — parameter slider list for CLAP/VST3 plugins (UI-C-11 / UI-D-08).
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../engine/engine_client.dart';

class GenericParamEditor extends StatelessWidget {
  const GenericParamEditor({
    required this.parameters,
    this.onParameterChanged,
    super.key,
  });

  final List<HostedParameter> parameters;
  final void Function(int paramId, double value)? onParameterChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    if (parameters.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.xl),
          child: Text(
            'No automatable parameters exposed by this plugin.',
            style: tokens.type.body.copyWith(color: tokens.color.textMuted),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(tokens.spacing.md),
      itemCount: parameters.length,
      itemBuilder: (BuildContext context, int index) {
        final HostedParameter param = parameters[index];
        final double normalized = param.maximum > param.minimum
            ? ((param.value - param.minimum) / (param.maximum - param.minimum)).clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: tokens.size.parameterLabelWidth,
                child: Text(
                  param.name,
                  style: tokens.type.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: _ParamSlider(
                  value: normalized,
                  onChanged: onParameterChanged == null
                      ? null
                      : (double v) {
                          final double denorm = param.minimum + v * (param.maximum - param.minimum);
                          onParameterChanged!(param.id, denorm);
                        },
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              SizedBox(
                width: tokens.size.parameterValueWidth,
                child: Text(
                  param.display.isNotEmpty ? param.display : param.value.toStringAsFixed(2),
                  style: tokens.type.numericSmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.value,
    this.onChanged,
  });

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) {
            if (onChanged == null || constraints.maxWidth <= 0) return;
            final double next = (value + d.delta.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onChanged!(next);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
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
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: tokens.color.accent,
                    borderRadius: tokens.radius.controlBorder,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
