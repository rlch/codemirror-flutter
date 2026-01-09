import 'package:flutter/widgets.dart' hide Decoration;
import 'package:test/test.dart';

import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/view/placeholder.dart';

void main() {
  group('placeholder', () {
    test('creates extension with string content', () {
      final ext = placeholder('Enter text...');
      expect(ext, isA<Extension>());
    });

    test('creates extension with empty string', () {
      final ext = placeholder('');
      expect(ext, isA<Extension>());
    });

    test('string placeholder adds content attributes', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: placeholder('Enter text...'),
      ));

      final attrs = state.facet(contentAttributes);
      expect(attrs['aria-placeholder'], equals('Enter text...'));
    });

    test('non-string placeholder does not add aria attribute', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: placeholder(const Text('Custom widget')),
      ));

      final attrs = state.facet(contentAttributes);
      // Non-string content should not set aria-placeholder
      expect(attrs['aria-placeholder'], isNull);
    });
  });

  group('contentAttributes facet', () {
    test('combines multiple attribute maps', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: ExtensionList([
          contentAttributes.of({'attr1': 'value1'}),
          contentAttributes.of({'attr2': 'value2'}),
        ]),
      ));

      final attrs = state.facet(contentAttributes);
      expect(attrs['attr1'], equals('value1'));
      expect(attrs['attr2'], equals('value2'));
    });

    test('later values override earlier ones', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: ExtensionList([
          contentAttributes.of({'attr': 'first'}),
          contentAttributes.of({'attr': 'second'}),
        ]),
      ));

      final attrs = state.facet(contentAttributes);
      expect(attrs['attr'], equals('second'));
    });

    test('returns empty map when no providers', () {
      final state = EditorState.create(EditorStateConfig());

      final attrs = state.facet(contentAttributes);
      expect(attrs, isEmpty);
    });
  });
}
