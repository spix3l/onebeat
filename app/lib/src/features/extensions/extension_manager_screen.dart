// The extension manager, its empty state and a docked extension panel
// (UI-C-11).
//
// Three surfaces, one argument: an extension is sandboxed, you can see exactly
// what it is allowed to touch, and the worst thing it can do to you is stop
// working. Every capability row, every reassurance in the crash card and the
// `sandboxed WASM · you grant capabilities` caption are product copy, not
// filler — they are the feature.
//
// Presentational only. Nothing here knows what a WASM module is (UI-D-08).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/docked_panel.dart';
import '../../ui_kit/empty_state.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/knob.dart';
import '../../ui_kit/prose.dart';
import 'extension_manager_vm.dart';

/// The installed list beside the detail panel — the content area of
/// `screens/ext-manager.png`.
class ExtensionManagerScreen extends StatelessWidget {
  const ExtensionManagerScreen({
    required this.vm,
    this.onSelect,
    this.onToggle,
    this.onInstall,
    this.onUninstall,
    this.onToggleSelected,
    this.onCrashAction,
    super.key,
  });

  final ExtensionManagerVm vm;

  /// Fired with the tapped extension's id.
  final ValueChanged<String>? onSelect;

  /// Fired with an extension's id and the state its switch was moved to.
  final void Function(String id, bool enabled)? onToggle;

  final VoidCallback? onInstall;
  final VoidCallback? onUninstall;

  /// The detail panel's `Enabled` button.
  final VoidCallback? onToggleSelected;

  /// Fired with the index of the crash card's action.
  final ValueChanged<int>? onCrashAction;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ListPanel(
            vm: vm,
            onSelect: onSelect,
            onToggle: onToggle,
            onInstall: onInstall,
          ),
          Container(
            height: tokens.border.hairline,
            color: tokens.color.line,
          ),
          Expanded(
            child: _DetailPanel(
              vm: vm.detail,
              onUninstall: onUninstall,
              onToggleEnabled: onToggleSelected,
              onCrashAction: onCrashAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// The upper block: the list column, and the empty gutter beside it that the
/// mockup leaves clear. The gutter is not a mistake — the detail panel below
/// runs the full width, and a list that also ran full width would read as the
/// same table continuing.
class _ListPanel extends StatelessWidget {
  const _ListPanel({
    required this.vm,
    this.onSelect,
    this.onToggle,
    this.onInstall,
  });

  final ExtensionManagerVm vm;
  final ValueChanged<String>? onSelect;
  final void Function(String id, bool enabled)? onToggle;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: tokens.size.extListWidth,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: tokens.size.playlistHeaderHeight,
                  child: Row(
                    children: <Widget>[
                      Text(
                        vm.listTitle,
                        style: tokens.type.sectionHeader.copyWith(
                          color: color.textSecondary,
                        ),
                      ),
                      SizedBox(width: tokens.spacing.sm),
                      Text('— ${vm.countLabel}', style: tokens.type.menu),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spacing.sm),
                for (final ExtensionVm ext in vm.extensions) ...<Widget>[
                  _ExtensionRow(
                    vm: ext,
                    onTap: onSelect == null ? null : () => onSelect!(ext.id),
                    onToggle:
                        onToggle == null
                            ? null
                            : (bool on) => onToggle!(ext.id, on),
                  ),
                  SizedBox(height: tokens.spacing.xs),
                ],
                SizedBox(height: tokens.spacing.sm),
                ObButton(
                  label: vm.installLabel,
                  icon: ObKitGlyphKind.plus,
                  onTap: onInstall,
                  width: double.infinity,
                ),
                SizedBox(height: tokens.spacing.sm),
                Center(child: Text(vm.caption, style: tokens.type.menu)),
                SizedBox(height: tokens.spacing.lg),
              ],
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _ExtensionRow extends StatefulWidget {
  const _ExtensionRow({required this.vm, this.onTap, this.onToggle});

  final ExtensionVm vm;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  @override
  State<_ExtensionRow> createState() => _ExtensionRowState();
}

class _ExtensionRowState extends State<_ExtensionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final ExtensionVm vm = widget.vm;
    final bool enabled = widget.onTap != null;

    final Color background;
    final Color border;
    if (vm.crashed) {
      background = color.dangerWash;
      border = color.dangerMuted;
    } else if (vm.selected) {
      background = color.accentWash;
      border = color.accent;
    } else {
      background = _hover && enabled ? color.surfaceRaised : color.surfacePanel;
      border = color.line;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.extRowHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          decoration: BoxDecoration(
            color: background,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: border, width: tokens.border.hairline),
          ),
          child: Row(
            children: <Widget>[
              _IconTile(
                icon: vm.icon,
                size: tokens.size.extRowTileSize,
                danger: vm.crashed,
                accent: vm.selected,
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vm.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.extName,
                    ),
                    SizedBox(height: tokens.spacing.xxs),
                    Text(
                      vm.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.extMeta,
                    ),
                  ],
                ),
              ),
              if (vm.crashed) ...<Widget>[
                _CrashedTag(),
                SizedBox(width: tokens.spacing.sm),
              ],
              ObSwitch(
                on: vm.enabled,
                onChanged: widget.onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rounded tile carrying an extension's mark. Accent-washed when the row
/// is selected, danger-washed when it has crashed — the tile is the only thing
/// in the row that changes colour, so the list still reads as a list.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.size,
    this.danger = false,
    this.accent = false,
  });

  final ObKitGlyphKind icon;
  final double size;
  final bool danger;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final Color fill =
        danger
            ? color.dangerWash
            : (accent ? color.accentWash : color.surfaceWell);
    final Color ink =
        danger
            ? color.danger
            : (accent ? color.accentBright : color.textSecondary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: danger ? color.dangerMuted : color.lineStrong,
          width: tokens.border.hairline,
        ),
      ),
      child: Center(child: ObKitGlyph(kind: icon, color: ink)),
    );
  }
}

