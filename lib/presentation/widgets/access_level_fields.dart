import 'package:flutter/material.dart';

import '../../domain/models/access_level.dart';

/// The Access filter on list screens. Null means every level.
class AccessLevelFilterDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const AccessLevelFilterDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration:
            const InputDecoration(isDense: true, labelText: 'Access'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final level in kAccessLevels)
            DropdownMenuItem<String?>(
              value: level,
              child: Text(accessLevelLabel(level),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// The Access Level picker on the room and facility forms.
class AccessLevelField extends StatelessWidget {
  final String value;

  /// The saved value, kept as a choice even if it is older free text.
  final String? stored;
  final ValueChanged<String> onChanged;

  const AccessLevelField({
    super.key,
    required this.value,
    required this.stored,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Access Level',
        helperMaxLines: 2,
        // The mobile AR card prints any value it doesn't treat as open.
        helperText: value == kDefaultAccessLevel
            ? null
            : 'The mobile AR card will show this as "Access: $value".',
      ),
      items: [
        for (final level in accessLevelOptions(stored))
          DropdownMenuItem(
            value: level,
            child:
                Text(accessLevelLabel(level), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
