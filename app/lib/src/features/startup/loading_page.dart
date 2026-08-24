import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

class OneBeatLoadingPage extends StatefulWidget {
  const OneBeatLoadingPage({super.key});

  @override
  State<OneBeatLoadingPage> createState() => _OneBeatLoadingPageState();
}

class _OneBeatLoadingPageState extends State<OneBeatLoadingPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OneBeatTokens.dark().motion.loadingCycle,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                'assets/branding/onebeat_logo.png',
                width: tokens.size.loadingLogoWidth,
                filterQuality: FilterQuality.high,
              ),
              SizedBox(height: tokens.spacing.xxl),
              AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return SizedBox(
                    width: tokens.size.loadingTrackWidth,
                    height: tokens.size.loadingTrackHeight,
                    child: Align(
                      alignment: Alignment(-1 + _controller.value * 2, 0),
                      child: FractionallySizedBox(widthFactor: 0.28, child: ColoredBox(color: tokens.color.accent)),
                    ),
                  );
                },
              ),
              SizedBox(height: tokens.spacing.md),
              Text('ONEBEAT', style: tokens.type.label),
            ],
          ),
        ),
      ),
    );
  }
}
