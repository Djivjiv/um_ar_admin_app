import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/graph_utils.dart';

void main() {
  test('dijkstra finds the shortest path on a simple graph', () {
    final nodes = ['a', 'b', 'c', 'd'];
    final edges = [
      const GraphEdge('a', 'b', 1),
      const GraphEdge('b', 'd', 5),
      const GraphEdge('a', 'c', 2),
      const GraphEdge('c', 'd', 1),
    ];
    final result = dijkstra(nodes, edges, 'a', 'd');
    expect(result.found, isTrue);
    expect(result.path, ['a', 'c', 'd']);
    expect(result.totalWeight, 3);
  });

  test('dijkstra reports no path when the graph is disconnected', () {
    final result = dijkstra(
      ['a', 'b'],
      [const GraphEdge('a', 'a', 1)],
      'a',
      'b',
    );
    expect(result.found, isFalse);
  });
}
