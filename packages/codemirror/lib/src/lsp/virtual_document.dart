/// Virtual document abstraction for LSP integration.
///
/// A virtual document wraps a visible portion of text with hidden prefix/suffix
/// content, allowing LSP operations to work on the full context while the editor
/// only shows the visible portion.
library;

import 'position.dart';

/// A virtual document that wraps visible content with hidden prefix/suffix.
///
/// This is useful when you want to show only part of a document in the editor
/// (e.g., a function body) but need the full context for LSP features like
/// completions, diagnostics, hover, etc.
///
/// ## Architecture
///
/// ```
/// Full Virtual Document:
/// ┌─────────────────────────────────────┐
/// │ interface Props { ... }             │  ← prefix (hidden from editor)
/// │ function Component(props) {         │
/// ├─────────────────────────────────────┤
/// │   return <div>Hello</div>;          │  ← visible body (shown in editor)
/// ├─────────────────────────────────────┤
/// │ }                                   │  ← suffix (hidden from editor)
/// └─────────────────────────────────────┘
/// ```
///
/// All LSP operations are performed on [fullContent], then positions are
/// mapped back to the visible range using [toVisiblePosition]/[toVisibleOffset].
class VirtualDocument {
  /// The prefix content (hidden, before the visible body).
  final String prefix;

  /// The visible body (what the editor shows and the user edits).
  final String body;

  /// The suffix content (hidden, after the visible body).
  final String suffix;

  /// Cached values computed from prefix.
  late final int _bodyOffset = prefix.length;
  late final int _bodyStartLine = prefix.split('\n').length - 1;

  /// Create a virtual document with the given prefix, body, and suffix.
  VirtualDocument({
    required this.prefix,
    required this.body,
    this.suffix = '',
  });

  /// Create a virtual document with no prefix or suffix.
  VirtualDocument.simple(this.body)
      : prefix = '',
        suffix = '';

  /// The offset where the visible body starts in the full document.
  int get bodyOffset => _bodyOffset;

  /// The line number where the visible body starts (0-indexed).
  int get bodyStartLine => _bodyStartLine;

  /// The full document content (prefix + body + suffix).
  String get fullContent => '$prefix$body$suffix';

  /// The length of the full document.
  int get fullLength => prefix.length + body.length + suffix.length;

  // ===========================================================================
  // Offset conversions
  // ===========================================================================

  /// Convert an offset in the visible body to an offset in the full document.
  int toFullOffset(int visibleOffset) {
    return _bodyOffset + visibleOffset.clamp(0, body.length);
  }

  /// Convert an offset in the full document to an offset in the visible body.
  ///
  /// Returns null if the offset is outside the visible range.
  int? toVisibleOffset(int fullOffset) {
    if (fullOffset < _bodyOffset) return null;
    if (fullOffset > _bodyOffset + body.length) return null;
    return fullOffset - _bodyOffset;
  }

  /// Check if an offset in the full document is within the visible body.
  bool isOffsetInVisibleRange(int fullOffset) {
    return fullOffset >= _bodyOffset && fullOffset <= _bodyOffset + body.length;
  }

  // ===========================================================================
  // Position conversions
  // ===========================================================================

  /// Convert a position in the visible body to a position in the full document.
  LspPosition toFullPosition(LspPosition visiblePosition) {
    return LspPosition(
      line: visiblePosition.line + _bodyStartLine,
      character: visiblePosition.character,
    );
  }

  /// Convert a position in the full document to a position in the visible body.
  ///
  /// Returns null if the position is outside the visible range.
  LspPosition? toVisiblePosition(LspPosition fullPosition) {
    final visibleLine = fullPosition.line - _bodyStartLine;
    if (visibleLine < 0) return null;

    final bodyLines = body.split('\n').length;
    if (visibleLine >= bodyLines) return null;

    return LspPosition(
      line: visibleLine,
      character: fullPosition.character,
    );
  }

  /// Check if a position in the full document is within the visible body.
  bool isPositionInVisibleRange(LspPosition fullPosition) {
    return toVisiblePosition(fullPosition) != null;
  }

  // ===========================================================================
  // Range conversions
  // ===========================================================================

  /// Convert a range in the visible body to a range in the full document.
  LspRange toFullRange(LspRange visibleRange) {
    return LspRange(
      start: toFullPosition(visibleRange.start),
      end: toFullPosition(visibleRange.end),
    );
  }

  /// Convert a range in the full document to a range in the visible body.
  ///
  /// Returns null if the range is entirely outside the visible range.
  /// If the range partially overlaps, it is clamped to the visible bounds.
  LspRange? toVisibleRange(LspRange fullRange) {
    final start = toVisiblePosition(fullRange.start);
    final end = toVisiblePosition(fullRange.end);

    if (start == null && end == null) return null;

    // Clamp to visible range
    final bodyEndPos = body.endLspPosition;
    return LspRange(
      start: start ?? const LspPosition.zero(),
      end: end ?? bodyEndPos,
    );
  }

  // ===========================================================================
  // Mutations
  // ===========================================================================

  /// Create a new virtual document with updated body content.
  ///
  /// The prefix and suffix remain unchanged.
  VirtualDocument withBody(String newBody) {
    return VirtualDocument(
      prefix: prefix,
      body: newBody,
      suffix: suffix,
    );
  }

  /// Create a new virtual document with updated prefix.
  VirtualDocument withPrefix(String newPrefix) {
    return VirtualDocument(
      prefix: newPrefix,
      body: body,
      suffix: suffix,
    );
  }

  /// Create a new virtual document with updated suffix.
  VirtualDocument withSuffix(String newSuffix) {
    return VirtualDocument(
      prefix: prefix,
      body: body,
      suffix: newSuffix,
    );
  }

  @override
  String toString() {
    return 'VirtualDocument(prefix: ${prefix.length} chars, '
        'body: ${body.length} chars, suffix: ${suffix.length} chars)';
  }
}
