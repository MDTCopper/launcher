import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/java_download_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/util/io/java/java_downloader.dart';
import 'package:flutter/material.dart';

///打开 Java 版本选择对话框，选中后创建 [JavaDownloadTask] 下载。
///
///[recommendedVersion] 为当前选中版本推荐的 Java 主版本，选中默认值并高亮提示。
Future<void> showJavaDownloadDialog(
  BuildContext context, {
  int? recommendedVersion,
}) {
  return showAnimatedDialog(
    context: context,
    pageBuilder: (context, _, _) =>
        _JavaDownloadDialog(recommendedVersion: recommendedVersion),
  );
}

class _JavaDownloadDialog extends StatefulWidget {
  final int? recommendedVersion;

  const _JavaDownloadDialog({this.recommendedVersion});

  @override
  State<StatefulWidget> createState() => _JavaDownloadDialogState();
}

class _JavaDownloadDialogState extends State<_JavaDownloadDialog> {
  ///可选版本列表（从 Adoptium 拉取，失败回退固定列表）
  List<int>? _versions;

  int? _selectedVersion;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final versions = await JavaDownloader.getAvailableVersions();
    if (!mounted) return;
    setState(() {
      _versions = versions;
      //默认选中推荐版本；不在列表时取最大版本
      _selectedVersion ??= versions.contains(widget.recommendedVersion)
          ? widget.recommendedVersion
          : versions.last;
    });
  }

  void _startDownload() {
    final version = _selectedVersion;
    if (version == null) return;
    Navigator.of(context).pop();
    addTask(JavaDownloadTask(version: version));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Row(
              spacing: 8,
              children: [
                ReboundButton(
                  child: Icon(Icons.arrow_back_ios_new),
                  onTap: () => Navigator.of(context).pop(),
                ),
                Text(
                  '下载Java',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (_versions == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              )
            else ...[
              DropdownLayer<int>(
                width: double.infinity,
                initialValue: _selectedVersion,
                onSelect: (value) => setState(() => _selectedVersion = value),
                options: [
                  for (final version in _versions!)
                    DropdownOption(value: version, label: 'Java $version'),
                ],
              ),
              if (widget.recommendedVersion != null)
                Row(
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.recommend_outlined,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    Text('当前版本推荐 Java ${widget.recommendedVersion}'),
                  ],
                ),
              Align(
                alignment: Alignment.center,
                child: ReboundButton(
                  pressedScale: 0.95,
                  elevation: 2,
                  hoverElevation: 4,
                  onTap: _startDownload,
                  child: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 30,
                          color: theme.colorScheme.secondary,
                        ),
                        Text(
                          '开始下载',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Center(child: child);
  }
}
