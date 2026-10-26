import 'package:flutter/material.dart';

import '../../data/models.dart';

/// 把站点要求的表单字段渲染成原生输入项，确认后返回提交值。
Future<Map<String, String>?> showSiteFormDialog(
  BuildContext context, {
  required String title,
  required List<MagicFormField> fields,
  String description = '',
  String confirmText = '确认',
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _SiteFormDialog(
      title: title,
      fields: fields,
      description: description,
      confirmText: confirmText,
    ),
  );
}

class _SiteFormDialog extends StatefulWidget {
  const _SiteFormDialog({
    required this.title,
    required this.fields,
    required this.description,
    required this.confirmText,
  });

  final String title;
  final List<MagicFormField> fields;
  final String description;
  final String confirmText;

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _choices = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        _controllers[field.name] = TextEditingController(text: field.value);
      } else if (field.options.isNotEmpty) {
        _choices[field.name] = field.options
            .firstWhere((option) => option.value == field.value, orElse: () => field.options.first)
            .value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = <String, String>{};
    for (final field in widget.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        values[field.name] = _controllers[field.name]?.text.trim() ?? '';
      } else {
        values[field.name] = _choices[field.name] ?? field.value;
      }
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description.isNotEmpty) ...[
              Text(
                widget.description,
                style: TextStyle(fontSize: 12, height: 1.45, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.fields.isEmpty)
              Text(
                '确认后立即提交到站点。',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
              ),
            for (final field in widget.fields) ...[
              if (field.label.isNotEmpty) ...[
                Text(
                  field.label,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
              ],
              _fieldInput(field),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }

  Widget _fieldInput(MagicFormField field) {
    switch (field.type) {
      case MagicFieldType.text:
        final numeric = field.name.contains('id') || field.name.contains('tid');
        return TextField(
          controller: _controllers[field.name],
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            hintText: field.label.isEmpty ? field.name : field.label,
            border: const OutlineInputBorder(),
          ),
        );
      case MagicFieldType.textarea:
        return TextField(
          controller: _controllers[field.name],
          maxLines: 3,
          decoration: InputDecoration(
            isDense: true,
            hintText: field.label.isEmpty ? field.name : field.label,
            border: const OutlineInputBorder(),
          ),
        );
      case MagicFieldType.radio:
        final selected = _choices[field.name] ?? field.value;
        return SegmentedButton<String>(
          segments: [
            for (final option in field.options)
              ButtonSegment(value: option.value, label: Text(option.label)),
          ],
          selected: {selected},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (value) => setState(() => _choices[field.name] = value.first),
        );
      case MagicFieldType.select:
        return DropdownButtonFormField<String>(
          initialValue: _choices[field.name],
          isDense: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _choices[field.name] = value);
          },
        );
    }
  }
}
