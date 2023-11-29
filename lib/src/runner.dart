import 'dart:async';

import 'package:uuid/uuid.dart';

import 'isolates.dart';

export 'isolates.dart' show Task, TaskWithArgs, OnStart, OnStop;

abstract interface class Runner {
  bool get isClosed;

  Future<R> run<R>(Task<R> task);

  Future<R> runWithArgs<R, A>(A args, TaskWithArgs<R, A> task);

  Future<void> close();
}

final class IsolateRunner implements Runner {
  IsolateRunner({
    this.debugName,
    OnStart? onStart,
    OnStop? onStop,
  })  : _onStart = onStart,
        _onStop = onStop;

  final String? debugName;

  final OnStart? _onStart;

  final OnStop? _onStop;

  IsolateClient? _client;

  bool _isClosed = false;

  Completer<void>? _completer;

  final _isolateToken = const Uuid().v1();

  var _nextId = 1;

  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('This runner($debugName) already closed.');
    }
  }

  Future<void> _init() async {
    _completer = Completer<void>();
    _client = await IsolateClient.create(
      isolateToken: _isolateToken,
      debugName: debugName,
      onStart: _onStart,
      onStop: _onStop,
    );
    _completer!.complete();
  }

  IsolateKey<T> createKey<T>() {
    final id = _nextId;
    _nextId += 1;
    return createIsolateKey(_isolateToken, id);
  }

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    _checkNotClosed();

    _isClosed = true;
    await _client?.close();
    _client = null;
  }

  @override
  Future<R> run<R>(Task<R> task) async {
    _checkNotClosed();

    if (_client == null) {
      if (_completer == null) {
        _init();
      }
      await _completer!.future;
    }

    return _client!.post(task);
  }

  @override
  Future<R> runWithArgs<R, A>(A args, TaskWithArgs<R, A> task) {
    return run(() => task(args));
  }
}
