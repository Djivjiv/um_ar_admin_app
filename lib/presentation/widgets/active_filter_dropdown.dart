import 'package:flutter/material.dart';

import '../../data/repositories/paged_query.dart';

/// The Status filter on list screens. Inactive rows only show when the admin
/// picks them here.
class ActiveFilterDropdown extends StatelessWidget {
  final ActiveFilter value;
  final ValueChanged<ActiveFilter> onChanged;
  final String label;

  const ActiveFilterDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Status',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<ActiveFilter>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(isDense: true, labelText: label),
        items: [
          for (final f in ActiveFilter.values)
            DropdownMenuItem(value: f, child: Text(f.label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
