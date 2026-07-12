// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mindustry_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MindustrySettingsPatch _$MindustrySettingsPatchFromJson(
  Map<String, dynamic> json,
) => MindustrySettingsPatch()
  ..saveInterval = (json['saveInterval'] as num?)?.toInt()
  ..autoTarget = json['autoTarget'] as bool?
  ..keyboard = json['keyboard'] as bool?
  ..crashReport = json['crashReport'] as bool?
  ..communityServers = json['communityServers'] as bool?
  ..saveCreate = json['saveCreate'] as bool?
  ..blockReplace = json['blockReplace'] as bool?
  ..conveyorPathfinding = json['conveyorPathfinding'] as bool?
  ..hints = json['hints'] as bool?
  ..logicHints = json['logicHints'] as bool?
  ..backgroundPause = json['backgroundPause'] as bool?
  ..buildAutoPause = json['buildAutoPause'] as bool?
  ..distinctControlGroups = json['distinctControlGroups'] as bool?
  ..doubleTapMine = json['doubleTapMine'] as bool?
  ..commandModeHold = json['commandModeHold'] as bool?
  ..modCrashDisable = json['modCrashDisable'] as bool?
  ..playerLimit = (json['playerLimit'] as num?)?.toInt()
  ..steamPublicHost = json['steamPublicHost'] as bool?
  ..console = json['console'] as bool?
  ..uiScale = (json['uiScale'] as num?)?.toInt()
  ..uiScaleChanged = json['uiScaleChanged'] as bool?
  ..screenShake = (json['screenShake'] as num?)?.toInt()
  ..bloomIntensity = (json['bloomIntensity'] as num?)?.toInt()
  ..bloomBlur = (json['bloomBlur'] as num?)?.toInt()
  ..fpsCap = (json['fpsCap'] as num?)?.toInt()
  ..chatOpacity = (json['chatOpacity'] as num?)?.toInt()
  ..lasersOpacity = (json['lasersOpacity'] as num?)?.toInt()
  ..preferredLaserOpacity = (json['preferredLaserOpacity'] as num?)?.toInt()
  ..unitLaserOpacity = (json['unitLaserOpacity'] as num?)?.toInt()
  ..bridgeOpacity = (json['bridgeOpacity'] as num?)?.toInt()
  ..maxMagnificationMultiplierPercent =
      (json['maxMagnificationMultiplierPercent'] as num?)?.toInt()
  ..maxZoomInGameMultiplier = (json['maxZoomInGameMultiplier'] as num?)
      ?.toDouble()
  ..minMagnificationMultiplierPercent =
      (json['minMagnificationMultiplierPercent'] as num?)?.toInt()
  ..minZoomInGameMultiplier = (json['minZoomInGameMultiplier'] as num?)
      ?.toDouble()
  ..vsync = json['vsync'] as bool?
  ..fullscreen = json['fullscreen'] as bool?
  ..borderlessWindow = json['borderlessWindow'] as bool?
  ..landscape = json['landscape'] as bool?
  ..effects = json['effects'] as bool?
  ..atmosphere = json['atmosphere'] as bool?
  ..drawLight = json['drawLight'] as bool?
  ..destroyedBlocks = json['destroyedBlocks'] as bool?
  ..blockStatus = json['blockStatus'] as bool?
  ..playerChat = json['playerChat'] as bool?
  ..coreItems = json['coreItems'] as bool?
  ..minimap = json['minimap'] as bool?
  ..smoothCamera = json['smoothCamera'] as bool?
  ..detachCamera = json['detachCamera'] as bool?
  ..position = json['position'] as bool?
  ..mousePosition = json['mousePosition'] as bool?
  ..fps = json['fps'] as bool?
  ..playerIndicators = json['playerIndicators'] as bool?
  ..indicators = json['indicators'] as bool?
  ..showWeather = json['showWeather'] as bool?
  ..animatedWater = json['animatedWater'] as bool?
  ..animatedShields = json['animatedShields'] as bool?
  ..bloom = json['bloom'] as bool?
  ..pixelate = json['pixelate'] as bool?
  ..linear = json['linear'] as bool?
  ..skipCoreAnimation = json['skipCoreAnimation'] as bool?
  ..hideDisplays = json['hideDisplays'] as bool?
  ..macNotch = json['macNotch'] as bool?
  ..swapDiagonal = json['swapDiagonal'] as bool?
  ..alwaysMusic = json['alwaysMusic'] as bool?
  ..musicVol = (json['musicVol'] as num?)?.toInt()
  ..sfxVol = (json['sfxVol'] as num?)?.toInt()
  ..ambientVol = (json['ambientVol'] as num?)?.toInt()
  ..locale = json['locale'] as String?
  ..blockSync = json['blockSync'] as bool?
  ..lastBuild = (json['lastBuild'] as num?)?.toInt()
  ..lastBuildString = json['lastBuildString'] as String?;

