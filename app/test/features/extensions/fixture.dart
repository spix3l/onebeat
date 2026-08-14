// Extension manager fixtures (UI-C-11).
//
// Every string here is transcribed from `screens/ext-manager.png`,
// `ext-empty.png` and `ext-panel.png`. It is product voice, not lorem: the
// capability notes and the crash card's reassurance are the feature the screen
// is selling, so they are quoted rather than paraphrased.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/extensions/extension_manager_vm.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';
import 'package:onebeat/src/ui_kit/kit_glyphs.dart';
import 'package:onebeat/src/ui_kit/popover_menu.dart';
import 'package:onebeat/src/ui_kit/prose.dart';

const List<ExtensionVm> demoExtensions = <ExtensionVm>[
  ExtensionVm(
    id: 'harmonizer',
    name: 'Harmonizer',
    meta: 'by @luma · v1.2.0 · bound to ⇧⌘H',
    icon: ObKitGlyphKind.waveform,
    selected: true,
  ),
  ExtensionVm(
    id: 'clip-roulette',
    name: 'Clip Roulette',
    meta: 'built by you · v0.3.1 · from console',
    icon: ObKitGlyphKind.cursor,
  ),
  ExtensionVm(
    id: 'drum-fill',
    name: 'Drum Fill Generator',
    meta: 'by @grain · v0.9.2 · panel',
    icon: ObKitGlyphKind.note,
  ),
  ExtensionVm(
    id: 'groove-fetcher',
    name: 'Groove Fetcher',
    meta: 'by @unknown · v0.1.0',
    icon: ObKitGlyphKind.warning,
    enabled: false,
    crashed: true,
  ),
];

const CrashCardVm demoCrashCard = CrashCardVm(
  title: 'GROOVE FETCHER CRASHED — CONTAINED & DISABLED',
  body: <ObProseRun>[
    ObProseRun('It failed twice within a minute ', strong: true),
    ObProseRun('(last: 14:01, inside its note listener)'),
    ObProseRun(
      '. Nothing else was affected, your project is untouched. It won\'t be '
      'retried until you say so.',
      strong: true,
    ),
  ],
  actions: <String>['Try again once', 'Report crash', 'Uninstall'],
);

const ExtensionDetailVm demoExtensionDetail = ExtensionDetailVm(
  name: 'Harmonizer',
  meta: 'by @luma · v1.2.0 · installed 2 days ago',
  icon: ObKitGlyphKind.waveform,
  description: <ObProseRun>[
    ObProseRun(
      "Adds a fifth above the chord you're playing, in key. Works on the "
      'selected pattern in the piano roll. ',
    ),
    ObProseRun(
      'Written against the public API — same one the built-ins use.',
      strong: true,
    ),
  ],
  capabilities: <CapabilityVm>[
    CapabilityVm(
      name: 'Read the project',
      granted: true,
      note: 'patterns, notes, mixer',
    ),
    CapabilityVm(
      name: 'Modify notes',
      granted: true,
      note: 'undoable, like your own edits',
    ),
    CapabilityVm(name: 'Read files', granted: false, note: 'has not asked'),
    CapabilityVm(name: 'Network', granted: false, note: 'never granted'),
    CapabilityVm(
      name: 'Audio thread',
      granted: false,
      note: 'impossible by design',
    ),
  ],
  bindings: <BindingVm>[
    BindingVm(
      icon: ObKitGlyphKind.keyboard,
      label: 'Keyboard shortcut',
      tag: '⇧⌘H',
    ),
    BindingVm(
      icon: ObKitGlyphKind.menuLines,
      label: 'Menu action',
      detail: 'Tools › Harmonize selection',
    ),
    BindingVm(
      icon: ObKitGlyphKind.note,
      label: 'MIDI note',
      tag: 'C#4',
      tagNote: 'when recording',
    ),
  ],
  crash: demoCrashCard,
);

const ExtensionManagerVm demoExtensionManager = ExtensionManagerVm(
  extensions: demoExtensions,
  detail: demoExtensionDetail,
);

/// The Tools menu, open over the top of the manager. `Extension manager…` is
/// the accented row: it is the screen you are already on.
const ObPopoverMenuVm demoToolsMenu = ObPopoverMenuVm(
  wide: true,
  sections: <ObMenuSectionVm>[
    ObMenuSectionVm(
      rows: <ObMenuRowVm>[
        ObMenuRowVm(label: 'Script console', shortcut: '⌘J'),
        ObMenuRowVm(
          label: 'Extension manager…',
          shortcut: '⇧⌘E',
          tone: ObMenuRowTone.active,
        ),
        ObMenuRowVm(label: 'Harmonize selection', shortcut: '⇧⌘H'),
        ObMenuRowVm(label: 'Clip roulette', shortcut: '⌥R'),
      ],
    ),
  ],
);

