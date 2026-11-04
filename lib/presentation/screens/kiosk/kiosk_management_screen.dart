import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/analytics_repository.dart' show ChartPoint;
import '../../../data/repositories/kiosk_repository.dart';
import '../../../domain/models/kiosk_session_model.dart';
import '../../../domain/models/kiosk_settings_model.dart';
import '../../widgets/charts.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/form_input.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';

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

/// Last 7 days including today, as whole calendar days.
DateTimeRange _defaultRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(
      start: today.subtract(const Duration(days: 6)), end: today);
}

/// The repository works on `[from, to)`; a picked range is inclusive days.
({DateTime from, DateTime to}) _bounds(DateTimeRange r) =>
    wholeDays(r.start, r.end);

class KioskManagementScreen extends StatefulWidget {
  const KioskManagementScreen({super.key});

  @override
  State<KioskManagementScreen> createState() => _KioskManagementScreenState();
}

class _KioskManagementScreenState extends State<KioskManagementScreen> {
  final _repo = KioskRepository();

  /// Shared by the Sessions and Analytics tabs.
  DateTimeRange _range = _defaultRange();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      // Render the picker as a compact centred popup instead of a full page.
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
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final rangeButton = OutlinedButton.icon(
      onPressed: _pickRange,
      icon: const Icon(Icons.date_range, size: 16),
      label: Text(
        '${DateFormat.yMMMd().format(_range.start)} – '
        '${DateFormat.yMMMd().format(_range.end)}',
      ),
    );
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Kiosk Management',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Settings and usage for the campus kiosk tablet app.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primaryMaroon,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.accentGold,
              indicatorWeight: 3,
              tabs: [
                Tab(icon: Icon(Icons.tune, size: 18), text: 'Settings'),
                Tab(icon: Icon(Icons.history, size: 18), text: 'Sessions'),
                Tab(icon: Icon(Icons.insights, size: 18), text: 'Analytics'),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              children: [
                _SettingsTab(repo: _repo),
                _SessionsTab(
                    repo: _repo, range: _range, rangeButton: rangeButton),
                _AnalyticsTab(
                    repo: _repo, range: _range, rangeButton: rangeButton),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — Settings
// ===========================================================================

class _SettingsTab extends StatefulWidget {
  final KioskRepository repo;

  const _SettingsTab({required this.repo});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _welcome = TextEditingController();
  final _disclaimer = TextEditingController();
  final _downloadUrl = TextEditingController();
  final _announcement = TextEditingController();

  KioskSettingsModel _saved = const KioskSettingsModel();
  int _idleTimeout = KioskSettingsModel.defaultIdleTimeout;
  bool _surveyEnabled = true;

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _welcome.dispose();
    _disclaimer.dispose();
    _downloadUrl.dispose();
    _announcement.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.repo.getSettings();
      if (!mounted) return;
      _apply(s);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _apply(KioskSettingsModel s) {
    _saved = s;
    _welcome.text = s.welcomeMessage;
    _disclaimer.text = s.disclaimerText;
    _downloadUrl.text = s.appDownloadUrl;
    _announcement.text = s.announcementText;
    _idleTimeout = s.idleTimeoutSeconds;
    _surveyEnabled = s.isSurveyEnabled;
  }

  /// The settings as currently shown in the form (saved or not).
  KioskSettingsModel get _current => _saved.copyWith(
        welcomeMessage: _welcome.text,
        disclaimerText: _disclaimer.text,
        appDownloadUrl: _downloadUrl.text.trim(),
        announcementText: _announcement.text,
        idleTimeoutSeconds: _idleTimeout,
        isSurveyEnabled: _surveyEnabled,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.repo.updateSettings(_current);
      if (!mounted) return;
      setState(() => _apply(saved));
      context.showSuccess('Kiosk settings saved');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _preview() {
    SlidePanel.show<void>(
      context,
      title: 'Kiosk Preview',
      subtitle: 'How the kiosk will look with these settings (unsaved '
          'changes included)',
      body: _KioskPreview(settings: _current),
    );
  }

  String? _validateUrl(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // optional
    final uri = Uri.tryParse(s);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Enter a full link starting with http:// or https://';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Kiosk Settings',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          Text(
                            _saved.updatedAt == null
                                ? 'Never saved'
                                : 'Last updated ${_fmtDateTime(_saved.updatedAt)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FormInput(
                        label: 'Welcome message',
                        controller: _welcome,
                        hint: 'Shown on the kiosk home screen',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      FormInput(
                        label: 'Disclaimer text',
                        controller: _disclaimer,
                        hint: 'e.g. Routes are approximate…',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      FormInput(
                        label: 'App download URL',
                        controller: _downloadUrl,
                        hint: 'https://… (shown as a QR code on the kiosk)',
                        keyboardType: TextInputType.url,
                        validator: _validateUrl,
                      ),
                      const SizedBox(height: 14),
                      FormInput(
                        label: 'Announcement text',
                        controller: _announcement,
                        hint: 'Optional banner — leave empty to hide',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text('Idle timeout',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(_fmtDuration(Duration(seconds: _idleTimeout)),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryMaroon)),
                        ],
                      ),
                      Slider(
                        value: _idleTimeout.toDouble(),
                        min: KioskSettingsModel.minIdleTimeout.toDouble(),
                        max: KioskSettingsModel.maxIdleTimeout.toDouble(),
                        divisions: (KioskSettingsModel.maxIdleTimeout -
                                KioskSettingsModel.minIdleTimeout) ~/
                            10,
                        label: '${_idleTimeout}s',
                        activeColor: AppColors.primaryMaroon,
                        inactiveColor: AppColors.accentGold.withValues(alpha: 0.3),
                        onChanged: (v) => setState(() => _idleTimeout = v.round()),
                      ),
                      const Text(
                        'The kiosk returns to the home screen after this long '
                        'without a touch (30 s – 5 min).',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Post-navigation survey enabled',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Ask kiosk users to rate the app at the end of a '
                              'session',
                              style: TextStyle(fontSize: 11)),
                          value: _surveyEnabled,
                          activeThumbColor: AppColors.primaryMaroon,
                          onChanged: (v) => setState(() => _surveyEnabled = v),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _preview,
                            icon: const Icon(Icons.visibility_outlined, size: 16),
                            label: const Text('Preview'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save, size: 16),
                            label: Text(_saving ? 'Saving…' : 'Save Settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ExitPinCard(
                repo: widget.repo,
                settings: _saved,
                onSaved: (id) => setState(() =>
                    _saved = _saved.copyWith(id: id, hasExitPin: true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets or changes `kiosk_settings.exit_pin`, which opens the kiosk's staff
/// screen. The saved PIN is never shown: the card only says whether one is
/// set. Typed PINs are hidden and cleared once saved.
class _ExitPinCard extends StatefulWidget {
  final KioskRepository repo;
  final KioskSettingsModel settings;

  /// Called with the settings row id after a save.
  final ValueChanged<int?> onSaved;

  const _ExitPinCard({
    required this.repo,
    required this.settings,
    required this.onSaved,
  });

  @override
  State<_ExitPinCard> createState() => _ExitPinCardState();
}

class _ExitPinCardState extends State<_ExitPinCard> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repo
          .setExitPin(_pin.text, settingsId: widget.settings.id);
      if (!mounted) return;
      final id = widget.settings.id ??
          (await widget.repo.getSettings()).id;
      if (!mounted) return;
      _pin.clear();
      _confirm.clear();
      widget.onSaved(id);
      context.showSuccess('Exit PIN saved. The kiosk picks it up within '
          '10 minutes, or at once with "Refresh now" on its staff screen.');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pinField(
    String label,
    TextEditingController controller,
    String? Function(String?) validator,
  ) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      maxLength: 8,
      validator: validator,
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSet = widget.settings.hasExitPin;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Kiosk Exit PIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              isSet
                  ? 'A PIN is set. Enter a new one to change it.'
                  : 'No PIN is set, so the kiosk\'s staff screen and exit '
                      'stay locked.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            _pinField(
              'New PIN (4 to 8 digits)',
              _pin,
              (v) => kExitPinFormat.hasMatch(v ?? '')
                  ? null
                  : 'Use 4 to 8 digits.',
            ),
            const SizedBox(height: 10),
            _pinField(
              'Confirm PIN',
              _confirm,
              (v) => exitPinProblem(_pin.text, v ?? ''),
            ),
            const SizedBox(height: 6),
            const Text(
              'Anyone holding the kiosk can try PINs, so prefer 6 to 8 digits '
              'and don\'t reuse a PIN that protects anything else.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock, size: 16),
                label: Text(_saving
                    ? 'Saving…'
                    : isSet
                        ? 'Change PIN'
                        : 'Set PIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Approximation of the kiosk home screen, rendered inside the SlidePanel.
class _KioskPreview extends StatelessWidget {
  final KioskSettingsModel settings;

  const _KioskPreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentGold, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.announcementText.trim().isNotEmpty)
                Container(
                  color: AppColors.accentGold,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign,
                          size: 16, color: AppColors.primaryMaroon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.announcementText.trim(),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryMaroon)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  children: [
                    const Icon(Icons.navigation,
                        size: 36, color: AppColors.accentGold),
                    const SizedBox(height: 12),
                    Text(
                      s.welcomeMessage.trim().isEmpty
                          ? 'Welcome!'
                          : s.welcomeMessage.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search,
                              size: 18, color: AppColors.textSecondary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Where do you want to go?',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                    if (s.appDownloadUrl.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.white,
                        child: QrImageView(
                            data: s.appDownloadUrl.trim(), size: 110),
                      ),
                      const SizedBox(height: 6),
                      const Text('Scan to get the UM Nav app',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ],
                ),
              ),
              if (s.disclaimerText.trim().isNotEmpty)
                Container(
                  color: Colors.black26,
                  padding: const EdgeInsets.all(10),
                  child: Text(s.disclaimerText.trim(),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _previewFact(Icons.timer_outlined,
            'Resets after ${_fmtDuration(Duration(seconds: s.idleTimeoutSeconds))} idle'),
        _previewFact(
            s.isSurveyEnabled ? Icons.check_circle : Icons.cancel_outlined,
            s.isSurveyEnabled
                ? 'Survey shown at the end of a session'
                : 'Survey turned off'),
      ],
    );
  }

  Widget _previewFact(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primaryMaroon),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}

// ===========================================================================
// TAB 2 — Sessions
// ===========================================================================

class _SessionsTab extends StatefulWidget {
  final KioskRepository repo;
  final DateTimeRange range;
  final Widget rangeButton;

  const _SessionsTab({
    required this.repo,
    required this.range,
    required this.rangeButton,
  });

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab>
    with AutomaticKeepAliveClientMixin {
  List<KioskSessionModel> _sessions = [];
  KioskSessionCounts _counts = const KioskSessionCounts();
  bool _loading = true;
  bool _exporting = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SessionsTab old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = _bounds(widget.range);
      final results = await Future.wait([
        widget.repo.getKioskSessions(from: b.from, to: b.to),
        widget.repo.getSessionCounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<KioskSessionModel>;
        _counts = results[1] as KioskSessionCounts;
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

  Future<void> _export() async {
    if (_sessions.isEmpty) {
      context.showInfo('No sessions in this date range to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final b = _bounds(widget.range);
      final path = await widget.repo
          .exportSessionsToExcel(_sessions, from: b.from, to: b.to);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    final loading = _loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow(cards: [
          StatCard(
            icon: Icons.today,
            title: 'Sessions Today',
            value: loading ? '—' : '${_counts.today}',
            iconColor: AppColors.primaryMaroon,
          ),
          StatCard(
            icon: Icons.date_range,
            title: 'Sessions This Week',
            value: loading ? '—' : '${_counts.thisWeek}',
            subtitle: 'Since Monday',
            iconColor: AppColors.accentGold,
          ),
          StatCard(
            icon: Icons.calendar_month,
            title: 'Sessions This Month',
            value: loading ? '—' : '${_counts.thisMonth}',
            subtitle: DateFormat('MMMM').format(DateTime.now()),
            iconColor: AppColors.infoBlue,
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: DataTableCard(
            title: 'Sessions (${_sessions.length})',
            isLoading: loading,
            minWidth: 820,
            emptyMessage: 'No kiosk sessions in this date range',
            actions: [
              widget.rangeButton,
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: _exporting || loading ? null : _export,
                icon: const Icon(Icons.download, size: 16),
                label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
              ),
            ],
            columns: const [
              DataColumn2(label: Text('Start Time'), size: ColumnSize.M),
              DataColumn2(label: Text('Duration'), size: ColumnSize.S),
              DataColumn2(
                  label: Text('Searches'), size: ColumnSize.S, numeric: true),
              DataColumn2(
                  label: Text('Routes'), size: ColumnSize.S, numeric: true),
              DataColumn2(
                  label: Text('Destinations Viewed'),
                  size: ColumnSize.S,
                  numeric: true),
              DataColumn2(label: Text('Feedback'), size: ColumnSize.S),
            ],
            rows: [
              for (final s in _sessions)
                DataRow2(
                  cells: [
                    DataCell(Text(_fmtDateTime(s.startedAt))),
                    DataCell(Text(s.isActive && s.startedAt != null
                        ? 'In progress'
                        : _fmtDuration(s.duration))),
                    DataCell(Text('${s.searchesCount}')),
                    DataCell(Text('${s.routesCalculated}')),
                    DataCell(Text('${s.destinationsViewed}')),
                    DataCell(StatusBadge(
                      status: s.feedbackGiven
                          ? BadgeStatus.active
                          : BadgeStatus.inactive,
                      label: s.feedbackGiven ? 'Yes' : 'No',
                    )),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// TAB 3 — Analytics
// ===========================================================================

class _AnalyticsTab extends StatefulWidget {
  final KioskRepository repo;
  final DateTimeRange range;
  final Widget rangeButton;

  const _AnalyticsTab({
    required this.repo,
    required this.range,
    required this.rangeButton,
  });

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<(KioskAnalytics, KioskSurveySummary)> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _AnalyticsTab old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range) _reload();
  }

  Future<(KioskAnalytics, KioskSurveySummary)> _load() {
    final b = _bounds(widget.range);
    return (
      widget.repo.getSessionAnalytics(from: b.from, to: b.to),
      widget.repo.getSurveySummary(from: b.from, to: b.to),
    ).wait;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<(KioskAnalytics, KioskSurveySummary)>(
      future: _future,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  widget.rangeButton,
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                _ErrorView(error: _unwrap(snapshot.error!), onRetry: _reload)
              else ...[
                _content(snapshot.data!.$1),
                const SizedBox(height: 24),
                _SurveySection(summary: snapshot.data!.$2),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _content(KioskAnalytics a) {
    String perSession(int total) => a.totalSessions == 0
        ? '0 per session'
        : '${(total / a.totalSessions).toStringAsFixed(1)} per session';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow(cards: [
          StatCard(
            icon: Icons.tablet_mac,
            title: 'Sessions (range)',
            value: '${a.totalSessions}',
            subtitle: '${a.feedbackCount} gave feedback',
            iconColor: AppColors.primaryMaroon,
          ),
          StatCard(
            icon: Icons.timer_outlined,
            title: 'Avg Session Duration',
            value: _fmtDuration(a.averageDuration),
            subtitle: a.averageDuration == null
                ? 'No ended sessions yet'
                : 'From ${a.sessionsWithDuration} ended sessions',
            iconColor: AppColors.accentGold,
          ),
          StatCard(
            icon: Icons.search,
            title: 'Searches',
            value: '${a.totalSearches}',
            subtitle: perSession(a.totalSearches),
            iconColor: AppColors.infoBlue,
          ),
          StatCard(
            icon: Icons.alt_route,
            title: 'Routes Calculated',
            value: '${a.totalRoutes}',
            subtitle: perSession(a.totalRoutes),
            iconColor: AppColors.successGreen,
          ),
        ]),
        const SizedBox(height: 16),
        ChartCard(
          title: 'Daily Usage',
          child: LineChartView(points: a.dailyUsage),
        ),
        const SizedBox(height: 16),
        ChartCard(
          title: 'Peak Usage Hours',
          height: 200,
          child: BarChartView(
              points: a.peakHours, color: AppColors.primaryMaroon),
        ),
        const SizedBox(height: 16),
        if (!a.eventsAvailable) ...[
          const _Notice(
            'Most searched locations, viewed buildings and requested routes '
            'need the kiosk_events table. Run db/kiosk_management.sql, then '
            'have the kiosk app log one kiosk_events row per search, building '
            'view and route.',
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              ChartCard(
                title: 'Most Searched Locations',
                child: _RankedList(
                    points: a.topSearches,
                    available: a.eventsAvailable,
                    color: AppColors.infoBlue),
              ),
              ChartCard(
                title: 'Most Viewed Buildings',
                child: _RankedList(
                    points: a.topBuildings,
                    available: a.eventsAvailable,
                    color: AppColors.accentGold),
              ),
              ChartCard(
                title: 'Most Requested Routes',
                child: _RankedList(
                    points: a.topRoutes,
                    available: a.eventsAvailable,
                    color: AppColors.primaryMaroon),
              ),
              if (a.eventsByKiosk.isNotEmpty)
                ChartCard(
                  title: 'Events by Kiosk',
                  child: _RankedList(
                      points: a.eventsByKiosk,
                      available: a.eventsAvailable,
                      color: AppColors.infoBlue),
                ),
            ];
            if (constraints.maxWidth < 1000) {
              return Column(children: [
                for (final c in cards) ...[c, const SizedBox(height: 16)],
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `(a, b).wait` wraps failures in a ParallelWaitError; show the real cause.
Object _unwrap(Object error) {
  if (error is ParallelWaitError) {
    final (a, b) = error.errors as (AsyncError?, AsyncError?);
    return (a ?? b)?.error ?? error;
  }
  return error;
}

/// Kiosk post-navigation survey: averages, "would use again" and comments.
class _SurveySection extends StatelessWidget {
  final KioskSurveySummary summary;

  const _SurveySection({required this.summary});

  static String _rating(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1)} / 5';

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final from = 'From ${s.responseCount} '
        '${s.responseCount == 1 ? 'response' : 'responses'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Visitor Survey',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text(
          'Answers from the kiosk survey shown after a visitor arrives at '
          'their destination.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (!s.available) ...[
          const _Notice(
            'The kiosk_survey_responses table does not exist yet. Run '
            'um_kiosk_app/supabase/kiosk_survey.sql in the Supabase SQL editor.',
          ),
          const SizedBox(height: 16),
        ],
        _StatRow(cards: [
          StatCard(
            icon: Icons.explore_outlined,
            title: 'Avg Ease of Finding',
            value: _rating(s.averageEase),
            subtitle: from,
            iconColor: AppColors.primaryMaroon,
          ),
          StatCard(
            icon: Icons.gps_fixed,
            title: 'Avg Navigation Accuracy',
            value: _rating(s.averageAccuracy),
            subtitle: from,
            iconColor: AppColors.infoBlue,
          ),
          StatCard(
            icon: Icons.star_outline,
            title: 'Avg Overall Experience',
            value: _rating(s.averageOverall),
            subtitle: from,
            iconColor: AppColors.accentGold,
          ),
          StatCard(
            icon: Icons.replay,
            title: 'Would Use Again',
            value: s.wouldUseAgainPercent == null
                ? '—'
                : '${s.wouldUseAgainPercent!.round()}%',
            subtitle: 'Yes ${s.wouldUseAgainYes} · Maybe '
                '${s.wouldUseAgainMaybe} · No ${s.wouldUseAgainNo}',
            iconColor: AppColors.successGreen,
          ),
        ]),
        const SizedBox(height: 16),
        ChartCard(
          title: 'Recent Comments',
          height: 280,
          child: s.recentComments.isEmpty
              ? Center(
                  child: Text(
                      s.available
                          ? 'No comments in this range'
                          : 'Not tracked yet',
                      style: const TextStyle(color: AppColors.textSecondary)),
                )
              : ListView.separated(
                  itemCount: s.recentComments.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final c = s.recentComments[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('“${c.text}”',
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            for (var k = 1; k <= 5; k++)
                              Icon(
                                  k <= c.overallRating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 13,
                                  color: AppColors.accentGold),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  if (c.destination?.isNotEmpty == true)
                                    c.destination!,
                                  if (c.kioskCode != null) 'Kiosk ${c.kioskCode}',
                                  _fmtDateTime(c.createdAt?.toLocal()),
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Horizontal bars with full labels — building names and "A → B" routes are
/// too long for a vertical bar chart's axis.
class _RankedList extends StatelessWidget {
  final List<ChartPoint> points;
  final bool available;
  final Color color;

  const _RankedList({
    required this.points,
    required this.available,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(available ? 'No data in this range' : 'Not tracked yet',
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final maxV = points.first.value <= 0 ? 1.0 : points.first.value;
    return ListView.separated(
      itemCount: points.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = points[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${i + 1}. ${p.label}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${p.value.toInt()}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p.value / maxV,
                minHeight: 6,
                backgroundColor: AppColors.backgroundGray,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// shared bits
// ===========================================================================

class _StatRow extends StatelessWidget {
  final List<Widget> cards;

  const _StatRow({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth > 1100
            ? cards.length
            : constraints.maxWidth > 640
                ? 2
                : 1;
        final width = (constraints.maxWidth - (perRow - 1) * 16) / perRow;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final c in cards) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningAmber),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: AppColors.warningAmber),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
