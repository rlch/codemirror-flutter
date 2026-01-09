// Selection tests ported from CodeMirror's ref/state/test/test-selection.ts
//
// This test file is a direct port of the original CodeMirror test suite
// to ensure feature parity and correct behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/state/selection.dart';

void main() {
  group('EditorSelection', () {
    // Ported from test-selection.ts: "stores ranges with a primary range"
    test('stores ranges with a primary range', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(3, 2),
        EditorSelection.range(4, 5),
      ], 1);

      expect(sel.main.from, 2);
      expect(sel.main.to, 3);
      expect(sel.main.anchor, 3);
      expect(sel.main.head, 2);
      expect(
        sel.ranges.map((r) => '${r.anchor}/${r.head}').join(','),
        '0/1,3/2,4/5',
      );
    });

    // Ported from test-selection.ts: "merges and sorts ranges when normalizing"
    test('merges and sorts ranges when normalizing', () {
      final sel = EditorSelection.create([
        EditorSelection.range(10, 12),
        EditorSelection.range(6, 7),
        EditorSelection.range(4, 5),
        EditorSelection.range(3, 4),
        EditorSelection.range(0, 6),
        EditorSelection.range(7, 8),
        EditorSelection.range(9, 13),
        EditorSelection.range(13, 14),
      ]);

      expect(
        sel.ranges.map((r) => '${r.anchor}/${r.head}').join(','),
        '0/6,6/7,7/8,9/13,13/14',
      );
    });

    // Ported from test-selection.ts: "merges adjacent point ranges when normalizing"
    test('merges adjacent point ranges when normalizing', () {
      final sel = EditorSelection.create([
        EditorSelection.range(10, 12),
        EditorSelection.range(12, 12),
        EditorSelection.range(12, 12),
        EditorSelection.range(10, 10),
        EditorSelection.range(8, 10),
      ]);

      expect(
        sel.ranges.map((r) => '${r.anchor}/${r.head}').join(','),
        '8/10,10/12',
      );
    });

    // Ported from test-selection.ts: "preserves the direction of the last range when merging ranges"
    test('preserves the direction of the last range when merging ranges', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 2),
        EditorSelection.range(10, 1),
      ]);

      expect(
        sel.ranges.map((r) => '${r.anchor}/${r.head}').join(','),
        '10/0',
      );
    });
  });

  // Additional tests for comprehensive coverage
  group('SelectionRange', () {
    test('cursor is empty', () {
      final cursor = EditorSelection.cursor(5);
      expect(cursor.empty, true);
      expect(cursor.from, 5);
      expect(cursor.to, 5);
      expect(cursor.anchor, 5);
      expect(cursor.head, 5);
    });

    test('range has correct anchor and head', () {
      // Forward range
      final forward = EditorSelection.range(5, 10);
      expect(forward.anchor, 5);
      expect(forward.head, 10);
      expect(forward.from, 5);
      expect(forward.to, 10);
      expect(forward.empty, false);

      // Backward range (inverted)
      final backward = EditorSelection.range(10, 5);
      expect(backward.anchor, 10);
      expect(backward.head, 5);
      expect(backward.from, 5);
      expect(backward.to, 10);
      expect(backward.empty, false);
    });

    test('assoc is set correctly for cursor', () {
      final before = EditorSelection.cursor(5, assoc: -1);
      expect(before.assoc, -1);

      final after = EditorSelection.cursor(5, assoc: 1);
      expect(after.assoc, 1);

      final none = EditorSelection.cursor(5, assoc: 0);
      expect(none.assoc, 0);
    });

    test('goalColumn is preserved', () {
      final range = EditorSelection.range(0, 5, goalColumn: 42);
      expect(range.goalColumn, 42);

      final noGoal = EditorSelection.range(0, 5);
      expect(noGoal.goalColumn, null);
    });

    test('bidiLevel is preserved', () {
      final range = EditorSelection.range(0, 5, bidiLevel: 2);
      expect(range.bidiLevel, 2);

      final noBidi = EditorSelection.range(0, 5);
      expect(noBidi.bidiLevel, null);
    });

    test('extend expands range', () {
      final range = EditorSelection.range(5, 10);

      // Extend forward
      final extendedForward = range.extend(15);
      expect(extendedForward.anchor, 5);
      expect(extendedForward.head, 15);

      // Extend backward
      final extendedBackward = range.extend(0);
      expect(extendedBackward.anchor, 5);
      expect(extendedBackward.head, 0);
    });

    test('eq compares ranges correctly', () {
      final a = EditorSelection.range(5, 10);
      final b = EditorSelection.range(5, 10);
      final c = EditorSelection.range(5, 11);

      expect(a.eq(b), true);
      expect(a.eq(c), false);
    });

    test('toJson and fromJson round-trip', () {
      final range = EditorSelection.range(5, 10);
      final json = range.toJson();
      final restored = SelectionRange.fromJson(json);

      expect(restored.anchor, range.anchor);
      expect(restored.head, range.head);
    });
  });

  group('EditorSelection additional', () {
    test('single creates single-range selection', () {
      final sel = EditorSelection.single(5);
      expect(sel.ranges.length, 1);
      expect(sel.main.anchor, 5);
      expect(sel.main.head, 5);

      final selWithHead = EditorSelection.single(5, 10);
      expect(selWithHead.ranges.length, 1);
      expect(selWithHead.main.anchor, 5);
      expect(selWithHead.main.head, 10);
    });

    test('main returns the main range', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
        EditorSelection.range(15, 20),
      ], 1);

      expect(sel.main.anchor, 5);
      expect(sel.main.head, 10);
      expect(sel.mainIndex, 1);
    });

    test('asSingle returns single-range selection', () {
      final multi = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
      ], 1);

      final single = multi.asSingle();
      expect(single.ranges.length, 1);
      expect(single.main.anchor, 5);
      expect(single.main.head, 10);
    });

    test('addRange adds a new range', () {
      final sel = EditorSelection.single(5, 10);
      final extended = sel.addRange(EditorSelection.range(15, 20));

      expect(extended.ranges.length, 2);
      // After normalization (sorting), the new range at 15-20 comes second
      // but main=true means we track it: mainIndex becomes 1 after sort
      expect(extended.main.anchor, 15);
      expect(extended.main.head, 20);
    });

    test('replaceRange replaces a range', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
      ], 1);

      final replaced = sel.replaceRange(EditorSelection.range(6, 11));
      expect(replaced.ranges.length, 2);
      expect(replaced.main.anchor, 6);
      expect(replaced.main.head, 11);
    });

    test('eq compares selections', () {
      final a = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
      ], 1);

      final b = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
      ], 1);

      final c = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 11),
      ], 1);

      expect(a.eq(b), true);
      expect(a.eq(c), false);
    });

    test('toJson and fromJson round-trip', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 1),
        EditorSelection.range(5, 10),
      ], 1);

      final json = sel.toJson();
      final restored = EditorSelection.fromJson(json);

      expect(restored.eq(sel), true);
      expect(restored.mainIndex, sel.mainIndex);
    });

    test('throws on empty ranges', () {
      expect(
        () => EditorSelection.create([]),
        throwsRangeError,
      );
    });

    test('throws on invalid JSON', () {
      expect(
        () => SelectionRange.fromJson({'anchor': 'not a number', 'head': 5}),
        throwsRangeError,
      );

      expect(
        () => EditorSelection.fromJson({'ranges': 'not a list', 'main': 0}),
        throwsRangeError,
      );
    });
  });

  group('checkSelection', () {
    test('validates selection within document', () {
      final sel = EditorSelection.single(5, 10);
      expect(() => checkSelection(sel, 100), returnsNormally);
      expect(() => checkSelection(sel, 10), returnsNormally);
    });

    test('throws when selection exceeds document', () {
      final sel = EditorSelection.single(5, 10);
      expect(() => checkSelection(sel, 5), throwsRangeError);
    });
  });
}
