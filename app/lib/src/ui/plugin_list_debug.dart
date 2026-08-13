// A minimal plug-in listing (OB-2-02 scope §5). Toggled with F10.
//
// Deliberately plain: OB-2-10 designs the real browser, and building an
// undesigned one here would either be thrown away or — worse — quietly become
// the design. What this does have to be right about is the *states*, because
// they are what the ticket is demonstrating: an empty library, a scan in
// progress with the list already populated, and rows that are honest about how
// much is actually known (FR-UX-12/13).
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'plugin_library_store.dart';

class PluginListDebugPanel extends StatelessWidget {
  const PluginListDebugPanel({required this.controller, super.key});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PluginLibraryStore library = controller.library;

    return Container(
      color: tokens.color.surfaceDeep,
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: AnimatedBuilder(
        animation: library,
        builder: (BuildContext context, Widget? child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('PLUG-INS  (F10 to close)', style: tokens.type.label),
            SizedBox(height: tokens.spacing.lg),
            Row(
              children: <Widget>[
                OneBeatButton(
                  label: library.status.isScanning ? 'STOP SCAN' : 'SCAN',
                  semanticLabel: library.status.isScanning
                      ? 'Stop scanning for plug-ins'
                      : 'Scan for plug-ins',
                  active: library.status.isScanning,
                  onPressed: () {
                    if (library.status.isScanning) {
                      library.cancelScan();
                    } else {
                      library.startScan();
                    }
                  },
                ),
                SizedBox(width: tokens.spacing.md),
                Expanded(child: Text(library.summary, style: tokens.type.body)),
              ],
            ),
            if (library.status.current.isNotEmpty) ...<Widget>[
              SizedBox(height: tokens.spacing.xs),
              Text(library.status.current, style: tokens.type.numericSmall),
            ],
            SizedBox(height: tokens.spacing.lg),
            Expanded(
              child: library.plugins.isEmpty
                  ? _EmptyLibrary(scanning: library.status.isScanning)
                  : ListView.builder(
                      itemCount: library.plugins.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _PluginRow(listing: library.plugins[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state, designed rather than deferred (FR-UX-13): it says what is
/// true, and offers the one action that changes it.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: tokens.size.proseWidth,
        child: Text(
          scanning
              ? 'Looking through your plug-in folders. Anything found appears here '
                  'as it is found — you do not have to wait for the scan to finish.'
              : 'No plug-ins yet. OneBeat looks in the standard CLAP folders: '
                  '/Library/Audio/Plug-Ins/CLAP and the same path inside your home '
                  'folder. Choose SCAN to look now.',
          style: tokens.type.body,
        ),
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({required this.listing});

  final PluginListing listing;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: tokens.size.proseWidth,
            child: Text(
              listing.name,
              style: listing.isUsable
                  ? tokens.type.body
                  : tokens.type.body.copyWith(color: tokens.color.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          Text(_detail(listing), style: tokens.type.numericSmall),
        ],
      ),
    );
  }

  // The row never asserts something the scan has not established. Until a probe
  // has actually opened the bundle, the port and parameter counts are zero
  // because nothing has counted them — printing "0 in / 0 out" would read as a
  // fact about the plug-in rather than about our knowledge of it.
  static String _detail(PluginListing listing) {
    switch (listing.outcome) {
      case ScanOutcome.notAPlugin:
        return 'not a plug-in we can host';
      case ScanOutcome.crashed:
        return 'crashed while scanning';
      case ScanOutcome.timedOut:
        return 'stopped responding while scanning';
      case ScanOutcome.ok:
        if (!listing.introspected) {
          return 'found, not yet inspected';
        }
        final String vendor = listing.vendor.isEmpty ? '' : '${listing.vendor} · ';
        return '$vendor${listing.audioOutputCount} out · '
            '${listing.paramCount} parameters';
    }
  }
}
