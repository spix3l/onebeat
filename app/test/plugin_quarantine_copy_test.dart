import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/plugin_list_debug.dart';

PluginListing quarantined({
  required ScanOutcome outcome,
  required ScanPhase phase,
}) => PluginListing(
  id: 'com.example.faulty',
  name: 'Faulty Synth',
  vendor: 'Example',
  version: '1.0',
  path: '/Library/Audio/Plug-Ins/CLAP/Faulty Synth.clap',
  format: PluginFormat.clap,
  outcome: outcome,
  failurePhase: phase,
  failureSignal: 11,
  retryCount: 0,
  introspected: false,
  paramCount: 0,
  audioInputCount: 0,
  audioOutputCount: 0,
  noteInputCount: 0,
  noteOutputCount: 0,
);

void main() {
  test('crash copy names the plugin, phase, consequence, and next actions', () {
    final String copy = pluginQuarantineMessage(
      quarantined(outcome: ScanOutcome.crashed, phase: ScanPhase.load),
    );

    expect(copy, contains('Faulty Synth'));
    expect(copy, contains('crashed while OneBeat was opening it'));
    expect(copy, contains('remains disabled'));
    expect(copy, contains('Retry'));
    expect(copy, contains('keep it quarantined'));
    expect(copy, isNot(contains('Sorry')));
    expect(copy, isNot(contains('!')));
  });

  test('timeout and enumerate phases use distinct plain-language copy', () {
    final String copy = pluginQuarantineMessage(
      quarantined(outcome: ScanOutcome.timedOut, phase: ScanPhase.enumerate),
    );

    expect(copy, contains('stopped responding'));
    expect(copy, contains('reading its plug-in list'));
  });
}
