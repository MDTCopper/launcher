import 'package:copper_launcher/ui/components/rebound/rebound_checkbox.dart';
import 'package:copper_launcher/ui/util/dialog/custom_animated_dialog.dart';
import 'package:flutter/material.dart';

import '../../../util/format/string_cleaner.dart';
import '../../../util/io/file_reader.dart';
import '../../feature/images.dart';
import 'appear_list_view.dart';
import 'feature_button.dart';
import 'feature_list_tile.dart';

bool isImporting = false;

Future<bool> showResourceImporter(List<String> files) async {
  if (isImporting) return true;
  if (files.isEmpty) return false;
  showDefaultDialogPopup(
    pageBuilder: (_, _, _) {
      return ResourceImporter(files: files);
    },
  );

  return false;
}

class ResourceImporter extends StatefulWidget {
  const ResourceImporter({super.key, required this.files});

  final List<String> files;

  @override
  State<ResourceImporter> createState() => ResourceImporterState();
}

class ResourceImporterState extends State<ResourceImporter> {
  final List<FileReader> importList = [];

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    for (var path in widget.files) {
      final reader = await FileReader.fromPath(path);
      if (reader.type == null) continue;
      importList.add(reader);
    }
    importList.sort((a, b) {
      if (a.type == ResourceType.mindustry) return -1;
      if (b.type == ResourceType.mindustry) return 1;
      if (a.type == ResourceType.mod) return -1;
      if (b.type == ResourceType.mod) return 1;
      if (a.type == ResourceType.mapSave) return -1;
      if (b.type == ResourceType.mapSave) return 1;
      if (a.type == ResourceType.schematic) return -1;
      if (b.type == ResourceType.schematic) return 1;
      return 0;
    });
    setState(() {});
  }

  var test = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ReboundButton(
              onTap: () {
                Navigator.pop(context);
              },
              child: Icon(Icons.arrow_back),
            ),
            SizedBox(width: 8),
            Text('导入本地资源', style: theme.textTheme.bodyLarge),
          ],
        ),
        SizedBox(height: 8),
        if (importList.isNotEmpty)
          Expanded(
            child: AppearListView(
              delay: 300,
              appearDuration: const Duration(milliseconds: 350),
              offset: Offset(-0.1, 0.0),
              items: importList.map((it) {
                final type = it.type;
                switch (type) {
                  case null:
                    return SizedBox();
                  case ResourceType.mindustry:
                    final m = it.mindustry!;
                    return ReboundListTile(
                      leading: Image.asset(Images.mindustry),
                      title: Text('Mindustry v${m.version}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('build ${m.build}  (${m.type})'),
                          Text('${m.path}'),
                        ],
                      ),
                      trailing: ReboundCheckChangeBox(value: test),
                      onTap: () {
                        setState(() {
                          test = !test;
                        });
                      },
                    );
                  case ResourceType.mod:
                    final mod = it.mod!;

                    Widget leading;
                    final icon = mod.icon;
                    if (icon == null) {
                      leading = Icon(Icons.question_mark, size: 64);
                    } else {
                      leading = Image.memory(icon, height: 64, width: 64);
                    }

                    return ReboundListTile(
                      leading: leading,
                      title: Text(
                        '模组  ${generalizeText(mod.name)}  |  作者  ${generalizeText(mod.author)}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '版本  ${mod.version}   |   minGameVersion ${mod.minGameVersion}',
                          ),
                          Text('${mod.path}'),
                        ],
                      ),

                      onTap: () {},
                    );
                  case ResourceType.mapSave:
                    final m = it.mapSave!;
                    return ReboundListTile(
                      leading: Icon(Icons.map_outlined, size: 64),
                      title: Text(
                        '地图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                      ),
                      subtitle: Text('${m.path}'),
                      onTap: () {},
                    );
                  case ResourceType.schematic:
                    final m = it.schematic!;
                    return ReboundListTile(
                      leading: Icon(Icons.paste, size: 64),
                      title: Text(
                        '蓝图  ${generalizeText(m.name)}  |  作者  ${generalizeText(m.author)}',
                      ),
                      subtitle: Text('${m.path}'),
                      onTap: () {},
                    );
                  case ResourceType.settings:
                    // TODO: Handle this case.
                    throw UnimplementedError();
                }
              }).toList(),
            ),
          ),
      ],
    );
  }
}
