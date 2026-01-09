// Text tests ported from CodeMirror's ref/text/test/test-text.ts
//
// This test file is a direct port of the original CodeMirror test suite
// to ensure feature parity and correct behavior.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/text/text.dart';

/// Helper to get tree depth.
int depth(Text node) {
  if (node.children == null) return 1;
  return 1 + node.children!.map(depth).reduce(max);
}

void main() {
  // Setup large test document (matches CodeMirror's test setup)
  final line = '1234567890' * 10; // 100 chars
  final lines = List.filled(200, line);
  final text0 = lines.join('\n');
  final doc0 = Text.of(lines);

  group('Text', () {
    // Ported from test-text.ts: "handles basic replacement"
    test('handles basic replacement', () {
      final doc = Text.of(['one', 'two', 'three']);
      expect(
        doc.replace(2, 5, Text.of(['foo', 'bar'])).toString(),
        'onfoo\nbarwo\nthree',
      );
    });

    // Ported from test-text.ts: "can append documents"
    test('can append documents', () {
      expect(
        Text.of(['one', 'two', 'three']).append(Text.of(['!', 'ok'])).toString(),
        'one\ntwo\nthree!\nok',
      );
    });

    // Ported from test-text.ts: "preserves length"
    test('preserves length', () {
      expect(doc0.length, text0.length);
    });

    // Ported from test-text.ts: "creates a balanced tree when loading a document"
    test('creates a balanced tree when loading a document', () {
      final doc = Text.of(List.filled(2000, line));
      final d = depth(doc);
      expect(d, lessThanOrEqualTo(2));
    });

    // Ported from test-text.ts: "rebalances on insert"
    test('rebalances on insert', () {
      var doc = doc0;
      final insert = 'abc' * 200;
      final at = doc.length ~/ 2;
      for (var i = 0; i < 10; i++) {
        doc = doc.replace(at, at, Text.of([insert]));
      }
      expect(depth(doc), lessThanOrEqualTo(2));
      expect(doc.toString(), text0.substring(0, at) + ('abc' * 2000) + text0.substring(at));
    });

    // Ported from test-text.ts: "collapses on delete"
    test('collapses on delete', () {
      final doc = doc0.replace(10, text0.length - 10, Text.empty);
      expect(depth(doc), 1);
      expect(doc.length, 20);
      expect(doc.toString(), line.substring(0, 20));
    });

    // Ported from test-text.ts: "handles deleting at start"
    test('handles deleting at start', () {
      final modifiedLines = [...lines.sublist(0, lines.length - 1), '$line!'];
      expect(
        Text.of(modifiedLines).replace(0, 9500, Text.empty).toString(),
        '${text0.substring(9500)}!',
      );
    });

    // Ported from test-text.ts: "handles deleting at end"
    test('handles deleting at end', () {
      final modifiedLines = ['?$line', ...lines.sublist(1)];
      expect(
        Text.of(modifiedLines).replace(9500, text0.length + 1, Text.empty).toString(),
        '?${text0.substring(0, 9499)}',
      );
    });

    // Ported from test-text.ts: "can handle deleting the entire document"
    test('can handle deleting the entire document', () {
      expect(doc0.replace(0, doc0.length, Text.empty).toString(), '');
    });

    // Ported from test-text.ts: "can insert on node boundaries"
    test('can insert on node boundaries', () {
      final doc = doc0;
      final pos = doc.children![0].length;
      expect(
        doc.replace(pos, pos, Text.of(['abc'])).slice(pos, pos + 3).toString(),
        'abc',
      );
    });

    // Ported from test-text.ts: "can build up a doc by repeated appending"
    test('can build up a doc by repeated appending', () {
      var doc = Text.of(['']);
      var text = '';
      for (var i = 1; i < 1000; ++i) {
        final add = 'newtext$i ';
        doc = doc.replace(doc.length, doc.length, Text.of([add]));
        text += add;
      }
      expect(doc.toString(), text);
    });

    // Ported from test-text.ts: "properly maintains content during editing"
    test('properly maintains content during editing', () {
      final random = Random(42); // Seeded for reproducibility
      var str = text0;
      var doc = doc0;
      for (var i = 0; i < 200; i++) {
        final insPos = random.nextInt(doc.length);
        final insChar = String.fromCharCode('A'.codeUnitAt(0) + random.nextInt(26));
        str = str.substring(0, insPos) + insChar + str.substring(insPos);
        doc = doc.replace(insPos, insPos, Text.of([insChar]));
        final delFrom = random.nextInt(doc.length);
        final delTo = min(doc.length, delFrom + random.nextInt(20));
        str = str.substring(0, delFrom) + str.substring(delTo);
        doc = doc.replace(delFrom, delTo, Text.empty);
      }
      expect(doc.toString(), str);
    });

    // Ported from test-text.ts: "returns the correct strings for slice"
    test('returns the correct strings for slice', () {
      final text = List.generate(1000, (i) => i.toString().padLeft(4, '0'));
      final doc = Text.of(text);
      final str = text.join('\n');
      final random = Random(42);
      for (var i = 0; i < 400; i++) {
        final start = i == 0 ? 0 : random.nextInt(doc.length);
        final end = i == 399 ? doc.length : start + random.nextInt(doc.length - start);
        // Note: Original test had fixed values on lines 96-97; we test general case
        expect(doc.slice(start, end).toString(), str.substring(start, end));
      }
    });

    // Ported from test-text.ts: "can be compared"
    test('can be compared', () {
      final doc = doc0;
      final doc2 = Text.of(lines);
      expect(doc.eq(doc), true);
      expect(doc.eq(doc2), true);
      expect(doc2.eq(doc), true);
      expect(doc.eq(doc2.replace(5000, 5000, Text.of(['y']))), false);
      expect(doc.eq(doc2.replace(5000, 5001, Text.of(['y']))), false);
      expect(doc.eq(doc.replace(5000, 5001, doc.slice(5000, 5001))), true);
      expect(doc.eq(doc.replace(5000, 5001, Text.of(['y']))), false);
    });

    // Ported from test-text.ts: "can be compared despite different tree shape"
    test('can be compared despite different tree shape', () {
      expect(
        doc0.replace(100, 201, Text.of(['abc'])).eq(
          Text.of(['${line}abc', ...lines.sublist(2)]),
        ),
        true,
      );
    });

    // Ported from test-text.ts: "can compare small documents"
    test('can compare small documents', () {
      expect(Text.of(['foo', 'bar']).eq(Text.of(['foo', 'bar'])), true);
      expect(Text.of(['foo', 'bar']).eq(Text.of(['foo', 'baz'])), false);
    });

    // Ported from test-text.ts: "is iterable"
    test('is iterable', () {
      var build = '';
      for (final iter = doc0.iter();;) {
        iter.next();
        if (iter.done) {
          expect(build, text0);
          break;
        }
        if (iter.lineBreak) {
          build += '\n';
        } else {
          expect(iter.value.contains('\n'), false);
          build += iter.value;
        }
      }
    });

    // Ported from test-text.ts: "is iterable in reverse"
    test('is iterable in reverse', () {
      var found = '';
      for (final iter = doc0.iter(-1); !iter.next().done;) {
        found = iter.value + found;
      }
      expect(found, text0);
    });

    // Ported from test-text.ts: "allows negative skip values in iteration"
    test('allows negative skip values in iteration', () {
      final iter = Text.of(['one', 'two', 'three', 'four']).iter();
      expect(iter.next(12).value, 'e');
      expect(iter.next(-12).value, 'ne');
      expect(iter.next(12).value, 'our');
      expect(iter.next(-1000).value, 'one');
    });

    // Ported from test-text.ts: "is partially iterable"
    test('is partially iterable', () {
      var found = '';
      for (final iter = doc0.iterRange(500, doc0.length - 500); !iter.next().done;) {
        found += iter.value;
      }
      expect(found, text0.substring(500, text0.length - 500));
    });

    // Ported from test-text.ts: "is partially iterable in reverse"
    test('is partially iterable in reverse', () {
      var found = '';
      for (final iter = doc0.iterRange(doc0.length - 500, 500); !iter.next().done;) {
        found = iter.value + found;
      }
      expect(found, text0.substring(500, text0.length - 500));
    });

    // Ported from test-text.ts: "can partially iter over subsections at the start and end"
    test('can partially iter over subsections at the start and end', () {
      expect(doc0.iterRange(0, 1).next().value, '1');
      expect(doc0.iterRange(1, 2).next().value, '2');
      expect(doc0.iterRange(doc0.length - 1, doc0.length).next().value, '0');
      expect(doc0.iterRange(doc0.length - 2, doc0.length - 1).next().value, '9');
    });

    // Ported from test-text.ts: "can iterate over lines"
    test('can iterate over lines', () {
      final doc = Text.of(['ab', 'cde', '', '', 'f', '', 'g']);
      
      String get([int? from, int? to]) {
        final result = <String>[];
        for (final iter = doc.iterLines(from, to); !iter.next().done;) {
          result.add(iter.value);
        }
        return result.join('\n');
      }
      
      expect(get(), 'ab\ncde\n\n\nf\n\ng');
      expect(get(1, doc.lines + 1), 'ab\ncde\n\n\nf\n\ng');
      expect(get(2, 3), 'cde');
      expect(get(1, 1), '');
      expect(get(2, 1), '');
      expect(get(3), '\n\nf\n\ng');
    });

    // Ported from test-text.ts: "can convert to JSON"
    test('can convert to JSON', () {
      final extendedLines = [...lines];
      for (var i = 0; i < 200; i++) {
        extendedLines.add('line $i');
      }
      final text = Text.of(extendedLines);
      expect(Text.of(text.toJson()).eq(text), true);
    });

    // Ported from test-text.ts: "can get line info by line number"
    test('can get line info by line number', () {
      expect(() => doc0.line(0), throwsRangeError);
      expect(() => doc0.line(doc0.lines + 1), throwsRangeError);
      for (var i = 1; i < doc0.lines; i += 5) {
        final l = doc0.line(i);
        expect(l.from, (i - 1) * 101);
        expect(l.to, i * 101 - 1);
        expect(l.number, i);
        expect(l.text, line);
      }
    });

    // Ported from test-text.ts: "can get line info by position"
    test('can get line info by position', () {
      expect(() => doc0.lineAt(-10), throwsRangeError);
      expect(() => doc0.lineAt(doc0.length + 1), throwsRangeError);
      for (var i = 0; i < doc0.length; i += 5) {
        final l = doc0.lineAt(i);
        expect(l.from, i - (i % 101));
        expect(l.to, i - (i % 101) + 100);
        expect(l.number, i ~/ 101 + 1);
        expect(l.text, line);
      }
    });

    // Ported from test-text.ts: "can delete a range at the start of a child node"
    test('can delete a range at the start of a child node', () {
      expect(doc0.replace(0, 100, Text.of(['x'])).toString(), 'x${text0.substring(100)}');
    });

    // Ported from test-text.ts: "can retrieve pieces of text"
    test('can retrieve pieces of text', () {
      final random = Random(42);
      for (var i = 0; i < 500; i++) {
        final from = random.nextInt(doc0.length - 1);
        final to = random.nextDouble() < 0.5
            ? from + 2
            : from + random.nextInt(doc0.length - 1 - from) + 1;
        expect(doc0.sliceString(from, to), text0.substring(from, to));
        expect(doc0.slice(from, to).toString(), text0.substring(from, to));
      }
    });
  });

  // Additional tests from our original test file that aren't in CodeMirror's suite
  // but are useful for Dart-specific behavior validation
  group('Text (additional Dart-specific tests)', () {
    group('Text.of', () {
      test('creates empty document', () {
        final doc = Text.of(['']);
        expect(doc.length, 0);
        expect(doc.lines, 1);
        expect(doc.toString(), '');
      });

      test('creates single line document', () {
        final doc = Text.of(['hello']);
        expect(doc.length, 5);
        expect(doc.lines, 1);
        expect(doc.toString(), 'hello');
      });

      test('creates multi-line document', () {
        final doc = Text.of(['hello', 'world']);
        expect(doc.length, 11); // 5 + 1 (newline) + 5
        expect(doc.lines, 2);
        expect(doc.toString(), 'hello\nworld');
      });

      test('throws on empty list', () {
        expect(() => Text.of([]), throwsRangeError);
      });

      test('handles large documents', () {
        // Create a document larger than branch factor (32)
        final lines = List.generate(100, (i) => 'Line $i');
        final doc = Text.of(lines);
        expect(doc.lines, 100);
        expect(doc is TextNode, true);
      });
    });

    group('sliceString', () {
      test('returns full string', () {
        final doc = Text.of(['hello', 'world']);
        expect(doc.sliceString(0), 'hello\nworld');
      });

      test('uses custom line separator', () {
        final doc = Text.of(['hello', 'world']);
        expect(doc.sliceString(0, null, '\r\n'), 'hello\r\nworld');
      });
    });

    group('toJson', () {
      test('returns list of lines', () {
        final doc = Text.of(['hello', 'world']);
        expect(doc.toJson(), ['hello', 'world']);
      });
    });
  });

  group('TextIterator (additional)', () {
    test('iterates forward', () {
      final doc = Text.of(['hello', 'world']);
      final iter = doc.iter();

      iter.next();
      expect(iter.value, 'hello');
      expect(iter.lineBreak, false);

      iter.next();
      expect(iter.value, '\n');
      expect(iter.lineBreak, true);

      iter.next();
      expect(iter.value, 'world');
      expect(iter.lineBreak, false);

      iter.next();
      expect(iter.done, true);
    });

    test('iterates backward', () {
      final doc = Text.of(['hello', 'world']);
      final iter = doc.iter(-1);

      iter.next();
      expect(iter.value, 'world');

      iter.next();
      expect(iter.lineBreak, true);

      iter.next();
      expect(iter.value, 'hello');

      iter.next();
      expect(iter.done, true);
    });

    test('iterates range', () {
      final doc = Text.of(['hello', 'world', 'test']);
      final iter = doc.iterRange(6, 11);

      iter.next();
      expect(iter.value, 'world');

      iter.next();
      expect(iter.done, true);
    });

    test('iterates lines via moveNext', () {
      final doc = Text.of(['hello', 'world', 'test']);
      final iter = doc.iterLines();
      final lines = <String>[];

      while (iter.moveNext()) {
        lines.add(iter.current);
      }

      expect(lines, ['hello', 'world', 'test']);
    });
  });

  group('Line', () {
    test('has correct properties', () {
      final line = Line(0, 5, 1, 'hello');
      expect(line.from, 0);
      expect(line.to, 5);
      expect(line.number, 1);
      expect(line.text, 'hello');
      expect(line.length, 5);
    });

    test('equality works', () {
      final line1 = Line(0, 5, 1, 'hello');
      final line2 = Line(0, 5, 1, 'hello');
      final line3 = Line(0, 5, 1, 'world');

      expect(line1, equals(line2));
      expect(line1, isNot(equals(line3)));
    });
  });

  group('Large documents', () {
    test('handles 1000 lines', () {
      final lines = List.generate(1000, (i) => 'Line number $i');
      final doc = Text.of(lines);

      expect(doc.lines, 1000);
      expect(doc.line(1).text, 'Line number 0');
      expect(doc.line(500).text, 'Line number 499');
      expect(doc.line(1000).text, 'Line number 999');
    });

    test('replace in large document', () {
      final lines = List.generate(100, (i) => 'Line $i');
      final doc = Text.of(lines);

      // Replace middle line
      final line50 = doc.line(50);
      final result = doc.replace(line50.from, line50.to, Text.of(['REPLACED']));

      expect(result.lines, 100);
      expect(result.line(50).text, 'REPLACED');
    });
  });
}
