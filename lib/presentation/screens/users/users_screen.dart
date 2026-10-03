import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/excel_export.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/kiosk_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/visitor_session_repository.dart';
import '../../../domain/models/kiosk_session_model.dart';
import '../../../domain/models/user_profile_model.dart';
import '../../../domain/models/visitor_session_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/status_badge.dart';

const _registeredRoles = {'student', 'faculty'};

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

String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

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
  List<VisitorSessionModel> _visitors = [];
  List<KioskSessionModel> _kiosk = [];

  bool _loading = true;
  Object? _error;

  String _userStatus = 'all'; // all | active | inactive
  String _visitorStatus = 'all'; // all | active | expired
  String _kioskStatus = 'all'; // all | active | ended
  bool _exportingUsers = false;

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
        _visitorRepo.getAll(),
        _kioskRepo.getSessions(),
      ]);
      setState(() {
        _users = results[0] as List<UserProfileModel>;
        _visitors = results[1] as List<VisitorSessionModel>;
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

  // --- box 1: registered accounts --------------------------------------

  List<UserProfileModel> get _registered {
    return _users.where((u) {
      final role = (u.role ?? '').toLowerCase();
      if (!_registeredRoles.contains(role)) return false;
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
      if (mounted) context.showError(e);
    }
  }

  Future<void> _suspend(UserProfileModel u) async {
    try {
      await _userRepo.suspendUser(u.id, suspended: u.isActive);
      if (mounted) {
        context.showSuccess(u.isActive ? 'User suspended' : 'User reinstated');
      }
      _load();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _delete(UserProfileModel u) async {
    final ok = await ConfirmDialog.show(context,
        itemName: u.fullName ?? u.email ?? u.id);
    if (!ok) return;
    try {
      await _userRepo.deleteUser(u.id);
      if (mounted) context.showSuccess('User deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e);
    }
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
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _exportingUsers = false);
    }
  }

  // --- box 2: visitor sessions ---------------------------------------

  List<VisitorSessionModel> get _filteredVisitors {
    return _visitors.where((v) {
      switch (_visitorStatus) {
        case 'active':
          return v.isActive;
        case 'expired':
          return !v.isActive;
      }
      return true;
    }).toList();
  }

  Duration? _visitorDuration(VisitorSessionModel v) {
    if (v.startedAt == null) return null;
    final end = v.isActive ? DateTime.now() : (v.expiresAt ?? DateTime.now());
    return end.difference(v.startedAt!);
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
    ValueChanged<String> onChanged,
  ) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: const InputDecoration(isDense: true, labelText: 'Status'),
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

  Widget _registeredBox() {
    final rows = _registered;
    return DataTableCard(
      title: 'Registered Accounts (${rows.length})',
      isLoading: _loading,
      minWidth: 980,
      actions: [
        OutlinedButton.icon(
          onPressed: _exportingUsers ? null : _exportRegistered,
          icon: const Icon(Icons.download, size: 15),
          label: Text(_exportingUsers ? 'Exporting…' : 'Export Excel'),
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
        DataColumn2(label: Text('Registered'), size: ColumnSize.M),
        DataColumn2(label: Text('Last Active'), size: ColumnSize.M),
        DataColumn2(label: Text('Actions'), size: ColumnSize.M),
      ],
      rows: [
        for (final u in rows)
          DataRow2(
            cells: [
              DataCell(Row(
                children: [
                  Expanded(
                    child: Text(u.fullName ?? '(no name)',
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (u.isVerified)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.verified,
                          size: 14, color: AppColors.infoBlue),
                    ),
                ],
              )),
              DataCell(Text(u.email ?? '—', overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.role ?? '—')),
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
                    tooltip: u.isActive ? 'Suspend' : 'Reinstate',
                    icon: Icon(u.isActive ? Icons.block : Icons.lock_open,
                        size: 18,
                        color: u.isActive
                            ? AppColors.warningAmber
                            : AppColors.successGreen),
                    onPressed: () => _suspend(u),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.errorRed),
                    onPressed: () => _delete(u),
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
        ], (v) => setState(() => _visitorStatus = v)),
      ],
      columns: const [
        DataColumn2(label: Text('Session ID'), size: ColumnSize.M),
        DataColumn2(label: Text('Device ID'), size: ColumnSize.L),
        DataColumn2(label: Text('Started At'), size: ColumnSize.M),
        DataColumn2(label: Text('Expires At'), size: ColumnSize.M),
        DataColumn2(label: Text('Duration'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
      ],
      rows: [
        for (final v in rows)
          DataRow2(
            cells: [
              DataCell(Text(_shortId(v.id))),
              DataCell(Text(v.deviceId ?? '—', overflow: TextOverflow.ellipsis)),
              DataCell(Text(_fmtDateTime(v.startedAt))),
              DataCell(Text(_fmtDateTime(v.expiresAt))),
              DataCell(Text(_fmtDuration(_visitorDuration(v)))),
              DataCell(StatusBadge(
                status:
                    v.isActive ? BadgeStatus.active : BadgeStatus.inactive,
                label: v.isActive ? 'Active' : 'Expired',
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
        DataColumn2(label: Text('Navigations'), size: ColumnSize.S),
      ],
      rows: [
        for (final k in rows)
          DataRow2(
            cells: [
              DataCell(Text(_shortId(k.id))),
              DataCell(Text(_fmtDateTime(k.startedAt))),
              DataCell(Text(k.isActive ? '— (active)' : _fmtDateTime(k.endedAt))),
              DataCell(Text(_fmtDuration(k.duration))),
              DataCell(Text('${k.navigationCount}')),
            ],
          ),
      ],
    );
  }
}
