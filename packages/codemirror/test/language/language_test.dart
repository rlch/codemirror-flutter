// ignore_for_file: avoid_relative_lib_imports

import 'package:lezer/lezer.dart';
import 'package:test/test.dart';

import '../../lib/src/language/language.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/change.dart';
import '../../lib/src/state/transaction.dart';
import '../../lib/src/state/facet.dart' hide EditorState, Transaction;
import '../../lib/src/text/text.dart';

/// A simple test parser that creates a basic tree structure.
class _TestParser extends Parser {
  final NodeSet nodeSet;
  
  _TestParser() : nodeSet = NodeSet([
    NodeType.define(id: 0, name: 'Script', top: true),
    NodeType.define(id: 1, name: 'Number'),
    NodeType.define(id: 2, name: 'String'),
    NodeType.define(id: 3, name: 'Identifier'),
  ]);
  
  @override
  PartialParse createParse(
    Input input,
    List<TreeFragment> fragments,
    List<Range> ranges,
  ) {
    return _TestPartialParse(input, nodeSet);
  }
}

class _TestPartialParse implements PartialParse {
  final Input input;
  final NodeSet nodeSet;
  int _pos = 0;
  
  @override
  int? stoppedAt;
  
  _TestPartialParse(this.input, this.nodeSet);
  
  @override
  int get parsedPos => _pos;
  
  @override
  Tree? advance() {
    final len = input.length;
    _pos = len;
    
    // Create a simple tree with Script as root
    return Tree(
      nodeSet.types[0], // Script
      [],
      [],
      len,
    );
  }
  
  @override
  void stopAt(int pos) {
    stoppedAt = pos;
  }
}

/// Helper to create parser.
Parser _testParser() => _TestParser();

/// Create a parse context for testing.
/// Note: We don't include language.extension because it includes ViewPlugin
/// which requires the view system. Just test ParseContext directly.
ParseContext _pContext(Text doc) {
  final parser = _testParser();
  final state = EditorState.create(EditorStateConfig(doc: doc));
  return ParseContext.create(parser, state, (from: 0, to: doc.length));
}

