// ObBrowserPanel — the docked library panel (UI-B-04).
//
// One 240px column, two contents: a tree of folders and patterns on the rack
// and piano-roll screens, and a flat list of samples on the arrangement
// screen. Both are the same rows at different depths, which is why there is
// one panel here and not two.
//
// The panel is handed a tree and a selected id and reports taps and disclosure
// toggles by id. Search is intentionally local to the panel so the field stays
// focusable even when the shell has no search command to route.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/search_field.dart';
import '../../ui_kit/search_icon.dart';
import 'browser_glyphs.dart';

/// A node in the browser tree.
///
/// Sealed so the panel's row switch is exhaustive: a new node kind is a
/// compile error at every place that draws one, rather than a row that
/// silently renders as a folder.
sealed class BrowserNodeVm {
  const BrowserNodeVm({required this.id, required this.name, this.dragData});

  final String id;
  final String name;

  /// Payload carried by a drag that starts on this row (a plug-in to drop into
  /// the channel rack). Rows with a null payload are not draggable.
  final Object? dragData;

  /// Rows nested under this one. Only shown when the node is expanded.
  List<BrowserNodeVm> get children;
}

/// A folder: an item count when the library knows one, and children.
class BrowserFolderVm extends BrowserNodeVm {
  const BrowserFolderVm({
    required super.id,
    required super.name,
    this.count,
    this.expanded = false,
    this.children = const <BrowserNodeVm>[],
  });

  /// `12`, `340` — omitted where the mockup shows no count.
  final int? count;
  final bool expanded;

  @override
  final List<BrowserNodeVm> children;
}

/// A pattern: identity colour, and a badge that is either a repeat count
/// (`4×`) or the kind of content it holds (`piano roll`).
class BrowserPatternVm extends BrowserNodeVm {
  const BrowserPatternVm({
    required super.id,
    required super.name,
    required this.color,
    this.badge,
    this.expanded = true,
    this.children = const <BrowserNodeVm>[],
  });

  final Color color;
  final String? badge;
  final bool expanded;

  @override
  final List<BrowserNodeVm> children;
}

/// A sample: identity dot and a waveform mark. Always a leaf.
class BrowserSampleVm extends BrowserNodeVm {
  const BrowserSampleVm({
    required super.id,
    required super.name,
    required this.color,
    super.dragData,
  });

  final Color color;

  @override
  List<BrowserNodeVm> get children => const <BrowserNodeVm>[];
}

@immutable
class ObBrowserPanelVm {
  const ObBrowserPanelVm({
    required this.nodes,
    this.selectedId,
    this.title = 'Browser',
    this.searchHint = 'Search samples, presets…',
    this.emptyHeading = 'No sound folders yet.',
    this.emptyButtonLabel = 'Add sound folder...',
  });

  final List<BrowserNodeVm> nodes;
  final String? selectedId;

  /// Micro-caps panel title; upper-cased on render.
  final String title;
  final String searchHint;
  final String emptyHeading;
  final String emptyButtonLabel;
}

class ObBrowserPanel extends StatefulWidget {
  const ObBrowserPanel({
    required this.vm,
    this.onTap,
    this.onToggle,
    this.onSearchTap,
    this.onAddFolder,
    super.key,
  });

  final ObBrowserPanelVm vm;

  /// Fired with the tapped node's id.
  final ValueChanged<String>? onTap;

  /// Fired with a folder or pattern's id when its disclosure is toggled.
  final ValueChanged<String>? onToggle;

  final VoidCallback? onSearchTap;
  final VoidCallback? onAddFolder;

  @override
  State<ObBrowserPanel> createState() => _ObBrowserPanelState();
}

