import '../../core/utils/parse_utils.dart';

/// Roles an admin can assign on the Users screen. `employee` is what the
/// mobile app's role picker writes, so it stays alongside the others.
const kUserRoles = ['student', 'employee', 'faculty', 'admin', 'visitor'];

/// Email domain of University of Mindanao accounts.
const kSchoolEmailDomain = '@umindanao.edu.ph';

/// first initial.lastname.idnumber@umindanao.edu.ph, as in
/// is_student_email() (db/user_roles.sql) and the mobile app's
/// EmailRoleConfig.
final kStudentEmail =
    RegExp(r'^[a-z]\.[a-z]+(-[a-z]+)*\.[0-9]+@umindanao\.edu\.ph$');

/// Why [target] may not be given [newRole] by the signed-in admin, or null
/// when the change is allowed. [allUsers] is every profile (for counting the
/// remaining admins); the signed-in account is matched by id, then by email,
/// because some profile rows are keyed on email rather than the auth uid.
String? roleChangeBlocker({
  required UserProfileModel target,
  required String newRole,
  required List<UserProfileModel> allUsers,
  String? currentUserId,
  String? currentUserEmail,
}) {
  if (!kUserRoles.contains(newRole)) return 'Unknown role "$newRole".';
  final oldRole = (target.role ?? '').toLowerCase();
  if (oldRole == newRole) return 'This account already has that role.';
  if (oldRole != 'admin') return null; // promotions / non-admin changes

  if (_isSelf(target, currentUserId, currentUserEmail)) {
    return 'You can\'t remove your own admin role. Ask another admin to do it.';
  }
  if (!_hasOtherActiveAdmin(target, allUsers)) {
    return 'This is the last active admin — promote another account first.';
  }
  return null;
}

/// Why [target] may not be deactivated by the signed-in admin, or null when
/// it may. Deactivating an admin locks them out just like demoting them.
String? deactivateBlocker({
  required UserProfileModel target,
  required List<UserProfileModel> allUsers,
  String? currentUserId,
  String? currentUserEmail,
}) {
  if (!target.isAdmin || !target.isActive) return null;
  if (_isSelf(target, currentUserId, currentUserEmail)) {
    return 'You can\'t deactivate your own account. Ask another admin to do '
        'it.';
  }
  if (!_hasOtherActiveAdmin(target, allUsers)) {
    return 'This is the last active admin — promote another account first.';
  }
  return null;
}

bool _isSelf(UserProfileModel target, String? id, String? email) {
  final lower = email?.toLowerCase();
  return (id != null && target.id == id) ||
      (lower != null &&
          lower.isNotEmpty &&
          target.email?.toLowerCase() == lower);
}

bool _hasOtherActiveAdmin(
        UserProfileModel target, List<UserProfileModel> allUsers) =>
    allUsers.any((u) => u.id != target.id && u.isAdmin && u.isActive);

class UserProfileModel {
  final String id;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isVerified;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  bool get isAdmin => (role ?? '').toLowerCase() == 'admin';

  /// A UM account waiting for an admin to approve or reject it. Only an email
  /// in the student format is verified automatically, so a student with any
  /// other email waits here too. Rejected accounts are inactive, so they
  /// leave this list.
  bool get isPendingApproval {
    final r = (role ?? '').toLowerCase();
    final address = (email ?? '').trim().toLowerCase();
    return isActive &&
        !isVerified &&
        r != 'admin' &&
        address.endsWith(kSchoolEmailDomain) &&
        !(r == 'student' && kStudentEmail.hasMatch(address));
  }

  const UserProfileModel({
    required this.id,
    this.email,
    this.fullName,
    this.role,
    this.isVerified = false,
    this.isActive = true,
    this.createdAt,
    this.lastSeen,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
      isVerified: parseBool(json['is_verified']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      lastSeen: parseDate(json['last_seen']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role,
      'is_verified': isVerified,
      'is_active': isActive,
    };
  }
}