class _CrashedTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.size.extCrashTagWidth,
      height: tokens.size.tagHeight,
      decoration: BoxDecoration(
        color: tokens.color.dangerWash,
        borderRadius: BorderRadius.all(tokens.radius.sm),
        border: Border.all(
          color: tokens.color.dangerMuted,
          width: tokens.border.hairline,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        'CRASHED',
        style: tokens.type.dangerCaps.copyWith(color: tokens.color.danger),
      ),
    );
  }
}

/// The pill switch. Off is a dark well with the knob at the left; on is the
/// accent with the knob at the right — position *and* colour, so it survives
/// being read at a glance and by someone who cannot tell the two colours apart.
class ObSwitch extends StatelessWidget {
  const ObSwitch({required this.on, this.onChanged, super.key});

  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double inset =
        (tokens.size.extSwitchHeight - tokens.size.extSwitchKnobSize) / 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!on),
      child: Container(
        width: tokens.size.extSwitchWidth,
        height: tokens.size.extSwitchHeight,
        decoration: BoxDecoration(
          color: on ? color.accent : color.surfaceWell,
          borderRadius: BorderRadius.all(tokens.radius.lg),
          border: Border.all(
            color: on ? color.accentDeep : color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child: Align(
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Container(
              width: tokens.size.extSwitchKnobSize,
              height: tokens.size.extSwitchKnobSize,
              decoration: BoxDecoration(
                color: on ? color.textPrimary : color.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.vm,
    this.onUninstall,
    this.onToggleEnabled,
    this.onCrashAction,
  });

  final ExtensionDetailVm vm;
  final VoidCallback? onUninstall;
  final VoidCallback? onToggleEnabled;
  final ValueChanged<int>? onCrashAction;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final CrashCardVm? crash = vm.crash;

    // Scrolls, and in the mockup it is already scrolled past its own bottom:
    // the crash card runs under the status bar. That is the right shape for
    // this panel — a capability table grows with the extension, and clipping
    // the reassurance at the foot of it would be the one thing worth reading
    // that you could not reach.
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconTile(
                icon: vm.icon,
                size: tokens.size.extDetailTileSize,
                accent: true,
              ),
              SizedBox(width: tokens.spacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(vm.name, style: tokens.type.extDetailName),
                  SizedBox(height: tokens.spacing.xxs),
                  Text(vm.meta, style: tokens.type.extMeta),
                ],
              ),
              const Spacer(),
              ObButton(
                label: vm.enabledLabel,
                tone: ObButtonTone.accentOutline,
                onTap: onToggleEnabled,
              ),
              SizedBox(width: tokens.spacing.sm),
              ObButton(label: vm.uninstallLabel, onTap: onUninstall),
            ],
          ),
          SizedBox(height: tokens.spacing.lg),
          ObProse(runs: vm.description, style: tokens.type.body),
          SizedBox(height: tokens.spacing.lg),
          _SectionHeader(
            left: vm.capabilitiesHeader,
            right: vm.capabilitiesRightHeader,
          ),
          SizedBox(height: tokens.spacing.sm),
          for (final CapabilityVm capability in vm.capabilities) ...<Widget>[
            _CapabilityRow(vm: capability),
            SizedBox(height: tokens.spacing.xs),
          ],
          SizedBox(height: tokens.spacing.md),
          _SectionHeader(left: vm.bindingsHeader),
          SizedBox(height: tokens.spacing.sm),
          for (final BindingVm binding in vm.bindings) ...<Widget>[
            _BindingRow(vm: binding),
            SizedBox(height: tokens.spacing.xs),
          ],
          if (crash != null) ...<Widget>[
            SizedBox(height: tokens.spacing.md),
            _CrashCard(vm: crash, onAction: onCrashAction),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.left, this.right});

  final String left;
  final String? right;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final String? right = this.right;
    return Row(
      children: <Widget>[
        Text(left, style: tokens.type.microCapsWide),
        const Spacer(),
        if (right != null) Text(right, style: tokens.type.microCapsWide),
      ],
    );
  }
}

