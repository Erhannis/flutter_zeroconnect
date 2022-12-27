import "dart:async";

class WaitGroup {
  int _counter = 0;
  Completer<void> _completer = Completer<void>();

  WaitGroup();

  factory WaitGroup.of(int i) => WaitGroup()..add(i);

  void add(int i) {
    _counter += i;
  }

  void done() {
    _counter--;
    if (_counter == 0) {
      _completer.complete();
      _completer = Completer();
    }
  }

  Future<void> wait() async {
    if (_counter > 0) {
      return _completer.future;
    }
  }
}
