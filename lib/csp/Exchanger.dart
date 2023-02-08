import 'dart:async';
import 'dart:developer';

//RAINY Export to separate package?
/**
 * Like java.util.concurrent.Exchanger; two Futures simultaneously exchange objects
 */
class Exchanger<T> {
  bool hasItem = false;
  T? pending = null;

  Completer<void>? _c = null;

  Future<T> exchange(T x) async {
    if (!hasItem) {
      pending = x;
      hasItem = true;
      _c = Completer<void>.sync();
      await _c!.future;
      /*
      I had a problem - pending is T?.  So I need to return r!.  But T can itself be nullable, and there that will fail.  Therefore, dynamic.
      (D'OH, I was using `pending == null` to mean "no item"; caused deadlock.)
       */
      dynamic r = pending;
      pending = null;
      hasItem = false;
      return r;
    } else {
      dynamic r = pending;
      pending = x;
      _c!.complete();
      return r;
    }
  }
}