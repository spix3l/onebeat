// ConsoleBinding — REPL and script console binding (UI-D-08).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.message,
    this.level = LogLevel.info,
  });

  final String timestamp;
  final String message;
  final LogLevel level;
}

class ConsoleBinding extends StatefulWidget {
  const ConsoleBinding({
    this.onClose,
    this.onExecuteScript,
    super.key,
  });

  final VoidCallback? onClose;
  final ValueChanged<String>? onExecuteScript;

  @override
  State<ConsoleBinding> createState() => _ConsoleBindingState();
}

class _ConsoleBindingState extends State<ConsoleBinding> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  LogLevel? _filterLevel;

  final List<LogEntry> _logs = <LogEntry>[
    const LogEntry(
      timestamp: '18:12:04.102',
      message: '[engine] Initialized audio device CoreAudio 48000Hz (buffer 128)',
      level: LogLevel.info,
    ),
    const LogEntry(
      timestamp: '18:12:04.145',
      message: '[plugins] Discovered 4 internal DSP processors',
      level: LogLevel.info,
    ),
    const LogEntry(
      timestamp: '18:12:05.890',
      message: '[sandbox] Extension runtime ready (wasm32-wasi)',
      level: LogLevel.info,
    ),
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submitInput() {
    final String text = _inputController.text.trim();
    if (text.isEmpty) return;

    final String now = DateTime.now().toIso8601String().substring(11, 23);
    setState(() {
      _logs.add(
        LogEntry(
          timestamp: now,
          message: '> $text',
          level: LogLevel.info,
        ),
      );
      _logs.add(
        LogEntry(
          timestamp: now,
          message: 'Executed: $text',
          level: LogLevel.info,
        ),
      );
      _inputController.clear();
    });

    widget.onExecuteScript?.call(text);
    _inputFocus.requestFocus();
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final List<LogEntry> displayedLogs = _filterLevel == null
        ? _logs
        : _logs.where((LogEntry l) => l.level == _filterLevel).toList();

    return Container(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
          Container(
            height: tokens.size.pianoToolbarHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            decoration: BoxDecoration(
              color: tokens.color.surfacePanel,
              border: Border(
                bottom: BorderSide(
                  color: tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text('SCRIPT CONSOLE', style: tokens.type.sectionHeader),
                SizedBox(width: tokens.spacing.sm),
                Text('REPL & engine diagnostics', style: tokens.type.label),
                const Spacer(),
                ObButton(
                  label: 'Clear',
                  onTap: _clearLogs,
                ),
                if (widget.onClose != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.sm),
                  GestureDetector(
                    onTap: widget.onClose,
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
              ],
            ),
          ),
          // Output logs
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(tokens.spacing.md),
              itemCount: displayedLogs.length,
              itemBuilder: (BuildContext context, int index) {
                final LogEntry entry = displayedLogs[index];
                final Color levelColor = switch (entry.level) {
                  LogLevel.warn => tokens.color.warning,
                  LogLevel.error => tokens.color.danger,
                  LogLevel.info => tokens.color.textSecondary,
                };

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.timestamp,
                        style: tokens.type.numericSmall.copyWith(
                          color: tokens.color.textMuted,
                        ),
                      ),
                      SizedBox(width: tokens.spacing.sm),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: tokens.type.numericSmall.copyWith(
                            color: levelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Input bar
          Container(
            padding: EdgeInsets.all(tokens.spacing.sm),
            decoration: BoxDecoration(
              color: tokens.color.surfacePanel,
              border: Border(
                top: BorderSide(
                  color: tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text('> ', style: tokens.type.numeric),
                Expanded(
                  child: EditableText(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    style: tokens.type.numeric.copyWith(
                      color: tokens.color.textPrimary,
                    ),
                    cursorColor: tokens.color.accent,
                    backgroundCursorColor: tokens.color.surfaceDeep,
                    onSubmitted: (_) => _submitInput(),
                  ),
                ),
                SizedBox(width: tokens.spacing.sm),
                ObButton(
                  label: 'Run',
                  tone: ObButtonTone.primary,
                  onTap: _submitInput,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
