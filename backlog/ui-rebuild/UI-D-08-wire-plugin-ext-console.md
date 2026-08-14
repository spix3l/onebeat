# UI-D-08 — Wire plugin windows, extensions, console

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-09, UI-C-10, UI-C-11, UI-D-01 |
| **Reference** | existing `plugin_builtin_view.dart`, `stock_plugins/`, `plugin_library_store.dart`, `extension_manager_view.dart`, `script_console_view.dart`, `plugin_list_debug.dart` |
| **Target files** | `app/lib/src/features/plugins/plugin_binding.dart`, `app/lib/src/features/extensions/extension_binding.dart`, `app/lib/src/features/console/console_binding.dart`; tests alongside |
| **Estimate** | L |

## Scope

1. **Plugin windows**: open from rack/inspector; native plugin view hosted inside `ObFloatingWindow.plugin` via the existing hosting mechanism; params fallback bound to real parameter lists; builtin editors rebuilt under `features/plugins/stock/` (port from `lib/src/stock_plugins/` — that directory is deleted in D-09 along with `lib/src/ui/`); crash containment → failed state (reuse quarantine behaviour, see `plugin_quarantine_copy_test.dart`). Bypass/wet/preset wired where the host supports them; gaps → `GAPS.md`.
2. **Extension manager**: bind list/detail to the real extension store (whatever `extension_manager_view.dart` reads today); enable/disable, install-from-file, crash card actions.
3. **Console**: bind editor/run/output to the existing script console backend; save-as-extension flow to its real action.
4. Tests with fakes: open/close plugin window lifecycle, crash → contained vm, extension toggle round-trip, console run appends output.

## Acceptance criteria

- [ ] A real CLAP/VST3 plugin editor opens in the new wrapper chrome; a stock plugin opens in the builtin layout; a killed plugin shows the failed card without taking the app down.
- [ ] Extension toggles and console run work against the real backends.
- [ ] Suite green; analyze + token lint clean; goldens unchanged.

## Out of scope

New extension capabilities (EPIC-6); FFI changes (human review — R4).
