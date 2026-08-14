// The pattern selector (OB-3-11 §1) and the D-M6 destructive-edit notice.
//
// The usage badge is the whole point of the panel. Reference semantics are
// absolute in this model — editing a pattern changes every clip that points at
// it — so the count of those clips has to be visible *before* the user edits,
// not discovered afterwards (D-M6).
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'action_registry.dart';
import 'controls.dart';
import 'icons.dart';
import 'pattern_store.dart';

class PatternSelector extends StatefulWidget {
  const PatternSelector({
    required this.store,
    required this.onOpenPattern,
    super.key,
  });

  final PatternStore store;

  /// Selecting a pattern points the rack and the piano roll at it.
  final ValueChanged<String> onOpenPattern;

  @override
  State<PatternSelector> createState() => _PatternSelectorState();
}

class _PatternSelectorState extends State<PatternSelector> {
  final TextEditingController _rename = TextEditingController();
  final FocusNode _renameFocus = FocusNode(debugLabel: 'pattern-rename');
  String _renamingId = '';
  bool _showColors = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'browser-search');

  @override
  void dispose() {
    _rename.dispose();
    _renameFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _startRename(PatternSummary pattern) {
    setState(() {
      _renamingId = pattern.id;
      _rename.text = pattern.name;
    });
    _renameFocus.requestFocus();
  }

  void _commitRename() {
    if (_renamingId.isEmpty) return;
    widget.store.rename(_renamingId, _rename.text);
    setState(() => _renamingId = '');
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (BuildContext context, Widget? child) {
        final PatternSummary? current = widget.store.current;
        return Container(
          width: tokens.size.patternSelectorWidth,
          decoration: BoxDecoration(
            color: tokens.color.surfacePanel,
            border: Border(
              right: BorderSide(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
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
                    Expanded(
                      child: Text(
                        'BROWSER',
                        style: tokens.type.sectionHeader,
                      ),
                    ),
                    OneBeatButton(
                      key: actionKey('pattern.create'),
                      label: '+',
                      semanticLabel: ActionRegistry.byId(
                        'pattern.create',
                      ).tooltip,
                      onPressed: () => widget.store.create(
                        'Pattern ${widget.store.patterns.length + 1}',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(tokens.spacing.sm),
                child: Container(
                  height: tokens.size.browserSearchHeight,
                  padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
                  decoration: BoxDecoration(
                    color: tokens.color.surfaceDeep,
                    borderRadius: tokens.radius.controlBorder,
                    border: Border.all(
                      color: tokens.color.line,
                      width: tokens.border.hairline,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      OneBeatIcon(
                        OneBeatIconData.search,
                        size: tokens.size.tagHeight,
                        color: tokens.color.textMuted,
                      ),
                      SizedBox(width: tokens.spacing.xs),
                      Expanded(
                        child: Text(
                          'Search samples, presets...',
                          style: tokens.type.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    const _BrowserFolderRow(
                      icon: OneBeatIconData.folder,
                      name: 'Packs',
                      badge: '12',
                      isFolder: true,
                    ),
                    _BrowserFolderRow(
                      icon: OneBeatIconData.folderOpen,
                      name: 'Current Project',
                      badge: '${widget.store.patterns.length}',
                      isFolder: true,
                      expanded: true,
                    ),
                    for (int index = 0; index < widget.store.patterns.length; index++) ...<Widget>[
                      if (widget.store.patterns[index].id == _renamingId)
                        _RenameRow(
                          controller: _rename,
                          focusNode: _renameFocus,
                          onCommit: _commitRename,
                        )
                      else
                        _PatternRow(
                          pattern: widget.store.patterns[index],
                          onTap: () => widget.onOpenPattern(widget.store.patterns[index].id),
                          onRename: () => _startRename(widget.store.patterns[index]),
                        ),
                    ],
                    const _BrowserFolderRow(
                      icon: OneBeatIconData.folder,
                      name: 'Drums',
                      badge: '340',
                      isFolder: true,
                    ),
                    const _BrowserFolderRow(
                      icon: OneBeatIconData.folder,
                      name: 'Synths',
                      badge: '',
                      isFolder: true,
                    ),
                  ],
                ),
              ),
              if (current != null) _buildActions(tokens, current),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions(OneBeatTokens tokens, PatternSummary current) {
    return Container(
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OneBeatButton(
                  key: actionKey('pattern.rename'),
                  label: ActionRegistry.byId('pattern.rename').label,
                  semanticLabel: ActionRegistry.byId('pattern.rename').tooltip,
                  onPressed: () => _startRename(current),
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              OneBeatToggle(
                key: actionKey('pattern.recolor'),
                label: '●',
                value: _showColors,
                tooltip: ActionRegistry.byId('pattern.recolor').label,
                activeColor: projectColor(current.color, tokens.color.accent),
                onChanged: (bool value) =>
                    setState(() => _showColors = value),
              ),
            ],
          ),
          if (_showColors) ...<Widget>[
            SizedBox(height: tokens.spacing.sm),
            ColorSwatchRow(
              selected: current.color,
              onChanged: (String hex) => widget.store.recolor(current.id, hex),
            ),
          ],
          SizedBox(height: tokens.spacing.xs),
          OneBeatButton(
            key: actionKey('pattern.duplicate'),
            label: ActionRegistry.byId('pattern.duplicate').label,
            semanticLabel: ActionRegistry.byId('pattern.duplicate').description,
            onPressed: () => widget.store.duplicate(current.id),
          ),
          SizedBox(height: tokens.spacing.xs),
          OneBeatButton(
            key: actionKey('pattern.delete'),
            // The clip count is in the label, not behind a confirmation the
            // user has to reach before learning the damage (D-M6).
            label: current.usageCount == 0
                ? 'Delete pattern'
                : 'Delete — ${current.usageCount} clips',
            semanticLabel: ActionRegistry.byId('pattern.delete').tooltip,
            onPressed: widget.store.patterns.length <= 1
                ? null
                : () => widget.store.remove(current.id),
          ),
        ],
      ),
    );
  }
}

class _PatternRow extends StatefulWidget {
  const _PatternRow({
    required this.pattern,
    required this.onTap,
    required this.onRename,
  });

  final PatternSummary pattern;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  State<_PatternRow> createState() => _PatternRowState();
}

class _PatternRowState extends State<_PatternRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PatternSummary pattern = widget.pattern;
    return Semantics(
      selected: pattern.isCurrent,
      button: true,
      label:
          '${pattern.name}, used in ${pattern.usageCount} clips, '
          '${pattern.noteCount} notes',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onRename,
          child: Container(
            height: tokens.size.patternRowHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            color: pattern.isCurrent
                ? tokens.color.accent
                : _hovered
                ? tokens.color.surfaceOverlay
                : null,
            child: Row(
              children: <Widget>[
                Container(
                  width: tokens.border.emphasis,
                  height: tokens.size.swatchSize,
                  color: projectColor(pattern.color, tokens.color.accent),
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    pattern.name,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.body.copyWith(
                      color: pattern.isCurrent
                          ? tokens.color.surfaceDeep
                          : tokens.color.textPrimary,
                    ),
                  ),
                ),
                // The usage badge. Shown for every pattern, including the ones
                // used once: a badge that appears only when it is interesting
                // teaches nothing about what it means.
                Text(
                  '${pattern.usageCount}×',
                  style: tokens.type.numericSmall.copyWith(
                    color: pattern.isCurrent
                        ? tokens.color.surfaceDeep
                        : pattern.isShared
                        ? tokens.color.textPrimary
                        : tokens.color.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameRow extends StatelessWidget {
  const _RenameRow({
    required this.controller,
    required this.focusNode,
    required this.onCommit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.patternRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      alignment: Alignment.centerLeft,
      child: EditableText(
        controller: controller,
        focusNode: focusNode,
        style: tokens.type.body,
        cursorColor: tokens.color.accent,
        backgroundCursorColor: tokens.color.line,
        selectionColor: tokens.color.accentMuted,
        maxLines: 1,
        onSubmitted: (_) => onCommit(),
        onTapOutside: (_) => onCommit(),
      ),
    );
  }
}

/// D-M6's non-blocking notice. It reports what just happened and offers the
/// escape hatch; it never asks permission, and it never sits in front of the
/// editor. The edit has already been applied by the time this appears.
class SharedPatternNoticeBar extends StatelessWidget {
  const SharedPatternNoticeBar({
    required this.store,
    required this.onMakeUnique,
    super.key,
  });

  final PatternStore store;

  /// Only offered when the edit context came from a specific clip — otherwise
  /// "unique for which one?" has no answer.
  final ValueChanged<String> onMakeUnique;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? child) {
        final SharedPatternNotice? notice = store.notice;
        if (notice == null) return const SizedBox.shrink();
        return Container(
          height: tokens.size.noticeHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          decoration: BoxDecoration(
            color: tokens.color.surfaceRaised,
            border: Border(
              bottom: BorderSide(
                color: tokens.color.warning,
                width: tokens.border.hairline,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  notice.message,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.type.body,
                ),
              ),
              if (notice.canMakeUnique) ...<Widget>[
                SizedBox(width: tokens.spacing.sm),
                OneBeatButton(
                  label: 'Make unique for this clip',
                  onPressed: () => onMakeUnique(notice.clipId),
                ),
              ],
              SizedBox(width: tokens.spacing.sm),
              OneBeatButton(
                label: 'Dismiss',
                semanticLabel: 'Dismiss the shared pattern notice',
                onPressed: store.dismissNotice,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrowserFolderRow extends StatelessWidget {
  const _BrowserFolderRow({
    required this.icon,
    required this.name,
    this.badge = '',
    this.isFolder = true,
    this.expanded = false,
  });

  final OneBeatIconData icon;
  final String name;
  final String badge;
  final bool isFolder;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.patternRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      child: Row(
        children: <Widget>[
          OneBeatIcon(
            icon,
            size: tokens.size.tagHeight,
            color: tokens.color.textMuted,
          ),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.body.copyWith(
                fontWeight: isFolder ? FontWeight.w500 : FontWeight.w400,
                color: isFolder ? tokens.color.textPrimary : tokens.color.textMuted,
              ),
            ),
          ),
          if (badge.isNotEmpty)
            Text(
              badge,
              style: tokens.type.numericSmall,
            ),
        ],
      ),
    );
  }
}

