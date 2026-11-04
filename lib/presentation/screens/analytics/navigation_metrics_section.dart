import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_metrics.dart';
import '../../../data/repositories/analytics_repository.dart' show ChartPoint;
import '../../widgets/charts.dart';

const _noData = 'No data yet';

/// Errors, task success, completion time, SUS and the AR vs 2D split. Each
/// metric says "No data yet" on its own and names the columns it needs, so one
/// missing column doesn't hide the others.
class NavigationMetricsSection extends StatelessWidget {
  final NavigationMetrics metrics;

  const NavigationMetricsSection({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cards = [
      _MetricCard(
        icon: Icons.wrong_location,
        color: AppColors.errorRed,
        title: 'Errors per route step',
        value: m.errorRate == null ? null : formatPercent(m.errorRate!),
        detail: 'error_count / total_steps, ${m.errorRateTrips} tracked '
            '${m.errorRateTrips == 1 ? 'trip' : 'trips'}',
        expected: kErrorRateColumns,
        missing: m.missingForErrorRate,
      ),
      _MetricCard(
        icon: Icons.alt_route,
        color: AppColors.warningAmber,
        title: 'Off-route events',
        value: m.offRouteEvents?.toString(),
        detail: '${m.reroutes} '
            '${m.reroutes == 1 ? 'reroute' : 'reroutes'}, over '
            '${m.offRouteTrips} tracked '
            '${m.offRouteTrips == 1 ? 'trip' : 'trips'}',
        expected: kOffRouteColumns,
        missing: m.missingForOffRoute,
      ),
      _MetricCard(
        icon: Icons.check_circle,
        color: AppColors.successGreen,
        title: 'Completion Rate',
        value:
            m.completionRate == null ? null : formatPercent(m.completionRate!),
        detail: '${m.completedTrips} of ${m.trips} '
            '${m.trips == 1 ? 'trip' : 'trips'} completed',
        expected: kCompletionRateColumns,
        missing: m.missingForCompletionRate,
      ),
      _MetricCard(
        icon: Icons.gps_fixed,
        color: AppColors.infoBlue,
        title: 'GPS-only arrivals',
        value:
            m.gpsArrivalRate == null ? null : formatPercent(m.gpsArrivalRate!),
        detail: '${m.gpsArrivals} of ${m.trips} '
            '${m.trips == 1 ? 'trip' : 'trips'}, plus ${m.manualArrivals} '
            'manual ${m.manualArrivals == 1 ? 'arrival' : 'arrivals'}',
        expected: kGpsArrivalColumns,
        missing: m.missingForGpsArrivals,
      ),
      _MetricCard(
        icon: Icons.timer,
        color: AppColors.infoBlue,
        title: 'Avg Completion Time',
        value: m.averageCompletionSeconds == null
            ? null
            : formatTripSeconds(m.averageCompletionSeconds!),
        detail: 'Over ${m.timedTrips} completed '
            '${m.timedTrips == 1 ? 'trip' : 'trips'}',
        expected: kCompletionTimeColumns,
        missing: m.missingForCompletionTime,
      ),
      _MetricCard(
        icon: Icons.thumb_up_alt,
        color: AppColors.successGreen,
        title: 'Average SUS Score',
        value: m.averageSus?.toStringAsFixed(1),
        detail: 'Over ${m.susResponses} '
            '${m.susResponses == 1 ? 'response' : 'responses'}',
        expected: kSusColumns,
        missing: m.missingForSus,
        note: m.susTableAvailable
            ? m.susNote
            : 'sus_responses table not found.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Navigation Evaluation',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          'From ${m.trips} ${m.trips == 1 ? 'trip' : 'trips'} in this range. '
          'A trip is the start and end rows sharing a trip_id; older rows '
          'without one are not counted.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final perRow = constraints.maxWidth > 900 ? 3 : 1;
            final width = (constraints.maxWidth - (perRow - 1) * 16) / perRow;
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
        const Text(
          'Errors per route step counts off-route events plus reroutes, so one '
          'deviation that is rerouted counts as 2. Off-route events is '
          'error_count minus reroute_count, which counts each deviation once. '
          'Trips logged before reroutes were added to error_count can show too '
          'few off-route events.\n'
          'Completion Rate is every completed trip. GPS-only arrivals leaves '
          'out manual arrivals, where the person said they had arrived.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ChartCard(
          title: 'AR vs 2D',
          height: 240,
          child: m.modes.isEmpty
              ? _EmptySplit(missing: m.missingForModeSplit)
              : _ModeSplit(metrics: m),
        ),
        const SizedBox(height: 16),
        _UserComparisonCard(comparison: m.comparison),
      ],
    );
  }
}

Widget _cell(String text, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    );

/// Visitors against verified users, on the same figures.
class _UserComparisonCard extends StatelessWidget {
  final UserComparison comparison;
  const _UserComparisonCard({required this.comparison});

