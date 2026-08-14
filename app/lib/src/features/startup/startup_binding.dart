// StartupBinding — manages initial startup, project template and recovery states (UI-D-07).
import 'package:flutter/widgets.dart';

import '../../engine/engine_client.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/empty_state.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/prose.dart';

enum StartupPhase { ready, loading, recovery }

class StartupBinding extends StatefulWidget {
  const StartupBinding({
    required this.client,
    required this.onNewProject,
    required this.onOpenProject,
    this.onLoadDemo,
    this.onRecoverProject,
    super.key,
  });

  final EngineClient client;
  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback? onLoadDemo;
  final VoidCallback? onRecoverProject;

  @override
  State<StartupBinding> createState() => _StartupBindingState();
}

class _StartupBindingState extends State<StartupBinding> {
  final StartupPhase _phase = StartupPhase.ready;

  static const ObEmptyStateVm _welcomeVm = ObEmptyStateVm(
    icon: ObKitGlyphKind.waveform,
    heading: 'Welcome to OneBeat',
    body: <ObProseRun>[
      ObProseRun('Create a new beat, open an existing project, or load the factory demo template to explore the sound engine.'),
    ],
    footnote: 'Audio engine initialized · CoreAudio 48.0 kHz 128 samples',
  );

  static const ObEmptyStateVm _recoveryVm = ObEmptyStateVm(
    icon: ObKitGlyphKind.warning,
    heading: 'Unsaved Session Detected',
    body: <ObProseRun>[
      ObProseRun('An unexpected session interruption was detected. Would you like to recover your unsaved project edits?'),
    ],
    footnote: 'Autosave checkpoint found from recent session',
  );

  @override
  Widget build(BuildContext context) {
    if (_phase == StartupPhase.recovery) {
      return ObEmptyState(
        vm: _recoveryVm,
        actions: <Widget>[
          ObButton(
            label: 'Recover Project',
            tone: ObButtonTone.primary,
            onTap: () {
              widget.onRecoverProject?.call();
              widget.onNewProject();
            },
          ),
          ObButton(
            label: 'Discard & Start Fresh',
            onTap: widget.onNewProject,
          ),
        ],
      );
    }

    return ObEmptyState(
      vm: _welcomeVm,
      actions: <Widget>[
        ObButton(
          label: 'New Project',
          tone: ObButtonTone.primary,
          onTap: widget.onNewProject,
        ),
        ObButton(
          label: 'Open Project...',
          onTap: widget.onOpenProject,
        ),
        if (widget.onLoadDemo != null)
          ObButton(
            label: 'Load Demo',
            tone: ObButtonTone.accentOutline,
            onTap: widget.onLoadDemo,
          ),
      ],
    );
  }
}
