import '../../core/utils/parse_utils.dart';

/// Columns of `feedback_comments`, see db/feedback_comments.sql. The user app
/// writes the table, but that SQL may not have been run on a given database,
/// so none of this assumes it exists.
const kFeedbackColumns = [
  'id',
  'comment',
  'rating_context',
  'role',
  'device_code',
  'user_id',
  'created_at',
];

/// Without these, rows can't be shown or ordered.
const kFeedbackRequiredColumns = ['id', 'comment', 'created_at'];

final _email = RegExp(r'[^\s@<>(),;:]+@[^\s@<>(),;:]+\.[^\s@<>(),;:]+');

/// [text] with email addresses removed. A comment can contain one even
/// though the table has no email column.
String removeEmails(String text) => text.replaceAll(_email, '[email removed]');

/// A short id that stays the same for one person but doesn't reveal their
/// user id or device code: an 8-digit FNV-1a hash. The shifts keep the result
/// the same on web and Windows, where large integers behave differently.
String anonymousId(String reference) {
  var hash = 0x811c9dc5;
  for (final unit in reference.codeUnits) {
    hash ^= unit;
    hash = (hash + (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) +
            (hash << 24)) &
        0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0').toUpperCase();
}

/// One comment, holding only what the screen may show: there are no name or
/// email fields, and the person is reduced to [anonymousRef] here.
class FeedbackCommentModel {
  final String id;
  final String comment;
  final String? ratingContext;
  final String? role;

  /// From `user_id`, else `device_code`; null when the row has neither.
  final String? anonymousRef;
  final DateTime? createdAt;

  const FeedbackCommentModel({
    required this.id,
    required this.comment,
    this.ratingContext,
    this.role,
    this.anonymousRef,
    this.createdAt,
  });

  factory FeedbackCommentModel.fromJson(Map<String, dynamic> json) {
    String? text(String column) {
      final value = json[column]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    final person = text('user_id') ?? text('device_code');
    final context = text('rating_context');
    return FeedbackCommentModel(
      id: json['id']?.toString() ?? '',
      comment: removeEmails(text('comment') ?? ''),
      ratingContext: context == null ? null : removeEmails(context),
      role: text('role')?.toLowerCase(),
      anonymousRef: person == null ? null : anonymousId(person),
      createdAt: parseDate(json['created_at']),
    );
  }
}

/// The role and search filters, applied in memory to the loaded rows. An
/// empty [search] or null [role] doesn't narrow anything.
List<FeedbackCommentModel> filterFeedback(
  Iterable<FeedbackCommentModel> rows, {
  String? role,
  String search = '',
}) {
  final needle = search.trim().toLowerCase();
  return [
    for (final r in rows)
      if ((role == null || r.role == role) &&
          (needle.isEmpty ||
              r.comment.toLowerCase().contains(needle) ||
              (r.ratingContext ?? '').toLowerCase().contains(needle)))
        r,
  ];
}

/// Rows for the CSV export, first row = header. Holds only what the screen
/// shows, so no user id or device code can leak through it.
List<List<Object?>> feedbackExportRows(Iterable<FeedbackCommentModel> rows) => [
      ['created_at', 'role', 'anonymous_id', 'rating_context', 'comment'],
      for (final r in rows)
        [
          r.createdAt?.toIso8601String() ?? '',
          r.role ?? '',
          r.anonymousRef ?? '',
          r.ratingContext ?? '',
          r.comment,
        ],
    ];
