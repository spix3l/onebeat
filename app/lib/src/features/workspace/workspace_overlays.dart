// The workspace overlays: the layouts control and menu, a detached panel
// window, and the mid-drag dock state (UI-C-12).
//
// These are the things drawn *over* the workspace rather than in it, which is
// why they live together and why none of them owns a screen. The detached
// window takes a `child` slot rather than reaching for the mixer: what a
// torn-off window contains is the workspace's decision at runtime, and a
// window that imported one panel's widgets could only ever hold that panel.
//
// Presentational only. No OS windowing, no drag gestures, no persistence — the
// drag state here is a picture of a drag, driven by [WorkspaceDragVm].
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/docked_panel.dart';
import '../../ui_kit/floating_window.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/popover_menu.dart';
import 'workspace_vm.dart';

/// The `Layouts Beatmaking` pill in the browser header.
///
/// Accent-outlined rather than filled: it reports the state you are in, and it
/// is open in the mockup — an accent *fill* here would compete with the accent
/// row inside the menu it opened.
class LayoutsPill extends StatelessWidget {
  const LayoutsPill({required this.vm, this.onTap, super.key});

  final WorkspaceLayoutsVm vm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return ObButton(
      label: vm.currentName,
      prefix: vm.pillPrefix,
      icon: ObKitGlyphKind.grid,
      tone: ObButtonTone.accentOutline,
      width: tokens.size.layoutsPillWidth,
      onTap: onTap,
    );
  }
}

/// Builds the LAYOUTS popover from [WorkspaceLayoutsVm].
///
/// The row order is the argument: your layouts, then the things you can do to
/// them, then — after its own rule and last — the escape hatch. `Reset to
/// default` is never the row your finger lands on by accident.
ObPopoverMenuVm layoutsMenuVm(WorkspaceLayoutsVm vm) {
  return ObPopoverMenuVm(
    sections: <ObMenuSectionVm>[
      ObMenuSectionVm(
        header: vm.sectionHeader,
        rows: <ObMenuRowVm>[
          for (final LayoutVm layout in vm.layouts)
            ObMenuRowVm(
              label: layout.name,
              checkable: true,
              checked: layout.current,
              tone: layout.current ? ObMenuRowTone.active : ObMenuRowTone.normal,
            ),
        ],
      ),
      ObMenuSectionVm(
        separated: true,
        rows: <ObMenuRowVm>[
          ObMenuRowVm(label: vm.saveAsLabel, icon: ObKitGlyphKind.plus),
          ObMenuRowVm(label: vm.renameLabel, icon: ObKitGlyphKind.pencil),
          ObMenuRowVm(
            label: vm.deleteLabel,
            icon: ObKitGlyphKind.trash,
            tone: ObMenuRowTone.danger,
          ),
        ],
      ),
      ObMenuSectionVm(
        separated: true,
        rows: <ObMenuRowVm>[
          ObMenuRowVm(label: vm.resetLabel, icon: ObKitGlyphKind.reset),
        ],
      ),
    ],
  );
}

/// The open layouts menu, wired to the five callbacks the ticket names.
class LayoutsMenu extends StatelessWidget {
  const LayoutsMenu({
    required this.vm,
    this.onLayoutSelect,
    this.onSaveAs,
    this.onRename,
    this.onDelete,
    this.onReset,
    super.key,
  });

  final WorkspaceLayoutsVm vm;

  /// Fired with the chosen layout's index in [WorkspaceLayoutsVm.layouts].
  final ValueChanged<int>? onLayoutSelect;

  final VoidCallback? onSaveAs;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final int layoutCount = vm.layouts.length;
    return ObPopoverMenu(
      vm: layoutsMenuVm(vm),
      onSelect: (int index) {
        if (index < layoutCount) {
          onLayoutSelect?.call(index);
          return;
        }
        switch (index - layoutCount) {
          case 0:
            onSaveAs?.call();
          case 1:
            onRename?.call();
          case 2:
            onDelete?.call();
          case 3:
            onReset?.call();
        }
      },
    );
  }
}

/// A torn-off panel in its own window.
///
/// The system draws the close/minimise/zoom buttons — [ObFloatingWindow.panel]
/// reserves the room for them and we style everything else.
class DetachedPanelWindow extends StatelessWidget {
  const DetachedPanelWindow({
    required this.title,
    required this.child,
    this.subtitle,
    this.onAdd,
    this.onClose,
    this.width,
    this.height,
    super.key,
  });

  final String title;

  /// `Drums Bus selected` — what the panel is pointed at, which matters more
  /// once the panel is no longer beside the thing it is pointed at.
  final String? subtitle;