void main() {
  // Ensure language is initialized
  ensureLanguageInitialized();
  
  group('ParseContext', () {
    test('can parse a document', () {
      final cx = _pContext(Text.of(['let x = 10']));
      cx.work(100000000);
      expect(cx.tree.length, 10);
      expect(cx.tree.type.name, 'Script');
    });
    
    test('can parse incrementally', () {
      final lines = <String>[];
      final baseLine = 'const readFile = require("fs");';
      for (var i = 0; i < 100; i++) {
        lines.add(baseLine);
      }
      final doc = Text.of(lines);
      
      final cx = _pContext(doc);
      
      // Parse completely
      cx.work(100000000);
      expect(cx.tree.length, doc.length);
      
      // Apply a change
      final change = ChangeSet.of([
        ChangeSpec(from: 0, to: 5, insert: Text.of(['let'])),
      ], doc.length);
      
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final newDoc = change.apply(doc);
      final newState = EditorState.create(EditorStateConfig(
        doc: newDoc,
        extensions: ExtensionList([lang.extension]),
      ));
      
      final newCx = cx.changes(change, newState);
      newCx.work(100000000);
      expect(newCx.tree.length, newDoc.length);
    });
    
    test('tracks parsed position', () {
      final cx = _pContext(Text.of(['hello world']));
      expect(cx.treeLen, 0);
      cx.work(100000000);
      expect(cx.treeLen, 11);
    });
    
    test('reports isDone correctly', () {
      final cx = _pContext(Text.of(['test']));
      expect(cx.isDone(4), false);
      cx.work(100000000);
      cx.takeTree();
      expect(cx.isDone(4), true);
    });
  });
  
  group('Language', () {
    test('creates extension', () {
      final parser = _testParser();
      final data = defineLanguageFacet({'test': 'value'});
      final lang = Language(data, parser, name: 'test');
      expect(lang.extension, isNotNull);
      expect(lang.name, 'test');
    });
    
    test('allows nesting by default', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser);
      expect(lang.allowsNesting, true);
    });
  });
  
  group('syntaxTree', () {
    test('returns empty tree when no language', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'test'));
      final tree = syntaxTree(state);
      expect(tree.length, 0);
    });
    
    test('returns parsed tree when language is set', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final state = EditorState.create(EditorStateConfig(
        doc: 'hello',
        extensions: ExtensionList([lang.extension]),
      ));
      
      // The tree should be parsed on state creation
      final tree = syntaxTree(state);
      expect(tree.length, 5);
    });
  });
  
  group('ensureSyntaxTree', () {
    test('returns tree when parsing completes', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final state = EditorState.create(EditorStateConfig(
        doc: 'hello world',
        extensions: ExtensionList([lang.extension]),
      ));
      
      final tree = ensureSyntaxTree(state, 11, 1000);
      expect(tree, isNotNull);
      expect(tree!.length, 11);
    });
    
    test('returns null when no language', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'test'));
      final tree = ensureSyntaxTree(state, 4);
      expect(tree, isNull);
    });
  });
  
  group('syntaxTreeAvailable', () {
    test('returns false when no language', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'test'));
      expect(syntaxTreeAvailable(state), false);
    });
    
    test('returns true when tree is complete', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final state = EditorState.create(EditorStateConfig(
        doc: 'test',
        extensions: ExtensionList([lang.extension]),
      ));
      
      // Force parsing
      ensureSyntaxTree(state, 4, 1000);
      expect(syntaxTreeAvailable(state, 4), true);
    });
  });
  
  group('DocInput', () {
    test('provides input from document', () {
      final doc = Text.of(['hello', 'world']);
      final input = DocInput(doc);
      
      expect(input.length, 11); // 'hello\nworld'
      expect(input.read(0, 5), 'hello');
      expect(input.read(6, 11), 'world');
    });
    
    test('chunks are line-based', () {
      final doc = Text.of(['line1', 'line2']);
      final input = DocInput(doc);
      
      expect(input.lineChunks, true);
      // chunk(0) returns just the line content, newlines are separate
      expect(input.chunk(0), 'line1');
    });
  });
  
  group('defineLanguageFacet', () {
    test('creates facet with no base data', () {
      final facet = defineLanguageFacet();
      expect(facet, isNotNull);
    });
    
    test('creates facet with base data', () {
      final facet = defineLanguageFacet({'autocomplete': true});
      expect(facet, isNotNull);
    });
  });
  
  group('LanguageDescription', () {
    test('creates with support', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final desc = LanguageDescription.of(
        name: 'Test',
        extensions: ['test', 'tst'],
        support: support,
      );
      
      expect(desc.name, 'Test');
      expect(desc.extensions, ['test', 'tst']);
      expect(desc.support, support);
    });
    
    test('loads language asynchronously', () async {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final desc = LanguageDescription.of(
        name: 'Test',
        load: () async => support,
      );
      
      expect(desc.support, isNull);
      final loaded = await desc.load();
      expect(loaded, support);
      expect(desc.support, support);
    });
    
    test('matchFilename matches by extension', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final jsDesc = LanguageDescription.of(
        name: 'JavaScript',
        extensions: ['js', 'mjs'],
        support: support,
      );
      
      final tsDesc = LanguageDescription.of(
        name: 'TypeScript',
        extensions: ['ts', 'tsx'],
        support: support,
      );
      
      final descs = [jsDesc, tsDesc];
      
      expect(LanguageDescription.matchFilename(descs, 'foo.js'), jsDesc);
      expect(LanguageDescription.matchFilename(descs, 'bar.ts'), tsDesc);
      expect(LanguageDescription.matchFilename(descs, 'baz.py'), isNull);
    });
    
    test('matchFilename matches by pattern', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final makefileDesc = LanguageDescription.of(
        name: 'Makefile',
        filename: RegExp(r'^[Mm]akefile$'),
        support: support,
      );
      
      final descs = [makefileDesc];
      
      expect(LanguageDescription.matchFilename(descs, 'Makefile'), makefileDesc);
      expect(LanguageDescription.matchFilename(descs, 'makefile'), makefileDesc);
      expect(LanguageDescription.matchFilename(descs, 'Makefile.txt'), isNull);
    });
    
    test('matchLanguageName matches by name', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final jsDesc = LanguageDescription.of(
        name: 'JavaScript',
        alias: ['js', 'ecmascript'],
        support: support,
      );
      
      final descs = [jsDesc];
      
      expect(LanguageDescription.matchLanguageName(descs, 'javascript'), jsDesc);
      expect(LanguageDescription.matchLanguageName(descs, 'JavaScript'), jsDesc);
      expect(LanguageDescription.matchLanguageName(descs, 'js'), jsDesc);
      expect(LanguageDescription.matchLanguageName(descs, 'ecmascript'), jsDesc);
    });
    
    test('matchLanguageName fuzzy matching', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      final jsDesc = LanguageDescription.of(
        name: 'JavaScript',
        support: support,
      );
      
      final descs = [jsDesc];
      
      // Fuzzy should find partial matches for longer names
      expect(
        LanguageDescription.matchLanguageName(descs, 'use javascript', true),
        jsDesc,
      );
      
      // Short names need word boundaries
      final pyDesc = LanguageDescription.of(
        name: 'Python',
        alias: ['py'],
        support: support,
      );
      
      final descs2 = [pyDesc];
      expect(
        LanguageDescription.matchLanguageName(descs2, 'py code', true),
        pyDesc,
      );
    });
  });
  
  group('LanguageSupport', () {
    test('bundles language and support extensions', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final support = LanguageSupport(lang);
      
      expect(support.language, lang);
      expect(support.extension, isNotNull);
    });
  });
  
  group('LanguageState', () {
    test('initializes with parsed tree', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final state = EditorState.create(EditorStateConfig(
        doc: 'test',
        extensions: ExtensionList([lang.extension]),
      ));
      
      final langState = state.field(Language.state);
      expect(langState, isNotNull);
      expect(langState!.tree.length, 4);
    });
    
    test('updates on document change', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      var state = EditorState.create(EditorStateConfig(
        doc: 'test',
        extensions: ExtensionList([lang.extension]),
      ));
      
      final tr = state.update([
        TransactionSpec(changes: ChangeSpec(from: 0, insert: 'hello ')),
      ]);
      state = tr.state as EditorState;
      
      final langState = state.field(Language.state);
      expect(langState!.tree.length, 10); // 'hello test'
    });
  });
  
  group('Sublanguage', () {
    test('creates sublanguage', () {
      final subFacet = defineLanguageFacet({'sub': true});
      final sublang = Sublanguage(
        type: SublanguageType.extend,
        test: (node, state) => node.type.name == 'String',
        facet: subFacet,
      );
      
      expect(sublang.type, SublanguageType.extend);
      expect(sublang.facet, subFacet);
    });
  });
  
  group('ParseContext.getSkippingParser', () {
    test('creates parser that skips content', () {
      final parser = ParseContext.getSkippingParser();
      expect(parser, isNotNull);
      
      final input = StringInput('test content');
      final parse = parser.startParse(input);
      final tree = parse.advance();
      
      expect(tree, isNotNull);
      expect(tree!.length, 12);
      expect(tree.type.name, '');  // NodeType.none
    });
  });
  
  group('language facet', () {
    test('can access current language', () {
      final parser = _testParser();
      final data = defineLanguageFacet();
      final lang = Language(data, parser, name: 'test');
      final state = EditorState.create(EditorStateConfig(
        doc: 'test',
        extensions: ExtensionList([lang.extension]),
      ));
      
      final currentLang = state.facet(language);
      expect(currentLang, lang);
    });
    
    test('returns null when no language', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'test'));
      final currentLang = state.facet(language);
      expect(currentLang, isNull);
    });
  });
}
