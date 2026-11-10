import 'package:copper_launcher/ui/pages/design/core_component_demo.dart';
import 'package:copper_launcher/ui/components/scroll/list_view.dart';
import 'package:copper_launcher/ui/pages/design/real_component_demo.dart';
import 'package:copper_launcher/ui/pages/design/template_catalog_page.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 组件设计页（`/component_design`，仅 debug 出现）：左边选一类，右边看那一类的全部状态
///
/// 第一项是「原组件对照」（真实组件库本体 + 设计版还缺的能力），其余是设计层样张；
/// 改 `lib/ui/pages/design/` 或 `lib/ui/components/` 后热重载即可看效果
class ComponentDesignPage extends StatefulWidget {
  const ComponentDesignPage({super.key});

  @override
  State<ComponentDesignPage> createState() => _ComponentDesignPageState();
}

class _ComponentDesignPageState extends State<ComponentDesignPage> {
  /// 目录：和组件清单一一对应；最后一项是「全部」
  static const _sections = <String>[
    '页面骨架（顶部栏 + 滚动区）',
    '外壳：logo + 应用名 / 收纳按钮在侧栏底部 / 页面左上圆角',
    '顶栏路由线路（整条栈 / 页面内路由用框 / 名称带 tag）',
    '浮层（对话框 / Toast）',
    '空 / 错 / 载三态',
    '按钮',
    '行',
    '控件',
    '标签页（下划线式）',
    '菜单 / 下拉 / 提示条语气',
    '键位 / 颜色 / 拖放',
    '滑块类型',
    '独立设置 tile（高度 = 原生开关默认高度）',
    '表格',
    '列表卡 / 网格卡',
    '分页 / 折叠 / 图片位',
    'Markdown（README）',
    '任务卡 / 日志卡（右侧抽屉）',
    '页面片段：启动前设置',
    '反馈与入口',
    '动效',
    '加载动效（候选）',
    '圆点矩阵动效（候选）',
    '圆点矩阵动效（全动画）',
    '圆点矩阵动效（帧序列）',
  ];

  int _selected = 0;

  /// 目录序号：0 = 原组件对照，1 = 全部设计样张，2 起 = 单节
  static const _realIndex = 0;
  static const _coreIndex = 1;
  static const _allIndex = 2;

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);

    return Material(
      color: skin.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(skin),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _index(skin),
                Expanded(
                  child: TemplateScrollView(
                    skin: skin,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: _content(skin),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(TemplateSkin skin) {
    if (_selected == _realIndex) return RealComponentDemo(skin: skin);
    if (_selected == _coreIndex) return CoreComponentDemo(skin: skin);
    return TemplateCatalogPage(
      skin: skin,
      onlySection: _selected == _allIndex ? null : _sections[_selected - 3],
    );
  }

  Widget _header(TemplateSkin skin) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.lg),
      decoration: BoxDecoration(
        color: skin.surface,
        border: Border(bottom: BorderSide(color: skin.border)),
      ),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          Text(
            '组件设计',
            style: TemplateType.section.copyWith(color: skin.textPrimary),
          ),
          Text(
            '左边选一类；「原组件对照」看旧组件能力，「内核组件」看新 core 组件，改完热重载生效',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _index(TemplateSkin skin) {
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: skin.surface,
        border: Border(right: BorderSide(color: skin.border)),
      ),
      child: CopperListView(
        padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
        children: [
          _indexItem(skin, '原组件对照（组件库）', _realIndex),
          _indexItem(skin, '内核组件（core）', _coreIndex),
          _indexItem(skin, '全部设计样张', _allIndex),
          for (var i = 0; i < _sections.length; i++)
            _indexItem(skin, _sections[i], i + 3),
        ],
      ),
    );
  }

  Widget _indexItem(TemplateSkin skin, String label, int index) {
    final selected = index == _selected;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.sm,
        vertical: 1,
      ),
      child: Material(
        color: selected ? skin.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(TemplateRadius.control),
          onTap: () => setState(() => _selected = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.sm,
              vertical: 7,
            ),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TemplateType.caption.copyWith(
                color: selected ? skin.textPrimary : skin.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
