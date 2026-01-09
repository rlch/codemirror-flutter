import 'package:codemirror/src/state/change.dart';
import 'package:codemirror/src/state/range_set.dart';
import 'package:test/test.dart';

/// Simple test range value implementation
class TestValue extends RangeValue {
  final String name;
  @override
  final int startSide;
  @override
  final int endSide;
  @override
  final bool point;

  TestValue(this.name, {this.startSide = 0, this.endSide = 0, this.point = false});

  @override
  bool eq(RangeValue other) => other is TestValue && other.name == name;

  @override
  String toString() => 'TestValue($name)';
}

void main() {
  group('RangeValue', () {
    test('creates range with default from and to', () {
      final value = TestValue('a');
      final range = value.range(5);
      expect(range.from, 5);
      expect(range.to, 5);
      expect(range.value, value);
    });

    test('creates range with from and to', () {
      final value = TestValue('a');
      final range = value.range(5, 10);
      expect(range.from, 5);
      expect(range.to, 10);
      expect(range.value, value);
    });

    test('has default properties', () {
      final value = TestValue('a');
      expect(value.startSide, 0);
      expect(value.endSide, 0);
      expect(value.point, false);
      expect(value.mapMode, MapMode.trackDel);
    });
  });

  group('RangeSet.of', () {
    test('creates empty set from empty list', () {
      final set = RangeSet.of<TestValue>([]);
      expect(set.isEmpty, true);
      expect(set.size, 0);
    });

    test('creates set from single range', () {
      final value = TestValue('a');
      final set = RangeSet.of([Range.create(0, 10, value)]);
      expect(set.isEmpty, false);
      expect(set.size, 1);
    });

    test('creates set from multiple ranges', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ];
      final set = RangeSet.of(ranges);
      expect(set.size, 3);
    });

    test('sorts ranges when sort=true', () {
      final ranges = [
        Range.create(20, 25, TestValue('c')),
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ];
      final set = RangeSet.of(ranges, true);
      expect(set.size, 3);
      
      // Verify order by iterating
      final cursor = set.iter();
      expect(cursor.from, 0);
      cursor.next();
      expect(cursor.from, 10);
      cursor.next();
      expect(cursor.from, 20);
    });
  });

  group('RangeSet.iter', () {
    test('iterates over empty set', () {
      final set = RangeSet.of<TestValue>([]);
      final cursor = set.iter();
      expect(cursor.value, null);
    });

    test('iterates over ranges in order', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ];
      final set = RangeSet.of(ranges);
      final cursor = set.iter();

      expect(cursor.from, 0);
      expect(cursor.to, 5);
      expect((cursor.value as TestValue).name, 'a');

      cursor.next();
      expect(cursor.from, 10);
      expect(cursor.to, 15);
      expect((cursor.value as TestValue).name, 'b');

      cursor.next();
      expect(cursor.from, 20);
      expect(cursor.to, 25);
      expect((cursor.value as TestValue).name, 'c');

      cursor.next();
      expect(cursor.value, null);
    });

    test('starts from specified position', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ];
      final set = RangeSet.of(ranges);
      final cursor = set.iter(12);

      expect(cursor.from, 10);
      expect((cursor.value as TestValue).name, 'b');
    });
  });

  group('RangeSet.between', () {
    test('finds ranges in region', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ];
      final set = RangeSet.of(ranges);

      final found = <String>[];
      set.between(8, 22, (from, to, value) {
        found.add((value as TestValue).name);
        return true;
      });

      expect(found, ['b', 'c']);
    });

    test('stops when callback returns false', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ];
      final set = RangeSet.of(ranges);

      final found = <String>[];
      set.between(0, 30, (from, to, value) {
        found.add((value as TestValue).name);
        return found.length < 2;
      });

      expect(found, ['a', 'b']);
    });
  });

  group('RangeSet.map', () {
    test('maps empty set returns same set', () {
      final set = RangeSet.of<TestValue>([]);
      final changes = ChangeDesc([10, -1]); // no change
      final mapped = set.map(changes);
      expect(mapped.isEmpty, true);
    });

    test('maps ranges through empty changes', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ];
      final set = RangeSet.of(ranges);
      final changes = ChangeDesc([20, -1]); // no change, 20 chars
      final mapped = set.map(changes);

      final cursor = mapped.iter();
      expect(cursor.from, 0);
      expect(cursor.to, 5);
      cursor.next();
      expect(cursor.from, 10);
      expect(cursor.to, 15);
    });

    test('maps ranges through insertion', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ];
      final set = RangeSet.of(ranges);
      // Insert 3 chars at position 3: [3 unchanged, 0 deleted -> 3 inserted, 17 unchanged]
      // Format: [len, ins_or_-1, len, ins_or_-1, ...]
      final changes = ChangeDesc([3, -1, 0, 3, 17, -1]);
      final mapped = set.map(changes);

      final cursor = mapped.iter();
      // First range: 0-5 becomes 0-8 (shifted by 3 for chars after pos 3)
      expect(cursor.from, 0);
      expect(cursor.to, 8);
      cursor.next();
      // Second range: 10-15 becomes 13-18 (shifted by 3)
      expect(cursor.from, 13);
      expect(cursor.to, 18);
    });

    test('maps ranges through deletion', () {
      final ranges = [
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ];
      final set = RangeSet.of(ranges);
      // Delete 3 chars at position 7 (7-10 deleted): [7 unchanged, 3 deleted -> 0 inserted, 10 unchanged]
      final changes = ChangeDesc([7, -1, 3, 0, 10, -1]);
      final mapped = set.map(changes);

      final cursor = mapped.iter();
      // First range: 0-5 unchanged
      expect(cursor.from, 0);
      expect(cursor.to, 5);
      cursor.next();
      // Second range: 10-15 becomes 7-12 (shifted left by 3)
      expect(cursor.from, 7);
      expect(cursor.to, 12);
    });
  });

  group('RangeSet.update', () {
    test('adds ranges to empty set', () {
      final set = RangeSet.of<TestValue>([]);
      final updated = set.update(RangeSetUpdate(
        add: [Range.create(0, 5, TestValue('a'))],
      ));

      expect(updated.size, 1);
      final cursor = updated.iter();
      expect(cursor.from, 0);
      expect(cursor.to, 5);
    });

    test('adds ranges to existing set', () {
      final set = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
      ]);
      final updated = set.update(RangeSetUpdate(
        add: [Range.create(10, 15, TestValue('b'))],
      ));

      expect(updated.size, 2);
    });

    test('filters ranges', () {
      final set = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
        Range.create(20, 25, TestValue('c')),
      ]);
      final updated = set.update(RangeSetUpdate(
        filter: (from, to, value) => (value as TestValue).name != 'b',
      ));

      expect(updated.size, 2);
      final cursor = updated.iter();
      expect((cursor.value as TestValue).name, 'a');
      cursor.next();
      expect((cursor.value as TestValue).name, 'c');
    });

    test('adds and filters at same time', () {
      final set = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ]);
      final updated = set.update(RangeSetUpdate(
        add: [Range.create(20, 25, TestValue('c'))],
        filter: (from, to, value) => (value as TestValue).name != 'a',
      ));

      expect(updated.size, 2);
      final cursor = updated.iter();
      expect((cursor.value as TestValue).name, 'b');
      cursor.next();
      expect((cursor.value as TestValue).name, 'c');
    });
  });

  group('RangeSet.eq', () {
    test('empty sets are equal', () {
      final a = RangeSet.of<TestValue>([]);
      final b = RangeSet.of<TestValue>([]);
      expect(RangeSet.eq([a], [b]), true);
    });

    test('same ranges are equal', () {
      final a = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ]);
      final b = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
        Range.create(10, 15, TestValue('b')),
      ]);
      expect(RangeSet.eq([a], [b]), true);
    });

    test('different ranges are not equal', () {
      final a = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
      ]);
      final b = RangeSet.of([
        Range.create(0, 5, TestValue('b')),
      ]);
      expect(RangeSet.eq([a], [b]), false);
    });

    test('different positions are not equal', () {
      final a = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
      ]);
      final b = RangeSet.of([
        Range.create(0, 10, TestValue('a')),
      ]);
      expect(RangeSet.eq([a], [b]), false);
    });
  });

  group('RangeSet.join', () {
    test('joins empty list returns empty', () {
      final joined = RangeSet.join<TestValue>([]);
      expect(joined.isEmpty, true);
    });

    test('joins single set returns same', () {
      final set = RangeSet.of([
        Range.create(0, 5, TestValue('a')),
      ]);
      final joined = RangeSet.join([set]);
      expect(joined.size, 1);
    });

    test('joins multiple sets', () {
      final a = RangeSet.of([Range.create(0, 5, TestValue('a'))]);
      final b = RangeSet.of([Range.create(10, 15, TestValue('b'))]);
      final joined = RangeSet.join([a, b]);

      expect(joined.size, 2);
    });
  });

  group('RangeSetBuilder', () {
    test('builds empty set', () {
      final builder = RangeSetBuilder<TestValue>();
      final set = builder.finish();
      expect(set.isEmpty, true);
    });

    test('builds set with ranges', () {
      final builder = RangeSetBuilder<TestValue>();
      builder.add(0, 5, TestValue('a'));
      builder.add(10, 15, TestValue('b'));
      final set = builder.finish();

      expect(set.size, 2);
    });

    test('throws on unsorted ranges', () {
      final builder = RangeSetBuilder<TestValue>();
      builder.add(10, 15, TestValue('a'));
      expect(
        () => builder.add(0, 5, TestValue('b')),
        throwsArgumentError,
      );
    });
  });

  group('Point ranges', () {
    test('point ranges work with spans', () {
      final ranges = [
        Range.create(5, 5, TestValue('point', point: true)),
        Range.create(0, 10, TestValue('range')),
      ];
      final set = RangeSet.of(ranges, true);

      final spans = <String>[];
      final points = <String>[];
      
      RangeSet.spans([set], 0, 20, _TestSpanIterator(spans, points));

      expect(points, isNotEmpty);
    });
  });

  group('Overlapping ranges', () {
    test('handles overlapping ranges', () {
      final ranges = [
        Range.create(0, 10, TestValue('a')),
        Range.create(5, 15, TestValue('b')),
      ];
      final set = RangeSet.of(ranges);

      expect(set.size, 2);

      final found = <String>[];
      set.between(0, 20, (from, to, value) {
        found.add((value as TestValue).name);
        return true;
      });
      expect(found, ['a', 'b']);
    });

    test('handles nested ranges', () {
      final ranges = [
        Range.create(0, 20, TestValue('outer')),
        Range.create(5, 15, TestValue('inner')),
      ];
      final set = RangeSet.of(ranges);

      expect(set.size, 2);
    });
  });

  group('Large sets', () {
    test('handles many ranges', () {
      final ranges = List.generate(
        500,
        (i) => Range.create(i * 10, i * 10 + 5, TestValue('r$i')),
      );
      final set = RangeSet.of(ranges);

      expect(set.size, 500);

      // Verify iteration works
      var count = 0;
      final cursor = set.iter();
      while (cursor.value != null) {
        count++;
        cursor.next();
      }
      expect(count, 500);
    });

    test('maps many ranges efficiently', () {
      final ranges = List.generate(
        500,
        (i) => Range.create(i * 10, i * 10 + 5, TestValue('r$i')),
      );
      final set = RangeSet.of(ranges);

      // Insert 10 chars at beginning: [0 unchanged, 0 deleted -> 10 inserted, 5000 unchanged]
      final changes = ChangeDesc([0, 10, 5000, -1]);
      final mapped = set.map(changes);

      expect(mapped.size, 500);

      // First range should be shifted by 10
      final cursor = mapped.iter();
      expect(cursor.from, 10);
    });
  });
}

class _TestSpanIterator implements SpanIterator<TestValue> {
  final List<String> spans;
  final List<String> points;

  _TestSpanIterator(this.spans, this.points);

  @override
  void span(int from, int to, List<TestValue> active, int openStart) {
    spans.add('$from-$to:${active.map((v) => v.name).join(",")}');
  }

  @override
  void point(int from, int to, TestValue value, List<TestValue> active,
      int openStart, int index) {
    points.add('$from-$to:${value.name}');
  }
}
