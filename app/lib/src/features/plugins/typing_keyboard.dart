// TypingKeyboard — the computer keyboard as a two-octave MIDI controller.
//
// An open plug-in window is the one place in the app where the user is
// listening to an instrument rather than editing a timeline, and reaching for
// the mouse to click a 40-pixel-wide on-screen key is the wrong instrument to
// play. Wrapping the window in this widget makes the letter rows play the
// selected channel through the ordinary audition path, so the notes come out of
// the same plug-in the window is showing.
//
// Two things this deliberately does not do:
//
//  * It never claims a key that carries a modifier. ⌘V still pastes, ⌘W still
//    closes the window — only bare letters and digits are notes.
//  * It never leaves a voice hanging. Losing focus, changing octave mid-hold
//    and being disposed all release exactly the notes that were started, which
//    is why the held map is keyed by the physical key rather than by pitch.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The lower letter row, starting at the base octave's C, then the upper row an
/// octave above it — the layout every tracker and DAW has used since Fasttracker
/// and the one a keyboard player's fingers already know.
/// Not `const`: [LogicalKeyboardKey] overrides `==`, which a constant map key
/// may not do.
final Map<LogicalKeyboardKey, int> kTypingKeyboardSemitones = <LogicalKeyboardKey, int>{
  // Lower row: C … E one octave up.
  LogicalKeyboardKey.keyZ: 0,
  LogicalKeyboardKey.keyS: 1,
  LogicalKeyboardKey.keyX: 2,
  LogicalKeyboardKey.keyD: 3,
  LogicalKeyboardKey.keyC: 4,
  LogicalKeyboardKey.keyV: 5,
  LogicalKeyboardKey.keyG: 6,
  LogicalKeyboardKey.keyB: 7,
  LogicalKeyboardKey.keyH: 8,
  LogicalKeyboardKey.keyN: 9,
  LogicalKeyboardKey.keyJ: 10,
  LogicalKeyboardKey.keyM: 11,
  LogicalKeyboardKey.comma: 12,
  LogicalKeyboardKey.keyL: 13,
  LogicalKeyboardKey.period: 14,
  LogicalKeyboardKey.semicolon: 15,
  LogicalKeyboardKey.slash: 16,

  // Upper row: one octave above the lower one.
  LogicalKeyboardKey.keyQ: 12,
  LogicalKeyboardKey.digit2: 13,
  LogicalKeyboardKey.keyW: 14,
  LogicalKeyboardKey.digit3: 15,
  LogicalKeyboardKey.keyE: 16,
  LogicalKeyboardKey.keyR: 17,
  LogicalKeyboardKey.digit5: 18,
  LogicalKeyboardKey.keyT: 19,
  LogicalKeyboardKey.digit6: 20,
  LogicalKeyboardKey.keyY: 21,
  LogicalKeyboardKey.digit7: 22,
  LogicalKeyboardKey.keyU: 23,
  LogicalKeyboardKey.keyI: 24,
  LogicalKeyboardKey.digit9: 25,
  LogicalKeyboardKey.keyO: 26,
  LogicalKeyboardKey.digit0: 27,
  LogicalKeyboardKey.keyP: 28,
};

/// Octave transpose. Brackets rather than the tracker convention of Z/X,
/// because Z and X are notes here.
const LogicalKeyboardKey kTypingOctaveDown = LogicalKeyboardKey.bracketLeft;
const LogicalKeyboardKey kTypingOctaveUp = LogicalKeyboardKey.bracketRight;

/// The MIDI keys the typing keyboard is currently holding down, published to
/// the on-screen keyboards so they light up under the notes being played.
///
/// This is an inherited notifier rather than a constructor argument because the
/// keyboards live several private widgets deep inside each stock editor; a
/// parameter would have to be threaded through every one of them to deliver a
/// purely decorative fact.
class TypingKeysScope extends InheritedNotifier<ValueNotifier<Set<int>>> {
  const TypingKeysScope({required ValueNotifier<Set<int>> keys, required super.child, super.key})
    : super(notifier: keys);

