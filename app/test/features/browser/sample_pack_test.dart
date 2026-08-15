import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/browser/sample_pack.dart';

void main() {
  test('rejects an empty folder', () async {
    final Directory root = await Directory.systemTemp.createTemp('onebeat-pack-');
    addTearDown(() => root.delete(recursive: true));

    expect(await SamplePackScanner.scan(root.path), isNull);
  });

  test('accepts WAV files recursively and ignores unsupported files', () async {
    final Directory root = await Directory.systemTemp.createTemp('onebeat-pack-');
    addTearDown(() => root.delete(recursive: true));
    final Directory drums = Directory('${root.path}/Drums')..createSync();
    File('${root.path}/readme.txt').writeAsStringSync('not audio');
    File('${drums.path}/Kick.WAV').writeAsBytesSync(<int>[0]);

    final SamplePack? pack = await SamplePackScanner.scan(root.path);

    expect(pack, isNotNull);
    expect(pack!.assets.map((SampleAsset asset) => asset.name), <String>[
      'Kick.WAV',
    ]);
    expect(pack.assets.single.path, '${drums.path}/Kick.WAV');
  });
}
