import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/excel_export.dart';
import '../../../core/utils/short_code.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/kiosk_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/visitor_session_repository.dart';
import '../../../domain/models/kiosk_session_model.dart';
import '../../../domain/models/user_profile_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/status_badge.dart';

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('MMM d, y').format(d);

String _fmtDateTime(DateTime? d) =>
    d == null ? '—' : DateFormat('MMM d, h:mm a').format(d);

String _fmtDuration(Duration? d) {
  if (d == null || d.isNegative) return '—';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _userRepo = UserRepository();
  final _visitorRepo = VisitorSessionRepository();
  final _kioskRepo = KioskRepository();

  List<UserProfileModel> _users = [];
  List<VisitorEntry> _visitors = [];
  List<KioskSessionModel> _kiosk = [];

  bool _loading = true;
  Object? _error;

  String _userStatus = 'all'; // all | active | inactive
  String _userRole = 'all'; // all | one of kUserRoles
  String _visitorStatus = 'all'; // all | active | expired | offline
  String _kioskStatus = 'all'; // all | active | ended
  bool _exportingUsers = false;
  bool _recheckingAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _userRepo.getAll(),
        _visitorRepo.getEntries(),
        _kioskRepo.getSessions(),
      ]);
      setState(() {
        _users = results[0] as List<UserProfileModel>;
        _visitors = results[1] as List<VisitorEntry>;
        _kiosk = results[2] as List<KioskSessionModel>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Checks the signed-in admin now instead of at the next 10-minute check.
  /// If access is gone the sign-out moves to the login screen, which says why.
  Future<void> _recheckAdmin() async {
    setState(() => _recheckingAdmin = true);
    final access = await AuthRepository.instance.recheckAdmin();
    if (!mounted) return;
    setState(() => _recheckingAdmin = false);
    if (access == AdminAccess.valid) {
      context.showSuccess('You are still an active admin');
    } else if (access == AdminAccess.unknown) {
      context.showError('Could not check your admin status. Nothing changed.',
          onRetry: _recheckAdmin);
    }
  }

  // --- box 1: registered accounts --------------------------------------

  /// Every account (all roles, so admins can be managed too), filtered by
  /// the Role and Status dropdowns.
  List<UserProfileModel> get _registered {
    return _users.where((u) {
      final role = (u.role ?? '').toLowerCase();
      if (_userRole != 'all' && role != _userRole) return false;
      switch (_userStatus) {
        case 'active':
          return u.isActive;
        case 'inactive':
          return !u.isActive;
      }
      return true;
    }).toList();
  }

  Future<void> _verify(UserProfileModel u) async {
    try {
      await _userRepo.verifyUser(u.id, verified: !u.isVerified);
      if (mounted) context.showSuccess('Verification updated');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _verify(u));
    }
  }

  // --- pending approvals ------------------------------------------------

  List<UserProfileModel> get _pending =>
      _users.where((u) => u.isPendingApproval).toList();

  Future<void> _approve(UserProfileModel u) async {
    try {
      await _userRepo.approveUser(u.id);
      if (mounted) context.showSuccess('Account approved');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _approve(u));
    }
  }

  Future<void> _reject(UserProfileModel u) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Reject account',
      verb: 'reject',
      itemName: u.fullName ?? u.email ?? u.id,
      message: 'The account will be marked unverified and inactive. You can '
          'reactivate it later, which returns it to this list.',
      confirmLabel: 'Reject',
    );
    if (!ok) return;
    try {
      await _userRepo.rejectUser(u.id);
      if (mounted) context.showSuccess('Account rejected');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _reject(u));
    }
  }

  /// Deactivates (is_active = false) or reactivates an account. There is no
  /// real delete: removing the Supabase Auth account needs a server-side
  /// function with the service role key, which this app must not hold.
  Future<void> _toggleActive(UserProfileModel u) async {
    if (u.isActive) {
      final me = AuthRepository.instance.user;
      final blocked = deactivateBlocker(
        target: u,
        allUsers: _users,
        currentUserId: me?.id,
        currentUserEmail: me?.email,
      );
      if (blocked != null) {
        context.showError(blocked);
        return;
      }
      final ok = await ConfirmDialog.show(
        context,
        title: 'Deactivate account',
        verb: 'deactivate',
        itemName: u.fullName ?? u.email ?? u.id,
        message: 'They will be marked inactive and treated as suspended. '
            'Their sign-in account and history are kept, and you can '
            'reactivate them at any time.',
        confirmLabel: 'Deactivate',
      );
      if (!ok) return;
    }
    try {
      await _userRepo.suspendUser(u.id, suspended: u.isActive);
      if (mounted) {
        context.showSuccess(
            u.isActive ? 'User deactivated' : 'User reactivated');
      }
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _toggleActive(u));
    }
  }

  /// Changes [u]'s role after the self / last-admin guard and a confirmation.
  Future<void> _changeRole(UserProfileModel u, String newRole) async {
    final me = AuthRepository.instance.user;
    final blocked = roleChangeBlocker(
      target: u,
      newRole: newRole,
      allUsers: _users,
      currentUserId: me?.id,
      currentUserEmail: me?.email,
    );
    if (blocked != null) {
      context.showError(blocked);
      return;
    }
    final oldRole = u.role ?? '(none)';
    final ok = await ConfirmDialog.show(
      context,
      title: 'Change role',
      verb: 'change the role of',
      itemName: u.fullName ?? u.email ?? u.id,
      message: switch (newRole) {
        'admin' => 'From $oldRole to admin. They will get full access to this '
            'admin panel.',
        'visitor' => 'From $oldRole to visitor. The mobile app only signs in '
            'student, faculty and employee accounts, so they will be signed '
            'out of it.',
        _ => 'From $oldRole to $newRole.',
      },
      confirmLabel: 'Change role',
    );
    if (!ok) return;
    try {
      await _userRepo.setRole(u.id, newRole);
      if (mounted) context.showSuccess('Role changed to $newRole');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _changeRole(u, newRole));
    }
  }

  Widget _roleCell(UserProfileModel u) {
    final current = (u.role ?? '').toLowerCase();
    return PopupMenuButton<String>(
      tooltip: 'Change role',
      onSelected: (r) => _changeRole(u, r),
      itemBuilder: (_) => [
        for (final r in kUserRoles)
          CheckedPopupMenuItem(
            value: r,
            checked: r == current,
            enabled: r != current,
            child: Text(r),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(u.role ?? '—', overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.arrow_drop_down,
              size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Future<void> _exportRegistered() async {
    setState(() => _exportingUsers = true);
    try {
      final rows = <List<Object?>>[
        ['name', 'email', 'role', 'is_verified', 'is_active', 'registered',
          'last_active'],
        for (final u in _registered)
          [
            u.fullName ?? '',
            u.email ?? '',
            u.role ?? '',
            u.isVerified,
            u.isActive,
            u.createdAt?.toIso8601String() ?? '',
            u.lastSeen?.toIso8601String() ?? '',
          ],
      ];
      final path =
          await saveExcelFile('registered_accounts', 'Users', rows);
      if (mounted) {
        context.showSuccess(
            path == null ? 'Export cancelled' : 'Saved to $path');
      }
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _exportRegistered);
    } finally {
      if (mounted) setState(() => _exportingUsers = false);
    }
  }

  // --- box 2: visitor sessions ---------------------------------------

  List<VisitorEntry> get _filteredVisitors {
    return _visitors.where((v) {
      switch (_visitorStatus) {
        case 'active':
          return v.isActive;
        case 'expired':
          return !v.isActive && !v.isOffline;
        case 'offline':
          return v.isOffline;
      }
      return true;
    }).toList();
  }

  /// Null for an offline visitor: with no session row, nothing says how long
  /// it ran.
  Duration? _visitorDuration(VisitorEntry v) {
    final session = v.session;
    if (session == null || session.startedAt == null) return null;
    final end = session.isActive
        ? DateTime.now()
        : (session.expiresAt ?? DateTime.now());
    return end.difference(session.startedAt!);
  }

  // --- box 3: kiosk sessions ---------------------------------------

  List<KioskSessionModel> get _filteredKiosk {
    return _kiosk.where((k) {
      switch (_kioskStatus) {
        case 'active':
          return k.isActive;
        case 'ended':
          return !k.isActive;
      }
      return true;
    }).toList();
  }

  // --- build -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final pending = _pending;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.isNotEmpty) ...[
            SizedBox(height: 260, child: _pendingBox(pending)),
            const SizedBox(height: 16),
          ],
          SizedBox(height: 420, child: _registeredBox()),
          const SizedBox(height: 16),
          SizedBox(height: 360, child: _visitorBox()),
          const SizedBox(height: 16),
          SizedBox(height: 360, child: _kioskBox()),
        ],
      ),
    );
  }

  Widget _statusDropdown(
    String value,
    List<(String, String)> options,
    ValueChanged<String> onChanged, {
    String label = 'Status',
  }) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(isDense: true, labelText: label),
        items: [
          for (final (v, label) in options)
            DropdownMenuItem(value: v, child: Text(label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _pendingBox(List<UserProfileModel> rows) {
    return DataTableCard(
      title: 'Pending Approval (${rows.length})',
      isLoading: _loading,
      minWidth: 820,
      columns: const [
        DataColumn2(label: Text('Name'), size: ColumnSize.L),
        DataColumn2(label: Text('Email'), size: ColumnSize.L),
        DataColumn2(label: Text('Requested Role'), size: ColumnSize.S),
        DataColumn2(label: Text('Registered'), size: ColumnSize.M),
        DataColumn2(label: Text('Decision'), size: ColumnSize.M),
      ],
      rows: [
        for (final u in rows)
          DataRow2(
            cells: [
              DataCell(Text(u.fullName ?? '(no name)',
                  overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.email ?? '—', overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.role ?? '(none)')),
              DataCell(Text(_fmtDate(u.createdAt))),
              DataCell(Row(
                children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.successGreen),
                    onPressed: () => _approve(u),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.cancel_outlined,
                        size: 18, color: AppColors.errorRed),
                    onPressed: () => _reject(u),
                  ),
                ],
              )),
            ],
          ),
      ],
    );
  }

  Widget _verifiedBadge(UserProfileModel u) {
    if (u.isVerified) return const StatusBadge(status: BadgeStatus.verified);
    return u.isPendingApproval
        ? const StatusBadge(status: BadgeStatus.pending)
        : const StatusBadge(
            status: BadgeStatus.inactive, label: 'Unverified');
  }

  Widget _registeredBox() {
    final rows = _registered;
    return DataTableCard(
      title: 'Registered Accounts (${rows.length})',
      isLoading: _loading,
      minWidth: 1100,
      actions: [
        OutlinedButton.icon(
          onPressed: _recheckingAdmin ? null : _recheckAdmin,
          icon: const Icon(Icons.verified_user_outlined, size: 15),
          label: const Text('Re-check admin status'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _exportingUsers ? null : _exportRegistered,
          icon: const Icon(Icons.download, size: 15),
          label: Text(_exportingUsers ? 'Exporting…' : 'Export Excel'),
        ),
        const SizedBox(width: 8),
        _statusDropdown(
          _userRole,
          [('all', 'All'), for (final r in kUserRoles) (r, r)],
          (v) => setState(() => _userRole = v),
          label: 'Role',
        ),
        const SizedBox(width: 8),
        _statusDropdown(_userStatus, const [
          ('all', 'All'),
          ('active', 'Active'),
          ('inactive', 'Inactive'),
        ], (v) => setState(() => _userStatus = v)),
      ],
      columns: const [
        DataColumn2(label: Text('Name'), size: ColumnSize.L),
        DataColumn2(label: Text('Email'), size: ColumnSize.L),
        DataColumn2(label: Text('Role'), size: ColumnSize.S),
        DataColumn2(label: Text('Verified'), size: ColumnSize.S),
        DataColumn2(label: Text('Registered'), size: ColumnSize.M),
        DataColumn2(label: Text('Last Active'), size: ColumnSize.M),
        DataColumn2(label: Text('Actions'), size: ColumnSize.M),
      ],
      rows: [
        for (final u in rows)
          DataRow2(
            cells: [
              DataCell(Text(u.fullName ?? '(no name)',
                  overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.email ?? '—', overflow: TextOverflow.ellipsis)),
              DataCell(_roleCell(u)),
              DataCell(_verifiedBadge(u)),
              DataCell(Text(_fmtDate(u.createdAt))),
              DataCell(Text(_fmtDateTime(u.lastSeen))),
              DataCell(Row(
                children: [
                  IconButton(
                    tooltip: u.isVerified ? 'Un-verify' : 'Verify',
                    icon: Icon(
                      u.isVerified
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      size: 18,
                      color: u.isVerified
                          ? AppColors.successGreen
                          : AppColors.textSecondary,
                    ),
                    onPressed: () => _verify(u),
                  ),
                  IconButton(
                    tooltip: u.isActive ? 'Deactivate' : 'Reactivate',
                    icon: Icon(u.isActive ? Icons.block : Icons.lock_open,
                        size: 18,
                        color: u.isActive
                            ? AppColors.errorRed
                            : AppColors.successGreen),
                    onPressed: () => _toggleActive(u),
                  ),
                ],
              )),
            ],
          ),
      ],
    );
  }

  Widget _visitorBox() {
    final rows = _filteredVisitors;
    return DataTableCard(
      title: 'Visitor Sessions (${rows.length})',
      isLoading: _loading,
      minWidth: 900,
      actions: [
        _statusDropdown(_visitorStatus, const [
          ('all', 'All'),
          ('active', 'Active'),
          ('expired', 'Expired'),
          ('offline', 'Offline'),
        ], (v) => setState(() => _visitorStatus = v)),
      ],
      columns: const [
        DataColumn2(label: Text('Session ID'), size: ColumnSize.M),
        DataColumn2(label: Text('Device Code'), size: ColumnSize.L),
        DataColumn2(label: Text('Started At'), size: ColumnSize.M),
        DataColumn2(label: Text('Expires At'), size: ColumnSize.M),
        DataColumn2(label: Text('Duration'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
      ],
      rows: [
        for (final v in rows)
          DataRow2(
            cells: [
              DataCell(Text(v.isOffline ? '—' : shortId(v.session!.id))),
              DataCell(Text(shortDeviceCode(v.deviceCode),
                  overflow: TextOverflow.ellipsis)),
              DataCell(Text(_fmtDateTime(v.startedAt))),
              DataCell(Text(_fmtDateTime(v.session?.expiresAt))),
              DataCell(Text(_fmtDuration(_visitorDuration(v)))),
              DataCell(StatusBadge(
                status: v.isOffline
                    ? BadgeStatus.pending
                    : v.isActive
                        ? BadgeStatus.active
                        : BadgeStatus.inactive,
                label: v.statusLabel,
              )),
            ],
          ),
      ],
    );
  }

  Widget _kioskBox() {
    final rows = _filteredKiosk;
    return DataTableCard(
      title: 'Kiosk Sessions (${rows.length})',
      isLoading: _loading,
      minWidth: 820,
      emptyMessage: _kiosk.isEmpty
          ? 'No kiosk_sessions rows (create the table / add data)'
          : 'No records found',
      actions: [
        _statusDropdown(_kioskStatus, const [
          ('all', 'All'),
          ('active', 'Active'),
          ('ended', 'Ended'),
        ], (v) => setState(() => _kioskStatus = v)),
      ],
      columns: const [
        DataColumn2(label: Text('Session ID'), size: ColumnSize.M),
        DataColumn2(label: Text('Started At'), size: ColumnSize.M),
        DataColumn2(label: Text('Ended At'), size: ColumnSize.M),
        DataColumn2(label: Text('Duration'), size: ColumnSize.S),
        DataColumn2(label: Text('Routes'), size: ColumnSize.S),
      ],
      rows: [
        for (final k in rows)
          DataRow2(
            cells: [
              DataCell(Text(shortId(k.id))),
              DataCell(Text(_fmtDateTime(k.startedAt))),
              DataCell(Text(k.isActive ? '— (active)' : _fmtDateTime(k.endedAt))),
              DataCell(Text(_fmtDuration(k.duration))),
              DataCell(Text('${k.routesCalculated}')),
            ],
          ),
      ],
    );
  }
}
