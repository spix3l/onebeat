// The real macOS menu bar.
//
// The design screens draw a menu bar across the top of the screen — File, Edit,
// Pattern, View, Tools, Mixer, Window, Help — and the status bar tells the user
// "Actions: system menu bar". The app used to draw that row *inside* its own
// top bar as plain text: it looked like the design at a glance, it consumed
// about 300px of a bar that was already overflowing, and none of it opened a
// menu. Meanwhile the actual system menu bar still said "onebeat / Edit / View
// / Window / Help" — Flutter's default.
//
// This is the same menu structure, handed to macOS. Items the app cannot yet
// perform are declared with a null callback, which macOS renders greyed — the
// design screens grey out "Export MIDI…" and "Delete pattern" for exactly that
// reason, so the shape of the product stays legible before every part of it
// exists (FR-UX-13).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'engine_controller.dart';

/// Wraps [child] in the platform menu bar. On anything other than macOS this
/// renders [child] untouched, which is what `PlatformMenuBar` does by design.
class OneBeatMenuBar extends StatefulWidget {
  const OneBeatMenuBar({
    required this.controller,
    required this.onOpenExport,
    required this.onOpenPreferences,
    required this.onOpenShortcuts,
    required this.child,
    super.key,
  });

  final EngineController controller;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenPreferences;
  final VoidCallback onOpenShortcuts;
  final Widget child;

  @override
  State<OneBeatMenuBar> createState() => _OneBeatMenuBarState();
}

