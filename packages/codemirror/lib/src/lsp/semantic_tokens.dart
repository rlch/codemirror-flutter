/// LSP Semantic Tokens support for CodeMirror.
///
/// This module provides integration with LSP semantic tokens for enhanced
/// syntax highlighting based on language server analysis.
///
/// ## Overview
///
/// LSP semantic tokens provide richer highlighting than tree-sitter/Lezer alone
/// because the language server has full semantic understanding of the code.
/// For example, it can distinguish between:
/// - Local variables vs parameters vs class fields
/// - Function declarations vs function calls
/// - Types vs interfaces vs type parameters
///
/// ## Usage
///
/// ```dart
/// final editor = EditorView(
///   extensions: [
///     semanticTokens(
///       client: myLspClient,
///       legend: serverCapabilities.semanticTokensProvider.legend,
///     ),
///   ],
/// );
/// ```
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/state.dart';
import '../state/transaction.dart' show StateEffectType, TransactionSpec;
import '../text/text.dart';
import '../view/decoration.dart';
import '../view/editor_view.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';

// ============================================================================
// LSP Types for Semantic Tokens
// ============================================================================

/// The legend describing token types and modifiers.
///
/// This is provided by the language server during initialization.
class SemanticTokensLegend {
  /// The token types (e.g., 'namespace', 'type', 'class', 'function').
  final List<String> tokenTypes;

  /// The token modifiers (e.g., 'declaration', 'definition', 'readonly').
  final List<String> tokenModifiers;

  const SemanticTokensLegend({
    required this.tokenTypes,
    required this.tokenModifiers,
  });

  factory SemanticTokensLegend.fromJson(Map<String, dynamic> json) {
    return SemanticTokensLegend(
      tokenTypes: (json['tokenTypes'] as List).cast<String>(),
      tokenModifiers: (json['tokenModifiers'] as List).cast<String>(),
    );
  }
}

/// Standard LSP token types.
///
/// These are the predefined token types from the LSP specification.
/// Language servers may define additional custom types.
abstract final class SemanticTokenTypes {
  static const String namespace = 'namespace';
  static const String type = 'type';
  static const String class_ = 'class';
  static const String enum_ = 'enum';
  static const String interface_ = 'interface';
  static const String struct = 'struct';
  static const String typeParameter = 'typeParameter';
  static const String parameter = 'parameter';
  static const String variable = 'variable';
  static const String property = 'property';
  static const String enumMember = 'enumMember';
  static const String event = 'event';
  static const String function = 'function';
  static const String method = 'method';
  static const String macro = 'macro';
  static const String keyword = 'keyword';
  static const String modifier = 'modifier';
  static const String comment = 'comment';
  static const String string = 'string';
  static const String number = 'number';
  static const String regexp = 'regexp';
  static const String operator = 'operator';
  static const String decorator = 'decorator';
}

/// Standard LSP token modifiers.
///
/// These are the predefined token modifiers from the LSP specification.
/// Modifiers are combined as bit flags.
abstract final class SemanticTokenModifiers {
  static const String declaration = 'declaration';
  static const String definition = 'definition';
  static const String readonly = 'readonly';
  static const String static_ = 'static';
  static const String deprecated = 'deprecated';
  static const String abstract_ = 'abstract';
  static const String async_ = 'async';
  static const String modification = 'modification';
  static const String documentation = 'documentation';
  static const String defaultLibrary = 'defaultLibrary';
}

/// A decoded semantic token with position and type information.
class SemanticToken {
  /// Start position in the document.
  final int from;

  /// End position in the document.
  final int to;

  /// The token type name (from the legend).
  final String type;

  /// The active modifiers for this token.
  final List<String> modifiers;

  const SemanticToken({
    required this.from,
    required this.to,
    required this.type,
    required this.modifiers,
  });

  @override
  String toString() =>
      'SemanticToken($from-$to, $type${modifiers.isNotEmpty ? ', ${modifiers.join(", ")}' : ''})';
}

// ============================================================================
// LSP Client Interface
// ============================================================================

/// Interface for LSP semantic token requests.
///
/// Implement this to connect to your language server.
abstract class SemanticTokensClient {
  /// Request full semantic tokens for a document.
  ///
  /// Returns the encoded token data as specified by LSP:
  /// Each token is 5 integers: [deltaLine, deltaStart, length, tokenType, tokenModifiers]
  Future<SemanticTokensResult?> requestSemanticTokensFull(String uri);

  /// Request semantic tokens for a range (optional optimization).
  ///
  /// Returns null if range requests are not supported.
  Future<SemanticTokensResult?> requestSemanticTokensRange(
    String uri,
    int startLine,
    int startChar,
    int endLine,
    int endChar,
  ) =>
      Future.value(null);

