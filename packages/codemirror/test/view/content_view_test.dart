import 'package:test/test.dart';
import 'package:codemirror/src/view/content_view.dart';
import 'package:codemirror/src/view/view_state.dart';

/// A simple test content view implementation.
class TestView extends ContentView {
  @override
  int length;

  @override
  final List<ContentView> children;

  TestView({this.length = 0, List<ContentView>? children})
      : children = children ?? [];

  @override
  EditorRect? coordsAt(int pos, int side) => null;

  @override
  ContentView split(int at) {
    final newView = TestView(length: length - at);
    length = at;
    return newView;
  }
}

void main() {
  group('ViewFlag', () {
    test('has correct flag values', () {
      expect(ViewFlag.childDirty, equals(1));
      expect(ViewFlag.nodeDirty, equals(2));
      expect(ViewFlag.attrsDirty, equals(4));
      expect(ViewFlag.dirty, equals(7));
      expect(ViewFlag.composition, equals(8));
    });

    test('dirty mask combines all dirty flags', () {
      expect(ViewFlag.dirty,
          equals(ViewFlag.childDirty | ViewFlag.nodeDirty | ViewFlag.attrsDirty));
    });
  });

  group('ContentView', () {
    test('initializes with nodeDirty flag', () {
      final view = TestView();
      expect(view.flags & ViewFlag.nodeDirty, equals(ViewFlag.nodeDirty));
    });

    test('breakAfter defaults to 0', () {
      final view = TestView();
      expect(view.breakAfter, equals(0));
    });

    test('posAtStart returns 0 for root view', () {
      final view = TestView(length: 100);
      expect(view.posAtStart, equals(0));
    });

    test('posAtEnd returns length for root view', () {
      final view = TestView(length: 100);
      expect(view.posAtEnd, equals(100));
    });

    test('posBefore calculates correct position', () {
      final parent = TestView(length: 30, children: [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ]);
      for (final child in parent.children) {
        child.parent = parent;
      }

      expect(parent.posBefore(parent.children[0]), equals(0));
      expect(parent.posBefore(parent.children[1]), equals(10));
      expect(parent.posBefore(parent.children[2]), equals(20));
    });

    test('posBefore accounts for breakAfter', () {
      final parent = TestView(length: 32, children: [
        TestView(length: 10)..breakAfter = 1,
        TestView(length: 10)..breakAfter = 1,
        TestView(length: 10),
      ]);
      for (final child in parent.children) {
        child.parent = parent;
      }

      expect(parent.posBefore(parent.children[0]), equals(0));
      expect(parent.posBefore(parent.children[1]), equals(11)); // 10 + 1
      expect(parent.posBefore(parent.children[2]), equals(22)); // 11 + 10 + 1
    });

    test('posBefore throws for invalid child', () {
      final parent = TestView(length: 10);
      final notChild = TestView(length: 5);

      expect(() => parent.posBefore(notChild), throwsRangeError);
    });

    test('posAfter calculates correct position', () {
      final parent = TestView(length: 30, children: [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ]);
      for (final child in parent.children) {
        child.parent = parent;
      }

      expect(parent.posAfter(parent.children[0]), equals(10));
      expect(parent.posAfter(parent.children[1]), equals(20));
      expect(parent.posAfter(parent.children[2]), equals(30));
    });
  });

  group('markDirty', () {
    test('sets nodeDirty flag', () {
      final view = TestView();
      view.flags = 0;
      view.markDirty();
      expect(view.flags & ViewFlag.nodeDirty, equals(ViewFlag.nodeDirty));
    });

    test('marks parents dirty when andParent is true', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 10, children: [child]);
      child.parent = parent;
      parent.flags = 0;

      child.markDirty(true);

      expect(parent.flags & ViewFlag.nodeDirty, equals(ViewFlag.nodeDirty));
    });

    test('marks parents with childDirty when andParent is false', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 10, children: [child]);
      child.parent = parent;
      parent.flags = 0;

      child.markDirty(false);

      expect(parent.flags & ViewFlag.childDirty, equals(ViewFlag.childDirty));
      expect(parent.flags & ViewFlag.nodeDirty, equals(0));
    });
  });

  group('setParent', () {
    test('sets parent correctly', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 20);

      child.setParent(parent);

      expect(child.parent, same(parent));
    });

    test('marks new parent dirty if child is dirty', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 20);
      parent.flags = 0;
      child.flags = ViewFlag.nodeDirty;

      child.setParent(parent);

      expect(parent.flags & ViewFlag.childDirty, isNonZero);
    });
  });

  group('rootView', () {
    test('returns self for root node', () {
      final view = TestView(length: 10);
      expect(view.rootView, same(view));
    });

    test('returns correct root for nested views', () {
      final root = TestView(length: 30);
      final child = TestView(length: 10);
      final grandchild = TestView(length: 5);

      child.parent = root;
      grandchild.parent = child;

      expect(grandchild.rootView, same(root));
    });
  });

  group('replaceChildren', () {
    test('replaces range of children', () {
      final parent = TestView(length: 30, children: [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ]);

      final newChild = TestView(length: 15);
      parent.replaceChildren(1, 2, [newChild]);

      // Replaced children[1] with newChild, children[0] and children[2] remain
      expect(parent.children.length, equals(3));
      expect(parent.children[0].length, equals(10));
      expect(parent.children[1], same(newChild));
      expect(parent.children[2].length, equals(10));
    });

    test('sets parent on new children', () {
      final parent = TestView(length: 10);
      final child = TestView(length: 5);

      parent.replaceChildren(0, 0, [child]);

      expect(child.parent, same(parent));
    });

    test('destroys removed children', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 10, children: [child]);
      child.parent = parent;

      parent.replaceChildren(0, 1);

      expect(child.parent, isNull);
    });

    test('does not destroy children that are being reinserted', () {
      final child = TestView(length: 10);
      final parent = TestView(length: 20, children: [
        child,
        TestView(length: 10),
      ]);
      child.parent = parent;

      parent.replaceChildren(0, 2, [child]); // Keep first, remove second

      expect(child.parent, same(parent));
    });

    test('marks parent as dirty', () {
      final parent = TestView(length: 10);
      parent.flags = 0;

      parent.replaceChildren(0, 0, [TestView(length: 5)]);

      expect(parent.flags & ViewFlag.nodeDirty, equals(ViewFlag.nodeDirty));
    });
  });

  group('ChildCursor', () {
    test('finds position at start', () {
      final children = [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ];
      final cursor = ChildCursor(children, 30, 3);

      final pos = cursor.findPos(0);

      expect(pos.i, equals(0));
      expect(pos.off, equals(0));
    });

    test('finds position in middle', () {
      final children = [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ];
      final cursor = ChildCursor(children, 30, 3);

      final pos = cursor.findPos(15);

      expect(pos.i, equals(1));
      expect(pos.off, equals(5));
    });

    test('finds position at end', () {
      final children = [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ];
      final cursor = ChildCursor(children, 30, 3);

      final pos = cursor.findPos(30);

      // At end with positive bias, stays in last child
      expect(pos.i, equals(3)); // Past the last child
      expect(pos.off, equals(0));
    });

    test('handles breakAfter correctly', () {
      final children = [
        TestView(length: 10)..breakAfter = 1,
        TestView(length: 10),
      ];
      final cursor = ChildCursor(children, 21, 2);

      final pos = cursor.findPos(11);

      expect(pos.i, equals(1));
      expect(pos.off, equals(0));
    });

    test('bias affects boundary positions', () {
      final children = [
        TestView(length: 10)..breakAfter = 1,
        TestView(length: 10),
      ];
      final cursor1 = ChildCursor(children, 21, 2);
      final cursor2 = ChildCursor(children, 21, 2);

      final posForward = cursor1.findPos(11, 1);
      final posBackward = cursor2.findPos(11, -1);

      // With positive bias at boundary, goes to next child
      expect(posForward.i, equals(1));
      expect(posForward.off, equals(0));
    });
  });

  group('childPos', () {
    test('returns correct child and offset', () {
      final parent = TestView(length: 30, children: [
        TestView(length: 10),
        TestView(length: 10),
        TestView(length: 10),
      ]);

      final pos = parent.childPos(25);

      expect(pos.i, equals(2));
      expect(pos.off, equals(5));
    });
  });

  group('canReuseDOM', () {
    test('returns true for same type without composition', () {
      final a = TestView(length: 10);
      final b = TestView(length: 20);

      expect(a.canReuseDOM(b), isTrue);
    });

    test('returns false when composition flag is set', () {
      final a = TestView(length: 10)..flags = ViewFlag.composition;
      final b = TestView(length: 20);

      expect(a.canReuseDOM(b), isFalse);
    });
  });

  group('destroy', () {
    test('destroys children recursively', () {
      final grandchild = TestView(length: 5);
      final child = TestView(length: 10, children: [grandchild]);
      final parent = TestView(length: 10, children: [child]);

      grandchild.parent = child;
      child.parent = parent;

      parent.destroy();

      expect(parent.parent, isNull);
      expect(child.parent, isNull);
      expect(grandchild.parent, isNull);
    });
  });

  group('toString', () {
    test('returns class name for empty view', () {
      final view = TestView();
      expect(view.toString(), equals('Test'));
    });

    test('includes length for non-empty view without children', () {
      final view = TestView(length: 42);
      expect(view.toString(), equals('Test[42]'));
    });

    test('includes children for view with children', () {
      final view = TestView(length: 30, children: [
        TestView(length: 10),
        TestView(length: 20),
      ]);
      expect(view.toString(), equals('Test(Test[10], Test[20])'));
    });

    test('includes # for breakAfter', () {
      final view = TestView()..breakAfter = 1;
      expect(view.toString(), equals('Test#'));
    });
  });

  group('ContentBounds', () {
    test('creates with correct values', () {
      final bounds = ContentBounds(
        from: 10,
        to: 20,
        startIndex: 1,
        endIndex: 2,
      );

      expect(bounds.from, equals(10));
      expect(bounds.to, equals(20));
      expect(bounds.startIndex, equals(1));
      expect(bounds.endIndex, equals(2));
    });
  });

  group('SyncTrack', () {
    test('initializes with node and written false', () {
      final track = SyncTrack('node');

      expect(track.node, equals('node'));
      expect(track.written, isFalse);
    });
  });
}