/// `Read the project ✓ … patterns, notes, mixer`.
///
/// A denied capability is not greyed out — it is marked with a cross and given
/// a reason. "Network ✗ never granted" tells you something; a missing row
/// tells you nothing.
class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.vm});

  final CapabilityVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      height: tokens.size.extCapabilityRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.extCapabilityMarkSize,
            height: tokens.size.extCapabilityMarkSize,
            decoration: BoxDecoration(
              color: vm.granted ? color.accentWash : color.surfaceWell,
              borderRadius: BorderRadius.all(tokens.radius.sm),
              border: Border.all(
                color: vm.granted ? color.accent : color.lineStrong,
                width: tokens.border.hairline,
              ),
            ),
            child: Center(
              child: ObKitGlyph(
                kind:
                    vm.granted ? ObKitGlyphKind.check : ObKitGlyphKind.cross,
                color: vm.granted ? color.accentBright : color.textMuted,
                size: ObKitGlyphSize.inline,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          Text(
            vm.name,
            style: tokens.type.body.copyWith(
              color: vm.granted ? color.textPrimary : color.textSecondary,
            ),
          ),
          const Spacer(),
          Text(vm.note, style: tokens.type.menu),
        ],
      ),
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({required this.vm});

  final BindingVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? detail = vm.detail;
    final String? tag = vm.tag;
    final String? tagNote = vm.tagNote;

    return Container(
      height: tokens.size.extBindingRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: Row(
        children: <Widget>[
          ObKitGlyph(kind: vm.icon, color: color.textSecondary),
          SizedBox(width: tokens.spacing.md),
          Text(vm.label, style: tokens.type.body),
          if (detail != null) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Text(detail, style: tokens.type.menu),
          ],
          const Spacer(),
          if (tag != null) _KeyTag(label: tag),
          if (tagNote != null) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Text(tagNote, style: tokens.type.menu),
          ],
        ],
      ),
    );
  }
}