  /// Request delta semantic tokens (optional optimization).
  ///
  /// Returns null if delta requests are not supported.
  Future<SemanticTokensDeltaResult?> requestSemanticTokensDelta(
    String uri,
    String previousResultId,
  ) =>
      Future.value(null);

  /// The legend from the server's capabilities.
  SemanticTokensLegend get legend;

  /// The document URI for the current document.
  String get documentUri;
}

/// Result of a semantic tokens request.
class SemanticTokensResult {
  /// An optional result ID for delta requests.
  final String? resultId;

  /// The encoded token data.
  ///
  /// Each token is represented by 5 integers:
  /// - deltaLine: line delta from previous token
  /// - deltaStart: start character delta (from 0 if new line, else from previous)
  /// - length: token length
  /// - tokenType: index into legend.tokenTypes
  /// - tokenModifiers: bit flags for legend.tokenModifiers
  final List<int> data;

  const SemanticTokensResult({
    this.resultId,
    required this.data,
  });

  factory SemanticTokensResult.fromJson(Map<String, dynamic> json) {
    return SemanticTokensResult(
      resultId: json['resultId'] as String?,
      data: (json['data'] as List).cast<int>(),
    );
  }
}

/// Result of a semantic tokens delta request.
class SemanticTokensDeltaResult {
  /// The new result ID.
  final String? resultId;

  /// The edits to apply to the previous token data.
  final List<SemanticTokensEdit> edits;

  const SemanticTokensDeltaResult({
    this.resultId,
    required this.edits,
  });

