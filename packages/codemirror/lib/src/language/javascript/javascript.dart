/// JavaScript language support for CodeMirror.
///
/// This module provides JavaScript/TypeScript/JSX parsing and
/// syntax highlighting for the editor.
library;

import 'package:lezer/lezer.dart';

import '../../state/facet.dart' show ExtensionList;
import '../../state/state.dart' show EditorState;
import '../fold.dart';
import '../indent.dart';
import '../language.dart';
import 'tokens.dart';
import 'highlight.dart' as js_highlight;
import 'parser_data.dart';
import 'auto_close_tags.dart';

// Re-export parser terms for external tokenizers
export 'parser_terms.dart';
export 'auto_close_tags.dart' show jsxAutoCloseTags;

/// Configuration for the JavaScript language.
class JavaScriptConfig {
  /// Enable JSX support (for React).
  final bool jsx;

  /// Enable TypeScript support.
  final bool typescript;

  /// Whether to include [jsxAutoCloseTags] extension.
  /// Defaults to true when jsx is enabled.
  final bool? autoCloseTags;

  const JavaScriptConfig({
    this.jsx = false,
    this.typescript = false,
    this.autoCloseTags,
  });
}

/// Get the JavaScript language with optional configuration.
///
/// Note: TSX (jsx + typescript together) is not currently supported due to
/// parser limitations. Use either JSX or TypeScript separately.
///
/// ## Example
///
/// ```dart
/// // Plain JavaScript
/// final js = javascript();
///
/// // TypeScript
/// final ts = javascript(JavaScriptConfig(typescript: true));
///
/// // JSX (React)
/// final jsx = javascript(JavaScriptConfig(jsx: true));
/// ```
LanguageSupport javascript([JavaScriptConfig config = const JavaScriptConfig()]) {
  if (config.jsx && config.typescript) {
    throw ArgumentError('TSX (jsx + typescript together) is not supported. '
        'Use either JSX or TypeScript separately.');
  }
  final dialect = _buildDialect(config);
  final name = _languageName(config);
  final lang = _jsLanguage.configure(
    ParserConfig(dialect: dialect),
    name,
  );
  
  // Include autoCloseTags if enabled (defaults to true when jsx is enabled)
  final includeAutoClose = config.autoCloseTags ?? config.jsx;
  
  return LanguageSupport(
    lang,
    includeAutoClose ? ExtensionList([jsxAutoCloseTags]) : const ExtensionList([]),
  );
}

String _buildDialect(JavaScriptConfig config) {
  final parts = <String>[];
  if (config.jsx) parts.add('jsx');
  if (config.typescript) parts.add('ts');
  return parts.join(' ');
}

String _languageName(JavaScriptConfig config) {
  if (config.typescript && config.jsx) return 'tsx';
  if (config.typescript) return 'typescript';
  if (config.jsx) return 'jsx';
  return 'javascript';
}

/// Block comment fold function.
({int from, int to})? _foldBlockComment(SyntaxNode node, EditorState _) =>
    node.to - node.from > 4 ? (from: node.from + 2, to: node.to - 2) : null;

/// Fold prop source for JavaScript nodes.
///
/// Configures folding for blocks, class bodies, switch bodies, objects, arrays, etc.
final NodePropSource _jsFoldNodeProp = foldNodeProp.add(<String, ({int from, int to})? Function(SyntaxNode, EditorState)>{
  // These node types fold using foldInside (first to last child)
  'Block': (node, _) => foldInside(node),
  'ClassBody': (node, _) => foldInside(node),
  'SwitchBody': (node, _) => foldInside(node),
  'EnumBody': (node, _) => foldInside(node),
  'ObjectExpression': (node, _) => foldInside(node),
  'ArrayExpression': (node, _) => foldInside(node),
  'ObjectType': (node, _) => foldInside(node),
  // Block comments fold from +2 to -2 to preserve /* and */
  'BlockComment': _foldBlockComment,
});

/// JSXElement indent strategy - matches JS reference exactly.
int? _jsxElementIndent(TreeIndentContext context) {
  final closed = RegExp(r'^\s*</').hasMatch(context.textAfter);
  return context.lineIndent(context.node.from) + (closed ? 0 : context.unit);
}

/// JSXEscape indent strategy (for {expressions} inside JSX).
int? _jsxEscapeIndent(TreeIndentContext context) {
  final closed = RegExp(r'\s*\}').hasMatch(context.textAfter);
  return context.lineIndent(context.node.from) + (closed ? 0 : context.unit);
}

