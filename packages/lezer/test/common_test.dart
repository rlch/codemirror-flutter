import 'package:lezer/lezer.dart';
import 'package:test/test.dart';

void main() {
  group('NodeType', () {
    test('defines a basic node type', () {
      final type = NodeType.define(id: 0, name: 'Test');
      expect(type.name, equals('Test'));
      expect(type.id, equals(0));
      expect(type.isTop, isFalse);
      expect(type.isError, isFalse);
      expect(type.isAnonymous, isFalse);
    });

    test('defines a top node type', () {
      final type = NodeType.define(id: 1, name: 'Program', top: true);
      expect(type.isTop, isTrue);
    });

    test('defines an error node type', () {
      final type = NodeType.define(id: 2, name: 'Error', error: true);
      expect(type.isError, isTrue);
    });

    test('defines an anonymous node type', () {
      final type = NodeType.define(id: 3);
      expect(type.isAnonymous, isTrue);
      expect(type.name, isEmpty);
    });

    test('NodeType.none is anonymous', () {
      expect(NodeType.none.isAnonymous, isTrue);
    });

    test('is_ checks name and groups', () {
      final type = NodeType.define(
        id: 0,
        name: 'Number',
        props: [(NodeProp.group, ['Literal', 'Expression'])],
      );
      expect(type.is_('Number'), isTrue);
      expect(type.is_('Literal'), isTrue);
      expect(type.is_('Expression'), isTrue);
      expect(type.is_('String'), isFalse);
      expect(type.is_(0), isTrue);
      expect(type.is_(1), isFalse);
    });
  });

  group('NodeSet', () {
    test('creates a node set', () {
      final types = [
        NodeType.define(id: 0, name: 'Program', top: true),
        NodeType.define(id: 1, name: 'Number'),
        NodeType.define(id: 2, name: 'String'),
      ];
      final set = NodeSet(types);
      expect(set.types.length, equals(3));
      expect(set.types[0].name, equals('Program'));
    });

    test('throws on mismatched ids', () {
      expect(
        () => NodeSet([NodeType.define(id: 1, name: 'Test')]),
        throwsRangeError,
      );
    });

    test('extends with props', () {
      final types = [
        NodeType.define(id: 0, name: 'Paren'),
        NodeType.define(id: 1, name: 'CloseParen'),
      ];
      final set = NodeSet(types);
      
      final extended = set.extend([
        NodeProp.closedBy.add({'Paren': ['CloseParen']}),
      ]);
      
      expect(extended.types[0].prop(NodeProp.closedBy), equals(['CloseParen']));
    });
  });

  group('Tree', () {
    test('creates an empty tree', () {
      expect(Tree.empty.length, equals(0));
      expect(Tree.empty.children, isEmpty);
    });

    test('creates a simple tree', () {
      final type = NodeType.define(id: 0, name: 'Root');
      final tree = Tree(type, [], [], 10);
      expect(tree.length, equals(10));
      expect(tree.type.name, equals('Root'));
    });

    test('toString produces readable output', () {
      final root = NodeType.define(id: 0, name: 'Root');
      final child = NodeType.define(id: 1, name: 'Child');
      
      final childTree = Tree(child, [], [], 5);
      final tree = Tree(root, [childTree], [0], 5);
      
      expect(tree.toString(), equals('Root(Child)'));
    });

    test('topNode returns a syntax node', () {
      final type = NodeType.define(id: 0, name: 'Root');
      final tree = Tree(type, [], [], 10);
      final node = tree.topNode;
      
      expect(node.from, equals(0));
      expect(node.to, equals(10));
      expect(node.type.name, equals('Root'));
    });
  });

  group('TreeCursor', () {
    test('navigates a simple tree', () {
      final program = NodeType.define(id: 0, name: 'Program', top: true);
      final number = NodeType.define(id: 1, name: 'Number');
      
      final child = Tree(number, [], [], 3);
      final tree = Tree(program, [child], [0], 3);
      
      final cursor = tree.cursor();
      expect(cursor.type.name, equals('Program'));
      
      expect(cursor.firstChild(), isTrue);
      expect(cursor.type.name, equals('Number'));
      
      expect(cursor.parent(), isTrue);
      expect(cursor.type.name, equals('Program'));
    });

    test('moveTo finds position', () {
      final program = NodeType.define(id: 0, name: 'Program', top: true);
      final number = NodeType.define(id: 1, name: 'Number');
      
      final child1 = Tree(number, [], [], 3);
      final child2 = Tree(number, [], [], 2);
      final tree = Tree(program, [child1, child2], [0, 3], 5);
      
      final cursor = tree.cursor();
      // Start at root
      expect(cursor.type.name, equals('Program'));
      
      // Move to child
      expect(cursor.firstChild(), isTrue);
      expect(cursor.type.name, equals('Number'));
      expect(cursor.from, equals(0));
      
      // Navigate to sibling
      expect(cursor.nextSibling(), isTrue);
      expect(cursor.from, equals(3));
    });
  });

  group('TreeFragment', () {
    test('creates a fragment', () {
      final tree = Tree(NodeType.define(id: 0, name: 'Test'), [], [], 10);
      final fragment = TreeFragment(0, 10, tree, 0);
      
      expect(fragment.from, equals(0));
      expect(fragment.to, equals(10));
      expect(fragment.offset, equals(0));
      expect(fragment.openStart, isFalse);
      expect(fragment.openEnd, isFalse);
    });

    test('addTree creates fragments', () {
      final tree = Tree(NodeType.define(id: 0, name: 'Test'), [], [], 10);
      final fragments = TreeFragment.addTree(tree);
      
      expect(fragments.length, equals(1));
      expect(fragments[0].from, equals(0));
      expect(fragments[0].to, equals(10));
    });

    test('applyChanges updates fragments', () {
      final tree = Tree(NodeType.define(id: 0, name: 'Test'), [], [], 100);
      final fragments = TreeFragment.addTree(tree);
      
      final updated = TreeFragment.applyChanges(fragments, [
        ChangedRange(fromA: 10, toA: 20, fromB: 10, toB: 15),
      ]);
      
      expect(updated.isNotEmpty, isTrue);
    });
  });

  group('NodeWeakMap', () {
    test('stores and retrieves values for tree nodes', () {
      final type = NodeType.define(id: 0, name: 'Root');
      final tree = Tree(type, [], [], 10);
      final node = tree.topNode;

      final map = NodeWeakMap<String>();
      map.set(node, 'test value');

      expect(map.get(node), equals('test value'));
    });

    test('returns null for unset nodes', () {
      final type = NodeType.define(id: 0, name: 'Root');
      final tree = Tree(type, [], [], 10);
      final node = tree.topNode;

      final map = NodeWeakMap<String>();

      expect(map.get(node), isNull);
    });

    test('stores different values for different nodes', () {
      final root = NodeType.define(id: 0, name: 'Root');
      final child = NodeType.define(id: 1, name: 'Child');

      final childTree1 = Tree(child, [], [], 5);
      final childTree2 = Tree(child, [], [], 5);
      final tree = Tree(root, [childTree1, childTree2], [0, 5], 10);

      final node1 = tree.topNode.firstChild!;
      final node2 = tree.topNode.lastChild!;

      final map = NodeWeakMap<int>();
      map.set(node1, 1);
      map.set(node2, 2);

      expect(map.get(node1), equals(1));
      expect(map.get(node2), equals(2));
    });

    test('cursorSet and cursorGet work with tree cursors', () {
      final root = NodeType.define(id: 0, name: 'Root');
      final child = NodeType.define(id: 1, name: 'Child');

      final childTree = Tree(child, [], [], 5);
      final tree = Tree(root, [childTree], [0], 5);

      final cursor = tree.cursor();
      final map = NodeWeakMap<String>();

      map.cursorSet(cursor, 'root value');
      expect(map.cursorGet(cursor), equals('root value'));

      cursor.firstChild();
      map.cursorSet(cursor, 'child value');
      expect(map.cursorGet(cursor), equals('child value'));

      cursor.parent();
      expect(map.cursorGet(cursor), equals('root value'));
    });
  });
}
