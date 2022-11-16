import 'package:sync/mutex.dart';

import 'Exchanger.dart';

//RAINY Export to separate package?
class Channel<T> implements ChannelIn<T>, ChannelOut<T> {
  final _ex = Exchanger<T?>();
  final _readLock = Mutex();
  final _writeLock = Mutex();

  Future<T> read() async {
    await _readLock.acquire();
    try {
      dynamic x = (await _ex.exchange(null));
      return x;
    } finally {
      _readLock.release();
    }
  }

  Future<void> write(T x) async {
    await _writeLock.acquire();
    try {
      await _ex.exchange(x);
    } finally {
      _writeLock.release();
    }
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