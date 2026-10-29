import 'dart:convert';

/// A family calendar choice is a civil date, independent of the device zone.
class CalendarPosition {
  static const storageKey = 'calendar_position';
  static const modes = {'День', 'Неделя', 'Месяц'};
  final DateTime day;
  final String mode;

  CalendarPosition(DateTime day, this.mode)
    : day = DateTime.utc(day.year, day.month, day.day) {
    if (!modes.contains(mode)) throw ArgumentError.value(mode, 'mode');
  }

  String encode(String endpoint, String sessionTag) => jsonEncode({
    'version': 1,
    'endpoint': endpoint,
    'session_tag': sessionTag,
    'date':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'mode': mode,
  });

  static CalendarPosition? decode(
    String? saved,
    String endpoint,
    String sessionTag,
  ) {
    if (saved == null || sessionTag.isEmpty) return null;
    try {
      final value = jsonDecode(saved);
      if (value is! Map ||
          value['version'] != 1 ||
          value['endpoint'] != endpoint ||
          value['session_tag'] != sessionTag ||
          !modes.contains(value['mode'])) {
        return null;
      }
      final date = value['date'];
      if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
        return null;
      }
      final day = DateTime.tryParse(date);
      if (day == null ||
          day.year < 1 ||
          '${day.year.toString().padLeft(4, '0')}-'
                  '${day.month.toString().padLeft(2, '0')}-'
                  '${day.day.toString().padLeft(2, '0')}' !=
              date) {
        return null;
      }
      return CalendarPosition(day, value['mode'] as String);
    } on FormatException {
      return null;
    }
  }
}
