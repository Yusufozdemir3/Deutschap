enum Motivation {
  moving('Almanya, Avusturya veya İsviçre\'ye taşınıyorum'),
  work('İş için'),
  study('Okul / üniversite için'),
  exam('Sınava hazırlanıyorum'),
  travel('Seyahat için'),
  culture('Kitap, dizi, kültür'),
  curiosity('Merak ediyorum');

  const Motivation(this.labelTr);
  final String labelTr;
}

const interestTopics = <String, String>{
  'alltag': 'Gündelik hayat',
  'essen': 'Yemek & kafe',
  'stadt': 'Şehir hayatı',
  'arbeit': 'İş hayatı',
  'reisen': 'Seyahat',
  'kultur': 'Kültür',
  'geheimnis': 'Gizem & hikâye',
  'buerokratie': 'Resmî işler',
};

/// Optional notification preferences. Stored only: v0.1 has no
/// notification delivery (see docs/KNOWN_LIMITATIONS.md).
class NotificationPrefs {
  const NotificationPrefs({
    this.studyReminder = false,
    this.reviewDue = false,
    this.newEpisodes = false,
    this.weeklySummary = false,
    this.reminderHour = 19,
    this.quietFrom = 22,
    this.quietTo = 8,
  });

  final bool studyReminder;
  final bool reviewDue;
  final bool newEpisodes;
  final bool weeklySummary;
  final int reminderHour;
  final int quietFrom;
  final int quietTo;

  bool get anyEnabled => studyReminder || reviewDue || newEpisodes || weeklySummary;

  NotificationPrefs copyWith({
    bool? studyReminder,
    bool? reviewDue,
    bool? newEpisodes,
    bool? weeklySummary,
    int? reminderHour,
    int? quietFrom,
    int? quietTo,
  }) =>
      NotificationPrefs(
        studyReminder: studyReminder ?? this.studyReminder,
        reviewDue: reviewDue ?? this.reviewDue,
        newEpisodes: newEpisodes ?? this.newEpisodes,
        weeklySummary: weeklySummary ?? this.weeklySummary,
        reminderHour: reminderHour ?? this.reminderHour,
        quietFrom: quietFrom ?? this.quietFrom,
        quietTo: quietTo ?? this.quietTo,
      );

  Map<String, Object?> toJson() => {
        'studyReminder': studyReminder,
        'reviewDue': reviewDue,
        'newEpisodes': newEpisodes,
        'weeklySummary': weeklySummary,
        'reminderHour': reminderHour,
        'quietFrom': quietFrom,
        'quietTo': quietTo,
      };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        studyReminder: j['studyReminder'] as bool? ?? false,
        reviewDue: j['reviewDue'] as bool? ?? false,
        newEpisodes: j['newEpisodes'] as bool? ?? false,
        weeklySummary: j['weeklySummary'] as bool? ?? false,
        reminderHour: j['reminderHour'] as int? ?? 19,
        quietFrom: j['quietFrom'] as int? ?? 22,
        quietTo: j['quietTo'] as int? ?? 8,
      );
}

/// Separate, approximate estimates per skill. A placement test gives a
/// starting point only; it is not a measurement of proficiency.
class SkillEstimates {
  const SkillEstimates({this.vocabulary, this.grammar, this.reading, this.listening});
  final String? vocabulary;
  final String? grammar;
  final String? reading;
  final String? listening;

  bool get isEmpty => vocabulary == null && grammar == null && reading == null && listening == null;

  Map<String, Object?> toJson() => {
        'vocabulary': vocabulary,
        'grammar': grammar,
        'reading': reading,
        'listening': listening,
      };

  factory SkillEstimates.fromJson(Map<String, dynamic> j) => SkillEstimates(
        vocabulary: j['vocabulary'] as String?,
        grammar: j['grammar'] as String?,
        reading: j['reading'] as String?,
        listening: j['listening'] as String?,
      );
}

class LearnerProfile {
  const LearnerProfile({
    this.onboarded = false,
    this.name,
    this.motivation,
    this.interests = const {},
    this.dailyMinutes = 10,
    this.level = 'A1',
    this.startedFromZero = true,
    this.skills = const SkillEstimates(),
    this.weeklyGoalDays = 3,
    this.showEnglish = false,
    this.detailedFeedback = false,
    this.keepTranscripts = false,
    this.speechRate = 0.45,
    this.notifications = const NotificationPrefs(),
    this.hiddenTopics = const {},
    this.voiceName,
    this.themeMode = 'system',
    this.textScale = 1.0,
    this.readableFont = false,
  });

  final bool onboarded;
  final String? name;
  final Motivation? motivation;
  final Set<String> interests;
  final int dailyMinutes;

  /// Content level used to pick story variants and texts.
  final String level;
  final bool startedFromZero;
  final SkillEstimates skills;

