/// One daily mood/wellbeing check-in. [score] is 1 (very low) to 5 (very
/// good) -- deliberately a small fixed scale, not a slider, so entries stay
/// quick enough that a patient actually fills them in every day; a daily
/// habit is what makes [MoodGaitCorrelation] eventually have enough paired
/// days to say anything.
class MoodEntry {
  final String id;
  final DateTime date;
  final int score;
  final String? note;

  const MoodEntry({
    required this.id,
    required this.date,
    required this.score,
    this.note,
  });

  /// "YYYY-MM-DD" -- used both as the Firestore doc id (one entry per day,
  /// a second check-in the same day overwrites rather than duplicates) and
  /// as the join key against [InsoleRecord.date] in [MoodGaitCorrelation].
  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'date': dateKey(date),
        'score': score,
        'note': note,
      };

  factory MoodEntry.fromJson(String id, Map<String, dynamic> json) => MoodEntry(
        id: id,
        date: DateTime.parse(json['date'] as String),
        score: (json['score'] as num).toInt(),
        note: json['note'] as String?,
      );
}
