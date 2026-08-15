// Test-suite bootstrap: every `flutter test` run in this package goes through
// here before the first test file executes.
//
// Its one job is the golden comparator. The default `LocalFileComparator`
// demands a byte-exact match, and that is stricter than the renderer can
// promise: the same widget, same Flutter version and same device pixel ratio
// still lands a handful of anti-aliased edge pixels differently on a developer
// Mac than on the CI runner. Every screen golden in this suite failed on CI at
// 0.01% or less — single-digit pixel counts on a 1600x1000 surface — while
// passing locally. Regenerating the files only moves the failure to whichever
// machine did not generate them.
//
// So the comparator below accepts a diff under [_goldenTolerance] and reports
// anything larger exactly as before. The threshold is deliberately far below a
// real regression: moving, resizing or recolouring anything a person can see
// changes thousands of pixels, two orders of magnitude past the bar.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The largest fraction of differing pixels a golden may have and still pass.
///
/// 0.001 is 0.1% — 1600 pixels on a full 1600x1000 screen golden. The worst
/// anti-aliasing drift observed between a local Mac and the CI runner is 222.
const double _goldenTolerance = 0.001;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  goldenFileComparator = _TolerantFileComparator(
    // `flutter_test` installs a `LocalFileComparator` rooted at the directory
    // of the test file being run, and golden paths are resolved against it.
    // Reusing that basedir keeps `goldens/<name>.png` resolving exactly as it
    // does by default, per test file.
    (goldenFileComparator as LocalFileComparator).basedir.resolve('test.dart'),
  );
  await testMain();
}

class _TolerantFileComparator extends LocalFileComparator {
  _TolerantFileComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= _goldenTolerance) {
      result.dispose();
      return true;
    }

    final String failure = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(failure);
  }
}