/// JSXOpenTag/JSXSelfClosingTag indent strategy - for multi-line tags.
int? _jsxOpenTagIndent(TreeIndentContext context) {
  return context.column(context.node.from) + context.unit;
}

/// SwitchBody indent strategy - special handling for case/default.
int? _switchBodyIndent(TreeIndentContext context) {
  final after = context.textAfter;
  final closed = RegExp(r'^\s*\}').hasMatch(after);
  final isCase = RegExp(r'^\s*(case|default)\b').hasMatch(after);
  return context.baseIndent + (closed ? 0 : isCase ? 1 : 2) * context.unit;
}

/// Indent prop source for JavaScript/JSX nodes.
///
/// Configures smart indentation for blocks, objects, arrays, and JSX elements.
/// Matches the JS CodeMirror lang-javascript configuration.
final NodePropSource _jsIndentNodeProp = indentNodeProp.add(<String, int? Function(TreeIndentContext)>{
  // Standard JS structures use delimited indentation
  'Block': delimitedIndent(closing: '}'),
  'ClassBody': delimitedIndent(closing: '}'),
  'EnumBody': delimitedIndent(closing: '}'),
  'ObjectExpression': delimitedIndent(closing: '}'),
  'ArrayExpression': delimitedIndent(closing: ']'),
  'ObjectType': delimitedIndent(closing: '}'),
  
  // SwitchBody has special handling for case/default
  'SwitchBody': _switchBodyIndent,
  
  // If/Try statements use continued indentation with exceptions
  'IfStatement': continuedIndent(except: RegExp(r'^\s*(\{|else\b)')),
  'TryStatement': continuedIndent(except: RegExp(r'^\s*(\{|catch\b|finally\b)')),
  
  // Property continues with indent (for multi-line object properties)
  'Property': continuedIndent(except: RegExp(r'^\s*\{')),
  
  // Arrow functions indent one level
  'ArrowFunction': (cx) => cx.baseIndent + cx.unit,
  
  // Labels use flat indent
  'LabeledStatement': flatIndent,
  
  // Template strings and block comments return null (no auto-indent)
  'TemplateString': (_) => null,
  'BlockComment': (_) => null,
  
  // JSX elements - use lineIndent from opening tag
  'JSXElement': _jsxElementIndent,
  'JSXFragment': _jsxElementIndent,
  
  // JSX escapes ({expressions})
  'JSXEscape': _jsxEscapeIndent,
  
  // JSX open/self-closing tags - for multi-line props
  'JSXOpenTag': _jsxOpenTagIndent,
  'JSXSelfClosingTag': _jsxOpenTagIndent,
});

/// The JavaScript parser.
///
/// Includes support for JSX and TypeScript via dialects.
final LRParserImpl jsParser = LRParserImpl.deserialize(
  ParserSpec(
    version: 14,
    states: jsParserStates,
    stateData: jsParserStateData,
    goto: jsParserGoto,
    nodeNames: jsParserNodeNames,
    maxTerm: 380,
    nodeProps: jsParserNodeProps,
    propSources: [js_highlight.jsHighlight, _jsFoldNodeProp, _jsIndentNodeProp],
    skippedNodes: [0, 5, 6, 278],
    repeatNodeCount: 37,
    tokenData: jsParserTokenData,
    tokenizers: [
      noSemicolon,
      noSemicolonType,
      operatorToken,
      jsx,
      2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
      insertSemicolon,
      LocalTokenGroup(jsLocalTokenData1, 141, 340),
      LocalTokenGroup(jsLocalTokenData2, 25, 323),
    ],
    topRules: {
      'Script': (0, 7),
      'SingleExpression': (1, 276),
      'SingleClassItem': (2, 277),
    },
    dialects: {'jsx': 0, 'ts': 15175},
    dynamicPrecedences: {80: 1, 82: 1, 94: 1, 169: 1, 199: 1},
    specialized: jsParserSpecialized,
    tokenPrec: 15201,
  ),
);

final LRLanguage _jsLanguage = LRLanguage.define(
  parser: jsParser,
  languageData: {
    'closeBrackets': const {'brackets': ['(', '[', '{', "'", '"', '`']},
    'commentTokens': const {'line': '//', 'block': {'open': '/*', 'close': '*/'}},
    'indentOnInput': RegExp(r'^\s*(?:case |default:|\{|\}|<\/)$'),
    'wordChars': r'$',
  },
);

/// Convenience alias for TypeScript.
LanguageSupport typescriptLanguage() =>
    javascript(const JavaScriptConfig(typescript: true));

/// Convenience alias for JSX.
LanguageSupport jsxLanguage() =>
    javascript(const JavaScriptConfig(jsx: true));
