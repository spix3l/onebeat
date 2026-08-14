// The UI-B-01 storybook golden: every core control in every state, laid out
// on a sunken board like a component sheet. Fixture labels are verbatim from
// the mockups (`Chorus`, `EQ 4`, `Reeverb 2`, `→ D1`, `Search samples,
// presets…`) so the golden diffs against `ui-files/` side by side.
// Behaviour tests live in the per-component files next to this one.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/dropdown.dart';
import 'package:onebeat/src/ui_kit/fx_chip.dart';
import 'package:onebeat/src/ui_kit/knob.dart';
import 'package:onebeat/src/ui_kit/rail_button.dart';
import 'package:onebeat/src/ui_kit/search_field.dart';
import 'package:onebeat/src/ui_kit/search_icon.dart';
import 'package:onebeat/src/ui_kit/tag_chip.dart';
import 'package:onebeat/src/ui_kit/toggle_chip.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../support/ui_glyphs.dart';
import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the core controls board renders as the storybook golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, const _ControlsBoard(), size: const Size(780, 560));
    await tester.pumpAndSettle();

    // Open one dropdown so the popover menu is part of the sheet.
    await tester.tap(find.byType(ObDropdown).last);
    await tester.pumpAndSettle();

    await expectLater(find.byType(_ControlsBoard), uiGolden('core_controls'));
  });
}

/// The board: one column of captioned sections.
class _ControlsBoard extends StatelessWidget {
  const _ControlsBoard();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Section(caption: 'KNOBS', child: _KnobRow()),
          SizedBox(height: tokens.spacing.lg),
          const _Section(caption: 'TRANSPORT', child: _TransportRow()),
          SizedBox(height: tokens.spacing.lg),
          const _Section(caption: 'RAIL', child: _RailRow()),
          SizedBox(height: tokens.spacing.lg),
          const _Section(caption: 'DROPDOWN', child: _DropdownRow()),
          SizedBox(height: tokens.spacing.lg),
          const _Section(caption: 'CHIPS', child: _ChipRow()),
          SizedBox(height: tokens.spacing.lg),
          const _Section(caption: 'SEARCH', child: _SearchRow()),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(caption, style: tokens.type.sectionHeader),
        SizedBox(height: tokens.spacing.sm),
        child,
      ],
    );
  }
}

class _KnobRow extends StatelessWidget {
  const _KnobRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        ObKnob(value: 0, onChanged: null),
        _Gap(),
        ObKnob(value: 0.25, onChanged: null),
        _Gap(),
        ObKnob(value: 0.5, onChanged: null),
        _Gap(),
        ObKnob(value: 0.75, onChanged: null),
        _Gap(),
        ObKnob(value: 1, onChanged: null),
        _Gap(),
        ObKnob(value: 0.6, onChanged: null, accent: true),
        _Gap(),
        ObKnob(value: 0.4, onChanged: null, label: 'VOL'),
        _Gap(),
        ObKnob(value: 0.5, onChanged: null, accent: true, label: 'PAN'),
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow();

  @override
  Widget build(BuildContext context) {
    final ColorTokens color = OneBeatTheme.of(context).color;
    return Row(
      children: <Widget>[
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.skipBack,
            color: color.textSecondary,
          ),
        ),
        const _Gap(),
        ObTransportButton(
          onTap: () {},
          active: true,
          child: TransportGlyph(kind: GlyphKind.play, color: color.textPrimary),
        ),
        const _Gap(),
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.stop,
            color: color.textSecondary,
          ),
        ),
        const _Gap(),
        ObTransportButton(
          onTap: () {},
          toggled: true,
          child: TransportGlyph(kind: GlyphKind.record, color: color.danger),
        ),
        const _Gap(),
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.loop,
            color: color.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ObRailButton(icon: RailGlyph.grid(), label: 'playlist', onTap: null),
        const _Gap(),
        ObRailButton(
          icon: RailGlyph.grid(),
          label: 'rack',
          active: true,
          onTap: null,
        ),
        const _Gap(),
        ObRailButton(icon: RailGlyph.sliders(), label: 'mixer', onTap: null),
        const _Gap(),
        ObRailButton(icon: RailGlyph.wave(), label: 'roll', onTap: null),
      ],
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        ObDropdown(
          label: 'SNAP',
          value: '1/4 step',
          items: <String>['none', '1/2 step', '1/4 step'],
        ),
        _Gap(),
        ObDropdown(
          label: 'SCALE',
          value: 'C minor',
          items: <String>['C minor', 'C major', 'chromatic'],
        ),
        _Gap(),
        ObDropdown(
          label: 'GROUP',
          value: 'Audio 2',
          items: <String>['Audio 1', 'Audio 2', 'Audio 3'],
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow();

  @override
  Widget build(BuildContext context) {
    final ColorTokens color = OneBeatTheme.of(context).color;
    return Row(
      children: <Widget>[
        ObFxChip(
          label: 'Chorus',
          dotColor: color.channelColors[4],
          onTap: () {},
        ),
        const _Gap(),
        ObFxChip(label: 'EQ 4', dotColor: color.channelColors[1], onTap: () {}),
        const _Gap(),
        ObFxChip(
          label: 'Reeverb 2',
          dotColor: color.channelColors[2],
          onTap: () {},
        ),
        const _Gap(),
        ObFxChip(label: '→ D1', dotColor: color.channelColors[0], mono: true),
        const _Gap(),
        ObToggleChip(tone: ObToggleTone.mute, on: true, onTap: () {}),
        const _Gap(small: true),
        ObToggleChip(tone: ObToggleTone.solo, on: true, onTap: () {}),
        const _Gap(small: true),
        ObToggleChip(tone: ObToggleTone.mute, on: false, onTap: () {}),
        const _Gap(small: true),
        ObToggleChip(tone: ObToggleTone.solo, on: false, onTap: () {}),
        const _Gap(),
        const ObTagChip(label: '4 tracks'),
        const _Gap(small: true),
        const ObTagChip(label: '12'),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        ObSearchField(hint: 'Search samples, presets…', onTap: null),
        _Gap(),
        ObSearchField(hint: 'Search actions', shortcut: '⌘K', onTap: null),
        _Gap(),
        ObSearchIcon(onTap: null),
      ],
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final SpacingTokens spacing = OneBeatTheme.of(context).spacing;
    return SizedBox(width: small ? spacing.xs : spacing.lg);
  }
}
