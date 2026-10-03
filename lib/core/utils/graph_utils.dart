import 'dart:math' as math;

/// A weighted undirected edge between two node ids.
class GraphEdge {
  final String from;
  final String to;
  final double weight;
  const GraphEdge(this.from, this.to, this.weight);
}

class DijkstraResult {
  final List<String> path;
  final double totalWeight;
  final bool found;

  const DijkstraResult({
    this.path = const [],
    this.totalWeight = 0,
    this.found = false,
  });
}

/// Runs Dijkstra's algorithm over an undirected weighted graph.
DijkstraResult dijkstra(
  Iterable<String> nodeIds,
  Iterable<GraphEdge> edges,
  String start,
  String goal,
) {
  final adjacency = <String, List<GraphEdge>>{
    for (final id in nodeIds) id: <GraphEdge>[],
  };
  for (final e in edges) {
    if (!adjacency.containsKey(e.from) || !adjacency.containsKey(e.to)) continue;
    final w = e.weight <= 0 ? 1.0 : e.weight;
    adjacency[e.from]!.add(GraphEdge(e.from, e.to, w));
    adjacency[e.to]!.add(GraphEdge(e.to, e.from, w));
  }

  if (!adjacency.containsKey(start) || !adjacency.containsKey(goal)) {
    return const DijkstraResult();
  }

  final dist = <String, double>{for (final id in adjacency.keys) id: double.infinity};
  final prev = <String, String?>{};
  dist[start] = 0;

  final queue = HashsetPriorityQueue();
  queue.add(start, 0);

  while (queue.isNotEmpty) {
    final current = queue.removeMin();
    if (current == goal) break;
    for (final edge in adjacency[current]!) {
      final alt = dist[current]! + edge.weight;
      if (alt < dist[edge.to]!) {
        dist[edge.to] = alt;
        prev[edge.to] = current;
        queue.add(edge.to, alt);
      }
    }
  }

  if (dist[goal] == double.infinity) return const DijkstraResult();

  final path = <String>[];
  String? step = goal;
  while (step != null) {
    path.insert(0, step);
    step = prev[step];
  }
  return DijkstraResult(path: path, totalWeight: dist[goal]!, found: true);
}

/// Minimal binary-heap priority queue keyed by double priority.
class HashsetPriorityQueue {
  final List<MapEntry<String, double>> _heap = [];

  bool get isNotEmpty => _heap.isNotEmpty;

  void add(String value, double priority) {
    _heap.add(MapEntry(value, priority));
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_heap[parent].value <= _heap[i].value) break;
      _swap(i, parent);
      i = parent;
    }
  }

  String removeMin() {
    final min = _heap.first.key;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = 2 * i + 2;
        var smallest = i;
        if (l < _heap.length && _heap[l].value < _heap[smallest].value) {
          smallest = l;
        }
        if (r < _heap.length && _heap[r].value < _heap[smallest].value) {
          smallest = r;
        }
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return min;
  }

  void _swap(int a, int b) {
    final tmp = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = tmp;
  }
}

/// Approximate great-circle distance in meters between two lat/lng pairs.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRad(double deg) => deg * math.pi / 180.0;