class _OneBeatMenuBarState extends State<OneBeatMenuBar> {
  /// What the menu actually depends on: the undo and redo entries. Everything
  /// else in it is static.
  ///
  /// The controller notifies on every frame, and rebuilding a `PlatformMenuBar`
  /// re-serialises the whole menu tree over a platform channel — so listening
  /// to it directly handed macOS a new menu 120 times a second to show a label
  /// that changes when the user edits something. This rebuilds when that label
  /// does, and not otherwise.
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _signature = _undoSignature();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(OneBeatMenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  String _undoSignature() {
    final EngineController controller = widget.controller;
    return '${controller.client.canUndoProject}|'
        '${controller.client.undoProjectName}|'
        '${controller.client.canRedoProject}|'
        '${controller.client.redoProjectName}';
  }

  void _onControllerChanged() {
    final String next = _undoSignature();
    if (next == _signature) return;
    setState(() => _signature = next);
  }

  EngineController get controller => widget.controller;
  VoidCallback get onOpenExport => widget.onOpenExport;
  VoidCallback get onOpenPreferences => widget.onOpenPreferences;
  VoidCallback get onOpenShortcuts => widget.onOpenShortcuts;

  @override
  Widget build(BuildContext context) =>
      PlatformMenuBar(menus: _menus(), child: widget.child);

  /// A platform-provided item, or nothing where the platform has no such menu.
  ///
  /// `PlatformProvidedMenuItem` throws rather than degrading when the target
  /// has no equivalent — which is every non-macOS target, including the widget
  /// test binding. Guarding here is what lets the shell be pumped in a test at
  /// all, and it is what the API asks callers to do.
  List<PlatformMenuItem> _provided(List<PlatformProvidedMenuItemType> types) {
    return <PlatformMenuItem>[
      for (final PlatformProvidedMenuItemType type in types)
        if (PlatformProvidedMenuItem.hasMenu(type))
          PlatformProvidedMenuItem(type: type),
    ];
  }

  /// The same, wrapped in a separator group — and omitted entirely when the
  /// platform provides none of [types], because an empty group asserts.
  List<PlatformMenuItem> _providedGroup(
    List<PlatformProvidedMenuItemType> types,
  ) {
    final List<PlatformMenuItem> members = _provided(types);
    if (members.isEmpty) return const <PlatformMenuItem>[];
    return <PlatformMenuItem>[PlatformMenuItemGroup(members: members)];
  }

  List<PlatformMenuItem> _menus() => <PlatformMenuItem>[
    // The first menu takes the application's name on macOS whatever it is
    // labelled here.
    PlatformMenu(
      label: 'OneBeat',
      menus: <PlatformMenuItem>[
        ..._provided(<PlatformProvidedMenuItemType>[
          PlatformProvidedMenuItemType.about,
        ]),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Settings…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: onOpenPreferences,
            ),
          ],
        ),
        ..._providedGroup(<PlatformProvidedMenuItemType>[
          PlatformProvidedMenuItemType.hide,
          PlatformProvidedMenuItemType.hideOtherApplications,
        ]),
        ..._providedGroup(<PlatformProvidedMenuItemType>[
          PlatformProvidedMenuItemType.quit,
        ]),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: <PlatformMenuItem>[
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(label: 'New project'),
            PlatformMenuItem(label: 'Open…'),
            PlatformMenuItem(label: 'Save'),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Export audio…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyE,
                meta: true,
                shift: true,
              ),
              onSelected: onOpenExport,
            ),
            const PlatformMenuItem(label: 'Export stems…'),
            const PlatformMenuItem(label: 'Export selection…'),
            const PlatformMenuItem(label: 'Export MIDI…'),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: controller.client.canUndoProject &&
                  controller.client.undoProjectName.isNotEmpty
              ? 'Undo ${controller.client.undoProjectName}'
              : 'Undo',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
          ),
          onSelected:
              controller.client.canUndoProject ? controller.undoProject : null,
        ),
        PlatformMenuItem(
          label: controller.client.canRedoProject &&
                  controller.client.redoProjectName.isNotEmpty
              ? 'Redo ${controller.client.redoProjectName}'
              : 'Redo',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
          onSelected:
              controller.client.canRedoProject ? controller.redoProject : null,
        ),
      ],
    ),
    const PlatformMenu(
      label: 'Pattern',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(label: 'New pattern'),
            PlatformMenuItem(label: 'Pattern selector…'),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(label: 'Insert pattern clip'),
            PlatformMenuItem(label: 'Duplicate clip'),
            PlatformMenuItem(label: 'Make unique'),
            PlatformMenuItem(label: 'Split clip at playhead'),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(label: 'Rename pattern'),
            PlatformMenuItem(label: 'Delete pattern'),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            for (final (WorkspaceView view, String label)
                in const <(WorkspaceView, String)>[
              (WorkspaceView.arrangement, 'Playlist'),
              (WorkspaceView.pianoRoll, 'Piano roll'),
              (WorkspaceView.rack, 'Channel rack'),
              (WorkspaceView.mixer, 'Mixer'),
            ])
              PlatformMenuItem(
                label: label,
                onSelected: () => controller.setView(view),
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Search actions',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
              ),
              onSelected: onOpenShortcuts,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Tools',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Script console',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyJ,
            meta: true,
          ),
          onSelected: () => controller.setView(WorkspaceView.console),
        ),
        PlatformMenuItem(
          label: 'Extension manager…',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            alt: true,
          ),
          onSelected: () => controller.setView(WorkspaceView.extensions),
        ),
        PlatformMenuItem(
          label: 'Built-in plug-ins',
          onSelected: () => controller.setView(WorkspaceView.plugins),
        ),
      ],
    ),
    PlatformMenu(
      label: 'Mixer',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Routing…',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
          ),
          onSelected: () => controller.setView(WorkspaceView.mixer),
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(label: 'Add send'),
            PlatformMenuItem(label: 'Add sidechain input'),
            PlatformMenuItem(label: 'Group selected tracks…'),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Window',
      menus: _provided(<PlatformProvidedMenuItemType>[
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
      ]),
    ),
    PlatformMenu(
      label: 'Help',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Keyboard shortcuts',
          onSelected: onOpenShortcuts,
        ),
      ],
    ),
  ];
}
