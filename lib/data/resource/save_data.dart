import 'campaign_data.dart';
import 'map_save.dart';
import 'mod.dart';
import 'schematic.dart';

///下面的数据类通过源文件实时解析
class SaveData {
  String path;

  List<Mod>? mods;

  List<MapSave>? maps;

  List<Schematic>? schematics;

  CampaignData? campaignData;

  SaveData({required this.path});
}