const ObStatusBarVm demoExtensionStatus = ObStatusBarVm(
  tone: StatusTone.ok,
  primary: '3 of 4 extensions enabled',
  details: <String>[
    '1 contained crash',
    'All extensions sandboxed — worst case is a disabled extension, never a '
        'lost project',
  ],
  rightHint: '⇧⌘E manager · ⌘K actions',
);

const ExtensionEmptyVm demoExtensionEmpty = ExtensionEmptyVm(
  heading: 'This is where OneBeat bends',
  body: <ObProseRun>[
    ObProseRun(
      'Built-in instruments, note generators, file importers, whole new '
      'panels — extensions are just scripts with ',
    ),
    ObProseRun('your project as the API', strong: true),
    ObProseRun(
      ". They're sandboxed, you grant what they can touch, and the worst case "
      'is a disabled extension — never a lost track. ',
    ),
    ObProseRun(
      "You've already used the console to shape this project",
      strong: true,
    ),
    ObProseRun('; make it repeatable.'),
  ],
  steps: <ExtensionStepVm>[
    ExtensionStepVm(
      title: 'Write in the console',
      body: 'Try things live against your own project',
    ),
    ExtensionStepVm(
      title: 'Save as an extension',
      body: 'Name it, version it, re-run it',
    ),
    ExtensionStepVm(
      title: 'Grant capabilities',
      body: 'You decide what it can read and touch',
    ),
  ],
  hints: <ExtensionHintVm>[
    ExtensionHintVm(keys: '⇧⌘E', label: 'reopen'),
    ExtensionHintVm(keys: '⌘J', label: 'console'),
    ExtensionHintVm(keys: '⌘K', label: 'search actions'),
  ],
);

const ObStatusBarVm demoExtensionEmptyStatus = ObStatusBarVm(
  tone: StatusTone.ok,
  primary: 'No extensions',
  details: <String>[
    'OneBeat is fully functional without them',
    'Extensions add: generators · note transforms · importers · panels',
  ],
  rightHint: 'First script takes about two minutes',
);

/// The docked-panel row of `screens/ext-panel.png`. The channel rack and the
/// compressor are context: they exist so the extension panel between them can
/// be seen to be drawn no differently.
final ExtensionPanelScreenVm demoExtensionPanelScreen = ExtensionPanelScreenVm(
  before: <PanelNeighbourVm>[
    PanelNeighbourVm(
      title: 'Channel Rack',
      rows: <PanelListRowVm>[
        PanelListRowVm(
          name: 'Kick 808',
          caption: 'Sampler',
          trailing: '→ D1',
          color: channelColors[0],
        ),
        PanelListRowVm(
          name: 'Sub Bass',
          caption: 'Reese',
          trailing: '→ B1',
          color: channelColors[2],
        ),
        PanelListRowVm(
          name: 'Soft Keys',
          caption: 'EP',
          trailing: '→ M1',
          color: channelColors[5],
        ),
      ],
    ),
  ],
  panel: const ExtensionPanelVm(
    title: 'Harmonizer',
    author: 'by @luma',
    params: <PanelParamVm>[
      PanelParamVm(label: 'AMOUNT', value: 0.62, readout: '0.62'),
      PanelParamVm(
        label: 'INTERVAL',
        value: 0.18,
        readout: '5th',
        readoutOnTrack: true,
      ),
    ],
    previewNotes: <PreviewNoteVm>[
      PreviewNoteVm(x: 0.15, y: 0.03),
      PreviewNoteVm(x: 0.21, y: 0.08),
      PreviewNoteVm(x: 0.35, y: 0.02),
      PreviewNoteVm(x: 0.41, y: 0.11),
      PreviewNoteVm(x: 0.56, y: 0.01),
      PreviewNoteVm(x: 0.63, y: 0.07),
    ],
  ),
  after: <PanelNeighbourVm>[
    const PanelNeighbourVm(
      title: 'Compressor',
      knobs: <PanelKnobVm>[
        PanelKnobVm(label: 'THRESH', value: 0.35, readout: '−18'),
        PanelKnobVm(label: 'RATIO', value: 0.5, readout: '4:1'),
        PanelKnobVm(label: 'ATTACK', value: 0.28, readout: '12'),
        PanelKnobVm(label: 'RELEASE', value: 0.6, readout: '180'),
        PanelKnobVm(label: 'MIX', value: 1, readout: '100'),
      ],
      wells: <PanelWellVm>[
        PanelWellVm(label: 'INPUT', readout: '−4.2', level: 0.72),
        PanelWellVm(label: 'GAIN RED.', readout: '−6', level: 0.42),
      ],
    ),
  ],
);

const ObStatusBarVm demoExtensionPanelStatus = ObStatusBarVm(
  tone: StatusTone.ok,
  primary: 'Harmonizer',
  details: <String>[
    'extension panel docked like any other',
    'Same chrome, same drag/tear-off · sandboxed, no access to audio',
  ],
  rightHint: 'Panels are registered by extensions via the API',
);