class _ObBrowserPanelState extends State<ObBrowserPanel> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'browser-search');
  String _query = '';

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    widget.onSearchTap?.call();
  }

  List<BrowserNodeVm> _filteredNodes(List<BrowserNodeVm> nodes) {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return nodes;

    final List<BrowserNodeVm> filtered = <BrowserNodeVm>[];
    for (final BrowserNodeVm node in nodes) {
      final BrowserNodeVm? match = _filteredNode(node, query);
      if (match != null) filtered.add(match);
    }
    return filtered;
  }

  /// Keeps matching ancestors in the result and expands them when a matching
  /// descendant is found, so searching never returns an apparently empty tree.
  BrowserNodeVm? _filteredNode(BrowserNodeVm node, String query) {
    final bool nameMatches = node.name.toLowerCase().contains(query);
    final List<BrowserNodeVm> children = <BrowserNodeVm>[];
    for (final BrowserNodeVm child in node.children) {
      final BrowserNodeVm? match = _filteredNode(child, query);
      if (match != null) children.add(match);
    }
    if (!nameMatches && children.isEmpty) return null;

    switch (node) {
      case BrowserFolderVm():
        return BrowserFolderVm(
          id: node.id,
          name: node.name,
          // While searching, the count describes the visible result set rather
          // than the unfiltered library total.
          count: nameMatches ? node.count : children.length,
          expanded: nameMatches || children.isNotEmpty,
          children: nameMatches ? node.children : children,
        );
      case BrowserPatternVm():
        return BrowserPatternVm(
          id: node.id,
          name: node.name,
          color: node.color,
          badge: node.badge,
          expanded: nameMatches || children.isNotEmpty,
          children: nameMatches ? node.children : children,
        );
      case BrowserSampleVm():
        return node;
    }
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final List<BrowserNodeVm> nodes = _filteredNodes(widget.vm.nodes);

    return Container(
      width: tokens.size.browserWidth,
      decoration: BoxDecoration(color: color.surfacePanel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(title: widget.vm.title, onSearchTap: _focusSearch),
          if (widget.vm.nodes.isNotEmpty) ...<Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.sm,
                vertical: tokens.spacing.sm,
              ),
              child: ObSearchField(
                hint: widget.vm.searchHint,
                // The field spans the panel's content width rather than the
                // kit's default: a search box narrower than the list it filters
                // reads as a control for something else.
                width: double.infinity,
                focusNode: _searchFocus,
                onTap: _focusSearch,
                onChanged: (String value) => setState(() => _query = value),
              ),
            ),
            Container(height: tokens.border.hairline, color: color.line),
          ],
          Expanded(
            child: widget.vm.nodes.isEmpty
                ? _BrowserEmptyState(
                    heading: widget.vm.emptyHeading,
                    buttonLabel: widget.vm.emptyButtonLabel,
                    onAddFolder: widget.onAddFolder,
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.sm,
                      vertical: tokens.spacing.sm,
                    ),
                    children: <Widget>[
                      for (final Widget row in _rows(nodes, 0)) row,
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Flattens the tree to rows, skipping the children of collapsed nodes.
  List<Widget> _rows(List<BrowserNodeVm> nodes, int depth) {
    final List<Widget> rows = <Widget>[];
    for (final BrowserNodeVm node in nodes) {
      final bool selected = node.id == widget.vm.selectedId;
      final VoidCallback? tap = widget.onTap == null
          ? null
          : () => widget.onTap!(node.id);
      final VoidCallback? toggle = widget.onToggle == null
          ? null
          : () => widget.onToggle!(node.id);
      switch (node) {
        case BrowserFolderVm():
          rows.add(
            _dragWrap(
              node,
              BrowserFolderRow(
                node: node,
                depth: depth,
                selected: selected,
                onTap: tap,
                onToggle: toggle,
              ),
            ),
          );
          if (node.children.isNotEmpty) {
            rows.add(_disclosure(node, depth));
          }
        case BrowserPatternVm():
          rows.add(
            _dragWrap(
              node,
              BrowserPatternRow(
                node: node,
                depth: depth,
                selected: selected,
                onTap: tap,
                onToggle: toggle,
              ),
            ),
          );
          if (node.children.isNotEmpty) {
            rows.add(_disclosure(node, depth));
          }
        case BrowserSampleVm():
          rows.add(
            _dragWrap(
              node,
              BrowserSampleRow(
                node: node,
                depth: depth,
                selected: selected,
                onTap: tap,
              ),
            ),
          );
      }
    }
    return rows;
  }

  /// Animates the height of a node's children without making a collapsed tree
  /// row reserve invisible space. The stable key keeps the animation attached
  /// to the same node while the parent view model is rebuilt.
  Widget _disclosure(BrowserNodeVm node, int depth) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final List<Widget> children = _rows(node.children, depth + 1);
    return KeyedSubtree(
      key: ValueKey<String>('browser-disclosure:${node.id}'),
      child: AnimatedSize(
        duration: tokens.motion.settled,
        curve: tokens.motion.standard,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: node is BrowserFolderVm && node.expanded ||
                node is BrowserPatternVm && node.expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// Wraps a row in a [Draggable] when it carries a drag payload, so built-in
  /// plug-ins can be dragged into the channel rack.
  Widget _dragWrap(BrowserNodeVm node, Widget row) {
    final Object? data = node.dragData;
    if (data == null) return row;
    return Draggable<Object>(
      data: data,
      feedback: _DragFeedback(label: node.name),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onSearchTap});

  final String title;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.browserHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            // A panel title names the column; it is not the loudest thing in
            // it. The mockup draws it at the same weight as the row names.
            style: tokens.type.sectionHeader.copyWith(
              color: tokens.color.textSecondary,
            ),
          ),
          const Spacer(),
          ObSearchIcon(onTap: onSearchTap),
        ],
      ),
    );
  }
}

