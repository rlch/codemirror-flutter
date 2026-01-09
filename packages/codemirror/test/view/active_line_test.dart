import 'package:test/test.dart';

import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/view/active_line.dart';

void main() {
  group('highlightActiveLine', () {
    test('creates extension', () {
      final ext = highlightActiveLine();
      expect(ext, isA<Extension>());
    });

    test('enables showActiveLine facet', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello\nWorld',
        extensions: highlightActiveLine(),
      ));

      expect(state.facet(showActiveLine), isTrue);
    });

    test('showActiveLine is false by default', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello\nWorld',
      ));

      expect(state.facet(showActiveLine), isFalse);
    });

    test('works with empty document', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: highlightActiveLine(),
      ));

      expect(state, isNotNull);
      expect(state.doc.length, equals(0));
      expect(state.facet(showActiveLine), isTrue);
    });

    test('can combine with other extensions', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'Line 1\nLine 2\nLine 3',
        extensions: ExtensionList([
          highlightActiveLine(),
        ]),
      ));

      expect(state, isNotNull);
      expect(state.facet(showActiveLine), isTrue);
    });
  });
}
