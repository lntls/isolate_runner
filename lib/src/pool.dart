import 'dart:io';
import 'dart:math';

import 'runner.dart';

class _IsolateRunnerWrapper {
  _IsolateRunnerWrapper(this._runner);

  final IsolateRunner _runner;

  var _load = 0;

  Future<R> run<R>(Task<R> task, int load) {
    _load += load;
    return _runner.run(task).whenComplete(() {
      _load -= load;
    });
  }

  Future<void> close() {
    return _runner.close();
  }
}

final class IsolatePool implements Runner {
  IsolatePool._(this._runners);

  factory IsolatePool({
    String? debugName,
    int? size,
    OnStart? onStart,
    OnStop? onStop,
  }) {
    size ??= max(4, (Platform.numberOfProcessors * 0.6).floor());
    final runners = List.generate(
      size,
      (index) {
        final runner = IsolateRunner(
          debugName: debugName == null ? null : '$debugName($index)',
          onStart: onStart,
          onStop: onStop,
        );
        return _IsolateRunnerWrapper(runner);
      },
      growable: false,
    );
    return IsolatePool._(runners);
  }

  final List<_IsolateRunnerWrapper> _runners;

  _IsolateRunnerWrapper get _runner {
    _IsolateRunnerWrapper? result;
    for (final runner in _runners) {
      if (runner._load == 0) {
        return runner;
      }
      if (result == null) {
        result = runner;
        continue;
      }
      if (runner._load < result._load) {
        result = runner;
      }
    }
    return result!;
  }

  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<R> run<R>(
    Task<R> task, {
    int load = 100,
  }) {
    return _runner.run(task, load);
  }

  @override
  Future<R> runWithArgs<R, A>(
    A args,
    TaskWithArgs<R, A> task, {
    int load = 100,
  }) {
    return _runner.run(() => task(args), load);
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    await Future.wait(_runners.map((e) => e.close()));
  }
}