/// The shared row frame: indent, selection shade, hover, tap target.
class _Row extends StatefulWidget {
  const _Row({
    required this.depth,
    required this.selected,
    required this.accentSelection,
    required this.children,
    this.onTap,
  });

  final int depth;
  final bool selected;

  /// Selected patterns fill with the accent; selected folders and samples
  /// take the overlay shade. Both appear in the mockups, on purpose: the
  /// accent means "this is what the editors are showing", the shade means
  /// "this is what you last touched".
  final bool accentSelection;

  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final Color fill;
    if (widget.selected) {
      fill = widget.accentSelection ? color.accent : color.surfaceOverlay;
    } else if (_hover && widget.onTap != null) {
      fill = color.surfaceRaised;
    } else {
      fill = color.none;
    }

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: widget.onTap == null
          ? null
          : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null
          ? null
          : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          // The indent sits outside the fill, so a selected child's pill
          // starts where its name does rather than reaching back under its
          // parent.
          padding: EdgeInsets.only(
            left: tokens.size.browserRowIndent * widget.depth,
          ),
          child: Container(
            height: tokens.size.browserRowHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: tokens.radius.panelBorder,
            ),
            child: Row(children: widget.children),
          ),
        ),
      ),
    );
  }
}

/// Folder icon, name, dim mono count.
class BrowserFolderRow extends StatelessWidget {
  const BrowserFolderRow({
    required this.node,
    required this.depth,
    this.selected = false,
    this.onTap,
    this.onToggle,
    super.key,
  });

  final BrowserFolderVm node;
  final int depth;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int? count = node.count;
    return _Row(
      depth: depth,
      selected: selected,
      accentSelection: false,
      // A folder's whole row is its disclosure: there is no second target to
      // aim at, and a tree where the triangle and the name do different
      // things is a tree people mis-click.
      onTap: onToggle ?? onTap,
      children: <Widget>[
        ObBrowserGlyph(
          kind: node.expanded
              ? ObBrowserGlyphKind.folderOpen
              : ObBrowserGlyphKind.folder,
          color: tokens.color.textSecondary,
        ),
        SizedBox(width: tokens.spacing.sm),
        Flexible(
          child: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected ? tokens.type.listRowSelected : tokens.type.listRow,
          ),
        ),
        if (count != null) ...<Widget>[
          SizedBox(width: tokens.spacing.sm),
          Text('$count', style: tokens.type.listRowMeta),
        ],
      ],
    );
  }
}

