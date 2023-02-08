import 'package:synchronized/synchronized.dart';

import 'Exchanger.dart';

//RAINY Export to separate package?
class Channel<T> implements ChannelIn<T>, ChannelOut<T> {
  final _ex = Exchanger<T?>();
  final _readLock = Lock();
  final _writeLock = Lock();

  Future<T> read() async {
    return await _readLock.synchronized(() async {
      dynamic x = (await _ex.exchange(null));
      return x;
    });
  }

  Future<void> write(T x) async {
    await _writeLock.synchronized(() async {
      await _ex.exchange(x);
    });
  }

  ChannelIn<T> getIn() {
    return this;
  }

  ChannelOut<T> getOut() {
    return this;
  }
}

abstract class ChannelIn<T> {
  Future<T> read();
}

abstract class ChannelOut<T> {
  Future<void> write(T x);
}