// View models for the workspace overlays (UI-C-12).
//
// A workspace is where panels are, which layout you are in, and — while you are
// moving one — where it could go. All three are data; none of them is a
// gesture. The drag state in particular is a *value*: the mid-drag screen in
// `screens/workspace-drag.png` is something the vm can describe, so a golden
// can record it and Phase D can produce it from a real pointer.
import 'package:flutter/widgets.dart';

/// One saved layout in the LAYOUTS menu.
@immutable
class LayoutVm {
  const LayoutVm({required this.name, this.current = false});

  final String name;

  /// The one on the accent row with its box ticked.
  final bool current;
}

@immutable
class WorkspaceLayoutsVm {
  const WorkspaceLayoutsVm({
    required this.layouts,
    this.pillPrefix = 'Layouts',
    this.sectionHeader = 'LAYOUTS',
    this.saveAsLabel = 'Save as…',
    this.renameLabel = 'Rename…',
    this.deleteLabel = 'Delete…',
    this.resetLabel = 'Reset to default',
  });

  final List<LayoutVm> layouts;

  /// The dim word before the value in the pill: `Layouts Beatmaking`.
  final String pillPrefix;

  final String sectionHeader;
  final String saveAsLabel;
  final String renameLabel;
  final String deleteLabel;
  final String resetLabel;

  /// What the pill shows — the current layout's name.
  String get currentName =>
      layouts
          .firstWhere(
            (LayoutVm l) => l.current,
            orElse: () => layouts.first,
          )
          .name;
}

/// Which edge of the target a dock chip offers.
enum DockEdge { left, top, right, bottom }

/// A drop target offered while a panel is in flight, positioned in logical
/// pixels within the drag layer. Positions come from the vm rather than from a
/// layout algorithm because the *real* positions are the edges of whatever
/// panel the pointer is over, which only the workspace store knows (Phase D).
@immutable
class DockTargetVm {
  const DockTargetVm({
    required this.label,
    required this.edge,
    required this.left,
    required this.top,
  });

  final String label;
  final DockEdge edge;
  final double left;
  final double top;
}

/// The translucent outline of the panel being dragged.
@immutable
class DragGhostVm {
  const DragGhostVm({
    required this.title,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.note = 'dragging…',
  });

  final String title;
  final double left;
  final double top;
  final double width;
  final double height;

  /// The dim word at the ghost header's right edge.
  final String note;
}

/// The centre card: dock into the target as a tab rather than beside it.
@immutable
class DockAsTabVm {
  const DockAsTabVm({
    required this.title,
    required this.path,
    required this.left,
    required this.top,
  });

  /// `Dock as tab`.
  final String title;

  /// `CHANNEL RACK → PLAYLIST`, in mono.
  final String path;

  final double left;
  final double top;
}

@immutable
class WorkspaceDragVm {
  const WorkspaceDragVm({
    required this.ghost,
    required this.targets,
    this.asTab,
    this.floatingNote,
  });

  final DragGhostVm ghost;
  final List<DockTargetVm> targets;
  final DockAsTabVm? asTab;

  /// The dim `dragging · Channel Rack` that rides at the top right of the
  /// content area, over the document's own header line.
  final String? floatingNote;
}
