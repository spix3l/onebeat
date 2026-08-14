// Piano roll fixtures (UI-B-07) — the Soft Keys phrase of
// `screens/piano-roll.png`, transcribed from the PNG.
//
// Positions were read off the mockup at the export's 2× scale: the grid starts
// at bar 1, one bar is 288 logical px, one row is 14, and the top row is A♯5.
// Bars and beats are written as ticks so the fixture stays readable as music.
import 'package:onebeat/src/features/piano_roll/note_grid.dart';

/// One bar of 4/4 at [prTicksPerBeat].
const int _bar = prTicksPerBeat * 4;

/// The mockup's top row: A♯5, ten semitones above middle C5 (72).
const int demoTopMidiNote = 82;

/// One bar spans 288 logical px in the mockup.
const double demoTicksPerPx = _bar / 288;

const PrViewport demoViewport = PrViewport(
  ticksPerPx: demoTicksPerPx,
  rowHeight: 14,
  firstVisibleTick: 0,
  topMidiNote: demoTopMidiNote,
);

/// Places a note at [bar] bars from the start (fractional), [length] bars long.
PrNoteVm _at(
  int id,
  int midi,
  double bar,
  double length, {
  double velocity = 0.8,
}) => PrNoteVm(
  id: id,
  midiNote: midi,
  startTick: (bar * _bar).round(),
  lengthTicks: (length * _bar).round(),
  velocity: velocity,
);

/// The nineteen played notes, in the mockup's order down the roll.
final List<PrNoteVm> demoNotes = <PrNoteVm>[
  _at(1, 77, 0.5, 0.25, velocity: 0.95),
  _at(2, 77, 1.25, 0.25, velocity: 0.7),
  _at(3, 75, 0.75, 0.25, velocity: 0.55),
  _at(4, 73, 0.25, 0.25, velocity: 0.8),
  _at(5, 73, 1.125, 0.125, velocity: 0.6),
  _at(6, 73, 1.5, 0.25, velocity: 0.75),
  _at(7, 70, 0, 0.25, velocity: 0.85),
  _at(8, 70, 1, 0.125, velocity: 0.6),
  _at(9, 70, 1.75, 0.25, velocity: 0.9),
  _at(10, 70, 3, 0.5, velocity: 0.95),
  _at(11, 68, 0, 0.25, velocity: 0.8),
  _at(12, 65, 1, 0.5, velocity: 0.7),
  _at(13, 65, 3.5, 0.5, velocity: 0.65),
  _at(14, 63, 0.25, 0.25, velocity: 0.75),
  _at(15, 63, 3.25, 0.25, velocity: 0.6),
  _at(16, 61, 3, 0.25, velocity: 0.5),
  _at(17, 58, 1.5, 0.5, velocity: 0.8),
  _at(18, 58, 2.5, 0.5, velocity: 0.7),
  _at(19, 53, 2, 0.5, velocity: 0.85),
];

/// The three notes the mockup draws white.
const Set<int> demoSelected = <int>{1, 3, 10};

/// The other channels' notes, in `noteGhost`.
final List<PrNoteVm> demoGhostNotes = <PrNoteVm>[
  _at(101, 53, 1, 0.5),
  _at(102, 53, 2.5, 0.5),
  _at(103, 49, 0.5, 0.5),
  _at(104, 49, 3, 1),
  _at(105, 46, 0, 0.5),
  _at(106, 46, 2, 0.5),
];

/// The playhead sits half-way through bar 2 in the mockup.
const int demoPlayheadTick = _bar + _bar ~/ 2;

final PianoRollVm demoPianoRoll = PianoRollVm(
  notes: demoNotes,
  ghostNotes: demoGhostNotes,
  viewport: demoViewport,
  playheadTick: demoPlayheadTick,
  selected: demoSelected,
);
