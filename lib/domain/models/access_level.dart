/// Who may use a room or facility (`access_level` on both tables).
const kDefaultAccessLevel = 'public';
const kAccessLevels = ['public', 'students_and_faculty', 'staff_only'];

const _labels = {
  'public': 'Public',
  'students_and_faculty': 'Students & Faculty',
  'staff_only': 'Staff Only',
};

/// The name shown for [level]. Empty means the default, and older free-text
/// values (rooms had a text field) are shown as they were typed.
String accessLevelLabel(String? level) {
  final value = selectedAccessLevel(level);
  return _labels[value] ?? value;
}

/// The value a form starts on: [stored], or the default when it is empty.
String selectedAccessLevel(String? stored) =>
    (stored ?? '').trim().isEmpty ? kDefaultAccessLevel : stored!;

/// The choices for a row holding [stored]: the three levels, plus an older
/// free-text value so that opening the form can't silently replace it.
List<String> accessLevelOptions(String? stored) {
  final current = selectedAccessLevel(stored);
  return kAccessLevels.contains(current)
      ? kAccessLevels
      : [...kAccessLevels, current];
}

/// What to write for [selected]. Null (leave the column out) when a row with
/// no stored value stays on the default: the database default covers it, and
/// saving keeps working before db/access_level.sql has been run.
String? accessLevelToSave(String selected, String? stored) =>
    selected == kDefaultAccessLevel && (stored ?? '').trim().isEmpty
        ? null
        : selected;
