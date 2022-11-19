Future<void> sleep(int ms) async {
  await Future.delayed(Duration(milliseconds: ms));
}

//RAINY Export to separate package?
/**
 * Transpose matrix.
 * Assumes matrix is uniform.
 * Good for making UI with less thinking.  Consider:
 * ```
 * Row(children: [Spacer(), ...transpose([
 *   [Text("Live voltage:"),Text("${widget._iface.liveVoltage}")],
 *   [Text("Live current:"),Text("${widget._iface.liveCurrent}")],
 *   [Text("Set voltage:"),Text("${widget._iface.voltageSetpoint}")],
 *   [Text("Set current:"),Text("${widget._iface.currentSetpoint}")],
 * ]).map((e) => Column(children: e, crossAxisAlignment: CrossAxisAlignment.end,)).toList(), Spacer()])
 * ```
 */
List<List<T>> transpose<T>(List<List<T>> matrix) {
  if (matrix.length == 0) {
    return [];
  }
  List<List<T>> result = [];
  for (var i = 0; i < matrix[0].length; i++) {
    result.add([]);
    for (var j = 0; j < matrix.length; j++) {
      result[i].add(matrix[j][i]);
    }
  }
  return result;
}

extension SWLap on Stopwatch {
  /**
   * Returns the elapsed time, then resets the stopwatch.
   */
  Duration lap() {
    var e = this.elapsed;
    this.reset();
    return e;
  }
}

class Pair<A, B> {
  A a;
  B b;

  Pair(this.a, this.b);

  @override
  String toString() {
    return "Pair($a, $b)";
  }
}