/// A mono key cap: `⇧⌘H`, `C#4`, `⌘J`.
class ObKeyTag extends StatelessWidget {
  const ObKeyTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => _KeyTag(label: label);
}

class _KeyTag extends StatelessWidget {
  const _KeyTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.tagHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs),
      decoration: BoxDecoration(
        color: tokens.color.surfaceWell,
        borderRadius: BorderRadius.all(tokens.radius.sm),
        border: Border.all(
          color: tokens.color.lineStrong,
          width: tokens.border.hairline,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: tokens.type.extMeta.copyWith(color: tokens.color.textSecondary),
      ),
    );
  }
}

/// The contained-failure card: outlined, never filled. See
/// [ColorTokens.dangerWash] for why.
class _CrashCard extends StatelessWidget {
  const _CrashCard({required this.vm, this.onAction});

  final CrashCardVm vm;
  final ValueChanged<int>? onAction;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: color.dangerWash,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(
          color: color.dangerMuted,
          width: tokens.border.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              ObKitGlyph(kind: ObKitGlyphKind.warning, color: color.danger),
              SizedBox(width: tokens.spacing.sm),
              Text(
                vm.title,
                style: tokens.type.dangerCaps.copyWith(color: color.danger),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.sm),
          ObProse(
            runs: vm.body,
            style: tokens.type.body.copyWith(color: color.textMuted),
            strongStyle: tokens.type.body,
          ),
          SizedBox(height: tokens.spacing.md),
          Row(
            children: <Widget>[
              for (int i = 0; i < vm.actions.length; i++) ...<Widget>[
                if (i > 0) SizedBox(width: tokens.spacing.sm),
                ObButton(
                  label: vm.actions[i],
                  onTap: onAction == null ? null : () => onAction!(i),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// `screens/ext-empty.png` — nothing installed, and the app's pitch for why
/// you might want to change that.
class ExtensionEmptyScreen extends StatelessWidget {
  const ExtensionEmptyScreen({
    required this.vm,
    this.onWriteScript,
    this.onBrowse,
    this.onTemplate,
    super.key,
  });

  final ExtensionEmptyVm vm;
  final VoidCallback? onWriteScript;
  final VoidCallback? onBrowse;
  final VoidCallback? onTemplate;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return ColoredBox(
      color: color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: tokens.size.playlistHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  vm.title,
                  style: tokens.type.sectionHeader.copyWith(
                    color: color.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(vm.rightNote, style: tokens.type.menu),
              ],
            ),
          ),
          Expanded(
            child: ObEmptyState(
              vm: ObEmptyStateVm(
                icon: ObKitGlyphKind.script,
                heading: vm.heading,
                body: vm.body,
              ),
              actions: <Widget>[
                ObButton(
                  label: vm.primaryAction,
                  tone: ObButtonTone.primary,
                  icon: ObKitGlyphKind.menuLines,
                  large: true,
                  onTap: onWriteScript,
                ),
                ObButton(
                  label: vm.browseAction,
                  icon: ObKitGlyphKind.folder,
                  large: true,
                  onTap: onBrowse,
                ),
                ObButton(
                  label: vm.templateAction,
                  tone: ObButtonTone.quiet,
                  large: true,
                  onTap: onTemplate,
                ),
              ],
              extra: _EmptyExtras(steps: vm.steps, hints: vm.hints),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three numbered steps and the keyboard hints under them. Below the fold
/// of the pitch on purpose: the buttons are for people who are convinced, this
/// is for people who are not yet.
class _EmptyExtras extends StatelessWidget {
  const _EmptyExtras({required this.steps, required this.hints});

  final List<ExtensionStepVm> steps;
  final List<ExtensionHintVm> hints;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: tokens.size.emptyProseWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < steps.length; i++)
                Expanded(child: _Step(index: i + 1, vm: steps[i])),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.xl),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < hints.length; i++) ...<Widget>[
              if (i > 0) ...<Widget>[
                SizedBox(width: tokens.spacing.xs),
                Text('·', style: tokens.type.menu),
                SizedBox(width: tokens.spacing.xs),
              ],
              _KeyTag(label: hints[i].keys),
              SizedBox(width: tokens.spacing.xs),
              Text(hints[i].label, style: tokens.type.menu),
            ],
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.vm});

  final int index;
  final ExtensionStepVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Column(
      children: <Widget>[
        Container(
          width: tokens.size.extCapabilityMarkSize,
          height: tokens.size.extCapabilityMarkSize,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: tokens.type.numericSmall.copyWith(color: color.accentBright),
          ),
        ),
        SizedBox(height: tokens.spacing.sm),
        Text(
          vm.title,
          textAlign: TextAlign.center,
          style: tokens.type.title,
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(
          vm.body,
          textAlign: TextAlign.center,
          style: tokens.type.menu,
        ),
      ],
    );
  }
}

/// `screens/ext-panel.png` — the docked-panel row, an extension's own surface
/// sitting between two native panels with the same chrome around all three.
class ExtensionPanelScreen extends StatelessWidget {
  const ExtensionPanelScreen({
    required this.vm,
    this.onRun,
    this.onUndo,
    this.onExpand,
    this.onClosePanel,
    this.onParam,
    super.key,
  });

  final ExtensionPanelScreenVm vm;
  final VoidCallback? onRun;
  final VoidCallback? onUndo;
  final VoidCallback? onExpand;
  final VoidCallback? onClosePanel;

  /// Fired with a parameter's index and its new 0..1 value.
  final void Function(int index, double value)? onParam;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final List<Widget> columns = <Widget>[];

    void add(Widget child, int flex) {
      if (columns.isNotEmpty) {
        columns.add(SizedBox(width: tokens.spacing.sm));
      }
      columns.add(Expanded(flex: flex, child: child));
    }

    for (final PanelNeighbourVm neighbour in vm.before) {
      add(_NeighbourPanel(vm: neighbour), neighbour.flex);
    }
    add(
      _ExtensionPanel(
        vm: vm.panel,
        onRun: onRun,
        onUndo: onUndo,
        onExpand: onExpand,
        onClose: onClosePanel,
        onParam: onParam,
      ),
      vm.panel.flex,
    );
    for (final PanelNeighbourVm neighbour in vm.after) {
      add(_NeighbourPanel(vm: neighbour), neighbour.flex);
    }

    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: columns,
        ),
      ),
    );
  }
}