  TableRow _row(GroupMetrics g) {
    String percent(double? rate) => rate == null ? '—' : formatPercent(rate);
    return TableRow(children: [
      _cell(g.label, bold: true),
      _cell('${g.trips}'),
      _cell(percent(g.completionRate)),
      _cell(g.averageSeconds == null
          ? '—'
          : formatTripSeconds(g.averageSeconds!)),
      _cell(percent(g.errorRate)),
      _cell(g.averageSus?.toStringAsFixed(1) ?? '—'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final other = comparison.otherSignedInTrips;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Visitors vs Verified Users',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                for (final h in const [
                  'Group',
                  'Trips',
                  'Completion rate',
                  'Avg time',
                  'Errors/step',
                  'Avg SUS',
                ])
                  _cell(h, bold: true),
              ]),
              _row(comparison.visitors),
              _row(comparison.verified),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Visitor = no user_id. Verified = signed in with is_verified '
            'true.'
            '${other == 0 ? '' : ' $other ${other == 1 ? 'trip' : 'trips'} by '
                'signed-in accounts that are not verified '
                '${other == 1 ? 'is' : 'are'} in neither group.'}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The columns line under a metric with no value.
String _columnsNote(List<String> expected, List<String> missing) {
  final base = 'Expected columns: ${expected.join(', ')}.';
  return missing.isEmpty ? base : '$base Missing: ${missing.join(', ')}.';
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final String detail;
  final List<String> expected;
  final List<String> missing;
  final String? note;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
    required this.expected,
    required this.missing,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(hasValue ? value! : _noData,
              style: TextStyle(
                fontSize: hasValue ? 24 : 18,
                fontWeight: FontWeight.bold,
                color: hasValue ? AppColors.textPrimary : AppColors.textSecondary,
              )),
          const SizedBox(height: 4),
          Text(
            [
              if (hasValue) detail else _columnsNote(expected, missing),
              ?note,
            ].join(' '),
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptySplit extends StatelessWidget {
  final List<String> missing;
  const _EmptySplit({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(_noData,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(_columnsNote(kModeSplitColumns, missing),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ModeSplit extends StatelessWidget {
  final NavigationMetrics metrics;
  const _ModeSplit({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final modes = metrics.modes;
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: DonutChartView(points: [
            for (final m in modes) ChartPoint(m.label, m.trips.toDouble()),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(children: [
                  for (final h in const [
                    'Mode',
                    'Trips',
                    'Share',
                    'Completed',
                    'Avg time',
                    'Errors/step',
                    'Avg SUS',
                  ])
                    _cell(h, bold: true),
                ]),
                for (final m in modes)
                  TableRow(children: [
                    _cell(m.label, bold: true),
                    _cell('${m.trips}'),
                    _cell('${(m.share * 100).toStringAsFixed(1)}%'),
                    _cell('${m.completedTrips}'),
                    _cell(m.averageSeconds == null
                        ? '—'
                        : formatTripSeconds(m.averageSeconds!)),
                    _cell(m.errorRate == null
                        ? '—'
                        : formatPercent(m.errorRate!)),
                    _cell(m.averageSus?.toStringAsFixed(1) ?? '—'),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
