import 'dart:async';
import 'dart:isolate';

typedef Task<R> = FutureOr<R> Function();
typedef TaskWithArgs<R, A> = FutureOr<R> Function(A);
typedef OnStart = void Function();
typedef OnStop = void Function();

final class _Message<R> {
  _Message(this.task, this.responsePort);

  final Task<R> task;

  final SendPort responsePort;
}

IsolateKey<T> createIsolateKey<T>(String isolateToken, int id) {
  return IsolateKey._(isolateToken, id);
}

void _checkLocalKeyUseInCorrectIsolate(IsolateKey<Object?> key) {
  if (key._isolateToken != IsolateService.current._isolateToken) {
    throw StateError('Please use key in correct isolate!');
  }
}

final class IsolateKey<T> {
  IsolateKey._(this._isolateToken, this._id);

  final String _isolateToken;

  final int _id;

  @override
  int get hashCode => Object.hash(_isolateToken, _id);

  @override
  bool operator ==(Object? other) {
    return other is IsolateKey &&
        other._id == _id &&
        other._isolateToken == _isolateToken;
  }
}

final class IsolateLocal {
  IsolateLocal._();

  static IsolateLocal? _current;
  static IsolateLocal get current => _current ??= IsolateLocal._();

  final _data = <IsolateKey, Object?>{};

  void put<T>(IsolateKey<T> key, T value) {
    _checkLocalKeyUseInCorrectIsolate(key);
    if (!containsKey(key)) {
      _data[key] = value;
    }
  }

  void uodate<T>(IsolateKey<T> key, T newValue) {
    _checkLocalKeyUseInCorrectIsolate(key);
    if (_data.containsKey(key)) {
      _data[key] = newValue;
    }
  }

  T get<T>(IsolateKey<T> key) {
    _checkLocalKeyUseInCorrectIsolate(key);
    return _data[key] as T;
  }

  bool containsKey<T>(IsolateKey<T> key) {
    _checkLocalKeyUseInCorrectIsolate(key);
    return _data.containsKey(key);
  }

  T remove<T>(IsolateKey<T> key) {
    _checkLocalKeyUseInCorrectIsolate(key);
    return _data.remove(key) as T;
  }
}

final class IsolateService {
  IsolateService._(this._isolateToken, this._onStart, this._onStop) {
    if (_current != null) {
      throw StateError('IsolateService already created.');
    }

    _current = this;
  }

  static IsolateService? _current;
  static IsolateService get current {
    if (_current == null) {
      throw StateError('IsolateService not created.');
    }

    if (_current!.isStopped) {
      throw StateError('IsolateService already stopped.');
    }

    return _current!;
  }

  final OnStart? _onStart;

  final OnStop? _onStop;

  final _port = RawReceivePort();

  final String _isolateToken;

  bool _isStopped = false;
  bool get isStopped => _isStopped;

  void _start() {
    try {
      _onStart?.call();
    } finally {
      _port.handler = _handleMessage;
    }
  }

  void _stop() {
    try {
      _onStop?.call();
    } finally {
      _isStopped = true;
      _port.close();
    }
  }

  Future<void> _handleMessage(_Message message) async {
    try {
      final Object? result;
      final potentiallyAsyncResult = message.task();
      if (potentiallyAsyncResult is Future) {
        result = await potentiallyAsyncResult;
      } else {
        result = potentiallyAsyncResult;
      }

      message.responsePort.send(List.filled(1, result));
    } catch (e, stackTrace) {
      message.responsePort.send(List<Object?>.filled(2, null)
        ..[0] = e
        ..[1] = stackTrace);
    }
  }
}

final class IsolateClient {
  IsolateClient._(this._isolate, this._sendPort);

  static Future<IsolateClient> create({
    required String isolateToken,
    String? debugName,
    OnStart? onStart,
    OnStop? onStop,
  }) async {
    final completer = Completer<SendPort>();
    final resultPort = RawReceivePort();
    resultPort.handler = (SendPort sendPort) {
      resultPort.close();
      completer.complete(sendPort);
    };

    try {
      final isolate = await Isolate.spawn(
        (message) {
          final sendPort = message.$1;
          final service = IsolateService._(
            message.$2,
            message.$3,
            message.$4,
          ).._start();
          sendPort.send(service._port.sendPort);
        },
        (resultPort.sendPort, isolateToken, onStart, onStop),
        debugName: debugName,
      );

      return IsolateClient._(isolate, await completer.future);
    } catch (error, stackTrace) {
      resultPort.close();
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  final Isolate _isolate;

  final SendPort _sendPort;

  Future<R> post<R>(Task<R> task) {
    final completer = Completer<R>();
    final responsePort = RawReceivePort();
    responsePort.handler = (List<Object?> response) {
      responsePort.close();
      if (response.length == 2) {
        completer.completeError(response[0]!, response[1] as StackTrace);
      } else {
        completer.complete(response[0] as R);
      }
    };

    _sendPort.send(_Message(task, responsePort.sendPort));

    return completer.future;
  }

  Future<void> close() {
    return post(() {
      return IsolateService.current._stop();
    });
  }
}
