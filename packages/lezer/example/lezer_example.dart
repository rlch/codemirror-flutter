import 'package:lezer/lezer.dart';

void main() {
  // Create a simple tree structure
  final nodeSet = NodeSet([
    NodeType.define(id: 0, name: 'Document', top: true),
    NodeType.define(id: 1, name: 'Paragraph'),
  ]);
  
  final tree = Tree(
    nodeSet.types[0],
    [Tree(nodeSet.types[1], [], [], 10)],
    [0],
    10,
  );
  
  print('Tree: $tree');
  print('Top node: ${tree.topNode.name}');
}
