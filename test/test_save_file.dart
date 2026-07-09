import 'dart:io';

import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/util/io/mindustry_save_file/save_file_codec.dart';

void main() {
  // 测试 .msav
  final msavPath = r'C:\Users\ASUS\AppData\Roaming\Mindustry\finalCampaign\saves\0.msav';
  final msavFile = File(msavPath);
  if (msavFile.existsSync()) {
    print('=== Testing .msav ===');
    try {
      final map = MapSave.fromFile(msavPath);

      print('wave: ${map.wave}');
      print('playtime: ${map.playtime}ms');
      print('build: ${map.build}');
      print('mods: ${map.mods}');
      print('saved: ${DateTime.fromMillisecondsSinceEpoch(map.saved)}');
      print('rules length: ${map.rules.length}');
      print('OK!');
    } catch (e, s) {
      print('FAIL: $e');
    }
  }

  // 测试 .msch
  final mschPath = r'C:\Users\ASUS\AppData\Roaming\Mindustry\finalCampaign\saves\bleeding-edge\schematics\5钍反.msch';
  final mschFile = File(mschPath);
  if (mschFile.existsSync()) {
    print('\n=== Testing .msch ===');
    try {
      final schem = Schematic.fromFile(mschPath);
      print('description: ${schem.description}');
      print('size: ${schem.width}x${schem.height}');
      print('tiles: ${schem.tileCount}');
      print('labels: ${schem.labels}');
      print('OK!');
    } catch (e, s) {
      print('FAIL: $e');
    }
  }
}
