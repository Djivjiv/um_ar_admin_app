import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/announcement_model.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';

const _maroon = AppColors.primaryMaroon;
const _gold = AppColors.accentGold;
const _blue = AppColors.infoBlue;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repo = DashboardRepository();

  late Future<DashboardTopStats> _topStats;
  late Future<DailySeries> _series;
  late Future<SusSummary> _sus;
  late Future<List<CommentEntry>> _comments;
  late Future<List<BuildingVisit>> _mostVisited;
  late Future<List<AnnouncementModel>> _announcements;
  late Future<SystemStatus> _status;

  int _rangeDays = 7;
  DateTime _commentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _topStats = _repo.getTopStats();
    _series = _repo.getDailySeries(_rangeDays);
    _sus = _repo.getSusSummary();
    _comments = _repo.getComments(_commentDate);
    _mostVisited = _repo.getMostVisited();
    _announcements = _repo.getRecentAnnouncements();
    _status = _repo.getSystemStatus();
  }

  void _setRange(int days) {
    setState(() {
      _rangeDays = days;
      _series = _repo.getDailySeries(days);
    });
  }

  Future<void> _pickCommentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _commentDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _commentDate = picked;
      _comments = _repo.getComments(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row1(),
          const SizedBox(height: 16),
          _row2(),
          const SizedBox(height: 16),
          _row3(),
          const SizedBox(height: 16),
          _row4(),
          const SizedBox(height: 16),
          _row5(),
        ],
      ),
    );
  }

  // ---- ROW 1 -----------------------------------------------------------

  Widget _row1() {
    return FutureBuilder<DashboardTopStats>(
      future: _topStats,
      builder: (context, snap) {
        final s = snap.data ?? const DashboardTopStats();
        final loading = snap.connectionState == ConnectionState.waiting;
        final error = snap.hasError ? snap.error : null;
        final cards = <Widget>[
          StatCard(
            icon: Icons.school,
            title: 'Total Users',
            value: loading ? '—' : '${s.students}',
            subtitle: 'Students',
          ),
          StatCard(
            icon: Icons.verified_user,
            title: 'Registered Accounts',
            value: loading ? '—' : '${s.registeredAccounts}',
            subtitle: 'Verified',
            iconColor: _maroon,
          ),
          StatCard(
            icon: Icons.travel_explore,
            title: 'Active Visitors',
            value: loading ? '—' : '${s.activeVisitors}',
            subtitle: 'Sessions live',
            iconColor: _maroon,
          ),
          StatCard(
            icon: Icons.groups,
            title: 'Active Users',
            value: loading ? '—' : '${s.activeUsers}',
            subtitle: 'Accounts + visitors',
            iconColor: _maroon,
          ),
          StatCard(
            icon: Icons.tv,
            title: 'Kiosk Users',
            value: loading ? '—' : '${s.kioskUsers}',
            subtitle: 'Kiosk sessions',
            iconColor: _maroon,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) _inlineError(error),
            _equalRow(cards),
          ],
        );
      },
    );
  }

  // ---- ROW 2 -----------------------------------------------------------

  Widget _row2() {
    return _responsivePair(
      leftFlex: 60,
      rightFlex: 40,
      left: _Panel(
        title: 'Daily Activity',
        trailing: _RangeDropdown(days: _rangeDays, onChanged: _setRange),
        child: SizedBox(
          height: 280,
          child: FutureBuilder<DailySeries>(
            future: _series,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _inlineError(snap.error!);
              final data = snap.data ?? const DailySeries();
              if (data.isEmpty) return _emptyChart();
              return Column(
                children: [
                  Expanded(child: _DailyLineChart(data: data)),
                  const SizedBox(height: 8),
                  const _Legend(items: [
                    _LegendItem('Mobile sessions', _maroon),
                    _LegendItem('Visitor sessions', _gold),
                    _LegendItem('Kiosk sessions', _blue),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
      right: _Panel(
        title: 'User Distribution',
        child: SizedBox(
          height: 280,
          child: FutureBuilder<DailySeries>(
            future: _series,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _inlineError(snap.error!);
              final data = snap.data ?? const DailySeries();
              if (data.isEmpty) return _emptyChart();
              return Column(
                children: [
                  Expanded(child: _GroupedBarChart(data: data)),
                  const SizedBox(height: 8),
                  const _Legend(items: [
                    _LegendItem('Registered', _maroon),
                    _LegendItem('Visitors', _gold),
                    _LegendItem('Kiosk', _blue),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- ROW 3 -----------------------------------------------------------

  Widget _row3() {
    return FutureBuilder<SusSummary>(
      future: _sus,
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? const SusSummary();
        final grade = s.grade;
        final gradeColor = switch (grade) {
          'Excellent' => AppColors.successGreen,
          'Good' => _gold,
          'Marginal' => AppColors.warningAmber,
          _ => AppColors.errorRed,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snap.hasError) _inlineError(snap.error!),
            _equalRow([
              StatCard(
                icon: Icons.assignment_turned_in,
                title: 'Survey Responses',
                value: loading ? '—' : '${s.totalResponses}',
                subtitle: 'App + kiosk',
                iconColor: _maroon,
              ),
              StatCard(
                icon: Icons.analytics,
                title: 'Average SUS Score',
                value: loading ? '—' : s.averageScore.toStringAsFixed(1),
                subtitle: 'out of 100',
                iconColor: _maroon,
              ),
              _GradeCard(
                grade: loading ? '—' : grade,
                color: gradeColor,
                score: s.averageScore,
              ),
            ]),
          ],
        );
      },
    );
  }

  // ---- ROW 4 -----------------------------------------------------------

  Widget _row4() {
    return _responsivePair(
      leftFlex: 60,
      rightFlex: 40,
      left: _Panel(
        title: 'SUS Score Distribution',
        child: SizedBox(
          height: 280,
          child: FutureBuilder<SusSummary>(
            future: _sus,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _inlineError(snap.error!);
              final s = snap.data ?? const SusSummary();
              return _SusDistributionChart(summary: s);
            },
          ),
        ),
      ),
      right: _Panel(
        title: 'User Comments & Suggestions',
        trailing: TextButton.icon(
          onPressed: _pickCommentDate,
          icon: const Icon(Icons.calendar_today, size: 15),
          label: Text(DateFormat('MMM d, y').format(_commentDate)),
        ),
        child: SizedBox(
          height: 280,
          child: FutureBuilder<List<CommentEntry>>(
            future: _comments,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _inlineError(snap.error!);
              final comments = snap.data ?? const [];
              if (comments.isEmpty) {
                return const Center(
                  child: Text('No comments for this date',
                      style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return ListView.separated(
                itemCount: comments.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (context, i) => _CommentTile(comments[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- ROW 5 -----------------------------------------------------------

  Widget _row5() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 1000;
        final panels = [
          _Panel(
            title: 'Most Visited Buildings',
            child: FutureBuilder<List<BuildingVisit>>(
              future: _mostVisited,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _PanelLoading();
                }
                if (snap.hasError) return _inlineError(snap.error!);
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const _PanelEmpty('No navigation data yet');
                }
                final max = items.first.count;
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _RankRow(
                        rank: i + 1,
                        name: items[i].name,
                        count: items[i].count,
                        fraction: max == 0 ? 0 : items[i].count / max,
                      ),
                  ],
                );
              },
            ),
          ),
          _Panel(
            title: 'Recent Announcements',
            child: FutureBuilder<List<AnnouncementModel>>(
              future: _announcements,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _PanelLoading();
                }
                if (snap.hasError) return _inlineError(snap.error!);
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const _PanelEmpty('No announcements');
                }
                return Column(
                  children: [
                    for (final a in items) _AnnouncementRow(a),
                  ],
                );
              },
            ),
          ),
          _Panel(
            title: 'System Status',
            child: FutureBuilder<SystemStatus>(
              future: _status,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _PanelLoading();
                }
                if (snap.hasError) return _inlineError(snap.error!);
                final s = snap.data ?? const SystemStatus();
                return Column(
                  children: [
                    _StatusRow.dot('Supabase connection', s.supabaseOk),
                    _StatusRow.dot('MapTiler API', s.mapTilerOk),
                    _StatusRow.value(
                        'Total Buildings', '${s.totalBuildings}'),
                    _StatusRow.value(
                        'Total Outdoor Nodes', '${s.totalOutdoorNodes}'),
                    _StatusRow.value(
                        'Total Indoor Nodes', '${s.totalIndoorNodes}'),
                    _StatusRow.value(
                        'Total Floor Plans', '${s.totalFloorPlans}'),
                    _StatusRow.value(
                      'Last data update',
                      s.lastDataUpdate == null
                          ? '—'
                          : DateFormat('MMM d, y h:mm a')
                              .format(s.lastDataUpdate!),
                    ),
                  ],
                );
              },
            ),
          ),
        ];
        if (!wide) {
          return Column(
            children: [
              for (final p in panels) ...[p, const SizedBox(height: 16)],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: panels[0]),
              const SizedBox(width: 16),
              Expanded(child: panels[1]),
              const SizedBox(width: 16),
              Expanded(child: panels[2]),
            ],
          ),
        );
      },
    );
  }

  // ---- shared helpers -------------------------------------------------

  Widget _equalRow(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth > 1180
            ? cards.length
            : constraints.maxWidth > 820
                ? 3
                : constraints.maxWidth > 520
                    ? 2
                    : 1;
        final width =
            (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in cards) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }

  Widget _responsivePair({
    required Widget left,
    required Widget right,
    required int leftFlex,
    required int rightFlex,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: 16),
              Expanded(flex: rightFlex, child: right),
            ],
          ),
        );
      },
    );
  }

  Widget _inlineError(Object error) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(error.toString(),
          style: const TextStyle(color: AppColors.errorRed, fontSize: 12)),
    );
  }

  Widget _emptyChart() => const Center(
        child: Text('No data available',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}

// ===========================================================================
// Panels & small widgets
// ===========================================================================

class _Panel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _Panel({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PanelLoading extends StatelessWidget {
  const _PanelLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _PanelEmpty extends StatelessWidget {
  final String message;
  const _PanelEmpty(this.message);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(message,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
}

class _RangeDropdown extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;

  const _RangeDropdown({required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: days,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: const [
        DropdownMenuItem(value: 7, child: Text('Last 7 Days')),
        DropdownMenuItem(value: 14, child: Text('Last 2 Weeks')),
        DropdownMenuItem(value: 30, child: Text('Last 1 Month')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _Legend extends StatelessWidget {
  final List<_LegendItem> items;
  const _Legend({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: item.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(item.label, style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);
}

class _GradeCard extends StatelessWidget {
  final String grade;
  final Color color;
  final double score;

  const _GradeCard(
      {required this.grade, required this.color, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.grade, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Score Grade',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(grade,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentEntry entry;
  const _CommentTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final isVisitor = entry.userType.toLowerCase().contains('visit');
    final pillColor = isVisitor ? _gold : _maroon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: pillColor.withValues(alpha: 0.15),
          child: Icon(isVisitor ? Icons.person_pin_circle : Icons.school,
              size: 16, color: pillColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: pillColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(entry.userType,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: pillColor)),
                  ),
                  const Spacer(),
                  Text(
                    entry.at == null
                        ? ''
                        : DateFormat('h:mm a').format(entry.at!),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(entry.text, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final String name;
  final int count;
  final double fraction;

  const _RankRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$rank',
                  style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.backgroundGray,
              valueColor: const AlwaysStoppedAnimation(_gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  final AnnouncementModel announcement;
  const _AnnouncementRow(this.announcement);

  IconData get _icon {
    switch ((announcement.type ?? '').toLowerCase()) {
      case 'emergency':
        return Icons.warning_amber_rounded;
      case 'event':
        return Icons.event;
      case 'maintenance':
        return Icons.build;
      default:
        return Icons.campaign;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: _maroon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(announcement.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  announcement.createdAt == null
                      ? ''
                      : DateFormat('MMM d, y').format(announcement.createdAt!),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(
            status: announcement.isExpired
                ? BadgeStatus.inactive
                : BadgeStatus.active,
            label: announcement.isExpired ? 'Expired' : 'Active',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool? ok;

  const _StatusRow._({required this.label, this.value, this.ok});

  factory _StatusRow.dot(String label, bool ok) =>
      _StatusRow._(label: label, ok: ok);

  factory _StatusRow.value(String label, String value) =>
      _StatusRow._(label: label, value: value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
          if (ok != null)
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        ok! ? AppColors.successGreen : AppColors.errorRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(ok! ? 'Connected' : 'Offline',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ok!
                            ? AppColors.successGreen
                            : AppColors.errorRed)),
              ],
            )
          else
            Text(value ?? '—',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Charts
// ===========================================================================

class _DailyLineChart extends StatelessWidget {
  final DailySeries data;
  const _DailyLineChart({required this.data});

  List<FlSpot> _spots(List<int> values) => [
        for (var i = 0; i < values.length; i++)
          FlSpot(i.toDouble(), values[i].toDouble()),
      ];

  @override
  Widget build(BuildContext context) {
    final allValues = [...data.mobile, ...data.visitor, ...data.kiosk];
    final maxY =
        allValues.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
    final step = (data.days.length / 6).ceil().clamp(1, 999);

    LineChartBarData bar(List<int> v, Color c) => LineChartBarData(
          spots: _spots(v),
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 3,
          dotData: const FlDotData(show: false),
        );

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= data.days.length) return const SizedBox();
                if (i % step != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('M/d').format(data.days[i]),
                      style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(
          touchTooltipData: LineTouchTooltipData(),
        ),
        lineBarsData: [
          bar(data.mobile, _maroon),
          bar(data.visitor, _gold),
          bar(data.kiosk, _blue),
        ],
      ),
    );
  }
}

class _GroupedBarChart extends StatelessWidget {
  final DailySeries data;
  const _GroupedBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final all = [...data.registered, ...data.visitor, ...data.kiosk];
    final maxY = all.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
    final step = (data.days.length / 6).ceil().clamp(1, 999);

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= data.days.length) return const SizedBox();
                if (i % step != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('M/d').format(data.days[i]),
                      style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.days.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                    toY: data.registered[i].toDouble(),
                    color: _maroon,
                    width: 5),
                BarChartRodData(
                    toY: data.visitor[i].toDouble(), color: _gold, width: 5),
                BarChartRodData(
                    toY: data.kiosk[i].toDouble(), color: _blue, width: 5),
              ],
            ),
        ],
      ),
    );
  }
}

class _SusDistributionChart extends StatelessWidget {
  final SusSummary summary;
  const _SusDistributionChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final bars = [
      ('Poor\n0-50', summary.poor, AppColors.errorRed),
      ('Marginal\n51-68', summary.marginal, AppColors.warningAmber),
      ('Good\n69-80', summary.good, _gold),
      ('Excellent\n81-100', summary.excellent, AppColors.successGreen),
    ];
    final maxY = bars
        .map((b) => b.$2)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.25,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 2,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${rod.toY.toInt()}',
              const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= bars.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(bars[i].$1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < bars.length; i++)
            BarChartGroupData(
              x: i,
              showingTooltipIndicators: [0],
              barRods: [
                BarChartRodData(
                  toY: bars[i].$2.toDouble(),
                  color: bars[i].$3,
                  width: 34,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
