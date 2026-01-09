import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

void main() {
  group('SearchQuery', () {
    test('creates valid query from search string', () {
      final query = SearchQuery(search: 'hello');

      expect(query.search, 'hello');
      expect(query.valid, isTrue);
      expect(query.caseSensitive, isFalse);
      expect(query.literal, isFalse);
      expect(query.regexp, isFalse);
      expect(query.wholeWord, isFalse);
    });

    test('empty search is invalid', () {
      final query = SearchQuery(search: '');
      expect(query.valid, isFalse);
    });

    test('invalid regexp is invalid', () {
      final query = SearchQuery(search: '[', regexp: true);
      expect(query.valid, isFalse);
    });

    test('valid regexp is valid', () {
      final query = SearchQuery(search: r'\d+', regexp: true);
      expect(query.valid, isTrue);
    });

    test('unquotes escape sequences', () {
      final query = SearchQuery(search: r'hello\nworld');
      expect(query.unquoted, 'hello\nworld');
    });

    test('does not unquote in literal mode', () {
      final query = SearchQuery(search: r'hello\nworld', literal: true);
      expect(query.unquoted, r'hello\nworld');
    });

    test('eq compares all fields', () {
      final q1 = SearchQuery(search: 'hello');
      final q2 = SearchQuery(search: 'hello');
      final q3 = SearchQuery(search: 'world');
      final q4 = SearchQuery(search: 'hello', caseSensitive: true);

      expect(q1.eq(q2), isTrue);
      expect(q1.eq(q3), isFalse);
      expect(q1.eq(q4), isFalse);
    });

    test('getCursor returns appropriate cursor type', () {
      final doc = Text.of(['hello world']);
      
      final stringQuery = SearchQuery(search: 'hello');
      final stringCursor = stringQuery.getCursor(doc);
      expect(stringCursor, isA<SearchCursor>());

      final regexpQuery = SearchQuery(search: r'\w+', regexp: true);
      final regexpCursor = regexpQuery.getCursor(doc);
      expect(regexpCursor, isA<RegExpCursor>());
    });

    test('getCursor works with EditorState', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final query = SearchQuery(search: 'hello');
      
      final cursor = query.getCursor(state) as SearchCursor;
      final match = cursor.next();
      expect(match, isNotNull);
      expect(match!.from, 0);
      expect(match.to, 5);
    });

    test('unquote processes replacement text', () {
      final query = SearchQuery(search: 'old', replace: r'new\nline');
      expect(query.unquote(query.replace), 'new\nline');
    });
  });

  group('SearchQuery edge cases', () {
    test('handles special regex characters in non-regex mode', () {
      final query = SearchQuery(search: r'hello.*world');
      expect(query.valid, isTrue);
      expect(query.unquoted, r'hello.*world');
    });

    test('handles tab escape sequence', () {
      final query = SearchQuery(search: r'hello\tworld');
      expect(query.unquoted, 'hello\tworld');
    });

    test('handles carriage return escape sequence', () {
      final query = SearchQuery(search: r'hello\rworld');
      expect(query.unquoted, 'hello\rworld');
    });

    test('handles backslash escape sequence', () {
      final query = SearchQuery(search: r'hello\\world');
      expect(query.unquoted, r'hello\world');
    });
  });
}
