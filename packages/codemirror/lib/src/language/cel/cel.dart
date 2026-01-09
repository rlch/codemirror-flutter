/// CEL (Common Expression Language) support for CodeMirror.
///
/// This module provides CEL parsing and syntax highlighting for the editor.
/// CEL is used in waku-expr for defining dynamic expressions on notes/cards.
library;

import 'package:lezer/lezer.dart';

import '../language.dart';
import 'highlight.dart' as cel_highlight;
import 'parser_data.dart';

/// Get the CEL language support.
///
/// ## Example
///
/// ```dart
/// final state = EditorState.create(EditorStateConfig(
///   doc: 'note.properties.title == "Hello"',
///   extensions: [cel()],
/// ));
/// ```
LanguageSupport cel() {
  return LanguageSupport(_celLanguage);
}

/// The CEL parser.
///
/// Parses CEL expressions for waku-expr.
final LRParserImpl celParser = LRParserImpl.deserialize(
  ParserSpec(
    version: 14,
    states: celParserStates,
    stateData: celParserStateData,
    goto: celParserGoto,
    nodeNames: celParserNodeNames,
    maxTerm: 82,
    nodeProps: celParserNodeProps,
    propSources: [cel_highlight.celHighlight],
    skippedNodes: [0, 1],
    repeatNodeCount: 10,
    tokenData: celParserTokenData,
    tokenizers: [0, 1, 2],
    topRules: {'Expression': (0, 2)},
    specialized: celParserSpecialized,
    tokenPrec: 1073,
  ),
);

/// The CEL language definition.
final LRLanguage _celLanguage = LRLanguage.define(
  parser: celParser,
  languageData: {
    'closeBrackets': const {'brackets': ['(', '[', '{', "'", '"']},
    'commentTokens': const {'line': '//'},
  },
);
