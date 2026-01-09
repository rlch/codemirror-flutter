/// Tests ported from ref/state/test/test-charcategory.ts
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/state/charcategory.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;

EditorState mk([Extension? extension]) {
  return EditorState.create(EditorStateConfig(
    extensions: extension,
  ));
}

void main() {
  // =========================================================================
  // Tests ported from ref/state/test/test-charcategory.ts
  // =========================================================================
  group('EditorState char categorizer', () {
    // Ported: "categorises into alphanumeric"
    test('categorises into alphanumeric', () {
      final st = mk();
      expect(st.charCategorizer(0)('1'), CharCategory.word);
      expect(st.charCategorizer(0)('a'), CharCategory.word);
    });

    // Ported: "categorises into whitespace"
    test('categorises into whitespace', () {
      final st = mk();
      expect(st.charCategorizer(0)(' '), CharCategory.space);
    });

    // Ported: "categorises into other"
    test('categorises into other', () {
      final st = mk();
      expect(st.charCategorizer(0)('/'), CharCategory.other);
      expect(st.charCategorizer(0)('<'), CharCategory.other);
    });
  });

  // =========================================================================
  // Additional Dart-specific tests
  // =========================================================================
  group('CharCategory', () {
    test('has three values', () {
      expect(CharCategory.values.length, 3);
      expect(CharCategory.values, contains(CharCategory.word));
      expect(CharCategory.values, contains(CharCategory.space));
      expect(CharCategory.values, contains(CharCategory.other));
    });
  });

  group('hasWordChar', () {
    test('returns true for ASCII letters', () {
      expect(hasWordChar('a'), true);
      expect(hasWordChar('Z'), true);
      expect(hasWordChar('hello'), true);
    });

    test('returns true for digits', () {
      expect(hasWordChar('0'), true);
      expect(hasWordChar('9'), true);
      expect(hasWordChar('123'), true);
    });

    test('returns true for underscore', () {
      expect(hasWordChar('_'), true);
      expect(hasWordChar('_foo'), true);
    });

    test('returns true for Unicode letters', () {
      expect(hasWordChar('ä'), true); // German
      expect(hasWordChar('中'), true); // Chinese
      expect(hasWordChar('日'), true); // Japanese
      expect(hasWordChar('한'), true); // Korean
      expect(hasWordChar('α'), true); // Greek
      expect(hasWordChar('ש'), true); // Hebrew
    });

    test('returns false for punctuation', () {
      expect(hasWordChar('.'), false);
      expect(hasWordChar(','), false);
      expect(hasWordChar('!'), false);
      expect(hasWordChar('-'), false);
      expect(hasWordChar('('), false);
    });

    test('returns false for whitespace', () {
      expect(hasWordChar(' '), false);
      expect(hasWordChar('\t'), false);
      expect(hasWordChar('\n'), false);
    });
  });

  group('makeCategorizer', () {
    test('categorizes basic characters', () {
      final cat = makeCategorizer('');
      expect(cat('a'), CharCategory.word);
      expect(cat('1'), CharCategory.word);
      expect(cat(' '), CharCategory.space);
      expect(cat('.'), CharCategory.other);
    });

    test('respects custom word chars', () {
      final cssCat = makeCategorizer('-');
      expect(cssCat('-'), CharCategory.word);
      expect(cssCat('background'), CharCategory.word);
      expect(cssCat('.'), CharCategory.other);
    });

    test('handles multiple custom word chars', () {
      final phpCat = makeCategorizer(r'$@');
      expect(phpCat(r'$'), CharCategory.word);
      expect(phpCat('@'), CharCategory.word);
      expect(phpCat('var'), CharCategory.word);
      expect(phpCat('.'), CharCategory.other);
    });
  });

  group('defaultCategorizer', () {
    test('categorizes word characters', () {
      expect(defaultCategorizer('a'), CharCategory.word);
      expect(defaultCategorizer('Z'), CharCategory.word);
      expect(defaultCategorizer('0'), CharCategory.word);
      expect(defaultCategorizer('9'), CharCategory.word);
      expect(defaultCategorizer('_'), CharCategory.word);
    });

    test('categorizes whitespace', () {
      expect(defaultCategorizer(' '), CharCategory.space);
      expect(defaultCategorizer('\t'), CharCategory.space);
      expect(defaultCategorizer('\n'), CharCategory.space);
      expect(defaultCategorizer('\r'), CharCategory.space);
    });

    test('categorizes punctuation as other', () {
      expect(defaultCategorizer('.'), CharCategory.other);
      expect(defaultCategorizer(','), CharCategory.other);
      expect(defaultCategorizer('!'), CharCategory.other);
      expect(defaultCategorizer('('), CharCategory.other);
      expect(defaultCategorizer(')'), CharCategory.other);
      expect(defaultCategorizer('-'), CharCategory.other);
    });

    test('handles Unicode letters as word chars', () {
      expect(defaultCategorizer('中'), CharCategory.word);
      expect(defaultCategorizer('ä'), CharCategory.word);
      expect(defaultCategorizer('日'), CharCategory.word);
    });
  });

  group('EditorState.charCategorizer with language data', () {
    test('returns default categorizer without language data', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final cat = state.charCategorizer(0);
      
      expect(cat('a'), CharCategory.word);
      expect(cat(' '), CharCategory.space);
      expect(cat('.'), CharCategory.other);
    });

    test('respects wordChars from language data', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'background-color',
        extensions: languageData.of((state, pos, side) => [
          {'wordChars': '-'}
        ]),
      ));
      
      final cat = state.charCategorizer(0);
      expect(cat('-'), CharCategory.word);
      expect(cat('b'), CharCategory.word);
      expect(cat('.'), CharCategory.other);
    });

    test('combines multiple wordChars sources', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'test',
        extensions: ExtensionList([
          languageData.of((state, pos, side) => [
            {'wordChars': '-'}
          ]),
          languageData.of((state, pos, side) => [
            {'wordChars': '@'}
          ]),
        ]),
      ));
      
      final cat = state.charCategorizer(0);
      expect(cat('-'), CharCategory.word);
      expect(cat('@'), CharCategory.word);
      expect(cat('.'), CharCategory.other);
    });
  });
}
