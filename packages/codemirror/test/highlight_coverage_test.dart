import 'package:codemirror/codemirror.dart' hide Decoration;
import 'package:codemirror/codemirror.dart' as cm show Decoration, MarkDecoration;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();
  
  testWidgets('JS highlighting coverage', (tester) async {
    final code = '''// Comment
const x = 1;
let y = "string";
function foo(a, b) {
  if (a > b) {
    return a + b;
  }
  console.log(y);
}
class MyClass {
  constructor() {
    this.value = null;
  }
}
''';

    final state = EditorState.create(EditorStateConfig(
      doc: code,
      extensions: ExtensionList([
        javascript().extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorView(key: key, state: state))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final viewState = key.currentState!;
    final classCounts = _countDecorations(viewState);
    
    print('\n=== JS Decoration classes ===');
    _printSorted(classCounts);
    
    expect(classCounts['cm-comment'], greaterThan(0), reason: 'comments');
    expect(classCounts['cm-keyword'], greaterThan(0), reason: 'keywords (includes this/null)');
    expect(classCounts['cm-string'], greaterThan(0), reason: 'strings');
    expect(classCounts['cm-number'], greaterThan(0), reason: 'numbers');
    expect(classCounts['cm-function'], greaterThan(0), reason: 'functions');
    expect(classCounts['cm-def'], greaterThan(0), reason: 'definitions');
    expect(classCounts['cm-variableName'], greaterThan(0), reason: 'variable names');
    expect(classCounts['cm-paren'], greaterThan(0), reason: 'parentheses');
    expect(classCounts['cm-brace'], greaterThan(0), reason: 'braces');
    expect(classCounts['cm-operator'], greaterThan(0), reason: 'operators');
  });
  
  testWidgets('JSX highlighting coverage', (tester) async {
    final code = '''// JSX
function App() {
  return (
    <div className="container">
      <h1>Hello</h1>
      <Button onClick={() => console.log("click")} />
    </div>
  );
}
''';

    final state = EditorState.create(EditorStateConfig(
      doc: code,
      extensions: ExtensionList([
        javascript(const JavaScriptConfig(jsx: true)).extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorView(key: key, state: state))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final viewState = key.currentState!;
    final classCounts = _countDecorations(viewState);
    
    print('\n=== JSX Decoration classes ===');
    _printSorted(classCounts);
    
    expect(classCounts['cm-tagName'], greaterThan(0), reason: 'JSX tag names');
    expect(classCounts['cm-attributeName'], greaterThan(0), reason: 'JSX attributes');
    expect(classCounts['cm-attributeValue'] ?? classCounts['cm-string'], greaterThan(0), reason: 'JSX attribute values');
    expect(classCounts['cm-angleBracket'], greaterThan(0), reason: 'JSX angle brackets');
  });
  
  testWidgets('TypeScript highlighting coverage', (tester) async {
    final code = '''// TypeScript
interface User {
  id: number;
  name: string;
}

type Status = 'active' | 'inactive';

function process<T extends User>(user: T): T {
  return user;
}

class Service {
  private cache: Map<string, unknown> = new Map();
}
''';

    final state = EditorState.create(EditorStateConfig(
      doc: code,
      extensions: ExtensionList([
        javascript(const JavaScriptConfig(typescript: true)).extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorView(key: key, state: state))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final viewState = key.currentState!;
    final classCounts = _countDecorations(viewState);
    
    print('\n=== TS Decoration classes ===');
    _printSorted(classCounts);
    
    expect(classCounts['cm-type'], greaterThan(0), reason: 'TypeScript types');
    expect(classCounts['cm-keyword'], greaterThan(0), reason: 'keywords');
    expect(classCounts['cm-def'], greaterThan(0), reason: 'definitions');
  });
}

Map<String, int> _countDecorations(EditorViewState viewState) {
  final classCounts = <String, int>{};
  final decoSources = viewState.state.facet(decorationsFacet);
  
  for (final source in decoSources) {
    RangeSet<cm.Decoration>? result;
    if (source is RangeSet<cm.Decoration>) {
      result = source;
    } else if (source is Function) {
      result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
    }
    if (result != null && !result.isEmpty) {
      final cursor = result.iter();
      while (cursor.value != null) {
        if (cursor.value is cm.MarkDecoration) {
          final cls = (cursor.value as cm.MarkDecoration).className;
          classCounts[cls] = (classCounts[cls] ?? 0) + 1;
        }
        cursor.next();
      }
    }
  }
  return classCounts;
}

void _printSorted(Map<String, int> counts) {
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    print('  ${e.key}: ${e.value}');
  }
}
