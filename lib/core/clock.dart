import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

typedef Clock = DateTime Function();

/// Overridden in tests to control time-dependent logic (reviews, goals).
final clockProvider = Provider<Clock>((ref) => DateTime.now);

typedef IdGenerator = String Function();

const _uuid = Uuid();
final idGeneratorProvider = Provider<IdGenerator>((ref) => () => _uuid.v4());

int toMillis(DateTime t) => t.millisecondsSinceEpoch;
DateTime fromMillis(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

DateTime startOfWeek(DateTime t) {
  final day = DateTime(t.year, t.month, t.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
