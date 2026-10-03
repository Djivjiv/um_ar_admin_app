import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/visitor_session_repository.dart';
import '../../../domain/models/navigation_session_model.dart';
import '../../../domain/models/visitor_session_model.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';

class VisitorSessionsScreen extends StatefulWidget {
  const VisitorSessionsScreen({super.key});

  @override
  State<VisitorSessionsScreen> createState() => _VisitorSessionsScreenState();
}

class _VisitorSessionsScreenState extends State<VisitorSessionsScreen> {
  final _repo = VisitorSessionRepository();
  late Future<List<VisitorSessionModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getAll();
  }

  void _reload() => setState(() => _future = _repo.getAll());

  void _openDetail(VisitorSessionModel session) {
    SlidePanel.show(
      context,
      title: 'Visitor Session',
      subtitle: session.deviceId,
      body: _SessionDetail(session: session, repo: _repo),
    );
  }

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, y h:mm a').format(d);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VisitorSessionModel>>(
      future: _future,
      builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting;
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(snapshot.error.toString()),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        final sessions = snapshot.data ?? [];
        return DataTableCard(
          title: '${sessions.length} Visitor Sessions',
          isLoading: loading,
          columns: const [
            DataColumn2(label: Text('Device'), size: ColumnSize.L),
            DataColumn2(label: Text('Started'), size: ColumnSize.L),
            DataColumn2(label: Text('Expires'), size: ColumnSize.L),
            DataColumn2(label: Text('Status'), size: ColumnSize.S),
          ],
          rows: [
            for (final s in sessions)
              DataRow2(
                onTap: () => _openDetail(s),
                color: s.isActive
                    ? WidgetStatePropertyAll(
                        AppColors.successGreen.withValues(alpha: 0.08))
                    : null,
                cells: [
                  DataCell(Text(s.deviceId ?? s.id)),
                  DataCell(Text(_fmt(s.startedAt))),
                  DataCell(Text(_fmt(s.expiresAt))),
                  DataCell(StatusBadge(
                    status: s.isActive
                        ? BadgeStatus.active
                        : BadgeStatus.inactive,
                    label: s.isActive ? 'Active' : 'Expired',
                  )),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _SessionDetail extends StatefulWidget {
  final VisitorSessionModel session;
  final VisitorSessionRepository repo;

  const _SessionDetail({required this.session, required this.repo});

  @override
  State<_SessionDetail> createState() => _SessionDetailState();
}

class _SessionDetailState extends State<_SessionDetail> {
  late Future<List<NavigationSessionModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.getNavigationHistory(widget.session.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('Session ID', s.id),
        _row('Device ID', s.deviceId ?? '—'),
        _row('Started', s.startedAt?.toString() ?? '—'),
        _row('Expires', s.expiresAt?.toString() ?? '—'),
        _row('Status', s.isActive ? 'Active' : 'Expired'),
        const Divider(height: 24),
        const Text('Navigation History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FutureBuilder<List<NavigationSessionModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text(snapshot.error.toString());
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const Text('No navigation sessions',
                  style: TextStyle(color: AppColors.textSecondary));
            }
            return Column(
              children: [
                for (final n in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.near_me, size: 16),
                    title: Text('${n.fromName ?? '?'} → ${n.toName ?? '?'}',
                        style: const TextStyle(fontSize: 12)),
                    subtitle: Text(
                      '${n.distanceMeters?.toStringAsFixed(0) ?? '?'} m · '
                      '${n.completed ? 'completed' : 'incomplete'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
