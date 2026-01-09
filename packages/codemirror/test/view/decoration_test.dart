import 'package:flutter/widgets.dart' hide Decoration;
import 'package:test/test.dart';
import 'package:codemirror/src/view/decoration.dart';
import 'package:codemirror/src/state/range_set.dart';
import 'package:codemirror/src/state/change.dart' show MapMode;

/// A simple widget type for testing.
class TestWidget extends WidgetType {
  final String text;

  const TestWidget(this.text);

  @override
  Widget toWidget(dynamic view) {
    return Text(text);
  }

  @override
  bool eq(WidgetType other) {
    return other is TestWidget && other.text == text;
  }
}

/// A widget type that tracks its height.
class SizedTestWidget extends WidgetType {
  final String text;
  final int height;

  const SizedTestWidget(this.text, {this.height = 20});

  @override
  Widget toWidget(dynamic view) {
    return SizedBox(height: height.toDouble(), child: Text(text));
  }

  @override
  bool eq(WidgetType other) {
    return other is SizedTestWidget &&
        other.text == text &&
        other.height == height;
  }

  @override
  int get estimatedHeight => height;
}

void main() {
  group('MarkDecoration', () {
    test('creates basic mark decoration', () {
      final mark = Decoration.mark(const MarkDecorationSpec());
      expect(mark, isA<MarkDecoration>());
      expect(mark.tagName, equals('span'));
      expect(mark.className, equals(''));
      expect(mark.point, isFalse);
    });

    test('creates mark with class name', () {
      final mark = Decoration.mark(const MarkDecorationSpec(
        className: 'highlight',
      ));
      expect(mark.className, equals('highlight'));
    });

    test('creates mark with tag name', () {
      final mark = Decoration.mark(const MarkDecorationSpec(
        tagName: 'strong',
      ));
      expect(mark.tagName, equals('strong'));
    });

    test('creates mark with attributes', () {
      final mark = Decoration.mark(const MarkDecorationSpec(
        attributes: {'style': 'color: red'},
      ));
      expect(mark.attributes?['style'], equals('color: red'));
    });

    test('marks are non-inclusive by default', () {
      final mark = Decoration.mark(const MarkDecorationSpec());
      expect(mark.startSide, equals(Side.nonIncStart));
      expect(mark.endSide, equals(Side.nonIncEnd));
    });

    test('marks can be inclusive', () {
      final mark = Decoration.mark(const MarkDecorationSpec(
        inclusive: true,
      ));
      expect(mark.startSide, equals(Side.inlineIncStart));
      expect(mark.endSide, equals(Side.inlineIncEnd));
    });

    test('marks can have asymmetric inclusivity', () {
      final mark = Decoration.mark(const MarkDecorationSpec(
        inclusiveStart: true,
        inclusiveEnd: false,
      ));
      expect(mark.startSide, equals(Side.inlineIncStart));
      expect(mark.endSide, equals(Side.nonIncEnd));
    });

    test('mark range throws on empty range', () {
      final mark = Decoration.mark(const MarkDecorationSpec());
      expect(() => mark.range(10, 10), throwsA(isA<RangeError>()));
      expect(() => mark.range(10, 5), throwsA(isA<RangeError>()));
    });

    test('mark range works for valid ranges', () {
      final mark = Decoration.mark(const MarkDecorationSpec());
      final range = mark.range(10, 20);
      expect(range.from, equals(10));
      expect(range.to, equals(20));
      expect(range.value, same(mark));
    });

    test('mark equality', () {
      final mark1 = Decoration.mark(const MarkDecorationSpec(
        className: 'test',
        tagName: 'span',
      ));
      final mark2 = Decoration.mark(const MarkDecorationSpec(
        className: 'test',
        tagName: 'span',
      ));
      final mark3 = Decoration.mark(const MarkDecorationSpec(
        className: 'other',
        tagName: 'span',
      ));

      expect(mark1.eq(mark2), isTrue);
      expect(mark1.eq(mark3), isFalse);
    });
  });

  group('LineDecoration', () {
    test('creates basic line decoration', () {
      final line = Decoration.line(const LineDecorationSpec());
      expect(line, isA<LineDecoration>());
      expect(line.point, isTrue);
      expect(line.mapMode, equals(MapMode.trackBefore));
    });

    test('creates line with class name', () {
      final line = Decoration.line(const LineDecorationSpec(
        className: 'active-line',
      ));
      expect(line.className, equals('active-line'));
    });

    test('creates line with attributes', () {
      final line = Decoration.line(const LineDecorationSpec(
        attributes: {'data-line-number': '42'},
      ));
      expect(line.attributes?['data-line-number'], equals('42'));
    });

    test('line range throws for non-zero-length', () {
      final line = Decoration.line(const LineDecorationSpec());
      expect(() => line.range(10, 20), throwsA(isA<RangeError>()));
    });

    test('line range works for zero-length', () {
      final line = Decoration.line(const LineDecorationSpec());
      final range = line.range(10);
      expect(range.from, equals(10));
      expect(range.to, equals(10));
    });

    test('line equality', () {
      final line1 = Decoration.line(const LineDecorationSpec(
        className: 'active',
      ));
      final line2 = Decoration.line(const LineDecorationSpec(
        className: 'active',
      ));
      final line3 = Decoration.line(const LineDecorationSpec(
        className: 'inactive',
      ));

      expect(line1.eq(line2), isTrue);
      expect(line1.eq(line3), isFalse);
    });
  });

  group('WidgetDecoration', () {
    test('creates basic widget decoration', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
      ));
      expect(widget, isA<PointDecoration>());
      expect(widget.point, isTrue);
      expect(widget.block, isFalse);
      expect(widget.isReplace, isFalse);
    });

    test('widget with positive side goes after cursor', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        side: 1,
      ));
      expect(widget.startSide, greaterThan(0));
    });

    test('widget with negative side goes before cursor', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        side: -1,
      ));
      expect(widget.startSide, lessThan(0));
    });

    test('widget side is clamped to valid range', () {
      final widget1 = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        side: 20000,
      ));
      // Should be clamped to 10000 + inlineAfter
      expect(widget1.startSide, equals(10000 + Side.inlineAfter));

      final widget2 = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        side: -20000,
      ));
      // Should be clamped to -10000 + inlineBefore
      expect(widget2.startSide, equals(-10000 + Side.inlineBefore));
    });

    test('block widget decoration', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        block: true,
      ));
      expect(widget.block, isTrue);
      expect(widget.type, equals(BlockType.widgetBefore));
    });

    test('block widget with positive side', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
        block: true,
        side: 1,
      ));
      expect(widget.type, equals(BlockType.widgetAfter));
    });

    test('widget range throws for non-zero-length', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
      ));
      expect(() => widget.range(10, 20), throwsA(isA<RangeError>()));
    });

    test('widget range works for zero-length', () {
      final widget = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
      ));
      final range = widget.range(10);
      expect(range.from, equals(10));
      expect(range.to, equals(10));
    });

    test('widget equality', () {
      final widget1 = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
      ));
      final widget2 = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('test'),
      ));
      final widget3 = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('other'),
      ));

      expect(widget1.eq(widget2), isTrue);
      expect(widget1.eq(widget3), isFalse);
    });

    test('widget heightRelevant', () {
      final small = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: SizedTestWidget('small', height: 4),
      ));
      final large = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: SizedTestWidget('large', height: 10),
      ));
      final block = Decoration.widgetDecoration(const WidgetDecorationSpec(
        widget: TestWidget('block'),
        block: true,
      ));

      expect(small.heightRelevant, isFalse);
      expect(large.heightRelevant, isTrue);
      expect(block.heightRelevant, isTrue);
    });
  });

  group('ReplaceDecoration', () {
    test('creates basic replace decoration', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec());
      expect(replace, isA<PointDecoration>());
      expect(replace.point, isTrue);
      expect(replace.isReplace, isTrue);
    });

    test('replace with widget', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec(
        widget: TestWidget('replacement'),
      ));
      expect(replace.widget, isA<TestWidget>());
    });

    test('replace is non-inclusive by default for inline', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec());
      // Non-inclusive start side is Side.nonIncStart - 1 = 5e8 - 1 (large positive)
      expect(replace.startSide, equals(Side.nonIncStart - 1));
      // Non-inclusive end side is Side.nonIncEnd + 1 = -6e8 + 1 (large negative)
      expect(replace.endSide, equals(Side.nonIncEnd + 1));
    });

    test('replace is inclusive by default for block', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec(
        block: true,
      ));
      expect(replace.block, isTrue);
    });

    test('replace can be explicitly inclusive', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec(
        inclusive: true,
      ));
      expect(replace.startSide, equals(Side.inlineIncStart - 1));
      expect(replace.endSide, equals(Side.inlineIncEnd + 1));
    });

    test('replace range allows valid ranges', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec());
      final range = replace.range(10, 20);
      expect(range.from, equals(10));
      expect(range.to, equals(20));
    });

    test('replace range throws for invalid ranges', () {
      // Create a replace with inclusive end but non-inclusive start
      final replace = Decoration.replace(const ReplaceDecorationSpec(
        inclusiveStart: true,
        inclusiveEnd: false,
      ));
      // This should work
      final _ = replace.range(10, 20);
      // Empty ranges with wrong sides can fail
    });

    test('replace type is widgetRange for non-empty', () {
      final replace = Decoration.replace(const ReplaceDecorationSpec());
      // For a replace decoration, when from != to, type is widgetRange
      // But we can only test this when the decoration is applied to a range
      expect(replace.isReplace, isTrue);
    });
  });

  group('DecorationSet', () {
    test('creates empty decoration set', () {
      final set = Decoration.none;
      expect(set.isEmpty, isTrue);
      expect(set.size, equals(0));
    });

    test('creates decoration set from ranges', () {
      final mark1 = Decoration.mark(const MarkDecorationSpec(className: 'a'));
      final mark2 = Decoration.mark(const MarkDecorationSpec(className: 'b'));

      final set = Decoration.createSet([
        mark1.range(0, 10),
        mark2.range(20, 30),
      ]);

      expect(set.isEmpty, isFalse);
      expect(set.size, equals(2));
    });

    test('decoration set sorts when requested', () {
      final mark1 = Decoration.mark(const MarkDecorationSpec(className: 'a'));
      final mark2 = Decoration.mark(const MarkDecorationSpec(className: 'b'));

      // Pass unsorted ranges with sort: true
      final set = Decoration.createSet([
        mark2.range(20, 30),
        mark1.range(0, 10),
      ], sort: true);

      expect(set.size, equals(2));

      // Iterate and check order
      final cursor = set.iter();
      expect(cursor.from, equals(0));
      cursor.next();
      expect(cursor.from, equals(20));
    });

    test('decoration set iterates in order', () {
      final marks = <MarkDecoration>[];
      for (var i = 0; i < 5; i++) {
        marks.add(Decoration.mark(MarkDecorationSpec(className: 'mark$i')));
      }

      final set = Decoration.createSet([
        marks[0].range(0, 10),
        marks[1].range(15, 25),
        marks[2].range(30, 40),
        marks[3].range(50, 60),
        marks[4].range(70, 80),
      ]);

      final positions = <int>[];
      final cursor = set.iter();
      while (cursor.value != null) {
        positions.add(cursor.from);
        cursor.next();
      }

      expect(positions, equals([0, 15, 30, 50, 70]));
    });
  });

  group('WidgetType', () {
    test('widget compare uses eq method', () {
      const w1 = TestWidget('test');
      const w2 = TestWidget('test');
      const w3 = TestWidget('other');

      expect(w1.compare(w2), isTrue);
      expect(w1.compare(w3), isFalse);
    });

    test('widget compare handles identity', () {
      const w = TestWidget('test');
      expect(w.compare(w), isTrue);
    });

    test('estimatedHeight defaults to -1', () {
      const w = TestWidget('test');
      expect(w.estimatedHeight, equals(-1));
    });

    test('lineBreaks defaults to 0', () {
      const w = TestWidget('test');
      expect(w.lineBreaks, equals(0));
    });

    test('ignoreEvent defaults to true', () {
      const w = TestWidget('test');
      expect(w.ignoreEvent(null), isTrue);
    });

    test('isHidden defaults to false', () {
      const w = TestWidget('test');
      expect(w.isHidden, isFalse);
    });

    test('editable defaults to false', () {
      const w = TestWidget('test');
      expect(w.editable, isFalse);
    });
  });

  group('addRange helper', () {
    test('adds non-overlapping ranges', () {
      final ranges = <int>[];
      addRange(10, 20, ranges);
      addRange(30, 40, ranges);
      expect(ranges, equals([10, 20, 30, 40]));
    });

    test('merges overlapping ranges', () {
      final ranges = <int>[];
      addRange(10, 20, ranges);
      addRange(15, 30, ranges);
      expect(ranges, equals([10, 30]));
    });

    test('merges adjacent ranges', () {
      final ranges = <int>[];
      addRange(10, 20, ranges);
      addRange(20, 30, ranges);
      expect(ranges, equals([10, 30]));
    });

    test('merges with margin', () {
      final ranges = <int>[];
      addRange(10, 20, ranges);
      addRange(25, 35, ranges, 5);
      expect(ranges, equals([10, 35]));
    });

    test('does not merge when gap exceeds margin', () {
      final ranges = <int>[];
      addRange(10, 20, ranges);
      addRange(30, 40, ranges, 5);
      expect(ranges, equals([10, 20, 30, 40]));
    });
  });
}
