import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/input/color_picker.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/feature/feature_curve.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';

import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:flutter/material.dart';

const gameUserPageRouteKey = '/user';

///页面首先读取当前选中版本的 settings.bin 中的玩家信息
///（`name` / `uuid` / `color-0`）作为临时用户信息，可编辑后保存为账户；
///游戏内用户保存在 config（[Setting.gameUsers]）中。
///账户项支持：点击选择、左滑露出删除、右键/长按弹出操作菜单。
///启动游戏时，选中的账户会自动覆盖 settings 的相关字段。
class GameUserPage extends StatefulWidget {
  const GameUserPage({super.key});

  @override
  State<StatefulWidget> createState() => _GameUserPageState();
}

class _GameUserPageState extends State<GameUserPage> {
  ///当前选中的游戏版本（其 settings.bin 作为临时用户信息来源）。
  Mindustry? get _mindustry => config.versionOptions.selectedVersion;

  final _nameController = TextEditingController();

  String _uuid = '';

  int _color = 0;

  ///正在编辑的已存账户；null 表示保存时新建一条
  GameUser? _editing;

  ///正在播删除动画的用户 id
  String? _removingUserId;

  @override
  void initState() {
    super.initState();
    _loadFromSetting();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  ///读取当前版本 settings.bin
  MindustrySettings? _readSetting() {
    final mindustry = _mindustry;
    if (mindustry == null) return null;
    return MindustrySettings.fromFile(mindustry.settingPath);
  }

  ///从 settings 载入临时用户信息
  void _loadFromSetting() {
    final setting = _readSetting();
    _nameController.text = setting?.name ?? '';
    _uuid = setting?.uuid ?? '';
    _color = setting?.color0 ?? 0;
    _editing = null;
  }

  ///保存：编辑态更新该用户，否则新建一条并选中
  void _saveGameUser() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSaveError('用户名称不能为空');
      return;
    }
    // 不允许重名：编辑时排除自己
    final editingId = _editing?.id;
    final duplicated = config.setting.gameUsers.any(
      (user) => user.id != editingId && user.name == name,
    );
    if (duplicated) {
      _showSaveError('已存在同名用户');
      return;
    }

    final target = _editing;
    if (target != null) {
      target.name = name;
      target.color = _color;
      config.setting.selectGameUser(target);
      config.save();
      addLog(.info, '更新用户：$name', tag: 'GameUser');
      setState(() => _editing = null);
      return;
    }

