import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OutlinedInputDecoration extends InputDecoration {
  @override
  OutlineInputBorder? get errorBorder =>
      super.errorBorder as OutlineInputBorder?;
  @override
  OutlineInputBorder? get focusedBorder =>
      super.focusedBorder as OutlineInputBorder?;
  @override
  OutlineInputBorder? get focusedErrorBorder =>
      super.focusedErrorBorder as OutlineInputBorder?;
  @override
  OutlineInputBorder? get disabledBorder =>
      super.disabledBorder as OutlineInputBorder?;
  @override
  OutlineInputBorder? get enabledBorder =>
      super.enabledBorder as OutlineInputBorder?;
  @override
  OutlineInputBorder? get border => super.border as OutlineInputBorder?;

  const OutlinedInputDecoration({
    super.icon,
    super.iconColor,
    //super.label,
    //super.labelText,
    super.labelStyle,
    super.floatingLabelStyle,
    //super.error,
    //super.errorText,
    super.errorStyle,
    super.isDense,
    super.contentPadding,
    super.prefixIcon,
    super.prefix,
    super.prefixText,
    super.prefixIconConstraints,
    super.prefixStyle,
    super.prefixIconColor,
    super.suffixIcon,
    super.suffix,
    super.suffixText,
    super.suffixStyle,
    super.suffixIconColor,
    super.suffixIconConstraints,
    super.filled,
    super.fillColor,
    super.focusColor,
    super.hoverColor,
    OutlineInputBorder? focusedBorder,
    OutlineInputBorder? focusedErrorBorder,
    OutlineInputBorder? disabledBorder,
    OutlineInputBorder? enabledBorder,
    OutlineInputBorder? border,
    super.enabled,
    super.constraints,
    super.visualDensity,
  }) : super(
         enabledBorder: enabledBorder,
         focusedErrorBorder: focusedErrorBorder,
         focusedBorder: focusedBorder,
         border: border,
         errorBorder: enabledBorder,
       );
}

class OutlinedTextField extends StatefulWidget {
  const OutlinedTextField({
    super.key,
    this.label,
    this.labelWidth,
    this.labelSpacing,
    this.controller,
    this.textStyle,
    this.inputFormatters,
    this.statesController,
    this.borderAnimationDuration,
    this.errorAnimationDuration,
    this.focusNode,
    this.enable,
    this.error,
    this.decoration,
    this.onEditingComplete,
  });

  final String? label;
  final double? labelWidth;
  final double? labelSpacing;
  final String? error;
  final TextEditingController? controller;
  final WidgetStatesController? statesController;
  final TextStyle? textStyle;
  final OutlinedInputDecoration? decoration;
  final List<TextInputFormatter>? inputFormatters;
  final Duration? borderAnimationDuration;
  final Duration? errorAnimationDuration;
  final FocusNode? focusNode;
  final bool? enable;
  final VoidCallback? onEditingComplete;

  @override
  State<StatefulWidget> createState() => _OutlinedTextFieldState();
}