class _NeighbourPanel extends StatelessWidget {
  const _NeighbourPanel({required this.vm});

  final PanelNeighbourVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return ObDockedPanel(
      title: vm.title,
      rightNote: vm.rightNote,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final PanelListRowVm row in vm.rows) ...<Widget>[
              _PanelListRow(vm: row),
              SizedBox(height: tokens.spacing.xs),
            ],
            if (vm.wells.isNotEmpty || vm.knobs.isNotEmpty)
              Expanded(child: _RackBody(vm: vm)),
          ],
        ),
      ),
    );
  }
}

/// A plug-in panel's insides: the knob column at the left, the meter wells at
/// the right. Enough of `screens/ext-panel.png`'s compressor to make the point
/// that the extension beside it is drawn no differently — the real thing is
/// UI-C-09's job.
class _RackBody extends StatelessWidget {
  const _RackBody({required this.vm});

  final PanelNeighbourVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Each knob takes an equal share rather than a fixed column:
                  // a plug-in panel is resizable, and five knobs at a fixed
                  // pitch are five knobs that fall off the edge of a narrow one.
                  for (final PanelKnobVm knob in vm.knobs)
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          ObKnob(value: knob.value, onChanged: null),
                          SizedBox(height: tokens.spacing.xs),
                          Text(
                            knob.label,
                            maxLines: 1,
                            style: tokens.type.microCaps,
                          ),
                          SizedBox(height: tokens.spacing.xxs),
                          Text(knob.readout, style: tokens.type.knobValue),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < vm.wells.length; i++) ...<Widget>[
                if (i > 0) SizedBox(height: tokens.spacing.sm),
                Expanded(child: _MeterWell(vm: vm.wells[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MeterWell extends StatelessWidget {
  const _MeterWell({required this.vm});

  final PanelWellVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.sm),
      decoration: BoxDecoration(
        color: color.surfaceSunken,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(vm.label, style: tokens.type.microCaps),
              const Spacer(),
              Text(vm.readout, style: tokens.type.numericSmall),
            ],
          ),
          const Spacer(),
          _WellBar(level: vm.level),
        ],
      ),
    );
  }
}

