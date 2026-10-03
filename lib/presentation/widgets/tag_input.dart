import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';

/// A labeled input that turns submitted text into removable maroon pills.
class TagInput extends StatefulWidget {
  final String label;
  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;
  final String? hint;

  const TagInput({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialTags = const [],
    this.hint,
  });

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  late List<String> _tags;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final value = raw.trim();
    if (value.isEmpty || _tags.contains(value)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tags.add(value);
      _controller.clear();
    });
    widget.onChanged(_tags);
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? AppColors.accentGold
                  : AppColors.border,
              width: _focusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in _tags)
                Chip(
                  label: Text(
                    tag,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: AppColors.primaryMaroon,
                  deleteIconColor: Colors.white70,
                  onDeleted: () => _removeTag(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.backspace &&
                        _controller.text.isEmpty &&
                        _tags.isNotEmpty) {
                      _removeTag(_tags.last);
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmitted: _addTag,
                    onTapOutside: (_) => _focusNode.unfocus(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: widget.hint ?? 'Type and press Enter',
                      hintStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
