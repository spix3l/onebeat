import 'package:flutter/foundation.dart';

@immutable
class SnapGridChoice {
  const SnapGridChoice(this.label, this.ticks);

  static const int ticksPerQuarter = 960;

  static const List<SnapGridChoice> all = <SnapGridChoice>[
    SnapGridChoice('1/4', ticksPerQuarter),
    SnapGridChoice('1/8', ticksPerQuarter ~/ 2),
    SnapGridChoice('1/3', ticksPerQuarter ~/ 3),
    SnapGridChoice('1/16', ticksPerQuarter ~/ 4),
    SnapGridChoice('1/6', ticksPerQuarter ~/ 6),
    SnapGridChoice('1/32', ticksPerQuarter ~/ 8),
    SnapGridChoice('None', 0),
  ];

  static List<String> get labels => all.map((SnapGridChoice choice) => choice.label).toList();

  static List<String> get rackLabels => <String>[
    for (final int index in <int>[0, 1, 3, 2, 4, 6]) all[index].label,
  ];

  final String label;
  final int ticks;
}
