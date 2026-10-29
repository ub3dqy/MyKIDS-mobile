class CalendarHeightNeed {
  final int start, end;
  final double height;
  const CalendarHeightNeed(this.start, this.end, this.height);
}

/// A complete civil day. Extra space is added only inside occupied intervals.
/// Splitting at event boundaries prevents a short event from stretching a whole
/// hour, and gives every day in a weekly view the same time coordinates.
class CalendarTimeAxis {
  final List<int> _minutes;
  final List<double> _offsets;
  CalendarTimeAxis._(this._minutes, this._offsets);

  factory CalendarTimeAxis({
    double emptyHourHeight = 28,
    Iterable<CalendarHeightNeed> needs = const [],
  }) {
    final ordered = needs.toList()
      ..sort((a, b) => (a.end - a.start).compareTo(b.end - b.start));
    if (!emptyHourHeight.isFinite || emptyHourHeight <= 0) {
      throw ArgumentError.value(emptyHourHeight, 'emptyHourHeight');
    }
    final boundaries = {for (var hour = 0; hour <= 24; hour++) hour * 60};
    for (final need in ordered) {
      if (need.start < 0 ||
          need.end > 1440 ||
          need.start >= need.end ||
          !need.height.isFinite ||
          need.height < 0) {
        throw ArgumentError('Invalid calendar interval');
      }
      boundaries.addAll([need.start, need.end]);
    }
    final minutes = boundaries.toList()..sort();
    final heights = [
      for (var i = 0; i < minutes.length - 1; i++)
        (minutes[i + 1] - minutes[i]) * emptyHourHeight / 60,
    ];
    for (final need in ordered) {
      final first = minutes.indexOf(need.start);
      final last = minutes.indexOf(need.end);
      var available = 0.0;
      for (var i = first; i < last; i++) {
        available += heights[i];
      }
      final extra = need.height - available;
      if (extra <= 0) continue;
      for (var i = first; i < last; i++) {
        heights[i] +=
            extra * (minutes[i + 1] - minutes[i]) / (need.end - need.start);
      }
    }
    final offsets = <double>[0];
    for (final height in heights) {
      offsets.add(offsets.last + height);
    }
    return CalendarTimeAxis._(minutes, offsets);
  }

  double get height => _offsets.last;

  double offsetAt(num minute) {
    final clamped = minute.clamp(0, 1440).toDouble();
    if (clamped == 1440) return height;
    final index = _minutes.indexWhere((value) => value > clamped) - 1;
    final fraction =
        (clamped - _minutes[index]) / (_minutes[index + 1] - _minutes[index]);
    return _offsets[index] + fraction * (_offsets[index + 1] - _offsets[index]);
  }

  double heightBetween(num start, num end) => offsetAt(end) - offsetAt(start);
}
