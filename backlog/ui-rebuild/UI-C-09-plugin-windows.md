# UI-C-09 — Plugin windows: float wrapper, params, builtin, failed

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01 (knobs), UI-B-11 (floating window, banner) |
| **Reference** | `ui-files/screens/plugin-float.png`, `plugin-params.png`, `plugin-builtin.png`, `plugin-failed.png` — open all four before writing code |
| **Target files** | `app/lib/src/features/plugins/plugin_windows.dart`, vms alongside; fixture `app/test/features/plugins/fixture.dart`; tests `app/test/features/plugins/plugin_windows_golden_test.dart` |
| **Estimate** | M |

## Context

Plugin editors float in `ObFloatingWindow.plugin` chrome (title `Synthpad One VST3`, `Bypass` chip, preset `Factory "Warm Keys"`, `WET 100%`, expand/min/close). Four states exist. The wrapper owns only the chrome — for native plugins the interior is the plugin's own view (status bar in the mockup: "Wrapper chrome only — the interior is the plugin's own view").

## Scope

1. **`PluginWindowVm`**: `{String name, String format /* VST3/CLAP */, bool bypassed, String preset, double wet, PluginBodyVm body}` where body is sealed: `.native(Size)` (grey placeholder slot in C — the real view arrives in D), `.params(...)`, `.builtin(...)`, `.failed(...)`.
2. **Params state** (`plugin-params.png`): transcribe — the generic parameter list/knob grid OneBeat renders when a plugin has no GUI.
3. **Builtin state** (`plugin-builtin.png`): transcribe — the stock-plugin editor layout (knob rows per the mockup, e.g. CUTOFF/RESO/ENV/DRIVE/SPREAD/MIX + ATTACK/DECAY/SUSTAIN/RELEASE/CHORUS/DELAY as in `plugin-float.png`'s interior if shared).
4. **Failed state** (`plugin-failed.png`): transcribe — crash containment card (danger banner + actions), consistent with the ext-manager crash card style.
5. Compose each over the dimmed shell backdrop exactly as its PNG shows.
6. Callbacks: `onBypass`, `onPresetTap`, `onWet`, `onClose`, `onExpand`, `onMinimise`, param `onChanged(i, v)`, failed-state actions.
7. Goldens: four full-frame goldens comparable 1:1 with the four PNGs (native interior = neutral placeholder fill; everything else exact).

## Acceptance criteria

- [ ] Four goldens match the mockups; wrapper chrome identical across states.
- [ ] Sealed vm switches states in one widget (widget test).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Hosting real plugin views (D-08), window dragging/resize, preset browser popup. Old `plugin_builtin_view.dart` / `stock_plugin_editor.dart` untouched.
