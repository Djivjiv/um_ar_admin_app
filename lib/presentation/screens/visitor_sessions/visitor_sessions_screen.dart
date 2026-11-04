import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_metrics.dart';
import '../../../core/utils/short_code.dart';
import '../../../data/repositories/visitor_session_repository.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';

String _fmt(DateTime? d) =>
    d == null ? '—' : DateFormat('MMM d, y h:mm a').format(d);

/// How the trip was logged, from `is_visitor` (`user_id` on older rows). A
/// visitor who later signs in on the same phone can have both in one history.
String tripAccountLabel(NavigationTrip trip) =>
    trip.isVisitor ? 'Visitor' : 'Signed in';

class VisitorSessionsScreen extends StatefulWidget {
  const VisitorSessionsScreen({super.key});

  @override
  State<VisitorSessionsScreen> createState() => _VisitorSessionsScreenState();
}

class _VisitorSessionsScreenState extends State<VisitorSessionsScreen> {
  final _repo = VisitorSessionRepository();
  late Future<List<VisitorEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getEntries();
  }

  void _reload() {
    setState(() {
      _future = _repo.getEntries();
    });
  }

  void _openDetail(VisitorEntry entry) {
    SlidePanel.show(
      context,
      title: entry.isOffline ? 'Offline Visitor' : 'Visitor Session',
      subtitle: shortDeviceCode(entry.deviceCode),
      body: _VisitorDetail(entry: entry, repo: _repo),
    );
  }

  StatusBadge _badge(VisitorEntry v) => StatusBadge(
        status: v.isOffline
            ? BadgeStatus.pending
            : v.isActive
                ? BadgeStatus.active
                : BadgeStatus.inactive,
        label: v.statusLabel,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VisitorEntry>>(
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
        final entries = snapshot.data ?? [];
        final offline = entries.where((e) => e.isOffline).length;
        return DataTableCard(
          title: '${entries.length - offline} Visitor Sessions'
              '${offline == 0 ? '' : ', $offline offline'}',
          isLoading: loading,
          columns: const [
            DataColumn2(label: Text('Device'), size: ColumnSize.L),
            DataColumn2(label: Text('Started'), size: ColumnSize.L),
            DataColumn2(label: Text('Expires'), size: ColumnSize.L),
            DataColumn2(label: Text('Status'), size: ColumnSize.S),
          ],
          rows: [
            for (final v in entries)
              DataRow2(
                onTap: () => _openDetail(v),
                color: v.isActive
                    ? WidgetStatePropertyAll(
                        AppColors.successGreen.withValues(alpha: 0.08))
                    : null,
                cells: [
                  DataCell(Text(v.deviceCode != null
                      ? shortDeviceCode(v.deviceCode)
                      : shortId(v.session?.id ?? '—'))),
                  DataCell(Text(_fmt(v.startedAt))),
                  DataCell(Text(_fmt(v.session?.expiresAt))),
                  DataCell(_badge(v)),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _VisitorDetail extends StatefulWidget {
  final VisitorEntry entry;
  final VisitorSessionRepository repo;

  const _VisitorDetail({required this.entry, required this.repo});

  @override
  State<_VisitorDetail> createState() => _VisitorDetailState();
}

class _VisitorDetailState extends State<_VisitorDetail> {
  late Future<VisitorHistory> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.getTripHistory(widget.entry);
  }

  void _reload() {
    setState(() {
      _future = widget.repo.getTripHistory(widget.entry);
    });
  }

  Widget _tripTile(NavigationTrip t) {
    final from = t.fromName.isEmpty ? '?' : t.fromName;
    final to = t.toName.isEmpty ? '?' : t.toName;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.near_me, size: 16),
      title: Text('$from → $to', style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        '${t.distanceMeters?.toStringAsFixed(0) ?? '?'} m · '
        '${modeLabel(t.mode)} · ${t.outcome} · ${tripAccountLabel(t)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.isOffline) ...[
          const Text(
            'No session row: the app had no connection when this visitor '
            'started. Found by device code in their trips and SUS answers.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _row('Device code', shortDeviceCode(v.deviceCode)),
          _row('First seen', _fmt(v.startedAt)),
          _row('Last seen', _fmt(v.lastSeenAt)),
        ] else ...[
          _row('Session ID', v.session!.id),
          _row('Device code', shortDeviceCode(v.deviceCode)),
          _row('Started', _fmt(v.startedAt)),
          _row('Expires', _fmt(v.session!.expiresAt)),
        ],
        _row('Status', v.statusLabel),
        const Divider(height: 24),
        const Text('Navigation History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FutureBuilder<VisitorHistory>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorBanner(
                  message: snapshot.error.toString(), onRetry: _reload);
            }
            final history = snapshot.data ?? const VisitorHistory();
            final older = history.rowsWithoutTrip;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (history.trips.isEmpty)
                  const Text('No navigation trips',
                      style: TextStyle(color: AppColors.textSecondary)),
                for (final t in history.trips) _tripTile(t),
                if (older > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$older older ${older == 1 ? 'row' : 'rows'} with no '
                    'trip_id left out.',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
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
