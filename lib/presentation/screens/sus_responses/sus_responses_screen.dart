import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/excel_export.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/analytics_repository.dart' show ChartPoint;
import '../../../data/repositories/survey_question_repository.dart';
import '../../../data/repositories/sus_repository.dart';
import '../../../domain/models/survey_question_model.dart';
import '../../../domain/models/sus_response_model.dart';
import '../../widgets/charts.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/stat_card.dart';

const _scaleOptions = [5, 7, 10];

class SusResponsesScreen extends StatefulWidget {
  const SusResponsesScreen({super.key});

  @override
  State<SusResponsesScreen> createState() => _SusResponsesScreenState();
}

class _SusData {
  final List<SusResponseModel> responses;
  final double average;
  final List<ChartPoint> distribution;
  final List<ChartPoint> byUserType;
  final List<SurveyQuestionModel> questions;

  _SusData({
    required this.responses,
    required this.average,
    required this.distribution,
    required this.byUserType,
    required this.questions,
  });
}

class _SusResponsesScreenState extends State<SusResponsesScreen> {
  final _repo = SusRepository();
  final _questionRepo = SurveyQuestionRepository();
  late Future<_SusData> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SusData> _load() async {
    final results = await Future.wait([
      _repo.getAll(),
      _repo.getAverageScore(),
      _repo.getScoreDistribution(),
      _repo.getScoreByUserType(),
      _questionRepo.getAll(),
    ]);
    return _SusData(
      responses: results[0] as List<SusResponseModel>,
      average: results[1] as double,
      distribution: results[2] as List<ChartPoint>,
      byUserType: results[3] as List<ChartPoint>,
      questions: results[4] as List<SurveyQuestionModel>,
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final rows = await _repo.exportRows();
      final path = await saveExcelFile('sus_responses', 'SUS Responses', rows);
      if (mounted) {
        context.showSuccess(
            path == null ? 'Export cancelled' : 'Saved to $path');
      }
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editQuestion(SurveyQuestionModel q) async {
    final updated = await showDialog<SurveyQuestionModel>(
      context: context,
      builder: (_) => _EditQuestionDialog(question: q),
    );
    if (updated == null) return;
    try {
      await _questionRepo.update(updated);
      if (mounted) context.showSuccess('Question ${q.questionNumber} updated');
      _reload();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  void _showAnswers(SusResponseModel r, List<SurveyQuestionModel> questions) {
    String textFor(int i) {
      final match = questions.where((q) => q.questionNumber == i);
      return match.isNotEmpty ? match.first.questionText : 'Question $i';
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:
            Text('Response · Score ${r.susScore?.toStringAsFixed(1) ?? '—'}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 10; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Q$i. ${textFor(i)}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      '${r.answerFor(i) ?? '—'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SusData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
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
        final d = snapshot.data!;
        final count = d.responses.length;
        final passing =
            d.responses.where((r) => (r.susScore ?? 0) >= 68).length;
        final grade = _grade(d.average);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('SUS Responses',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SurveyQuestionsCard(
                questions: d.questions,
                onEdit: _editQuestion,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final perRow = constraints.maxWidth > 1100
                      ? 4
                      : constraints.maxWidth > 640
                          ? 2
                          : 1;
                  final width =
                      (constraints.maxWidth - (perRow - 1) * 16) / perRow;
                  final cards = [
                    StatCard(
                      icon: Icons.assignment_turned_in,
                      title: 'Total Responses',
                      value: '$count',
                      iconColor: AppColors.primaryMaroon,
                    ),
                    StatCard(
                      icon: Icons.analytics,
                      title: 'Average Score',
                      value: d.average.toStringAsFixed(1),
                      iconColor: AppColors.infoBlue,
                    ),
                    StatCard(
                      icon: Icons.grade,
                      title: 'Grade',
                      value: grade,
                      iconColor: AppColors.accentGold,
                    ),
                    StatCard(
                      icon: Icons.thumb_up,
                      title: 'Passing (≥68)',
                      value: count == 0
                          ? '0%'
                          : '${(passing / count * 100).toStringAsFixed(0)}%',
                      iconColor: AppColors.successGreen,
                    ),
                  ];
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final c in cards)
                        SizedBox(width: width, child: c),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final two = constraints.maxWidth > 900;
                  final a = ChartCard(
                    title: 'Score Distribution',
                    child: BarChartView(points: d.distribution),
                  );
                  final b = ChartCard(
                    title: 'Average Score by User Type',
                    child: BarChartView(
                        points: d.byUserType, color: AppColors.infoBlue),
                  );
                  if (!two) {
                    return Column(
                        children: [a, const SizedBox(height: 16), b]);
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
              const SizedBox(height: 16),
              SizedBox(
                height: 420,
                child: DataTableCard(
                  title: 'Individual Responses',
                  columns: const [
                    DataColumn2(label: Text('Submitted'), size: ColumnSize.L),
                    DataColumn2(label: Text('User Type'), size: ColumnSize.M),
                    DataColumn2(label: Text('Score'), size: ColumnSize.S),
                    DataColumn2(label: Text(''), size: ColumnSize.S),
                  ],
                  rows: [
                    for (final r in d.responses)
                      DataRow2(
                        onTap: () => _showAnswers(r, d.questions),
                        cells: [
                          DataCell(Text(r.submittedAt != null
                              ? DateFormat('MMM d, y h:mm a')
                                  .format(r.submittedAt!)
                              : '—')),
                          DataCell(Text(r.userType ?? '—')),
                          DataCell(Text(
                              r.susScore?.toStringAsFixed(1) ?? '—',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                          DataCell(TextButton(
                            onPressed: () => _showAnswers(r, d.questions),
                            child: const Text('View'),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _grade(double score) {
    if (score >= 80.3) return 'A';
    if (score >= 74) return 'B';
    if (score >= 68) return 'C';
    if (score >= 51) return 'D';
    return 'F';
  }
}

class _SurveyQuestionsCard extends StatelessWidget {
  final List<SurveyQuestionModel> questions;
  final ValueChanged<SurveyQuestionModel> onEdit;

  const _SurveyQuestionsCard({required this.questions, required this.onEdit});

  @override
  Widget build(BuildContext context) {
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
              const Text('Survey Questions',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('(${questions.length})',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Statements shown to respondents in the mobile SUS survey.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text('${q.questionNumber}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryMaroon)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(q.questionText,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundGray,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('1–${q.scale}',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary)),
                  ),
                  IconButton(
                    tooltip: 'Edit Question',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: () => onEdit(q),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EditQuestionDialog extends StatefulWidget {
  final SurveyQuestionModel question;
  const _EditQuestionDialog({required this.question});

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  late final TextEditingController _text;
  late int _scale;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.question.questionText);
    _scale = _scaleOptions.contains(widget.question.scale)
        ? widget.question.scale
        : 5;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Question ${widget.question.questionNumber}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Question text',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _text,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter the survey statement…',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Rating Scale',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _scale,
                  items: [
                    for (final s in _scaleOptions)
                      DropdownMenuItem(value: s, child: Text('1 – $s')),
                  ],
                  onChanged: (v) => setState(() => _scale = v ?? _scale),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final text = _text.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(
              context,
              widget.question.copyWith(questionText: text, scale: _scale),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
