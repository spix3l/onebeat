import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/floating_window.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../channel_rack/channel_settings_editor.dart';
import 'plugin_binding.dart';

/// The first view shown when a channel editor opens.
enum ChannelEditorTab { plugin, settings }

/// Shared FL-style channel editor chrome. The plugin and settings surfaces use
/// the same channel identity and window, so switching tabs never loses the
/// selected instrument or opens a second modal surface.
class ChannelEditorBinding extends StatefulWidget {
  const ChannelEditorBinding({
    required this.client,
    required this.trackId,
    required this.channelName,
    required this.plugin,
    required this.initialSettings,
    required this.onApplySettings,
    required this.onClose,
    this.parameters = const <HostedParameter>[],
    this.sampleName,
    this.initialTab = ChannelEditorTab.plugin,
    this.onDragUpdate,
    this.onTabChanged,
    super.key,
  });

  final EngineClient client;
  final String trackId;
  final String channelName;
  final HostedInstance plugin;
  final List<HostedParameter> parameters;
  final String? sampleName;
  final InstrumentSettings initialSettings;
  final ChannelEditorTab initialTab;
  final ValueChanged<InstrumentSettings> onApplySettings;
  final VoidCallback onClose;
  final ValueChanged<Offset>? onDragUpdate;
  final ValueChanged<ChannelEditorTab>? onTabChanged;

  @override
  State<ChannelEditorBinding> createState() => _ChannelEditorBindingState();
}

class _ChannelEditorBindingState extends State<ChannelEditorBinding> {
  late ChannelEditorTab _tab = widget.initialTab;

  @override
  void didUpdateWidget(covariant ChannelEditorBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId || oldWidget.plugin.id != widget.plugin.id) {
      _tab = widget.initialTab;
    }
  }

  Widget _tabButton(BuildContext context, String label, ChannelEditorTab tab) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool selected = _tab == tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _tab = tab);
        widget.onTabChanged?.call(tab);
      },
      child: Container(
        height: tokens.size.microFieldHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.color.accentWash : tokens.color.surfaceWell,
          border: Border.all(
            color: selected ? tokens.color.accentMuted : tokens.color.line,
            width: tokens.border.hairline,
          ),
          borderRadius: tokens.radius.controlBorder,
        ),
        child: Text(
          label,
          style: tokens.type.microCaps.copyWith(
            color: selected ? tokens.color.textPrimary : tokens.color.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final String pluginName = widget.plugin.name.isEmpty ? 'Plugin' : widget.plugin.name;

    final Widget pluginTab = PluginBinding(
      client: widget.client,
      trackId: widget.trackId,
      pluginName: pluginName,
      trackName: widget.channelName,
      sampleName: widget.sampleName,
      parameters: widget.parameters,
      embedded: true,
      onClose: widget.onClose,
    );
    final Widget settingsTab = ChannelSettingsEditor(
      channelName: widget.channelName,
      initial: widget.initialSettings,
      embedded: true,
      onApply: widget.onApplySettings,
      onClose: widget.onClose,
    );

    return ObFloatingWindow.plugin(
      vm: ObFloatingWindowVm(
        title: widget.channelName,
        subtitle: '$pluginName · CHANNEL EDITOR',
        actions: <ObWindowAction>[
          ObWindowAction(icon: ObKitGlyphKind.close, onTap: widget.onClose, tooltip: 'Close channel editor'),
        ],
      ),
      width: tokens.size.channelEditorWindowWidth,
      height: tokens.size.channelEditorWindowHeight,
      onDragUpdate: widget.onDragUpdate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: tokens.size.rackHeaderHeight + tokens.spacing.sm,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md, vertical: tokens.spacing.xs),
            decoration: BoxDecoration(
              color: tokens.color.surfaceRaised,
              border: Border(
                bottom: BorderSide(color: tokens.color.line, width: tokens.border.hairline),
              ),
            ),
            child: Row(
              children: <Widget>[
                _tabButton(context, 'Plugin', ChannelEditorTab.plugin),
                SizedBox(width: tokens.spacing.xs),
                _tabButton(context, 'Settings', ChannelEditorTab.settings),
                const Spacer(),
                Text(widget.channelName, style: tokens.type.label),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.plugin.hasEditor && widget.plugin.format != PluginFormat.builtin)
                  _NativePluginEditorHost(client: widget.client, plugin: widget.plugin),
                Expanded(
                  child: IndexedStack(
                    index: _tab.index,
                    children: <Widget>[pluginTab, settingsTab],
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

/// The current native seam opens a plug-in editor in its helper window. This
/// region makes that capability explicit in the shared editor and leaves a
/// stable place to replace it with an embedded platform view once the engine
/// exposes a view handle.
class _NativePluginEditorHost extends StatelessWidget {
  const _NativePluginEditorHost({required this.client, required this.plugin});

  final EngineClient client;
  final HostedInstance plugin;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.zero,
      ),
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md, vertical: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.accentWash,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(color: tokens.color.accentMuted, width: tokens.border.hairline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Native plug-in editor available · opens in its host window',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.bodySecondary,
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          ObButton(
            label: 'Open native editor',
            tone: ObButtonTone.secondary,
            onTap: () {
              try {
                client.openPluginEditor(plugin.id);
              } catch (_) {
                // A missing or crashed editor is reported by the engine; the
                // shared Flutter editor remains usable as the fallback.
              }
            },
          ),
        ],
      ),
    );
  }
}