/// The green→amber→red bar across a well's foot.
class _WellBar extends StatelessWidget {
  const _WellBar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return SizedBox(
      height: tokens.size.mixerColorBarHeight,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: level.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(tokens.radius.xs),
            gradient: LinearGradient(
              colors: <Color>[color.meterLow, color.meterMid, color.meterHigh],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelListRow extends StatelessWidget {
  const _PanelListRow({required this.vm});

  final PanelListRowVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      height: tokens.size.panelListRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.browserTickWidth,
            height: tokens.size.browserTickHeight,
            decoration: BoxDecoration(
              color: vm.color,
              borderRadius: BorderRadius.all(tokens.radius.xs),
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(vm.name, style: tokens.type.rackName),
              Text(vm.caption, style: tokens.type.rackCaption),
            ],
          ),
          const Spacer(),
          Text(vm.trailing, style: tokens.type.stripRoute),
        ],
      ),
    );
  }
}

/// The extension's own panel. Same [ObDockedPanel] frame as its neighbours —
/// the `EXT` badge is the only thing that says it is not native, which is what
/// the status bar under this screen claims and what this widget has to make
/// true.
class _ExtensionPanel extends StatelessWidget {
  const _ExtensionPanel({
    required this.vm,
    this.onRun,
    this.onUndo,
    this.onExpand,
    this.onClose,
    this.onParam,
  });

