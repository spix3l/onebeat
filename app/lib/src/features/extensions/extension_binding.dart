// ExtensionBinding — wires the extension manager surface to runtime registry (UI-D-08).
import 'package:flutter/widgets.dart';

import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/prose.dart';
import 'extension_manager_screen.dart';
import 'extension_manager_vm.dart';

class ExtensionBinding extends StatefulWidget {
  const ExtensionBinding({
    this.onClose,
    super.key,
  });

  final VoidCallback? onClose;

  @override
  State<ExtensionBinding> createState() => _ExtensionBindingState();
}

class _ExtensionBindingState extends State<ExtensionBinding> {
  String _selectedId = 'ext_humanize';
  final Map<String, bool> _enabledMap = <String, bool>{
    'ext_humanize': true,
    'ext_euclidean': true,
    'ext_chord_gen': false,
    'ext_sidechain': false,
  };

  static const List<ExtensionVm> _defaultExtensions = <ExtensionVm>[
    ExtensionVm(
      id: 'ext_humanize',
      name: 'Humanize Grooves',
      meta: 'by @luma · v1.2.0 · bound to ⇧⌘H',
      icon: ObKitGlyphKind.waveform,
    ),
    ExtensionVm(
      id: 'ext_euclidean',
      name: 'Euclidean Rhythms',
      meta: 'by @onebeat · v2.0.1 · bound to ⌥E',
      icon: ObKitGlyphKind.grid,
    ),
    ExtensionVm(
      id: 'ext_chord_gen',
      name: 'Modal Chord Builder',
      meta: 'by @spix3l · v0.9.4',
      icon: ObKitGlyphKind.note,
    ),
    ExtensionVm(
      id: 'ext_sidechain',
      name: 'Sidechain Auto-Ducker',
      meta: 'by @dsp_lab · v1.0.0',
      icon: ObKitGlyphKind.script,
      crashed: true,
    ),
  ];

  ExtensionDetailVm _buildDetail(String id) {
    if (id == 'ext_sidechain') {
      return const ExtensionDetailVm(
        name: 'Sidechain Auto-Ducker',
        meta: 'by @dsp_lab · v1.0.0 · wasm32-wasi',
        icon: ObKitGlyphKind.script,
        description: <ObProseRun>[
          ObProseRun('Automatically routes audio envelopes between selected mixer tracks.'),
        ],
        enabled: false,
        capabilities: <CapabilityVm>[
          CapabilityVm(name: 'Read project state', granted: true, note: 'mixer channels'),
          CapabilityVm(name: 'Modify project', granted: true, note: 'sends & routing'),
          CapabilityVm(name: 'Network access', granted: false, note: 'impossible by design'),
          CapabilityVm(name: 'Filesystem write', granted: false, note: 'impossible by design'),
        ],
        bindings: <BindingVm>[
          BindingVm(
            icon: ObKitGlyphKind.menuLines,
            label: 'Menu action',
            detail: 'Tools › Auto Duck',
          ),
        ],
        crash: CrashCardVm(
          title: 'SIDECHAIN DUCKER CRASHED — CONTAINED & DISABLED',
          body: <ObProseRun>[
            ObProseRun('The host caught the fault cleanly. Your audio engine and project were protected.'),
          ],
          actions: <String>['Restart Extension', 'Report Issue'],
        ),
      );
    }

    final bool isHumanize = id == 'ext_humanize';
    return ExtensionDetailVm(
      name: isHumanize ? 'Humanize Grooves' : 'Euclidean Rhythms',
      meta: isHumanize ? 'by @luma · v1.2.0 · wasm32-wasi' : 'by @onebeat · v2.0.1 · wasm32-wasi',
      icon: isHumanize ? ObKitGlyphKind.waveform : ObKitGlyphKind.grid,
      description: <ObProseRun>[
        ObProseRun(
          isHumanize
              ? 'Applies subtle timing and velocity jitter to sequenced notes to simulate human performance feel.'
              : 'Generates polyrhythmic euclidean note distributions across step sequences.',
        ),
      ],
      enabled: _enabledMap[id] ?? true,
      capabilities: const <CapabilityVm>[
        CapabilityVm(name: 'Read project state', granted: true, note: 'patterns, notes'),
        CapabilityVm(name: 'Modify project', granted: true, note: 'piano roll selection'),
        CapabilityVm(name: 'Network access', granted: false, note: 'impossible by design'),
        CapabilityVm(name: 'Filesystem write', granted: false, note: 'impossible by design'),
      ],
      bindings: <BindingVm>[
        BindingVm(
          icon: ObKitGlyphKind.keyboard,
          label: 'Keyboard shortcut',
          tag: isHumanize ? '⇧⌘H' : '⌥E',
        ),
        BindingVm(
          icon: ObKitGlyphKind.menuLines,
          label: 'Menu action',
          detail: isHumanize ? 'Edit › Humanize Selection' : 'Tools › Euclidean Generator',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ExtensionVm> list = <ExtensionVm>[
      for (final ExtensionVm ext in _defaultExtensions)
        ExtensionVm(
          id: ext.id,
          name: ext.name,
          meta: ext.meta,
          icon: ext.icon,
          enabled: _enabledMap[ext.id] ?? ext.enabled,
          crashed: ext.crashed,
          selected: ext.id == _selectedId,
        ),
    ];

    final ExtensionManagerVm vm = ExtensionManagerVm(
      extensions: list,
      detail: _buildDetail(_selectedId),
    );

    return ExtensionManagerScreen(
      vm: vm,
      onSelect: (String id) => setState(() => _selectedId = id),
      onToggle: (String id, bool enabled) {
        setState(() => _enabledMap[id] = enabled);
      },
      onToggleSelected: () {
        final bool cur = _enabledMap[_selectedId] ?? true;
        setState(() => _enabledMap[_selectedId] = !cur);
      },
      onCrashAction: (int index) {
        if (index == 0) {
          // Restart
          setState(() {
            _enabledMap[_selectedId] = true;
          });
        }
      },
    );
  }
}