  final Widget child;
  final VoidCallback? onAdd;
  final VoidCallback? onClose;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return ObFloatingWindow.panel(
      vm: ObFloatingWindowVm(
        title: title,
        subtitle: subtitle,
        actions: <ObWindowAction>[
          ObWindowAction(icon: ObKitGlyphKind.plus, onTap: onAdd),
          ObWindowAction(icon: ObKitGlyphKind.close, onTap: onClose),
        ],
      ),
      width: width ?? tokens.size.detachedWindowWidth,
      height: height ?? tokens.size.detachedWindowHeight,
      child: child,
    );
  }
}

/// The mid-drag layer: dock chips at the edges, the dragged panel's ghost, and
/// the centre "dock as tab" card.
///
/// Everything is positioned from the vm and nothing moves — this is the frame
/// of a drag, not the drag. It sits in a [Stack] over the content area.
class WorkspaceDragLayer extends StatelessWidget {
  const WorkspaceDragLayer({required this.vm, this.onDock, super.key});

  final WorkspaceDragVm vm;

  /// Fired with the edge of the target dropped onto; null for the tab card.
  final ValueChanged<DockEdge?>? onDock;

  @override
  Widget build(BuildContext context) {
    final DockAsTabVm? asTab = vm.asTab;
    final String? note = vm.floatingNote;

    return Stack(
      children: <Widget>[
        Positioned(
          left: vm.ghost.left,
          top: vm.ghost.top,
          width: vm.ghost.width,
          height: vm.ghost.height,
          child: _DragGhost(vm: vm.ghost),
        ),
        for (final DockTargetVm target in vm.targets)
          Positioned(
            left: target.left,
            top: target.top,
            child: _DockChip(
              vm: target,
              onTap: onDock == null ? null : () => onDock!(target.edge),
            ),
          ),
        if (asTab != null)
          Positioned(
            left: asTab.left,
            top: asTab.top,
            child: _DockAsTabCard(
              vm: asTab,
              onTap: onDock == null ? null : () => onDock!(null),
            ),
          ),
        if (note != null)
          Positioned(
            right: 0,
            top: 0,
            child: _FloatingNote(text: note),
          ),
      ],
    );
  }
}

class _FloatingNote extends StatelessWidget {
  const _FloatingNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      child: Text(
        text,
        style: tokens.type.menu.copyWith(color: tokens.color.accentBright),
      ),
    );
  }
}

/// A dock chip: accent outline over an accent wash, small enough that a row of
/// four does not read as a toolbar.
class _DockChip extends StatelessWidget {
  const _DockChip({required this.vm, this.onTap});

  final DockTargetVm vm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: tokens.size.dockChipHeight,
        constraints: BoxConstraints(minWidth: tokens.size.dockChipMinWidth),
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
        decoration: BoxDecoration(
          color: color.accentWash,
          borderRadius: BorderRadius.all(tokens.radius.md),
          border: Border.all(color: color.accent, width: tokens.border.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          vm.label,
          style: tokens.type.menu.copyWith(color: color.textPrimary),
        ),
      ),
    );
  }
}

/// The dragged panel's outline. Washed rather than filled so the arrangement
/// under it stays readable — what you are aiming at matters more than what you
/// are holding.
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.vm});

  final DragGhostVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      decoration: BoxDecoration(
        color: color.dragGhostFill,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(color: color.accent, width: tokens.border.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: tokens.size.dragGhostHeaderHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
              child: Row(
                children: <Widget>[
                  ObPanelGrip(color: color.accentBright),
                  SizedBox(width: tokens.spacing.sm),
                  Text(
                    vm.title.toUpperCase(),
                    style: tokens.type.sectionHeader.copyWith(
                      color: color.accentBright,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    vm.note,
                    style: tokens.type.menu.copyWith(color: color.accentBright),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _DockAsTabCard extends StatelessWidget {
  const _DockAsTabCard({required this.vm, this.onTap});

  final DockAsTabVm vm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: tokens.size.dockTabCardWidth,
        height: tokens.size.dockTabCardHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
        decoration: BoxDecoration(
          color: color.surfaceSunken,
          borderRadius: tokens.radius.panelBorder,
          border: Border.all(
            color: color.lineStrong,
            width: tokens.border.hairline,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.windowShadow,
              blurRadius: tokens.size.windowShadowBlur,
              offset: Offset(0, tokens.size.windowShadowOffset),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: tokens.size.dockTabTileSize,
              height: tokens.size.dockTabTileSize,
              decoration: BoxDecoration(
                color: color.accent,
                borderRadius: BorderRadius.all(tokens.radius.md),
              ),
              child: Center(
                child: ObKitGlyph(
                  kind: ObKitGlyphKind.note,
                  color: color.textPrimary,
                  size: ObKitGlyphSize.inline,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(vm.title, style: tokens.type.title),
                SizedBox(height: tokens.spacing.xxs),
                Text(vm.path, style: tokens.type.extMeta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
