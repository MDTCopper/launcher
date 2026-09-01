import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:flutter/material.dart';

/// 通用标签输入对话框：title / label / 默认值 / 校验器
///
/// 用于录入版本 tag、目录（分类）名称等；[validate] 返回错误文案或 null，
/// 输入中实时校验，确定按钮在校验通过前不可提交
class TagInputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String defaultText;
  final String? Function(String tag) validate;

  const TagInputDialog({
    super.key,
    required this.title,
    required this.label,
    required this.defaultText,
    required this.validate,
  });

  @override
  State<TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<TagInputDialog> {
  late final TextEditingController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.defaultText);
    error = widget.validate(controller.text);
    controller.addListener(() {
      setState(() => error = widget.validate(controller.text));
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black,
        child: Container(
          width: 400,
          padding: EdgeInsets.all(8),
          constraints: BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: 8,
                children: [
                  ReboundButton(
                    child: Icon(Icons.arrow_back_ios_new),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              OutlinedTextField(
                label: widget.label,
                error: error,
                controller: controller,
              ),
              IconTextButton(
                icon: Icons.check,
                content: '确定',
                onTap: () {
                  if (error != null) return;
                  Navigator.of(context).pop(controller.text);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}