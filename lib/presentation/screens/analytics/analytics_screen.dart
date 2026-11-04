import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/excel_export.dart';
import '../../../core/utils/navigation_metrics.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/stat_card.dart';
import 'navigation_metrics_section.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsData {
  final TripSummary trips;
  final UserDistribution userDistribution;
  final int tripsToday;
  final int totalUsers;
  final NavigationMetrics navigationMetrics;

  _AnalyticsData({
    required this.trips,
    required this.userDistribution,
    required this.tripsToday,
    required this.totalUsers,
    required this.navigationMetrics,
  });
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _repo = AnalyticsRepository();
  late Future<_AnalyticsData> _future;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AnalyticsData> _load() async {
    final span = wholeDays(_range.start, _range.end);
    final results = await Future.wait([
      _repo.getTripSummary(from: span.from, to: span.to),
      _repo.getUserDistribution(from: span.from, to: span.to),
      _repo.getTripsTodayCount(),
      _repo.getTotalUsersCount(),
      _repo.getNavigationMetrics(from: span.from, to: span.to),
    ]);
    return _AnalyticsData(
      trips: results[0] as TripSummary,
      userDistribution: results[1] as UserDistribution,
      tripsToday: results[2] as int,
      totalUsers: results[3] as int,
      navigationMetrics: results[4] as NavigationMetrics,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
    if (picked != null) {
      setState(() => _range = picked);
      _reload();
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final span = wholeDays(_range.start, _range.end);
      final day = DateFormat('yyyy-MM-dd');
      final sheets = await _repo.exportTripWorkbook(
        from: span.from,
        to: span.to,
        rangeLabel:
            '${day.format(_range.start)} to ${day.format(_range.end)}',
      );
      final fileDay = DateFormat('yyyyMMdd');
      final path = await saveExcelWorkbook(
        'navigation_trips_${fileDay.format(_range.start)}_'
        '${fileDay.format(_range.end)}',
        sheets,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AnalyticsData>(
      future: _future,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      '${DateFormat.yMMMd().format(_range.start)} – '
                      '${DateFormat.yMMMd().format(_range.end)}',
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
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
                Center(
                  child: Column(
                    children: [
                      Text(snapshot.error.toString()),
                      const SizedBox(height: 8),
                      ElevatedButton(
                          onPressed: _reload, child: const Text('Retry')),
                    ],
                  ),
                )
              else
                _content(snapshot.data!),
            ],
          ),
        );
      },
    );
  }

  Widget _content(_AnalyticsData d) {
    final trips = d.trips;
    final rate = trips.completionRate;
    final distance = trips.averageDistance;
    final unmatched = d.userDistribution.rowsWithoutPerson;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final perRow = constraints.maxWidth > 1100
                ? 4
                : constraints.maxWidth > 640
                    ? 2
                    : 1;
            final width = (constraints.maxWidth - (perRow - 1) * 16) / perRow;
            final cards = [
              StatCard(
                icon: Icons.route,
                title: 'Trips (range)',
                value: '${trips.trips}',
                iconColor: AppColors.primaryMaroon,
              ),
              StatCard(
                icon: Icons.today,
                title: 'Trips Today',
                value: '${d.tripsToday}',
                iconColor: AppColors.infoBlue,
              ),
              StatCard(
                icon: Icons.check_circle,
                title: 'Completion Rate',
                value: rate == null
                    ? 'No data yet'
                    : '${rate.toStringAsFixed(1)}%',
                iconColor: AppColors.successGreen,
              ),
              StatCard(
                icon: Icons.straighten,
                title: 'Avg Distance',
                value: distance == null
                    ? 'No data yet'
                    : '${distance.toStringAsFixed(0)} m',
                iconColor: AppColors.accentGold,
              ),
            ];
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in cards) SizedBox(width: width, child: c),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Counted per trip: one start and end pair sharing a trip_id.'
          '${trips.rowsWithoutTrip == 0 ? '' : ' ${trips.rowsWithoutTrip} '
              'older ${trips.rowsWithoutTrip == 1 ? 'row' : 'rows'} with no '
              'trip_id ${trips.rowsWithoutTrip == 1 ? 'is' : 'are'} left out.'} '
          'Avg Distance ignores trips with a distance of 0 or empty.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        NavigationMetricsSection(metrics: d.navigationMetrics),
        const SizedBox(height: 24),
        ChartCard(
          title: 'Trips Over Time',
          child: LineChartView(points: trips.perDay),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final two = constraints.maxWidth > 900;
            final a = ChartCard(
              title: 'Most Visited Buildings',
              child: BarChartView(points: trips.mostVisited),
            );
            final b = ChartCard(
              title: 'User Distribution',
              child: DonutChartView(points: d.userDistribution.points),
            );
            if (!two) {
              return Column(children: [a, const SizedBox(height: 16), b]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                const SizedBox(width: 16),
                Expanded(child: b),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'User Distribution counts people active in this range: one per '
          'user_id, or per device_code for visitors.'
          '${unmatched == 0 ? '' : ' $unmatched ${unmatched == 1 ? 'row' : 'rows'} '
              'with neither could not be counted.'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ChartCard(
          title: 'Peak Hours',
          height: 120,
          child: _PeakHoursHeatmap(points: trips.peakHours),
        ),
        const SizedBox(height: 16),
        ChartCard(
          title: 'Completion Rate',
          height: 160,
          child: rate == null
              ? const Center(child: Text('No data yet'))
              : _CompletionGauge(rate: rate),
        ),
      ],
    );
  }
}

class _PeakHoursHeatmap extends StatelessWidget {
  final List<ChartPoint> points;
  const _PeakHoursHeatmap({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('No data'));
    }
    final maxV = points.map((p) => p.value).fold<double>(1, (a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 23 * 4) / 24;
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final p in points)
              Tooltip(
                message: '${p.label}:00 — ${p.value.toInt()} trips',
                child: Container(
                  width: cell.clamp(12, 40),
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon
                        .withValues(alpha: 0.15 + 0.85 * (p.value / maxV)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(p.label,
                      style: const TextStyle(fontSize: 8, color: Colors.white)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompletionGauge extends StatelessWidget {
  final double rate;
  const _CompletionGauge({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${rate.toStringAsFixed(1)}%',
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.successGreen)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (rate / 100).clamp(0, 1),
            minHeight: 14,
            backgroundColor: AppColors.backgroundGray,
            color: AppColors.successGreen,
          ),
        ),
        const SizedBox(height: 6),
        const Text('of trips completed',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
