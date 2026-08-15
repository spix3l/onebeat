# Keyboard shortcuts and focus

The rules, and the three bugs that produced them. If you are adding a shortcut,
the section you want is [Adding an action](#adding-an-action) at the bottom.

Code: `app/lib/src/ui/shortcuts.dart`, `app/lib/src/ui/action_registry.dart`.
Tests: `app/test/shortcuts_test.dart`,
`app/test/action_reachability_test.dart`.

## The three bugs

### 1. Typing triggered tools

The piano roll bound bare `B` and `V` for its draw and select tools. Those
activators **still match while a text field has focus** — a raw key event
reaches `Shortcuts` whether or not an `EditableText` also consumed it. Renaming
a pattern to "Bass" switched tools twice, and the first backspace deleted the
selected notes.

**Fix:** `OneBeatShortcutManager` refuses *bare-key* activators while the
primary focus is inside an `EditableText`. Modified shortcuts are unaffected —
nobody types ⌘Z into a name, so suppressing it would be the opposite bug.

The rule, precisely:

| While typing | Suppressed? | Why |
|---|---|---|
| `B`, `V`, `1` | yes | indistinguishable from typing |
| `⌫`, `⌦` | yes | in a field these mean "delete a character" |
| `⇧D` | yes | still just typing a capital letter |
| `⌘Z`, `⇧⌘D` | **no** | unambiguous; suppressing them makes undo mysteriously dead |
| `⌥`-anything | **no** | option-key combinations are not text entry here |

### 2. Two widgets both claimed the keyboard

The shell and the piano roll each had `Focus(autofocus: true)`. Which one won
depended on build order, so Space-to-play worked or did not depending on how you
navigated there.

**Fix:** exactly one `autofocus` in the app, on the shell. Editors take focus on
pointer-down inside their canvas. `Shortcuts` resolve *up* the tree, so an
editor owning its own keys does not shadow the global ones.

### 3. Tooltips drifted from bindings

The display string was hand-typed next to the binding, and nothing checked them
against each other. One entry claimed `⌥drag` — not an activator at all.

**Fix:** the activator is the source of truth and `UiAction.shortcut` is
*derived* from it by `describeActivator`. They cannot disagree. An action whose
gesture is genuinely a mouse action now says so in prose, in `description`,
where it belongs.

## Scopes

| Scope | Lives on | Examples |
|---|---|---|
| `global` | the shell | Space, ⌘Z, ⇧⌘Z, ⌘S, ⇧⌘S, ⌘O, ⌘K, 1/2/3 view switching |
| `editor` | whichever editor has focus | B/V, ⌘J, ⌘D, ⌫ |

`⌘D` is bound in both the piano roll and the arrangement, to different actions.
That is fine and intentional: they are different subtrees and only one is
mounted at a time. `shortcuts_test.dart` asserts no *two actions in the same
area* claim the same key, which is the collision that would actually be silent.

## Focus ownership

- **The shell** holds the only `autofocus`. It never gives focus up
  permanently.
- **An editor** takes focus on pointer-down in its canvas, via
  `FocusPolicy.takeUnlessTyping` — which declines if a text field is mid-edit,
  so clicking a canvas while renaming does not silently drop the rename.
- **A text field** takes focus on tap and returns it on Enter, Escape, or tap
  outside.
- **Space is the transport, everywhere, always.** No control binds it, so it
  works no matter what was clicked last (FR-UX-24). This rule predates the
  revamp and survives it unchanged.

## Escape

Escape unwinds **one layer at a time**, so it is always clear what it did:

1. an in-flight drag → cancel it, reverting every intermediate edit;
2. otherwise → clear the selection.

Never both at once.

## Adding an action

1. Declare it in `ActionRegistry.all`: id, label, area, and an `activator` if it
   has a key. Do **not** write a display string — it is generated.
2. Give its visible control `key: actionKey(id)`. This is not optional:
   `action_reachability_test.dart` fails the build otherwise, for every area
   including transport.
3. Put the id in the owning editor's `ScopedShortcuts` handler map.

That is the whole contract. If the action has no key, skip step 1's `activator`
and steps 2 and 3 still apply — reachability is about the control, not the key.

## What is deliberately not done yet

- **FR-UX-22 (remappable shortcuts).** The registry is the right shape for it —
  ids are stable and activators are data — but nothing persists an override yet.
- **The command palette.** ⌘K currently opens a read-only shortcut sheet
  generated from the registry. Turning it into a searchable, executable palette
  is the natural next step and needs no new data model.
- **Menu-bar integration.** The design shows a system menu bar (File, Edit,
  Pattern, View…). The registry carries everything a menu needs except the
  placement, which is why `UiAction` has room for it.