    final user = GameUser(
      id: 'acc_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      uuid: _uuid,
      color: _color,
    );
    config.setting.gameUsers.add(user);
    config.setting.selectGameUser(user);
    config.save();
    addLog(.info, '新建用户：$name', tag: 'GameUser');
    setState(() {});
  }

  /// 保存失败提示：走项目统一的通知（不用 SnackBar——那属于待统一的旧方式）
  void _showSaveError(String message) {
    addNotice(icon: Icons.close, title: '保存失败', content: message);
  }

  void _selectGameUser(GameUser user) {
    config.setting.selectGameUser(user);
    config.save();
    addLog(.info, '切换用户：${user.name}', tag: 'GameUser');
    setState(() {});
  }

  ///删除：先播退场动画，动画播完才真正落库（见 [_finishDeleteGameUser]）
  void _deleteGameUser(GameUser user) {
    if (_removingUserId != null) return;
    setState(() => _removingUserId = user.id);
  }

  void _finishDeleteGameUser(GameUser user) {
    config.setting.gameUsers.remove(user);
    if (config.setting.currentGameUserId == user.id) {
      config.setting.currentGameUserId = '';
    }
    config.save();
    addLog(.info, '删除用户：${user.name}', tag: 'GameUser');
    setState(() => _removingUserId = null);
  }

  ///把账户信息载入临时编辑区（进入编辑态，保存即更新该账户）。
  void _loadToEdit(GameUser user) {
    _nameController.text = user.name;
    _uuid = user.uuid;
    _color = user.color;
    setState(() => _editing = user);
  }

  // ── 临时用户信息区 ──

  Widget _buildTemporaryPanel() {
    final theme = Theme.of(context);
    final editing = _editing;

    return ContentPanelModule(
      title: editing == null ? '临时信息' : '临时信息（正在编辑 [${editing.name}]）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_mindustry == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '先在主页选一个游戏版本——这里的信息是从它的设置里读出来的',
                style: theme.textTheme.bodySmall,
              ),
            ),
          OutlinedTextField(label: '玩家名', controller: _nameController),
          const SizedBox(height: 12),
          Text('名字颜色'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final color in _presetColors)
                _ColorDot(
                  color: _arcToFlutter(color),
                  selected: _color == color,
                  showCheck: true,
                  onTap: () => setState(() => _color = color),
                ),
              _buildCustomColorChip(),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.save_outlined,
                content: editing == null ? '保存为用户' : '更新用户',
                onTap: _saveGameUser,
              ),
              if (editing != null)
                IconTextButton(
                  icon: Icons.close,
                  content: '取消编辑',
                  onTap: () => setState(() => _editing = null),
                ),
              IconTextButton(
                icon: Icons.refresh,
                content: '从设置重新载入',
                onTap: () => setState(_loadFromSetting),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「自定义」胶囊：当前色不在预设里时高亮并显示该色小圆点
  Widget _buildCustomColorChip() {
    final colors = AppColors.of(context);
    final isCustom = !_presetColors.contains(_color);

    return ReboundContainer(
      borderRadius: BorderRadius.circular(16),
      backgroundColor: isCustom ? colors.interactive.withAlpha(40) : null,
      onTap: _pickCustomColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (isCustom)
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _arcToFlutter(_color),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                )
              else
                Icon(Icons.colorize, size: 14, color: colors.itemPrimary),
              Text(
                '自定义',
                style: TextStyle(
                  color: isCustom ? colors.interactive : colors.itemPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取色：结果写回 arc `rgba8888`
  Future<void> _pickCustomColor() async {
    // 未设色（0）时从游戏默认橙起调，免得从全透明开始
    final initial = _color == 0 ? 0xFFA108FF : _color;
    final picked = await showColorPickerDialog(
      context: context,
      initialColor: _arcToFlutter(initial),
    );
    if (picked == null || !mounted) return;
    setState(() => _color = _flutterToArc(picked));
  }

  // ── 已保存账户区 ──

  Widget _buildGameUsersPanel() {
    final users = config.setting.gameUsers;
    final currentId = config.setting.currentGameUserId;

    return ContentPanelModule(
      title: '已保存的游戏内用户',
      child: users.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂无用户，在上方填写信息后点击',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                for (final user in users)
                  _GameUserTile(
                    key: ValueKey(user.id),
                    removing: _removingUserId == user.id,
                    onRemoved: () => _finishDeleteGameUser(user),
                    child: _buildGameUserItem(
                      user,
                      current: user.id == currentId,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildGameUserItem(GameUser user, {required bool current}) {
    final colors = AppColors.of(context);

    // 行内容：色点 + 名称/UUID + 选中标记
    Widget child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _ColorDot(
            color: _arcToFlutter(user.color),
            size: 28,
            selected: current,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.name,
              style: TextStyle(
                color: _arcToFlutter(user.color),
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (current)
            Icon(Icons.check_circle, color: colors.interactive)
          else
            Icon(Icons.radio_button_unchecked, color: colors.itemHint),
        ],
      ),
    );

    // 整行点击选择
    child = ReboundButton(
      pressedScale: 0.98,

      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectGameUser(user),
      child: child,
    );

    child = ActionMenu(
      actions: [
        SlideActionButton(
          icon: const Icon(Icons.delete_outline),
          label: '删除',
          color: Colors.white,
          backgroundColor: colors.error,
          onTap: () => _deleteGameUser(user),
        ),
      ],
      menuBuilder: (context, controller) => [
        _menuItem(
          context,
          icon: Icons.check,

          label: '设为当前',
          onTap: () {
            _selectGameUser(user);
            controller.dismiss();
          },
        ),
        _menuItem(
          context,
          icon: Icons.edit_outlined,
          label: '载入到编辑',
          onTap: () {
            _loadToEdit(user);
            controller.dismiss();
          },
        ),
        _menuItem(
          context,
          icon: Icons.delete_outline,
          label: '删除',
          danger: true,
          onTap: () {
            _deleteGameUser(user);
            controller.dismiss();
          },
        ),
      ],
      child: child,
    );

    return child;
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final colors = AppColors.of(context);
    final color = danger ? colors.error : colors.itemPrimary;
    return SizedBox(
      width: 120,
      child: ReboundButton(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [_buildTemporaryPanel(), _buildGameUsersPanel()],
    );
  }
}

/// 游戏里可选的玩家色：与 Mindustry `Vars.playerColors` 一致的 16 个
///
/// arc `rgba8888` 编码：0xRRGGBBAA
const _presetColors = <int>[
  0x82759AFF, // 灰紫
  0xC0C1C5FF, // 浅灰
  0xFFFFFFFF, // 白
  0x7D2953FF, // 深酒红
  0xFF074EFF, // 玫红
  0xFF072AFF, // 红
  0xFF76A6FF, // 粉
  0xA95238FF, // 棕
  0xFFA108FF, // 橙（游戏默认）
  0xFEEB2CFF, // 黄
  0xFFCAA8FF, // 米
  0x008551FF, // 深绿
  0x00E339FF, // 绿
  0x423C7BFF, // 蓝紫
  0x4B5EF1FF, // 蓝
  0x2CABFEFF, // 天蓝
];

///arc 0xRRGGBBAA → Flutter Color。
///
/// arc `rgba8888` 的字节布局：R << 24 | G << 16 | B << 8 | A。
Color _arcToFlutter(int arc) => Color.fromARGB(
  arc & 0xFF,
  (arc >> 24) & 0xFF,
  (arc >> 16) & 0xFF,
  (arc >> 8) & 0xFF,
);

/// Flutter Color → arc `rgba8888`（取色器给的是 Color，存回 config 要 arc 编码）
int _flutterToArc(Color color) {
  final argb = color.toARGB32();
  return ((argb >> 16 & 0xFF) << 24) |
      ((argb >> 8 & 0xFF) << 16) |
      ((argb & 0xFF) << 8) |
      (argb >> 24 & 0xFF);
}

///颜色圆点（选择器与账户列表共用）。
class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  /// 选中时是否在圆点上画对勾（列表里已有独立选中标记，就不重复画）
  final bool showCheck;

  const _ColorDot({
    required this.color,
    this.size = 40,
    this.selected = false,
    this.onTap,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // 选中：主题色粗描边 + 外发光（+ 可选对勾）；未选中：细边框
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.interactive : colors.border,
          width: selected ? 3 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: colors.interactive.withAlpha(90),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: selected && showCheck
          ? Icon(Icons.check, size: size * 0.5, color: _contrastOn(color))
          : null,
    );

    if (onTap == null) return dot;
    return ReboundButton(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: dot,
    );
  }
}

/// 用户行：入场浮现（新加的用户、以及进页面时）；删除时先收缩淡出，
/// 动画播完再回调 [onRemoved] 去落库
class _GameUserTile extends StatefulWidget {
  const _GameUserTile({
    super.key,
    required this.child,
    required this.removing,
    required this.onRemoved,
  });

  final Widget child;

  /// true 时播放退场动画（播完调 [onRemoved]）
  final bool removing;

  final VoidCallback onRemoved;

  @override
  State<_GameUserTile> createState() => _GameUserTileState();
}

class _GameUserTileState extends State<_GameUserTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: FeatureCurves.reboundIn,
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后再播入场：布局期间动画 paint 会让未布局条目崩
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(covariant _GameUserTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.removing && widget.removing) _playOut();
  }

  Future<void> _playOut() async {
    await _controller.reverse();
    if (mounted) widget.onRemoved();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(_curve),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 底色上取黑 / 白前景（亮度阈值，保证对勾看得清）
Color _contrastOn(Color background) =>
    background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
