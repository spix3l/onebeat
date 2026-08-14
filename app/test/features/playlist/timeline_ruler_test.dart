// Timeline ruler (UI-B-08): the repaint contract of the bar ruler above the
// playlist canvas.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/playlist/timeline_ruler.dart';

void main() {
  test('the ruler repaints only when its mapping changes', () {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    PlaylistRulerPainter build(double pxPerBar) => PlaylistRulerPainter(
      pxPerBar: pxPerBar,
      labelEvery: tokens.size.playlistBarLabelEvery,
      line: tokens.color.line,
      lineWidth: tokens.border.hairline,
      style: tokens.type.numericSmall,
    );
    final PlaylistRulerPainter base = build(38.3);
    expect(build(38.3).shouldRepaint(base), isFalse);
    expect(build(76.6).shouldRepaint(base), isTrue);
  });
}
