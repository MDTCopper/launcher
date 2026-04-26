import 'package:flutter/material.dart';


//混合状态类，组合后直接使用状态判断

mixin StatefulMixin<T extends StatefulWidget> on State<T> {

  final statesController =WidgetStatesController();

  Set<WidgetState> get states => statesController.value;

  //bool _is(WidgetState state) => states.contains(state);

  bool get isFocused => states.contains(WidgetState.focused);
  bool get isDisabled => states.contains(WidgetState.disabled);
  bool get isDragged => states.contains(WidgetState.dragged);
  bool get isError => states.contains(WidgetState.error);
  bool get isHovered => states.contains(WidgetState.hovered);
  bool get isPressed => states.contains(WidgetState.pressed);
  bool get isScrolledUnder => states.contains(WidgetState.scrolledUnder);
  bool get isSelected => states.contains(WidgetState.selected);

  @override
  void dispose() {
    statesController.dispose();
    super.dispose();
  }

}


class _States {

  _States(this._states);

  final Set<WidgetState> _states;

  bool get focused => _states.contains(WidgetState.focused);
  bool get disabled => _states.contains(WidgetState.disabled);
  bool get dragged => _states.contains(WidgetState.dragged);
  bool get error => _states.contains(WidgetState.error);
  bool get hovered => _states.contains(WidgetState.hovered);
  bool get pressed => _states.contains(WidgetState.pressed);
  bool get scrolledUnder => _states.contains(WidgetState.scrolledUnder);
  bool get selected => _states.contains(WidgetState.selected);

}