  factory SemanticTokensDeltaResult.fromJson(Map<String, dynamic> json) {
    return SemanticTokensDeltaResult(
      resultId: json['resultId'] as String?,
      edits: (json['edits'] as List)
          .map((e) => SemanticTokensEdit.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// An edit to apply to semantic token data.
class SemanticTokensEdit {
  /// Start index in the data array.
  final int start;

  /// Number of elements to delete.
  final int deleteCount;

  /// Elements to insert.
  final List<int>? data;

  const SemanticTokensEdit({
    required this.start,
    required this.deleteCount,
    this.data,
  });

  factory SemanticTokensEdit.fromJson(Map<String, dynamic> json) {
    return SemanticTokensEdit(
      start: json['start'] as int,
      deleteCount: json['deleteCount'] as int,
      data: (json['data'] as List?)?.cast<int>(),
    );
  }
}

// ============================================================================
// Token Decoding
// ============================================================================

/// Decode LSP semantic token data into [SemanticToken] objects.
///
/// The LSP protocol encodes tokens as a flat array of 5-integer tuples
/// with relative positions. This function decodes them into absolute
/// positions for the given document.
List<SemanticToken> decodeSemanticTokens(
  List<int> data,
  SemanticTokensLegend legend,
  Text doc,
) {
  final tokens = <SemanticToken>[];
  var line = 0;
  var char = 0;

  for (var i = 0; i + 4 < data.length; i += 5) {
    final deltaLine = data[i];
    final deltaStart = data[i + 1];
    final length = data[i + 2];
    final tokenTypeIndex = data[i + 3];
    final tokenModifierBits = data[i + 4];

    // Update position
    if (deltaLine > 0) {
      line += deltaLine;
      char = deltaStart;
    } else {
      char += deltaStart;
    }

    // Convert line/char to absolute position
    if (line >= doc.lines) continue;
    final lineInfo = doc.line(line + 1); // 1-indexed
    final from = lineInfo.from + char;
    final to = from + length;

    // Clamp to document bounds
    if (from >= doc.length) continue;
    final clampedTo = to > doc.length ? doc.length : to;

    // Decode token type
    final tokenType = tokenTypeIndex < legend.tokenTypes.length
        ? legend.tokenTypes[tokenTypeIndex]
        : 'unknown';

    // Decode modifiers (bit flags)
    final modifiers = <String>[];
    for (var m = 0; m < legend.tokenModifiers.length; m++) {
      if ((tokenModifierBits & (1 << m)) != 0) {
        modifiers.add(legend.tokenModifiers[m]);
      }
    }

    tokens.add(SemanticToken(
      from: from,
      to: clampedTo,
      type: tokenType,
      modifiers: modifiers,
    ));
  }

  return tokens;
}

/// Apply delta edits to existing token data.
List<int> applySemanticTokensEdits(
    List<int> data, List<SemanticTokensEdit> edits) {
  // Sort edits by start position descending (apply from back to front)
  final sortedEdits = [...edits]..sort((a, b) => b.start.compareTo(a.start));

  final result = [...data];
  for (final edit in sortedEdits) {
    result.replaceRange(
      edit.start,
      edit.start + edit.deleteCount,
      edit.data ?? [],
    );
  }
  return result;
}

// ============================================================================
// Decoration Mapping
// ============================================================================

/// Configuration for mapping semantic tokens to decorations.
class SemanticTokensTheme {
  /// CSS class prefix for token types.
  ///
  /// Defaults to 'cm-sem-' which matches the styles in [HighlightTheme].
  final String classPrefix;

  /// Custom class mappings for specific token types.
  ///
  /// Keys are token type names, values are CSS class names.
  final Map<String, String>? typeClasses;

  /// Custom class mappings for specific modifiers.
  ///
  /// Keys are modifier names, values are CSS class names.
  final Map<String, String>? modifierClasses;

  /// Whether to include modifier classes.
  final bool includeModifiers;

  const SemanticTokensTheme({
    this.classPrefix = 'cm-sem-',
    this.typeClasses,
    this.modifierClasses,
    this.includeModifiers = true,
  });

  /// Get the CSS class for a token.
  String getClass(SemanticToken token) {
    final classes = <String>[];

    // Add type class
    final typeClass = typeClasses?[token.type] ?? '$classPrefix${token.type}';
    classes.add(typeClass);

    // Add modifier classes
    if (includeModifiers) {
      for (final mod in token.modifiers) {
        final modClass = modifierClasses?[mod] ?? '$classPrefix$mod';
        classes.add(modClass);
      }
    }

    return classes.join(' ');
  }
}

/// Default theme for semantic tokens.
const defaultSemanticTokensTheme = SemanticTokensTheme();

/// Convert semantic tokens to CodeMirror decorations.
RangeSet<Decoration> tokensToDecorations(
  List<SemanticToken> tokens, {
  SemanticTokensTheme theme = defaultSemanticTokensTheme,
}) {
  if (tokens.isEmpty) return Decoration.none;

  // Sort tokens by position - RangeSetBuilder requires sorted input
  final sortedTokens = [...tokens]
    ..sort((a, b) {
      final cmp = a.from.compareTo(b.from);
      if (cmp != 0) return cmp;
      return a.to.compareTo(b.to);
    });

  final builder = RangeSetBuilder<Decoration>();

  for (final token in sortedTokens) {
    final className = theme.getClass(token);
    final decoration = Decoration.mark(MarkDecorationSpec(className: className));
    builder.add(token.from, token.to, decoration);
  }

  return builder.finish();
}

// ============================================================================
// State Management
// ============================================================================

/// State effect to update semantic tokens.
final setSemanticTokens = StateEffectType<SemanticTokensState>(
  (value, mapping) => value, // Tokens don't map through changes (we re-request)
);

/// Internal state for semantic tokens.
@internal
class SemanticTokensState {
  /// The decoded tokens.
  final List<SemanticToken> tokens;

  /// The decorations generated from tokens.
  final RangeSet<Decoration> decorations;

  /// The result ID for delta requests.
  final String? resultId;

  /// The raw token data (for applying deltas).
  final List<int> data;

  /// Document version when tokens were computed.
  final int version;

  const SemanticTokensState({
    required this.tokens,
    required this.decorations,
    this.resultId,
    required this.data,
    required this.version,
  });

  static final empty = SemanticTokensState(
    tokens: const [],
    decorations: Decoration.none,
    data: const [],
    version: -1,
  );
}

/// State field for storing semantic tokens.
final semanticTokensField = StateField.define(
  StateFieldConfig<SemanticTokensState>(
    create: (_) => SemanticTokensState.empty,
    update: (value, tr) {
      // Check for explicit token updates
      for (final effect in tr.effects) {
        if (effect.is_(setSemanticTokens)) {
          return effect.value as SemanticTokensState;
        }
      }

      // Map decorations through document changes
      if (tr.docChanged && !value.decorations.isEmpty) {
        // Note: We need access to the ChangeSet from the transaction
        // For now, just invalidate - the plugin will re-request tokens
        return SemanticTokensState(
          tokens: value.tokens, // Tokens become stale, will be refreshed
          decorations: Decoration.none, // Clear stale decorations
          resultId: null, // Invalidate result ID on doc change
          data: value.data,
          version: value.version,
        );
      }

      return value;
    },
    provide: (field) => decorationsFacet.from(
      field,
      (state) => state.decorations,
    ),
  ),
);

// ============================================================================
// View Plugin
// ============================================================================

/// Configuration for the semantic tokens extension.
class SemanticTokensConfig {
  /// The LSP client to use for requests.
  final SemanticTokensClient client;

  /// Theme for mapping tokens to CSS classes.
  final SemanticTokensTheme theme;

  /// Debounce delay for token requests after edits (milliseconds).
  final int debounceMs;

  /// Whether to use range requests for large documents.
  final bool useRangeRequests;

  /// Document size threshold for using range requests.
  final int rangeRequestThreshold;

  const SemanticTokensConfig({
    required this.client,
    this.theme = defaultSemanticTokensTheme,
    this.debounceMs = 100,
    this.useRangeRequests = true,
    this.rangeRequestThreshold = 50000,
  });
}

/// View plugin that manages semantic token requests.
class SemanticTokensPlugin extends PluginValue {
  final SemanticTokensConfig config;
  final EditorViewState view;

  Timer? _debounceTimer;
  int _pendingVersion = 0;
  bool _requestInFlight = false;

  SemanticTokensPlugin(this.view, this.config) {
    // Request initial tokens
    _scheduleTokenRequest();
  }

  @override
  void update(ViewUpdate update) {
    if (update.docChanged) {
      _scheduleTokenRequest();
    }
  }

  @override
  void destroy(EditorViewState view) {
    _debounceTimer?.cancel();
  }

  void _scheduleTokenRequest() {
    _debounceTimer?.cancel();
    _pendingVersion++;
    final version = _pendingVersion;

    _debounceTimer = Timer(
      Duration(milliseconds: config.debounceMs),
      () => _requestTokens(version),
    );
  }

  Future<void> _requestTokens(int version) async {
    // Skip if another request is pending or version changed
    if (_requestInFlight || version != _pendingVersion) return;

    _requestInFlight = true;
    try {
      final state = view.state;
      final currentState = state.field(semanticTokensField);

      SemanticTokensResult? result;

      // Try delta request first if we have a previous result ID
      if (currentState != null && currentState.resultId != null) {
        final delta = await config.client.requestSemanticTokensDelta(
          config.client.documentUri,
          currentState.resultId!,
        );

        if (delta != null) {
          final newData =
              applySemanticTokensEdits(currentState.data, delta.edits);
          result = SemanticTokensResult(
            resultId: delta.resultId,
            data: newData,
          );
        }
      }

      // Fall back to full request
      result ??= await config.client.requestSemanticTokensFull(
        config.client.documentUri,
      );

      // Check if version is still current
      if (version != _pendingVersion || result == null) return;

      // Decode tokens
      final tokens = decodeSemanticTokens(
        result.data,
        config.client.legend,
        view.state.doc,
      );

      // Convert to decorations
      final decorations = tokensToDecorations(tokens, theme: config.theme);

      // Update state
      final newState = SemanticTokensState(
        tokens: tokens,
        decorations: decorations,
        resultId: result.resultId,
        data: result.data,
        version: version,
      );

      view.dispatch([
        TransactionSpec(effects: [setSemanticTokens.of(newState)]),
      ]);
    } catch (e) {
      logException(view.state, e, 'semantic tokens request');
    } finally {
      _requestInFlight = false;
    }
  }
}

/// Create the semantic tokens view plugin.
ViewPlugin<SemanticTokensPlugin> _createSemanticTokensPlugin(
    SemanticTokensConfig config) {
  return ViewPlugin.define(
    (view) => SemanticTokensPlugin(view, config),
    ViewPluginSpec(
      decorations: (plugin) =>
          plugin.view.state.field(semanticTokensField)?.decorations ??
          Decoration.none,
    ),
  );
}

// ============================================================================
// Public API
// ============================================================================

/// Create an extension that enables LSP semantic tokens highlighting.
///
/// ## Example
///
/// ```dart
/// final editor = EditorView(
///   extensions: [
///     semanticTokens(SemanticTokensConfig(
///       client: MyLspClient(),
///       theme: SemanticTokensTheme(
///         classPrefix: 'tok-',
///       ),
///     )),
///   ],
/// );
/// ```
///
/// ## CSS Classes
///
/// By default, tokens get classes like:
/// - `cm-semantic-function` for function tokens
/// - `cm-semantic-variable` for variable tokens
/// - `cm-semantic-readonly` for readonly modifier
///
/// You can customize this with a [SemanticTokensTheme].
Extension semanticTokens(SemanticTokensConfig config) {
  return ExtensionList([
    semanticTokensField,
    _createSemanticTokensPlugin(config).extension,
  ]);
}

/// Get the semantic tokens for the current state.
///
/// Returns the list of decoded tokens, or an empty list if none are available.
List<SemanticToken> getSemanticTokens(EditorState state) {
  return state.field(semanticTokensField)?.tokens ?? [];
}

// ============================================================================
// CSS Theme Helper
// ============================================================================

/// Generate CSS for semantic token highlighting.
///
/// This is a helper for generating a basic CSS stylesheet for semantic
/// tokens. In production, you'd typically define these styles in your
/// app's CSS.
///
/// ```dart
/// final css = generateSemanticTokensCss(
///   prefix: 'cm-semantic-',
///   dark: true,
/// );
/// ```
String generateSemanticTokensCss({
  String prefix = 'cm-semantic-',
  bool dark = false,
}) {
  final colors = dark ? _darkColors : _lightColors;

  return '''
/* Semantic Token Types */
.$prefix${SemanticTokenTypes.namespace} { color: ${colors['namespace']}; }
.$prefix${SemanticTokenTypes.type} { color: ${colors['type']}; }
.$prefix${SemanticTokenTypes.class_} { color: ${colors['class']}; }
.$prefix${SemanticTokenTypes.enum_} { color: ${colors['enum']}; }
.$prefix${SemanticTokenTypes.interface_} { color: ${colors['interface']}; }
.$prefix${SemanticTokenTypes.struct} { color: ${colors['struct']}; }
.$prefix${SemanticTokenTypes.typeParameter} { color: ${colors['typeParameter']}; }
.$prefix${SemanticTokenTypes.parameter} { color: ${colors['parameter']}; }
.$prefix${SemanticTokenTypes.variable} { color: ${colors['variable']}; }
.$prefix${SemanticTokenTypes.property} { color: ${colors['property']}; }
.$prefix${SemanticTokenTypes.enumMember} { color: ${colors['enumMember']}; }
.$prefix${SemanticTokenTypes.function} { color: ${colors['function']}; }
.$prefix${SemanticTokenTypes.method} { color: ${colors['method']}; }
.$prefix${SemanticTokenTypes.macro} { color: ${colors['macro']}; }
.$prefix${SemanticTokenTypes.keyword} { color: ${colors['keyword']}; }
.$prefix${SemanticTokenTypes.comment} { color: ${colors['comment']}; font-style: italic; }
.$prefix${SemanticTokenTypes.string} { color: ${colors['string']}; }
.$prefix${SemanticTokenTypes.number} { color: ${colors['number']}; }
.$prefix${SemanticTokenTypes.regexp} { color: ${colors['regexp']}; }
.$prefix${SemanticTokenTypes.operator} { color: ${colors['operator']}; }
.$prefix${SemanticTokenTypes.decorator} { color: ${colors['decorator']}; }

/* Semantic Token Modifiers */
.$prefix${SemanticTokenModifiers.declaration} { font-weight: bold; }
.$prefix${SemanticTokenModifiers.definition} { font-weight: bold; }
.$prefix${SemanticTokenModifiers.readonly} { font-style: italic; }
.$prefix${SemanticTokenModifiers.deprecated} { text-decoration: line-through; }
.$prefix${SemanticTokenModifiers.abstract_} { font-style: italic; }
.$prefix${SemanticTokenModifiers.async_} { text-decoration: underline; }
''';
}

const _lightColors = {
  'namespace': '#267f99',
  'type': '#267f99',
  'class': '#267f99',
  'enum': '#267f99',
  'interface': '#267f99',
  'struct': '#267f99',
  'typeParameter': '#267f99',
  'parameter': '#001080',
  'variable': '#001080',
  'property': '#001080',
  'enumMember': '#0070c1',
  'function': '#795e26',
  'method': '#795e26',
  'macro': '#795e26',
  'keyword': '#0000ff',
  'comment': '#008000',
  'string': '#a31515',
  'number': '#098658',
  'regexp': '#811f3f',
  'operator': '#000000',
  'decorator': '#795e26',
};

const _darkColors = {
  'namespace': '#4ec9b0',
  'type': '#4ec9b0',
  'class': '#4ec9b0',
  'enum': '#4ec9b0',
  'interface': '#4ec9b0',
  'struct': '#4ec9b0',
  'typeParameter': '#4ec9b0',
  'parameter': '#9cdcfe',
  'variable': '#9cdcfe',
  'property': '#9cdcfe',
  'enumMember': '#4fc1ff',
  'function': '#dcdcaa',
  'method': '#dcdcaa',
  'macro': '#dcdcaa',
  'keyword': '#569cd6',
  'comment': '#6a9955',
  'string': '#ce9178',
  'number': '#b5cea8',
  'regexp': '#d16969',
  'operator': '#d4d4d4',
  'decorator': '#dcdcaa',
};