class _OutlinedTextFieldState extends State<OutlinedTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  late final widgetStatesController =
      widget.statesController ??
      WidgetStatesController({
        if (!(widget.enable ?? true)) WidgetState.disabled,
      });

  late final _textEditingController =
      widget.controller ?? TextEditingController();

  late final FocusNode focusNode = widget.focusNode ?? FocusNode();

  Set<WidgetState> lastStates = {};

  WidgetStateProperty<OutlineInputBorder> get borders {
    final theme = Theme.of(context).inputDecorationTheme;
    final decoration = widget.decoration;
    return WidgetStateProperty.resolveWith<OutlineInputBorder>((status) {
      if (status.contains(WidgetState.disabled)) {
        final border = decoration?.disabledBorder ?? theme.disabledBorder;
        if (border is OutlineInputBorder) return border;
      }
      if (status.contains(WidgetState.error)) {
        if (status.contains(WidgetState.focused)) {
          final border =
              decoration?.focusedErrorBorder ?? theme.focusedErrorBorder;
          if (border is OutlineInputBorder) return border;
        } else {
          final border = decoration?.errorBorder ?? theme.errorBorder;
          if (border is OutlineInputBorder) return border;
        }
      }
      if (status.contains(WidgetState.focused)) {
        final border = decoration?.focusedBorder ?? theme.focusedBorder;
        if (border is OutlineInputBorder) return border;
      }

      if (status.contains(WidgetState.hovered)) {
        final border = decoration?.enabled ?? theme.enabledBorder;
        if (border is OutlineInputBorder) return border;
      }
      final border = decoration?.border ?? theme.border;
      if (border is OutlineInputBorder) return border;
      return OutlineInputBorder();
    });
  }

  WidgetStateProperty<Color?> get fillColors {
    final theme = Theme.of(context).inputDecorationTheme;
    final decoration = widget.decoration;
    final fillColor = decoration?.fillColor ?? theme.fillColor;
    return WidgetStateProperty.resolveWith<Color?>((status) {
      if (status.contains(WidgetState.error)) {
        return Theme.of(context).colorScheme.error.withAlpha(30);
      }
      if (status.contains(WidgetState.focused) ||
          status.contains(WidgetState.hovered)) {
        return fillColor;
      }
      return fillColor?.withAlpha(0);
    });
  }

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    _animationController = AnimationController(
      vsync: this,
      duration:
          widget.borderAnimationDuration ?? const Duration(milliseconds: 150),
    );
    if (widget.error != null) {
      //若有错误直接进行动画
      widgetStatesController.update(WidgetState.error, true);
      lastStates = widgetStatesController.value;
      _animationController.forward();
    }
    widgetStatesController.addListener(_change);
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        widgetStatesController.update(WidgetState.focused, true);
      } else {
        widgetStatesController.update(WidgetState.focused, false);
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _textEditingController.dispose();
    if (widget.focusNode == null) focusNode.dispose();
    if (widget.statesController == null) widgetStatesController.dispose();
    _animationController.dispose();
    errorTimer.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OutlinedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error == widget.error) return;
    if (widget.error == null) {
      widgetStatesController.update(WidgetState.error, false);
    } else {
      widgetStatesController.update(WidgetState.error, true);
    }
  }

  void _change() {
    final currentState = widgetStatesController.value;
    if (lastStates == currentState) return;
    _animationController
        .forward(from: 0.0)
        .then((_) => lastStates = currentState.toSet());
  }

  Timer errorTimer = Timer(const Duration(milliseconds: 0), () {});
  String? error;

  Widget _buildError() {
    Widget? errorW() {
      if (errorTimer.isActive) {
        //计时未结束，则重置倒计时
        errorTimer.cancel();
        errorTimer = Timer(const Duration(milliseconds: 200), () {
          setState(() {
            error = widget.error;
          });
        });
      } else {
        //计时结束直接更新
        errorTimer.cancel();
        errorTimer = Timer(const Duration(milliseconds: 200), () {});
        error = widget.error;
      }
      if (error == null) return null;
      final theme = Theme.of(context);
      final style =
          widget.decoration?.errorStyle ??
          theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error);
      return Row(
        key: ValueKey(error),
        children: [
          SizedBox(width: 16),
          Text(error!, style: style, maxLines: 1),
        ],
      );
    }

    return AnimatedSize(
      duration:
          widget.errorAnimationDuration ?? const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      child: AnimatedSwitcher(
        duration:
            widget.errorAnimationDuration ?? const Duration(milliseconds: 300),
        switchInCurve: Interval(0.4, 1.0),
        switchOutCurve: Interval(0.6, 1.0),
        child: errorW(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = widget.decoration ?? InputDecoration();
    return Row(
      children: [
        if (widget.label != null)
          SizedBox(
            width: widget.labelWidth,
            child: Text(
              widget.label!,
              style: widget.textStyle ?? theme.textTheme.bodyMedium,
            ),
          ),
        if (widget.label != null) SizedBox(width: widget.labelSpacing ?? 16),
        Expanded(
          child: MouseRegion(
            onEnter: (_) {
              widgetStatesController.update(WidgetState.hovered, true);
            },
            onExit: (_) {
              widgetStatesController.update(WidgetState.hovered, false);
            },
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                final states = widgetStatesController.value;
                final border = borders.resolve(states);

                final fillColor = ColorTween(
                  begin: fillColors.resolve(lastStates),
                  end: fillColors.resolve(states),
                ).animate(_animationController).value;

                final inputDecoration = decoration.copyWith(
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  fillColor: fillColor,
                  focusedBorder: border,
                  border: border,
                  enabledBorder: border,
                  disabledBorder: border,
                  focusedErrorBorder: border,
                );

                return TextField(
                  controller: _textEditingController,
                  focusNode: focusNode,
                  cursorHeight: 18,
                  inputFormatters: widget.inputFormatters,
                  style: theme.textTheme.bodyMedium,
                  decoration: inputDecoration,
                  onEditingComplete: widget.onEditingComplete,
                );
              },
            ),
          ),
        ),
        _buildError(),
      ],
    );
  }
}
