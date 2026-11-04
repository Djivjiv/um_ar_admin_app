import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/csv_export.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/feedback_repository.dart';
import '../../../domain/models/feedback_comment_model.dart';
import '../../widgets/data_table_card.dart';

/// Always offered in the Role filter; other roles join it once a row has them.
const _baseRoles = ['student', 'faculty', 'visitor'];

class FeedbackCommentsScreen extends StatefulWidget {
  const FeedbackCommentsScreen({super.key});

  @override
  State<FeedbackCommentsScreen> createState() => _FeedbackCommentsScreenState();
}

class _FeedbackCommentsScreenState extends State<FeedbackCommentsScreen> {
  final _repo = FeedbackRepository();
  static const _perPage = 50;

  FeedbackLoad? _data;
  bool _loading = true;
  Object? _error;

  /// Null means every date.
  DateTimeRange? _range;
  String? _role;
  String _search = '';
  int _page = 0;
  bool _exporting = false;

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
    final range = _range;
    final span = range == null ? null : wholeDays(range.start, range.end);
    try {
      final data =
          await _repo.getComments(from: span?.from, to: span?.to);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _page = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<FeedbackCommentModel> get _filtered => filterFeedback(
        _data?.rows ?? const [],
        role: _role,
        search: _search,
      );

  List<String> get _roles => {
        ..._baseRoles,
        for (final r in _data?.rows ?? const <FeedbackCommentModel>[]) ?r.role,
      }.toList();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _range = picked);
      _load();
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await saveCsvFile(
        'feedback_comments',
        feedbackExportRows(_filtered),
      );
      if (mounted) {
        context.showSuccess(
            path == null ? 'Export cancelled' : 'Saved to $path');
      }
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _export);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showComment(FeedbackCommentModel c) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${c.role ?? 'Unknown role'} · ${_when(c.createdAt)}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.ratingContext != null) ...[
                  Text(c.ratingContext!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                ],
                SelectableText(c.comment),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  String _when(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, y h:mm a').format(d);

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.length;
    final pages = total == 0 ? 1 : ((total - 1) ~/ _perPage) + 1;
    final page = _page >= pages ? pages - 1 : _page;
    final start = page * _perPage;
    final end = start + _perPage > total ? total : start + _perPage;
    final range = _range;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(range == null
                  ? 'All dates'
                  : '${DateFormat.yMMMd().format(range.start)} – '
                      '${DateFormat.yMMMd().format(range.end)}'),
            ),
            if (range != null)
              IconButton(
                tooltip: 'Clear dates',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  setState(() => _range = null);
                  _load();
                },
              ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(_roles.length),
                initialValue: _role,
                isExpanded: true,
                decoration:
                    const InputDecoration(isDense: true, labelText: 'Role'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All')),
                  for (final r in _roles)
                    DropdownMenuItem<String?>(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() {
                  _role = v;
                  _page = 0;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search comments…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() {
                  _search = v;
                  _page = 0;
                }),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _exporting || filtered.isEmpty ? null : _export,
              icon: const Icon(Icons.download, size: 16),
              label: Text(_exporting ? 'Exporting…' : 'Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(filtered.sublist(start, end), total)),
        if (!_loading && _error == null && total > _perPage)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Page ${page + 1} of $pages',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: page < pages - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
            ],
          ),
      ],
    );
  }

  Widget _body(List<FeedbackCommentModel> rows, int total) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final data = _data;
    if (data != null && !_loading && data.rows.isEmpty) {
      return _NoDataYet(data: data, hasDateFilter: _range != null);
    }
    return DataTableCard(
      title: '$total ${total == 1 ? 'Comment' : 'Comments'}',
      isLoading: _loading,
      emptyMessage: 'No comments match these filters',
      minWidth: 900,
      columns: const [
        DataColumn2(label: Text('Comment'), size: ColumnSize.L),
        DataColumn2(label: Text('Rating Context'), size: ColumnSize.M),
        DataColumn2(label: Text('Role'), size: ColumnSize.S),
        DataColumn2(label: Text('Anonymous ID'), size: ColumnSize.S),
        DataColumn2(label: Text('Date'), size: ColumnSize.M),
      ],
      rows: [
        for (final c in rows)
          DataRow2(
            onTap: () => _showComment(c),
            cells: [
              DataCell(Text(c.comment,
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              DataCell(Text(c.ratingContext ?? '—',
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              DataCell(Text(c.role ?? '—')),
              DataCell(Text(c.anonymousRef ?? '—')),
              DataCell(Text(_when(c.createdAt))),
            ],
          ),
      ],
    );
  }
}

class _NoDataYet extends StatelessWidget {
  final FeedbackLoad data;
  final bool hasDateFilter;

  const _NoDataYet({required this.data, required this.hasDateFilter});

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No data yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          if (hasDateFilter)
            const Text('Nothing in this date range.', style: small),
          if (!data.tableExists)
            const Text('The feedback_comments table was not found.',
                style: small),
          Text('Expected columns: ${kFeedbackColumns.join(', ')}.',
              textAlign: TextAlign.center, style: small),
          if (data.missingColumns.isNotEmpty)
            Text('Missing: ${data.missingColumns.join(', ')}.',
                textAlign: TextAlign.center, style: small),
        ],
      ),
    );
  }
}
