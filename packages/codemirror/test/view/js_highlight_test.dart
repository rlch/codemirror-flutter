import 'package:codemirror/codemirror.dart' hide Decoration;
import 'package:codemirror/codemirror.dart' as cm show Decoration, MarkDecoration;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  testWidgets('JavaScript syntax highlighting produces decorations', (tester) async {
    final state = EditorState.create(EditorStateConfig(
      doc: '''// Comment line
function foo() { return 42; }
const x = "hello";
class Bar {}''',
      extensions: ExtensionList([
        javascript().extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorView(key: key, state: state)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final viewState = key.currentState!;
    
    // Check the syntax tree exists
    final tree = syntaxTree(viewState.state);
    print('Tree length: ${tree.length}');
    print('Tree type: ${tree.type.name}');
    
    // Check highlighters exist
    final highlighters = getHighlighters(viewState.state);
    print('Highlighters: ${highlighters?.length ?? 0}');
    
    // Check decoration sources
    final decoSources = viewState.state.facet(decorationsFacet);
    print('Decoration sources: ${decoSources.length}');
    
    // Evaluate decorations
    bool hasDecorations = false;
    for (final source in decoSources) {
      RangeSet<cm.Decoration>? result;
      if (source is RangeSet<cm.Decoration>) {
        result = source;
      } else if (source is Function) {
        result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
      }
      if (result != null) {
        print('Source produced ${result.isEmpty ? "empty" : "non-empty"} decorations');
        if (!result.isEmpty) {
          hasDecorations = true;
          final cursor = result.iter();
          int count = 0;
          while (cursor.value != null && count < 15) {
            final deco = cursor.value!;
            if (deco is cm.MarkDecoration) {
              print('  Deco: ${cursor.from}-${cursor.to} className="${deco.className}"');
            }
            cursor.next();
            count++;
          }
        }
      }
    }
    
    expect(hasDecorations, isTrue, reason: 'Syntax highlighting should produce decorations');
    
    // Check that TextSpan has styled children
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    final controller = editableText.controller as HighlightingTextEditingController;
    final textSpan = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    
    print('TextSpan children: ${textSpan.children?.length ?? 0}');
    if (textSpan.children != null) {
      for (var i = 0; i < textSpan.children!.length && i < 5; i++) {
        final child = textSpan.children![i];
        if (child is TextSpan) {
          print('  Child $i: "${child.text}" color=${child.style?.color}');
        }
      }
    }
    
    final hasColoredChild = textSpan.children?.any((child) {
      if (child is TextSpan) {
        return child.style?.color != null;
      }
      return false;
    }) ?? false;
    
    expect(hasColoredChild, isTrue, reason: 'TextSpan should have colored children from syntax highlighting');
  });
}