  final ExtensionPanelVm vm;
  final VoidCallback? onRun;
  final VoidCallback? onUndo;
  final VoidCallback? onExpand;
  final VoidCallback? onClose;
  final void Function(int index, double value)? onParam;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return ObDockedPanel(
      title: vm.title,
      badge: _ExtBadge(label: vm.badge),
      rightNote: vm.author,
      actions: <Widget>[
        _PanelIconButton(icon: ObKitGlyphKind.expand, onTap: onExpand),
        _PanelIconButton(icon: ObKitGlyphKind.close, onTap: onClose),
      ],
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < vm.params.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: tokens.spacing.xs),
              _ParamRow(
                vm: vm.params[i],
                onChanged:
                    onParam == null
                        ? null
                        : (double value) => onParam!(i, value),
              ),
            ],
            SizedBox(height: tokens.spacing.sm),
            Expanded(
              child: _Preview(
                caption: vm.previewCaption,
                notes: vm.previewNotes,
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            Row(
              children: <Widget>[
                ObButton(
                  label: vm.runAction,
                  tone: ObButtonTone.primary,
                  icon: ObKitGlyphKind.play,
                  onTap: onRun,
                ),
                SizedBox(width: tokens.spacing.sm),
                ObButton(
                  label: vm.undoAction,
                  icon: ObKitGlyphKind.undo,
                  onTap: onUndo,
                ),
                const Spacer(),
                _KeyTag(label: vm.binding),
                SizedBox(width: tokens.spacing.xs),
                Text(vm.bindingNote, style: tokens.type.menu),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtBadge extends StatelessWidget {
  const _ExtBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.tagHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs),
      decoration: BoxDecoration(
        color: tokens.color.accentWash,
        borderRadius: BorderRadius.all(tokens.radius.sm),
        border: Border.all(
          color: tokens.color.accent,
          width: tokens.border.hairline,
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ObKitGlyph(
            kind: ObKitGlyphKind.script,
            color: tokens.color.accentBright,
            size: ObKitGlyphSize.inline,
          ),
          SizedBox(width: tokens.spacing.xxs),
          Text(
            label,
            style: tokens.type.tag.copyWith(color: tokens.color.accentBright),
          ),
        ],
      ),
    );
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({required this.icon, this.onTap});

  final ObKitGlyphKind icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: tokens.spacing.sm),
        child: ObKitGlyph(kind: icon, color: tokens.color.textSecondary),
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.vm, this.onChanged});

  final PanelParamVm vm;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return SizedBox(
      height: tokens.size.panelParamRowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: tokens.size.panelParamLabelWidth,
            child: Text(vm.label, style: tokens.type.microCaps),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown:
                      onChanged == null
                          ? null
                          : (TapDownDetails details) => onChanged!(
                            (details.localPosition.dx / constraints.maxWidth)
                                .clamp(0.0, 1.0),
                          ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        height: tokens.size.panelParamTrackHeight,
                        decoration: BoxDecoration(
                          color: color.surfaceWell,
                          borderRadius: BorderRadius.all(tokens.radius.xs),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: vm.value.clamp(0.0, 1.0),
                        child: Container(
                          height: tokens.size.panelParamTrackHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(tokens.radius.xs),
                            gradient: LinearGradient(
                              colors: <Color>[
                                color.accentMuted,
                                color.accent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (vm.readoutOnTrack)
                        Padding(
                          padding: EdgeInsets.only(
                            left:
                                constraints.maxWidth *
                                    vm.value.clamp(0.0, 1.0) +
                                tokens.spacing.sm,
                          ),
                          child: Text(
                            vm.readout,
                            style: tokens.type.knobValue,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (!vm.readoutOnTrack) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Text(vm.readout, style: tokens.type.knobValue),
          ],
        ],
      ),
    );
  }
}

/// The panel's live preview: the extension's proposed notes over the app's own
/// grid, in the app's own note colour. It is a preview of *your* project, so it
/// is drawn the way your project is drawn.
class _Preview extends StatelessWidget {
  const _Preview({required this.caption, required this.notes});

  final String caption;
  final List<PreviewNoteVm> notes;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      decoration: BoxDecoration(
        color: color.rollCanvas,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: CustomPaint(
        painter: PreviewPainter(
          notes: notes,
          gridLine: color.gridLine,
          note: color.noteFill,
          lineWidth: tokens.border.hairline,
          noteHeight: tokens.size.prNoteHeight,
          noteWidth: tokens.size.prVelocityStemWidth,
          radius: tokens.radius.xs,
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.sm),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(caption, style: tokens.type.extMeta),
          ),
        ),
      ),
    );
  }
}

/// Public so a paint-cost test can build one without the widget around it.
class PreviewPainter extends CustomPainter {
  PreviewPainter({
    required this.notes,
    required this.gridLine,
    required this.note,
    required this.lineWidth,
    required this.noteHeight,
    required this.noteWidth,
    required this.radius,
  });

  final List<PreviewNoteVm> notes;
  final Color gridLine;
  final Color note;
  final double lineWidth;
  final double noteHeight;
  final double noteWidth;
  final Radius radius;

  /// The preview is a fixed grid rather than one derived from a viewport: it
  /// is a picture of a result, not an editor.
  static const int _columns = 8;
  static const int _rows = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..color = gridLine
          ..strokeWidth = lineWidth;
    for (int i = 1; i < _columns; i++) {
      final double x = size.width * i / _columns;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (int i = 1; i < _rows; i++) {
      final double y = size.height * i / _rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final Paint fill = Paint()..color = note;
    for (final PreviewNoteVm vm in notes) {
      final Rect rect = Rect.fromLTWH(
        size.width * vm.x,
        size.height * vm.y,
        noteWidth,
        noteHeight * 2,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
    }
  }

  @override
  bool shouldRepaint(PreviewPainter oldDelegate) =>
      oldDelegate.notes != notes || oldDelegate.note != note;
}
