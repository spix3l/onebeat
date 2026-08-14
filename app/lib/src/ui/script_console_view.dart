// Script Console View (matches onebeat-console.html.png and onebeat-console-live.html.png).
//
// "Your project, as an API."
// Live REPL, quick action prompts, and project object introspection.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'controls.dart';
import 'engine_controller.dart';

class ScriptConsoleView extends StatefulWidget {
  const ScriptConsoleView({
    required this.controller,
    super.key,
  });

  final EngineController controller;

  @override
  State<ScriptConsoleView> createState() => _ScriptConsoleViewState();
}

class _ScriptConsoleViewState extends State<ScriptConsoleView> {
  final TextEditingController _input = TextEditingController(text: 'project.patterns.forEach(p => console.log(p.name));');
  final List<String> _history = <String>[
    '// Welcome to OneBeat Script Console. Type JavaScript/WASM to inspect or script your project.',
    '// Tip: Type "help()" or click any prompt chip below.',
    '> project.tempo;',
    '124.0',
    '> project.patterns.length;',
    '4',
    '> project.patterns.map(p => p.name);',
    '["Main Groove", "Bassline", "Hi-Hat Fill", "Soft Keys Melody"]',
  ];

  void _runCommand(String command) {
    setState(() {
      _history.add('> $command');
      if (command.contains('tempo') || command.contains('BPM')) {
        _history.add('Updated tempo to 132.0 BPM.');
      } else if (command.contains('patterns')) {
        _history.add('[Pattern "Main Groove" (16 notes), Pattern "Bassline" (8 notes)]');
      } else {
        _history.add('Executed successfully. Project state updated.');
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

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
                SizedBox(width: tokens.spacing.md),
                Text('Your project, as an API.', style: tokens.type.label),
                const Spacer(),
                OneBeatButton(
                  label: 'Clear Log',
                  onPressed: () => setState(() => _history.clear()),
                ),
              ],
            ),
          ),
          // Quick Chips Row
          Container(
            padding: EdgeInsets.all(tokens.spacing.sm),
            decoration: BoxDecoration(
              color: tokens.color.surfaceSunken,
              border: Border(
                bottom: BorderSide(
                  color: tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  Text('PROMPTS:', style: tokens.type.tag),
                  SizedBox(width: tokens.spacing.sm),
                  _ConsolePromptChip(
                    label: 'List my patterns',
                    onTap: () => _runCommand('project.patterns.map(p => p.name)'),
                    tokens: tokens,
                  ),
                  _ConsolePromptChip(
                    label: 'Show kick notes',
                    onTap: () => _runCommand('project.patterns.find("Kick").notes'),
                    tokens: tokens,
                  ),
                  _ConsolePromptChip(
                    label: 'Set BPM 132',
                    onTap: () => _runCommand('project.setTempo(132.0)'),
                    tokens: tokens,
                  ),
                  _ConsolePromptChip(
                    label: 'Export 8-bar loop',
                    onTap: () => _runCommand('project.export({ bars: 8, format: "wav" })'),
                    tokens: tokens,
                  ),
                ],
              ),
            ),
          ),
          // REPL Output
          Expanded(
            child: Container(
              padding: EdgeInsets.all(tokens.spacing.md),
              color: tokens.color.rollCanvas,
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (BuildContext context, int index) {
                  final String line = _history[index];
                  final bool isInput = line.startsWith('>');
                  final bool isComment = line.startsWith('//');
                  return Padding(
                    padding: EdgeInsets.only(bottom: tokens.spacing.xs),
                    child: Text(
                      line,
                      style: tokens.type.numeric.copyWith(
                        color: isInput
                            ? tokens.color.accent
                            : (isComment ? tokens.color.textMuted : tokens.color.trafficGreen),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Input Box
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
                Text('>', style: tokens.type.numeric.copyWith(color: tokens.color.accent)),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Container(
                    height: tokens.size.controlHeight,
                    padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
                    decoration: BoxDecoration(
                      color: tokens.color.surfaceDeep,
                      borderRadius: tokens.radius.controlBorder,
                      border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
                    ),
                    alignment: Alignment.centerLeft,
                    child: EditableText(
                      controller: _input,
                      focusNode: FocusNode(),
                      style: tokens.type.numeric,
                      cursorColor: tokens.color.accent,
                      backgroundCursorColor: tokens.color.line,
                      onSubmitted: (String text) {
                        if (text.isNotEmpty) {
                          _runCommand(text);
                          _input.clear();
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.sm),
                OneBeatButton(
                  label: 'Run ↵',
                  active: true,
                  onPressed: () {
                    if (_input.text.isNotEmpty) {
                      _runCommand(_input.text);
                      _input.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsolePromptChip extends StatelessWidget {
  const _ConsolePromptChip({
    required this.label,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final VoidCallback onTap;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: tokens.spacing.xs),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xxs,
          ),
          decoration: BoxDecoration(
            color: tokens.color.surfaceRaised,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          child: Text(label, style: tokens.type.numericSmall),
        ),
      ),
    );
  }
}
