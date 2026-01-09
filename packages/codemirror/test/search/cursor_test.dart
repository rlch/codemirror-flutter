import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

void main() {
  group('SearchCursor', () {
    test('finds simple matches', () {
      final doc = Text.of(['hello world hello']);
      final cursor = SearchCursor(doc, 'hello');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 5);

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.from, 12);
      expect(match2.to, 17);

      final match3 = cursor.next();
      expect(match3, isNull);
    });

    test('finds no matches in empty document', () {
      final doc = Text.of(['']);
      final cursor = SearchCursor(doc, 'hello');

      expect(cursor.next(), isNull);
    });

    test('empty query finds nothing', () {
      final doc = Text.of(['abc']);
      final cursor = SearchCursor(doc, '');

      // Empty query should find nothing
      expect(cursor.next(), isNull);
      expect(cursor.done, isTrue);
    });

    test('case insensitive search', () {
      final doc = Text.of(['Hello HELLO hello']);
      final cursor = SearchCursor(
        doc,
        'hello',
        normalize: (s) => s.toLowerCase(),
      );

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 5);

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.from, 6);
      expect(match2.to, 11);

      final match3 = cursor.next();
      expect(match3, isNotNull);
      expect(match3!.from, 12);
      expect(match3.to, 17);
    });

    test('searches within range', () {
      final doc = Text.of(['hello world hello']);
      final cursor = SearchCursor(doc, 'hello', from: 6);

      final match = cursor.next();
      expect(match, isNotNull);
      expect(match!.from, 12);
      expect(match.to, 17);

      expect(cursor.next(), isNull);
    });

    test('searches up to range end', () {
      final doc = Text.of(['hello world hello']);
      final cursor = SearchCursor(doc, 'hello', from: 0, to: 10);

      final match = cursor.next();
      expect(match, isNotNull);
      expect(match!.from, 0);
      expect(match.to, 5);

      expect(cursor.next(), isNull);
    });

    test('handles multi-line document', () {
      final doc = Text.of(['hello', 'world', 'hello']);
      final cursor = SearchCursor(doc, 'hello');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 5);

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.from, 12);
      expect(match2.to, 17);
    });

    test('implements Iterator interface', () {
      final doc = Text.of(['aaa']);
      final cursor = SearchCursor(doc, 'a');

      final matches = <({int from, int to})>[];
      while (cursor.moveNext()) {
        matches.add(cursor.current);
      }

      expect(matches.length, 3);
      expect(matches[0].from, 0);
      expect(matches[1].from, 1);
      expect(matches[2].from, 2);
    });

    test('finds overlapping matches', () {
      final doc = Text.of(['aaa']);
      final cursor = SearchCursor(doc, 'aa');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 2);

      // Without overlapping, should only find one match
      // The next() method clears matches before searching
      expect(cursor.next(), isNull);
    });

    test('nextOverlapping finds overlapping matches', () {
      final doc = Text.of(['aaa']);
      final cursor = SearchCursor(doc, 'aa');

      cursor.next(); // Find first match

      final match2 = cursor.nextOverlapping();
      expect(match2, isNotNull);
      expect(match2!.from, 1);
      expect(match2.to, 3);
    });
  });
}
