import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/floor_scale.dart';
import '../../../data/repositories/floor_distance_repository.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../../domain/models/indoor_node_model.dart';

const kMeasureHint = 'Measure in a straight line between the two nodes.';

/// The Check distance panel, beside the plan so a tapped row's nodes can be
/// seen. Everything shown comes from the arguments.
class FloorDistancePanel extends StatelessWidget {
  final FloorPlanModel plan;
  final FloorScaleSummary summary;
  final List<EdgeDistanceLine> edges;
  final List<IndoorNodeModel> nodes;

  /// The table hasn't been created yet; edges still show.
  final bool tableMissing;

  /// Disables the actions while something saves.
  final bool busy;
  final String? selectedId;

  /// Measurements whose nodes the admin moved in the last save.
  final Set<String> movedIds;
  final VoidCallback onClose;
  final VoidCallback onSaveScale;
  final ValueChanged<MeasurementLine> onSelect;
  final ValueChanged<MeasurementLine> onEdit;
  final ValueChanged<MeasurementLine> onDelete;
  final void Function(MeasurementLine line, bool ignored) onIgnore;

  const FloorDistancePanel({
    super.key,
    required this.plan,
    required this.summary,
    required this.edges,
    required this.nodes,
    this.tableMissing = false,
    this.busy = false,
    this.selectedId,
    this.movedIds = const {},
    required this.onClose,
    required this.onSaveScale,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onIgnore,
  });

  String _name(String id) {
    for (final n in nodes) {
      if (n.id == id) return nodeDisplayName(n, id);
    }
    return id;
  }

  /// The measurements point to a different scale than the floor holds: the
  /// scale was typed in by hand, or a save failed.
  bool get _scaleIsStale =>
      summary.metersPerPixel != null &&
      summary.metersPerPixel != plan.metersPerPixel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Check distance',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _section('Measurements'),
                if (tableMissing)
                  _notice(kFloorDistancesMissingMessage, AppColors.errorRed)
                else ...[
                  _summaryBlock(),
                  const SizedBox(height: 8),
                  if (summary.lines.isEmpty)
                    const Text('No measurements on this floor yet.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  for (final line in summary.lines) _measurementRow(line),
                ],
                const SizedBox(height: 16),
                _section('Connected nodes'),
                if (edges.isEmpty)
                  const Text('No edges on this floor yet.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                for (final line in edges) _edgeRow(line),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _notice(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );

  Widget _summaryBlock() {
    final spread = summary.spreadPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Counted measurements: ${summary.counted}',
            style: const TextStyle(fontSize: 12)),
        Text(
          'Scale: ${summary.metersPerPixel == null ? plan.scaleLabel : '${summary.metersPerPixel} m/px'}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          'Spread: ${spread == null ? '—' : '${spread.toStringAsFixed(1)}%'}',
          style: const TextStyle(fontSize: 12),
        ),
        if (summary.counted == 0)
          _notice(unchangedScaleNote(plan), AppColors.textSecondary),
        for (final warning in summary.warnings)
          _notice(warning, AppColors.warningAmber),
        if (_scaleIsStale) ...[
          _notice(
            'The floor holds ${plan.scaleLabel}, but these measurements give '
            '${summary.metersPerPixel} m/px.',
            AppColors.warningAmber,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: busy ? null : onSaveScale,
              child: const Text('Save this scale'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _measurementRow(MeasurementLine line) {
    final m = line.measurement;
    final selected = m.id == selectedId;
    final pixels = line.pixels;
    final scale = line.scale;
    final difference = line.differencePercent;
    final faded = line.counted ? AppColors.textPrimary : AppColors.textSecondary;
    return Container(
      key: ValueKey('measurement-${m.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentGold.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () => onSelect(line),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_name(m.nodeAId)} ↔ ${_name(m.nodeBId)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: faded)),
              const SizedBox(height: 2),
              Text(
                '${m.realMeters} m · '
                '${pixels == null ? 'no position' : '${pixels.toStringAsFixed(0)} px'} · '
                '${scale == null ? 'no scale' : '${scale.toStringAsFixed(5)} m/px'}',
                style: TextStyle(fontSize: 11, color: faded),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (difference != null)
                    _chip(
                      '${difference >= 0 ? '+' : ''}'
                      '${difference.toStringAsFixed(1)}%',
                      line.isOutlier
                          ? AppColors.errorRed
                          : AppColors.textSecondary,
                      key: line.isOutlier
                          ? ValueKey('outlier-${m.id}')
                          : null,
                    ),
                  if (m.ignored) _chip('Ignored', AppColors.textSecondary),
                  if (line.tooClose)
                    _chip('Too close to count', AppColors.warningAmber),
                  if (movedIds.contains(m.id))
                    _chip('Node moved', AppColors.warningAmber),
                ],
              ),
              Row(
                children: [
                  const Text('Ignore', style: TextStyle(fontSize: 11)),
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: m.ignored,
                      onChanged: busy ? null : (v) => onIgnore(line, v),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: busy ? null : () => onEdit(line),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: AppColors.errorRed),
                    onPressed: busy ? null : () => onDelete(line),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _edgeRow(EdgeDistanceLine line) {
    final e = line.edge;
    final meters = line.meters;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_name(e.fromNode)} ${e.isTwoWay ? '↔' : '→'} ${_name(e.toNode)}',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (meters == null)
                const Text('No length: one end is off this floor plan',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary))
              else ...[
                Text('${meters.toStringAsFixed(1)} m',
                    style: const TextStyle(fontSize: 11)),
                _chip('calculated', AppColors.textSecondary),
                if (!plan.isScaleCalibrated)
                  _chip('not calibrated yet', AppColors.warningAmber),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the real distance between two nodes. Pops it, or null on cancel.
class MeasurementDialog extends StatefulWidget {
  final String nameA;
  final String nameB;
  final double pixels;

  /// The current value, when editing.
  final double? initialMeters;

  const MeasurementDialog({
    super.key,
    required this.nameA,
    required this.nameB,
    required this.pixels,
    this.initialMeters,
  });

  @override
  State<MeasurementDialog> createState() => _MeasurementDialogState();
}

class _MeasurementDialogState extends State<MeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _meters =
      TextEditingController(text: widget.initialMeters?.toString() ?? '');

  @override
  void dispose() {
    _meters.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, double.parse(_meters.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.initialMeters == null ? 'Add distance' : 'Edit distance'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${widget.nameA} ↔ ${widget.nameB}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              Text('${widget.pixels.toStringAsFixed(0)} px apart on the plan',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _meters,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Real distance (meters)'),
                validator: (v) => validateRealMeters(v, widget.pixels),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              const Text(kMeasureHint,
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