  /// Flexible weekly target: days with any learning activity.
  final int weeklyGoalDays;
  final bool showEnglish;
  final bool detailedFeedback;

  /// Whether full conversation transcripts are kept after a scenario ends.
  final bool keepTranscripts;
  final double speechRate;
  final NotificationPrefs notifications;

  /// Discover topics the learner asked not to see.
  final Set<String> hiddenTopics;

  /// Text-to-speech voice chosen in settings; null = pick the best one.
  final String? voiceName;

  /// 'system', 'light' or 'dark'.
  final String themeMode;

  /// Extra text scale on top of the system setting.
  final double textScale;

  /// Atkinson Hyperlegible instead of Manrope/Literata.
  final bool readableFont;

  LearnerProfile copyWith({
    bool? onboarded,
    String? name,
    Motivation? motivation,
    Set<String>? interests,
    int? dailyMinutes,
    String? level,
    bool? startedFromZero,
    SkillEstimates? skills,
    int? weeklyGoalDays,
    bool? showEnglish,
    bool? detailedFeedback,
    bool? keepTranscripts,
    double? speechRate,
    NotificationPrefs? notifications,
    Set<String>? hiddenTopics,
    String? Function()? voiceName,
    String? themeMode,
    double? textScale,
    bool? readableFont,
  }) =>
      LearnerProfile(
        onboarded: onboarded ?? this.onboarded,
        name: name ?? this.name,
        motivation: motivation ?? this.motivation,
        interests: interests ?? this.interests,
        dailyMinutes: dailyMinutes ?? this.dailyMinutes,
        level: level ?? this.level,
        startedFromZero: startedFromZero ?? this.startedFromZero,
        skills: skills ?? this.skills,
        weeklyGoalDays: weeklyGoalDays ?? this.weeklyGoalDays,
        showEnglish: showEnglish ?? this.showEnglish,
        detailedFeedback: detailedFeedback ?? this.detailedFeedback,
        keepTranscripts: keepTranscripts ?? this.keepTranscripts,
        speechRate: speechRate ?? this.speechRate,
        notifications: notifications ?? this.notifications,
        hiddenTopics: hiddenTopics ?? this.hiddenTopics,
        voiceName: voiceName == null ? this.voiceName : voiceName(),
        themeMode: themeMode ?? this.themeMode,
        textScale: textScale ?? this.textScale,
        readableFont: readableFont ?? this.readableFont,
      );

  Map<String, Object?> toJson() => {
        'onboarded': onboarded,
        'name': name,
        'motivation': motivation?.name,
        'interests': interests.toList(),
        'dailyMinutes': dailyMinutes,
        'level': level,
        'startedFromZero': startedFromZero,
        'skills': skills.toJson(),
        'weeklyGoalDays': weeklyGoalDays,
        'showEnglish': showEnglish,
        'detailedFeedback': detailedFeedback,
        'keepTranscripts': keepTranscripts,
        'speechRate': speechRate,
        'notifications': notifications.toJson(),
        'hiddenTopics': hiddenTopics.toList(),
        'voiceName': voiceName,
        'themeMode': themeMode,
        'textScale': textScale,
        'readableFont': readableFont,
      };

  factory LearnerProfile.fromJson(Map<String, dynamic> j) => LearnerProfile(
        onboarded: j['onboarded'] as bool? ?? false,
        name: j['name'] as String?,
        motivation: switch (j['motivation']) {
          final String m => Motivation.values.where((v) => v.name == m).firstOrNull,
          _ => null,
        },
        interests: {...((j['interests'] as List?) ?? const []).cast<String>()},
        dailyMinutes: j['dailyMinutes'] as int? ?? 10,
        level: j['level'] as String? ?? 'A1',
        startedFromZero: j['startedFromZero'] as bool? ?? true,
        skills: SkillEstimates.fromJson((j['skills'] as Map?)?.cast<String, dynamic>() ?? const {}),
        weeklyGoalDays: j['weeklyGoalDays'] as int? ?? 3,
        showEnglish: j['showEnglish'] as bool? ?? false,
        detailedFeedback: j['detailedFeedback'] as bool? ?? false,
        keepTranscripts: j['keepTranscripts'] as bool? ?? false,
        speechRate: (j['speechRate'] as num?)?.toDouble() ?? 0.45,
        notifications: NotificationPrefs.fromJson((j['notifications'] as Map?)?.cast<String, dynamic>() ?? const {}),
        hiddenTopics: {...((j['hiddenTopics'] as List?) ?? const []).cast<String>()},
        voiceName: j['voiceName'] as String?,
        themeMode: j['themeMode'] as String? ?? 'system',
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
        readableFont: j['readableFont'] as bool? ?? false,
      );
}