Map<String, dynamic> _$MindustrySettingsPatchToJson(
  MindustrySettingsPatch instance,
) => <String, dynamic>{
  'saveInterval': instance.saveInterval,
  'autoTarget': instance.autoTarget,
  'keyboard': instance.keyboard,
  'crashReport': instance.crashReport,
  'communityServers': instance.communityServers,
  'saveCreate': instance.saveCreate,
  'blockReplace': instance.blockReplace,
  'conveyorPathfinding': instance.conveyorPathfinding,
  'hints': instance.hints,
  'logicHints': instance.logicHints,
  'backgroundPause': instance.backgroundPause,
  'buildAutoPause': instance.buildAutoPause,
  'distinctControlGroups': instance.distinctControlGroups,
  'doubleTapMine': instance.doubleTapMine,
  'commandModeHold': instance.commandModeHold,
  'modCrashDisable': instance.modCrashDisable,
  'playerLimit': instance.playerLimit,
  'steamPublicHost': instance.steamPublicHost,
  'console': instance.console,
  'uiScale': instance.uiScale,
  'uiScaleChanged': instance.uiScaleChanged,
  'screenShake': instance.screenShake,
  'bloomIntensity': instance.bloomIntensity,
  'bloomBlur': instance.bloomBlur,
  'fpsCap': instance.fpsCap,
  'chatOpacity': instance.chatOpacity,
  'lasersOpacity': instance.lasersOpacity,
  'preferredLaserOpacity': instance.preferredLaserOpacity,
  'unitLaserOpacity': instance.unitLaserOpacity,
  'bridgeOpacity': instance.bridgeOpacity,
  'maxMagnificationMultiplierPercent':
      instance.maxMagnificationMultiplierPercent,
  'maxZoomInGameMultiplier': instance.maxZoomInGameMultiplier,
  'minMagnificationMultiplierPercent':
      instance.minMagnificationMultiplierPercent,
  'minZoomInGameMultiplier': instance.minZoomInGameMultiplier,
  'vsync': instance.vsync,
  'fullscreen': instance.fullscreen,
  'borderlessWindow': instance.borderlessWindow,
  'landscape': instance.landscape,
  'effects': instance.effects,
  'atmosphere': instance.atmosphere,
  'drawLight': instance.drawLight,
  'destroyedBlocks': instance.destroyedBlocks,
  'blockStatus': instance.blockStatus,
  'playerChat': instance.playerChat,
  'coreItems': instance.coreItems,
  'minimap': instance.minimap,
  'smoothCamera': instance.smoothCamera,
  'detachCamera': instance.detachCamera,
  'position': instance.position,
  'mousePosition': instance.mousePosition,
  'fps': instance.fps,
  'playerIndicators': instance.playerIndicators,
  'indicators': instance.indicators,
  'showWeather': instance.showWeather,
  'animatedWater': instance.animatedWater,
  'animatedShields': instance.animatedShields,
  'bloom': instance.bloom,
  'pixelate': instance.pixelate,
  'linear': instance.linear,
  'skipCoreAnimation': instance.skipCoreAnimation,
  'hideDisplays': instance.hideDisplays,
  'macNotch': instance.macNotch,
  'swapDiagonal': instance.swapDiagonal,
  'alwaysMusic': instance.alwaysMusic,
  'musicVol': instance.musicVol,
  'sfxVol': instance.sfxVol,
  'ambientVol': instance.ambientVol,
  'locale': instance.locale,
  'blockSync': instance.blockSync,
  'lastBuild': instance.lastBuild,
  'lastBuildString': instance.lastBuildString,
};
