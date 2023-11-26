import 'dart:isolate';

import 'package:isolate_runner/isolate_runner.dart';

void main() async {
  final pool = IsolatePool(debugName: 'test', size: 12);
  for (var i = 0; i < 18; i++) {
    pool.run(() {
      print('I am ${Isolate.current.debugName}');
    });
  }
}