/// Pattern glyph, colour tick, name, and either a repeat count or a kind tag.
class BrowserPatternRow extends StatelessWidget {
  const BrowserPatternRow({
    required this.node,
    required this.depth,
    this.selected = false,
    this.onTap,
    this.onToggle,
    super.key,
  });

  final BrowserPatternVm node;
  final int depth;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? badge = node.badge;
    // On the accent fill every foreground goes to full strength: a muted
    // count on a saturated row reads as disabled.
    final Color ink = selected ? color.textPrimary : color.textSecondary;

    return _Row(
      depth: depth,
      selected: selected,
      accentSelection: true,
      onTap: onTap,
      children: <Widget>[
        ObBrowserGlyph(kind: ObBrowserGlyphKind.pattern, color: ink),
        SizedBox(width: tokens.spacing.sm),
        Container(
          width: tokens.size.browserTickWidth,
          height: tokens.size.browserTickHeight,
          decoration: BoxDecoration(
            color: node.color,
            borderRadius: BorderRadius.all(tokens.radius.xs),
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Flexible(
          child: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected ? tokens.type.listRowSelected : tokens.type.listRow,
          ),
        ),
        if (badge != null) ...<Widget>[
          SizedBox(width: tokens.spacing.sm),
          Text(
            badge,
            style: selected
                ? tokens.type.listRowMeta.copyWith(color: color.textPrimary)
                : tokens.type.listRowMeta,
          ),
        ],
      ],
    );
  }
}

/// Identity dot, name, waveform mark.
class BrowserSampleRow extends StatelessWidget {
  const BrowserSampleRow({
    required this.node,
    required this.depth,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final BrowserSampleVm node;
  final int depth;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return _Row(
      depth: depth,
      selected: selected,
      accentSelection: false,
      onTap: onTap,
      children: <Widget>[
        Container(
          width: tokens.size.browserDotSize,
          height: tokens.size.browserDotSize,
          decoration: BoxDecoration(color: node.color, shape: BoxShape.circle),
        ),
        SizedBox(width: tokens.spacing.md),
        // Expanded, not Flexible-plus-Spacer: the waveform mark belongs at the
        // panel's right edge, and two flexible children would split the slack
        // between them and float it mid-row.
        Expanded(
          child: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected ? tokens.type.listRowSelected : tokens.type.listRow,
          ),
        ),
        ObSampleWaveGlyph(color: tokens.color.textMuted),
      ],
    );
  }
}

class _BrowserEmptyState extends StatelessWidget {
  const _BrowserEmptyState({
    required this.heading,
    required this.buttonLabel,
    this.onAddFolder,
  });

  final String heading;
  final String buttonLabel;
  final VoidCallback? onAddFolder;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: tokens.size.emptyTileSize,
              height: tokens.size.emptyTileSize,
              decoration: BoxDecoration(
                color: color.surfaceWell,
                borderRadius: BorderRadius.all(tokens.radius.xxl),
                border: Border.all(
                  color: color.lineStrong,
                  width: tokens.border.hairline,
                ),
              ),
              child: Center(
                child: ObKitGlyph(
                  kind: ObKitGlyphKind.folder,
                  color: color.textSecondary,
                  size: ObKitGlyphSize.feature,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.md),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: tokens.type.body.copyWith(color: color.textMuted),
            ),
            SizedBox(height: tokens.spacing.lg),
            ObButton(
              label: buttonLabel,
              icon: ObKitGlyphKind.folder,
              tone: ObButtonTone.primary,
              onTap: onAddFolder,
            ),
          ],
        ),
      ),
    );
  }
}

/// The chip that rides the cursor while a plug-in is dragged out of the
/// browser: a small raised tag carrying the node's name.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.lineStrong,
          width: tokens.border.hairline,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.color.windowShadow,
            blurRadius: tokens.size.windowShadowBlur,
            offset: Offset(0, tokens.size.windowShadowOffset),
          ),
        ],
      ),
      child: Text(
        label,
        style: tokens.type.body.copyWith(color: tokens.color.textPrimary),
      ),
    );
  }
}
