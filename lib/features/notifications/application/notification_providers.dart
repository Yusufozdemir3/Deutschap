import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/clock.dart';
import '../domain/notification_planner.dart';
import 'notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  if (!LocalNotificationService.platformSupported) return const NoNotifications();
  return LocalNotificationService(onTap: (route) => ref.read(routerProvider).push(route));
});

final notificationFactsProvider = FutureProvider<NotificationFacts>((ref) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final progress = ref.watch(progressRepositoryProvider);
  final today = DateTime(now.year, now.month, now.day);
  final week = await progress.activeDays(startOfWeek(now));
  return NotificationFacts(
    now: now,
    studiedToday: week.contains(today),
    nextReviewDue: await ref.watch(vocabRepositoryProvider).nextDueAt(),
    activeDaysThisWeek: week.length,
    weeklyGoalDays: ref.watch(profileProvider.select((p) => p.valueOrNull?.weeklyGoalDays ?? 3)),
  );
});

/// The current plan. Watching it keeps the scheduled notifications in
/// step with the learner's data and choices; an unchanged plan is not
/// rescheduled.
final notificationSyncProvider = FutureProvider<List<PlannedNotification>>((ref) async {
  final prefs = ref.watch(profileProvider.select((p) => p.valueOrNull?.notifications));
  final service = ref.watch(notificationServiceProvider);
  if (prefs == null || !service.supported) return const [];
  final facts = await ref.watch(notificationFactsProvider.future);
  final plan = const NotificationPlanner().plan(prefs, facts);
  final signature = plan.map((n) => '${n.id}|${n.at.millisecondsSinceEpoch}|${n.body}').join(';');
  if (signature != _lastSignature) {
    _lastSignature = signature;
    await service.replaceAll(plan);
  }
  return plan;
});

String? _lastSignature;
