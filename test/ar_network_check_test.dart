import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/ar_network_check.dart';
import 'package:um_ar_admin/domain/models/outdoor_ar_edge_model.dart';
import 'package:um_ar_admin/domain/models/outdoor_ar_node_model.dart';

OutdoorArNodeModel _node(String id, {int? building, bool active = true}) =>
    OutdoorArNodeModel(
        id: id, lat: 0, lng: 0, buildingId: building, isActive: active);

OutdoorArEdgeModel _edge(String a, String b, {bool active = true}) =>
    OutdoorArEdgeModel(fromNode: a, toNode: b, isActive: active);

void main() {
  group('checkArNetwork', () {
    test('an empty network is healthy when no buildings are required', () {
      final r = checkArNetwork(nodes: [], edges: [], buildingIds: []);
      expect(r.components, isEmpty);
      expect(r.isHealthy, isTrue);
    });

    test('one connected network covering every building is healthy', () {
      final r = checkArNetwork(
        nodes: [_node('a', building: 1), _node('b'), _node('c', building: 2)],
        edges: [_edge('a', 'b'), _edge('b', 'c')],
        buildingIds: [1, 2],
      );
      expect(r.components, hasLength(1));
      expect(r.components.first.toSet(), {'a', 'b', 'c'});
      expect(r.isolatedNodeIds, isEmpty);
      expect(r.buildingsWithoutNode, isEmpty);
      expect(r.buildingsOffMainNetwork, isEmpty);
      expect(r.isHealthy, isTrue);
    });

    test('splits pieces, largest first, and lists isolated nodes', () {
      final r = checkArNetwork(
        nodes: [
          _node('x1'), _node('x2'), // small piece
          _node('m1'), _node('m2'), _node('m3'), // main piece
          _node('lonely'),
        ],
        edges: [
          _edge('x1', 'x2'),
          _edge('m1', 'm2'),
          _edge('m3', 'm2'), // direction doesn't matter
        ],
        buildingIds: [],
      );
      expect(r.components.map((g) => g.length), [3, 2, 1]);
      expect(r.components.first.toSet(), {'m1', 'm2', 'm3'});
      expect(r.isolatedNodeIds, ['lonely']);
      expect(r.isHealthy, isFalse);
    });

    test('inactive nodes and edges are ignored', () {
      final r = checkArNetwork(
        nodes: [_node('a'), _node('b'), _node('off', active: false)],
        edges: [
          _edge('a', 'b', active: false), // inactive edge: a, b split
          _edge('a', 'off'), // other end is inactive
        ],
        buildingIds: [],
      );
      expect(r.components, hasLength(2));
      expect(r.isolatedNodeIds.toSet(), {'a', 'b'});
      expect(r.components.expand((g) => g), isNot(contains('off')));
    });

    test('edges to missing nodes and self-loops do not connect anything', () {
      final r = checkArNetwork(
        nodes: [_node('a'), _node('b')],
        edges: [_edge('a', 'ghost'), _edge('b', 'b')],
        buildingIds: [],
      );
      expect(r.isolatedNodeIds.toSet(), {'a', 'b'});
    });

    test('buildings with no active linked node are reported', () {
      final r = checkArNetwork(
        nodes: [
          _node('a', building: 1),
          _node('b', building: 2, active: false), // inactive link: no node
        ],
        edges: [],
        buildingIds: [1, 2, 3, 3], // duplicates are reported once
      );
      expect(r.buildingsWithoutNode, [2, 3]);
    });

    test('counts match what the Check tab reports', () {
      final r = checkArNetwork(
        nodes: [
          _node('a', building: 1), _node('b'),
          _node('c'), _node('d'),
          _node('lonely'),
        ],
        edges: [_edge('a', 'b'), _edge('c', 'd')],
        buildingIds: [1, 2],
      );
      expect(r.components, hasLength(3), reason: 'disconnected pieces');
      expect(r.isolatedNodeIds, ['lonely'], reason: 'nodes with no edges');
      expect(r.buildingsWithoutNode, [2], reason: 'no link to the network');
    });

    test('buildings linked only outside the main piece are off-network', () {
      final r = checkArNetwork(
        nodes: [
          _node('m1', building: 1), _node('m2'), _node('m3'),
          _node('s1', building: 2), _node('s2'),
          _node('t1', building: 3), // building 3 has nodes in both pieces
          _node('t2', building: 3),
        ],
        edges: [
          _edge('m1', 'm2'), _edge('m2', 'm3'), _edge('m3', 't1'),
          _edge('s1', 's2'),
        ],
        buildingIds: [1, 2, 3],
      );
      expect(r.buildingsOffMainNetwork, [2]);
      expect(r.buildingsWithoutNode, isEmpty);
    });
  });
}
