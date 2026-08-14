// Extension Manager View (matches onebeat-ext-mgr.html.png and onebeat-ext-panel.html.png).
//
// Installed WASM extensions, permission capabilities, and crash containment inspectors.
// Built entirely from tokens with zero raw literals.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'icons.dart';

class ExtensionManagerView extends StatefulWidget {
  const ExtensionManagerView({
    required this.controller,
    super.key,
  });

  final EngineController controller;

  @override
  State<ExtensionManagerView> createState() => _ExtensionManagerViewState();
}

class _ExtensionManagerViewState extends State<ExtensionManagerView> {
  int _selectedExtension = 0;

  final List<_ExtensionData> _extensions = const <_ExtensionData>[
    _ExtensionData(
      name: 'Harmonizer',
      version: 'v1.2',
      author: 'OneBeat Team',
      description: 'Generates modal and jazz chord progressions from monophonic basslines.',
      permissions: <String>['Pattern read/write', 'Realtime preview'],
      enabled: true,
    ),
    _ExtensionData(
      name: 'Clip Roulette',
      version: 'v0.8',
      author: 'GlitchWorks',
      description: 'Randomizes arrangement slice positions with mathematical constraints.',
      permissions: <String>['Arrangement write', 'Undo history'],
      enabled: true,
    ),
    _ExtensionData(
      name: 'Drum Fill Generator',
      version: 'v2.0',
      author: 'BeatCrafter',
      description: 'Automatic velocity-sensitive snare rolls and syncopated trap fills.',
      permissions: <String>['Channel rack write'],
      enabled: true,
    ),
    _ExtensionData(
      name: 'Groove Fetcher',
      version: 'v1.1',
      author: 'CloudMIDI',
      description: 'Pulls open-access human drummer swing patterns from local & remote repository.',
      permissions: <String>['Network access', 'Preset import'],
      enabled: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final _ExtensionData selected = _extensions[_selectedExtension.clamp(0, _extensions.length - 1)];

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
                Text('EXTENSION MANAGER', style: tokens.type.sectionHeader),
                SizedBox(width: tokens.spacing.md),
                Text('WASM plugins run in secure isolated sandboxes (NFR-03)', style: tokens.type.label),
                const Spacer(),
                OneBeatButton(
                  label: '+ Install Extension...',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          // Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // List of extensions
                Container(
                  width: tokens.size.patternSelectorWidth * 1.2, // token-lint-ok: ratio
                  decoration: BoxDecoration(
                    color: tokens.color.surfacePanel,
                    border: Border(
                      right: BorderSide(
                        color: tokens.color.line,
                        width: tokens.border.hairline,
                      ),
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: _extensions.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _ExtensionData ext = _extensions[index];
                      final bool isSelected = index == _selectedExtension;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedExtension = index),
                        child: Container(
                          padding: EdgeInsets.all(tokens.spacing.md),
                          decoration: BoxDecoration(
                            color: isSelected ? tokens.color.surfaceOverlay : null,
                            border: Border(
                              bottom: BorderSide(color: tokens.color.line, width: tokens.border.hairline),
                              left: isSelected ? BorderSide(color: tokens.color.accent, width: tokens.border.emphasis) : BorderSide.none,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      ext.name,
                                      style: tokens.type.body.copyWith(
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        color: isSelected ? tokens.color.accent : tokens.color.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(ext.version, style: tokens.type.numericSmall),
                                ],
                              ),
                              SizedBox(height: tokens.spacing.xxs),
                              Text(
                                ext.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.type.numericSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Extension Detail Inspector
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.xl),
                    child: ListView(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(selected.name, style: tokens.type.title),
                            SizedBox(width: tokens.spacing.sm),
                            Text(selected.version, style: tokens.type.numeric),
                            const Spacer(),
                            OneBeatButton(
                              label: selected.enabled ? 'ACTIVE' : 'DISABLED',
                              active: selected.enabled,
                              onPressed: () {},
                            ),
                          ],
                        ),
                        SizedBox(height: tokens.spacing.xs),
                        Text('By ${selected.author}', style: tokens.type.label),
                        SizedBox(height: tokens.spacing.md),
                        Text(selected.description, style: tokens.type.body),
                        SizedBox(height: tokens.spacing.xl),
                        Text('CAPABILITY & PERMISSIONS (SANDBOX)', style: tokens.type.label),
                        SizedBox(height: tokens.spacing.sm),
                        for (final String perm in selected.permissions)
                          Container(
                            margin: EdgeInsets.only(bottom: tokens.spacing.xs),
                            padding: EdgeInsets.all(tokens.spacing.sm),
                            decoration: BoxDecoration(
                              color: tokens.color.surfaceDeep,
                              borderRadius: tokens.radius.controlBorder,
                              border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
                            ),
                            child: Row(
                              children: <Widget>[
                                OneBeatIcon(
                                  OneBeatIconData.lock,
                                  size: tokens.size.tagHeight,
                                  color: tokens.color.textMuted,
                                ),
                                SizedBox(width: tokens.spacing.sm),
                                Text(perm, style: tokens.type.body),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionData {
  const _ExtensionData({
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.permissions,
    required this.enabled,
  });

  final String name;
  final String version;
  final String author;
  final String description;
  final List<String> permissions;
  final bool enabled;
}
