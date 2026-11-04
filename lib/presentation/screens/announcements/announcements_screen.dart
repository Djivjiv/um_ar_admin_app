import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/announcement_repository.dart';
import '../../../domain/models/announcement_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';
import 'announcement_form.dart';

enum _StatusFilter { all, active, inactive, expired }

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _repo = AnnouncementRepository();

  List<AnnouncementModel> _items = [];
  bool _loading = true;
  Object? _error;
  _StatusFilter _filter = _StatusFilter.all;
  bool _expiring = false;

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
      final items = await _repo.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<AnnouncementModel> get _filtered => _items.where((a) {
        switch (_filter) {
          case _StatusFilter.all:
            return true;
          case _StatusFilter.active:
            return a.isActive && !a.isExpired;
          case _StatusFilter.inactive:
            return !a.isActive;
          case _StatusFilter.expired:
            return a.isExpired;
        }
      }).toList();

  int get _expiredActiveCount =>
      _items.where((a) => a.isActive && a.isExpired).length;

  Future<void> _openForm([AnnouncementModel? announcement]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: announcement == null ? 'Add Announcement' : 'Edit Announcement',
      subtitle: announcement?.title,
      body: AnnouncementForm(announcement: announcement),
    );
    if (result == true) _load();
  }

  Future<void> _toggle(AnnouncementModel a) async {
    try {
      await _repo.toggleActive(a.id!, !a.isActive);
      if (mounted) context.showSuccess('Status updated');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _toggle(a));
    }
  }

  Future<void> _delete(AnnouncementModel a) async {
    final ok = await ConfirmDialog.show(context, itemName: a.title);
    if (!ok) return;
    try {
      await _repo.delete(a.id!);
      if (mounted) context.showSuccess('Deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _delete(a));
    }
  }

  Future<void> _expireOld() async {
    setState(() => _expiring = true);
    try {
      final n = await _repo.expireOld();
      if (mounted) {
        context.showSuccess(n == 1
            ? '1 expired announcement deactivated'
            : '$n expired announcements deactivated');
      }
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _expireOld);
    } finally {
      if (mounted) setState(() => _expiring = false);
    }
  }

  Widget _badge(AnnouncementModel a) {
    if (a.isExpired) {
      return const StatusBadge(status: BadgeStatus.pending, label: 'Expired');
    }
    return StatusBadge.fromBool(a.isActive);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error.toString()),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final dateFmt = DateFormat('MMM d, y h:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<_StatusFilter>(
                initialValue: _filter,
                decoration:
                    const InputDecoration(isDense: true, labelText: 'Status'),
                items: const [
                  DropdownMenuItem(
                      value: _StatusFilter.all, child: Text('All')),
                  DropdownMenuItem(
                      value: _StatusFilter.active, child: Text('Active')),
                  DropdownMenuItem(
                      value: _StatusFilter.inactive, child: Text('Inactive')),
                  DropdownMenuItem(
                      value: _StatusFilter.expired, child: Text('Expired')),
                ],
                onChanged: (v) => setState(() => _filter = v ?? _filter),
              ),
            ),
            const Spacer(),
            if (_expiredActiveCount > 0) ...[
              OutlinedButton.icon(
                onPressed: _expiring ? null : _expireOld,
                icon: const Icon(Icons.event_busy, size: 18),
                label: Text('Deactivate expired ($_expiredActiveCount)'),
              ),
              const SizedBox(width: 12),
            ],
            ElevatedButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Announcement'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? const Center(child: Text('No announcements found'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth > 900 ? 2 : 1;
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            mainAxisExtent: 180,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final a = _filtered[i];
                            final expiry = a.expiresAt == null
                                ? 'No expiry'
                                : '${a.isExpired ? 'Expired' : 'Expires'} '
                                    '${dateFmt.format(a.expiresAt!.toLocal())}';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: a.isEmergency
                                        ? AppColors.errorRed
                                        : AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (a.isEmergency) ...[
                                        const Icon(Icons.warning_amber,
                                            size: 18,
                                            color: AppColors.errorRed),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(a.title,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      _badge(a),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${a.type ?? '—'} · $expiry',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: Text(
                                      a.body ?? '',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const Spacer(),
                                      IconButton(
                                        tooltip: 'Edit',
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _openForm(a),
                                      ),
                                      IconButton(
                                        tooltip: a.isActive
                                            ? 'Deactivate'
                                            : 'Activate',
                                        icon: Icon(
                                          a.isActive
                                              ? Icons.toggle_on
                                              : Icons.toggle_off,
                                          size: 20,
                                          color: a.isActive
                                              ? AppColors.successGreen
                                              : AppColors.textSecondary,
                                        ),
                                        onPressed: () => _toggle(a),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18, color: AppColors.errorRed),
                                        onPressed: () => _delete(a),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