  /// The held keys, or an empty set outside a [TypingKeyboard] — every
  /// on-screen keyboard is also used in places that have no typing keyboard
  /// above them, so absence is normal rather than an error.
  static Set<int> of(BuildContext context) {
    final TypingKeysScope? scope = context.dependOnInheritedWidgetOfExactType<TypingKeysScope>();
    return scope?.notifier?.value ?? const <int>{};
  }
}

class TypingKeyboard extends StatefulWidget {
  const TypingKeyboard({
    required this.child,
    this.onNoteOn,
    this.onNoteOff,
    this.onFocusGained,
    this.onBaseKeyChanged,
    this.focusNode,
    this.baseOctave = 4,
    this.velocity = 0.8,
    this.autofocus = true,
    super.key,
  });

  final Widget child;
  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  /// Called when the wrapped surface takes the keyboard. The plug-in window
  /// uses it to point the engine's audition voice at its own instrument, so the
  /// window you are typing into is the one you hear.
  final VoidCallback? onFocusGained;

  /// Reports the lowest reachable note after an octave change, so the window
  /// can tell the user where the letter rows currently are.
  final ValueChanged<int>? onBaseKeyChanged;

  final FocusNode? focusNode;

  /// C of the lower row, in octaves. 4 puts it at MIDI 48.
  final int baseOctave;
  final double velocity;
  final bool autofocus;

  @override
  State<TypingKeyboard> createState() => TypingKeyboardState();
}

class TypingKeyboardState extends State<TypingKeyboard> {
  /// Physical key → the note it started. Keyed this way so that a note started
  /// before an octave change is released with the pitch it was started with.
  final Map<LogicalKeyboardKey, int> _held = <LogicalKeyboardKey, int>{};
  final ValueNotifier<Set<int>> _heldKeys = ValueNotifier<Set<int>>(const <int>{});

  FocusNode? _ownedNode;
  int _octaveShift = 0;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode(debugLabel: 'typing-keyboard'));

  /// The lowest note the letter rows can reach, after the octave offset.
  int get baseKey => ((widget.baseOctave + _octaveShift) * 12).clamp(0, 127);

  @override
  void dispose() {
    _releaseAll();
    _heldKeys.dispose();
    _ownedNode?.dispose();
    super.dispose();
  }

  void _publish() => _heldKeys.value = Set<int>.unmodifiable(_held.values.toSet());

  void _releaseAll() {
    if (_held.isEmpty) return;
    for (final int key in _held.values) {
      widget.onNoteOff?.call(key);
    }
    _held.clear();
    _publish();
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus) {
      widget.onFocusGained?.call();
      return;
    }
    // Focus left mid-chord — a click on the rack, or ⌘Tab. The key-up events
    // will never arrive here, so the voices have to be ended now.
    _releaseAll();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A modifier means the user is reaching for a command, not a note.
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;

    if (event is KeyDownEvent && (key == kTypingOctaveDown || key == kTypingOctaveUp)) {
      final int next = (_octaveShift + (key == kTypingOctaveUp ? 1 : -1)).clamp(-4, 4);
      if (next != _octaveShift) {
        setState(() => _octaveShift = next);
        widget.onBaseKeyChanged?.call(baseKey);
      }
      return KeyEventResult.handled;
    }

    final int? semitone = kTypingKeyboardSemitones[key];
    if (semitone == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      // Auto-repeat arrives as KeyRepeatEvent and is ignored above; this guard
      // covers a down without a matching up, which a focus change can produce.
      if (_held.containsKey(key)) return KeyEventResult.handled;
      final int note = baseKey + semitone;
      if (note < 0 || note > 127) return KeyEventResult.handled;
      _held[key] = note;
      _publish();
      widget.onNoteOn?.call(note, widget.velocity);
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final int? note = _held.remove(key);
      if (note == null) return KeyEventResult.ignored;
      _publish();
      widget.onNoteOff?.call(note);
      return KeyEventResult.handled;
    }

    // KeyRepeatEvent: swallowed, so holding a key sustains one voice instead of
    // machine-gunning note-ons at the repeat rate.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: Listener(
        // A click anywhere in the window brings the typing keyboard back,
        // including after a text field or another editor took focus away.
        onPointerDown: (_) {
          if (!_node.hasFocus) _node.requestFocus();
        },
        child: TypingKeysScope(keys: _heldKeys, child: widget.child),
      ),
    );
  }
}
