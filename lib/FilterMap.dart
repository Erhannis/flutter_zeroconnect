import 'package:collection/collection.dart';

//RAINY Export
/**
 * (Translated from Python, may be phrased a little weird.)
 * Addressed by lists.  `size` is size of list.<br/>
 * Get can contain Nones.<br/>
 * Set *can* contain Nones, but it's not recommended - I suspect it'll be a little messy.<br/>
 * getExact returns a single entry, or throws.<br/>
 * getFilter returns a list of matching entries.<br/>
 * Get performs getExact or getFilter, depending on whether the key contains Nones.<br/>
 * <br/>
 * fm = FilterMap(3)<br/>
 * fm[(0,0,0)] = 0<br/>
 * fm[(0,0,1)] = 1<br/>
 * fm[(0,1,0)] = 2<br/>
 * fm[(0,1,1)] = 3<br/>
 * fm[(1,0,0)] = 4<br/>
 * fm[(1,0,1)] = 5<br/>
 * fm[(1,1,0)] = 6<br/>
 * fm[(1,1,1)] = 7<br/>
 * <br/>
 * fm[(1,1,1)]    # = 7<br/>
 * fm[(1,1,None)] # = [6, 7]<br/>
 * <br/>
 * I abandoned fast-lookup; now if the key contains Nones it iterates the map.  Sigh.<br/>
 * ...I probably shouldn't put commentary in my documentation.<br/>
 */
class FilterMap<K, V> { //THINK extend/implement Map?  [] doesn't return V, but rather List<V>....
    Map<List<K>, V> _map = EqualityMap(ListEquality<K>());
    final int size;

    FilterMap(this.size);

    int length() {
        return _map.length;
    }

    V? getExact(List<K> key) {
        return _map[key];
    }

    List<V> getFilter(List<K?> key) {
        List<V> results = [];
        outer: for (var e in _map.entries) {
            var k = e.key;
            var v = e.value;
            for (var i = 0; i < size; i++) {
                if (key[i] != null && k[i] != key[i]) {
                    // This key doesn't match
                    continue outer;
                }
            }
            results.add(v);
        }
        return results;
    }

    List<V> operator [](List<K?> key) {
        bool hasNone = false;
        for (var i = 0; i < size; i++) {
            if (key[i] == null) {
                hasNone = true;
                break;
            }
        }
        if (hasNone) {
            return getFilter(key);
        } else {
            var r = getExact(key.map((e) => e!).toList());
            if (r == null) {
                return [];
            } else {
                return [r];
            }
        }
    }

    void operator []=(List<K> key, V value) {
        _map[key] = value;
    }

    /**
     * Deletes key.  Exact match.  See `delFilter`.
     */
    V? remove(key) {
        return _map.remove(key);
    }

    List<V> delFilter(key) {
        List<MapEntry<List<K>, V>> entries = [];
        outer: for (var e in _map.entries) {
            for (var i = 0; i < size; i++) {
                if (key[i] != null && e.key[i] != key[i]) {
                    continue outer;
                }
            }
            entries.add(e);
        }
        List<V> removed = [];
        for (var e in entries) {
            _map.remove(e);
            removed.add(e.value);
        }
        return removed;
    }

    /**
     * Like getFilter, but returns a list of keys instead of values.<br/>
     */
    List<List<K>> filterKeys(key) {
        List<List<K>> results = [];
        outer: for (var e in _map.entries) {
            var k = e.key;
            var v = e.value;
            for (var i = 0; i < size; i++) {
                if (key[i] != null && k[i] != key[i]) {
                    // This key doesn't match
                    continue outer;
                }
            }
            results.add(k);
        }
        return results;
    }

    Iterable<MapEntry<List<K>, V>> entries() {
        return _map.entries;
    }

    Iterable<List<K>> keys() {
        return _map.keys;
    }

    Iterable<V> values() {
        return _map.values;
    }

    void clear() {
        _map.clear();
    }
}