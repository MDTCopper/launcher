import 'package:flutter/material.dart';
import 'package:async/async.dart';

class CancelableFutureBuilder<T> extends StatefulWidget {
  final Future<T>? future;

  // true:重建保留旧任务不重启  false:重建强制重启
  final bool refreshOnRebuild;

  final T? initialData;
  final Widget Function(BuildContext, AsyncSnapshot<T>) builder;

  const CancelableFutureBuilder({
    super.key,
    required this.future,
    required this.builder,

    this.refreshOnRebuild = false,
    this.initialData,
  });

  @override
  State<CancelableFutureBuilder<T>> createState() =>
      _CancelableFutureBuilderState<T>();
}

class _CancelableFutureBuilderState<T>
    extends State<CancelableFutureBuilder<T>> {
  CancelableOperation<T>? _activeOp;
  //Future<T>? _cacheFuture;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    super.initState();
    _runFuture(widget.future);
  }

  @override
  void didUpdateWidget(covariant CancelableFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.refreshOnRebuild) return;
    _runFuture(widget.future);
  }

  void _runFuture(Future<T>? future) {
    _activeOp?.cancel();

    if (future == null) {
      setState(() {
        _snapshot = AsyncSnapshot<T>.nothing().inState(ConnectionState.none);
      });
      return;
    }

    setState(() {
      _snapshot = AsyncSnapshot<T>.nothing().inState(ConnectionState.waiting);
    });

    final op = CancelableOperation.fromFuture(future);
    _activeOp = op;
    op.value
        .then((data) {
          if (mounted) {
            setState(() {
              _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, data);
            });
          }
        })
        .catchError((error) {
          if (mounted) {
            setState(() {
              _snapshot = AsyncSnapshot<T>.withError(
                ConnectionState.done,
                error,
              );
            });
          }
        });
  }

  @override
  void dispose() {
    _activeOp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _snapshot);
  }
}
