import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class FormInput extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? initialValue;
  final int maxLines;
  final bool required;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const FormInput({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.initialValue,
    this.maxLines = 1,
    this.required = false,
    this.keyboardType,
    this.onChanged,
    this.validator,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: RichText(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.errorRed),
                  ),
              ],
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          validator: validator ??
              (required
                  ? (v) => (v == null || v.trim().isEmpty)
                      ? '$label is required'
                      : null
                  : null),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
