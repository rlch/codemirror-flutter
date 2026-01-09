/// Syntax highlighting text editing controller.
///
/// This module provides [HighlightingTextEditingController] which overrides
/// buildTextSpan to apply syntax highlighting styles from decorations.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../state/range_set.dart';
import 'decoration.dart';

/// A TextEditingController that applies syntax highlighting.
///
/// This controller overrides [buildTextSpan] to apply styling from
/// decoration ranges. It reads decorations from the decorations facet
/// and converts them to Flutter TextStyles.
class HighlightingTextEditingController extends TextEditingController {
  /// Function to get the current decorations.
  final RangeSet<Decoration> Function()? _getDecorations;
  
  /// Theme for mapping class names to styles.
  final HighlightTheme theme;
  
  /// Optional link range to show as underlined (for Ctrl+hover go-to-definition).
  ({int from, int to})? linkRange;
  
  /// Color for the link underline.
  Color linkColor;
  
  HighlightingTextEditingController({
    super.text,
    RangeSet<Decoration> Function()? getDecorations,
    this.theme = const HighlightTheme(),
    this.linkRange,
    this.linkColor = const Color(0xFF0066CC),
  }) : _getDecorations = getDecorations;
  
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // If no decorations available and no link range, use default behavior
    final decorations = _getDecorations?.call();
    final hasDecorations = decorations != null && decorations.size > 0;
    final hasLink = linkRange != null;
    
    if (!hasDecorations && !hasLink) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    
    final text = this.text;
    final textLen = text.length;
    
    // Build boundary points where decorations start/end
    // Each point maps position -> list of (isStart, decoration, isLink)
    final events = <int, List<(bool isStart, MarkDecoration? deco, bool isLink)>>{};
    
    // Add decoration boundaries
    if (hasDecorations) {
      final cursor = decorations!.iter();
      while (cursor.value != null) {
        final deco = cursor.value;
        if (deco is MarkDecoration) {
          final from = cursor.from.clamp(0, textLen);
          final to = cursor.to.clamp(0, textLen);
          if (from < to) {
            events.putIfAbsent(from, () => []).add((true, deco, false));
            events.putIfAbsent(to, () => []).add((false, deco, false));
          }
        }
        cursor.next();
      }
    }
    
    // Add link underline boundaries
    if (hasLink) {
      final from = linkRange!.from.clamp(0, textLen);
      final to = linkRange!.to.clamp(0, textLen);
      if (from < to) {
        events.putIfAbsent(from, () => []).add((true, null, true));
        events.putIfAbsent(to, () => []).add((false, null, true));
      }
    }
    
    // Sort positions
    final positions = events.keys.toList()..sort();
    
    // Build spans by walking through positions
    final children = <TextSpan>[];
    final active = <MarkDecoration>[];
    var isInLink = false;
    var pos = 0;
    
    for (final boundary in positions) {
      // Add text from pos to boundary with current active styles
      if (boundary > pos) {
        var spanStyle = _mergeActiveStyles(active, style);
        if (isInLink) {
          spanStyle = _applyLinkStyle(spanStyle);
        }
        children.add(TextSpan(
          text: text.substring(pos, boundary),
          style: spanStyle,
        ));
        pos = boundary;
      }
      
      // Process events at this boundary
      for (final (isStart, deco, isLink) in events[boundary]!) {
        if (isLink) {
          isInLink = isStart;
        } else if (isStart) {
          active.add(deco!);
        } else {
          active.remove(deco);
        }
      }
    }
    
    // Add remaining text
    if (pos < textLen) {
      var spanStyle = _mergeActiveStyles(active, style);
      if (isInLink) {
        spanStyle = _applyLinkStyle(spanStyle);
      }
      children.add(TextSpan(
        text: text.substring(pos),
        style: spanStyle,
      ));
    }
    
    // Handle composing region (underline for IME)
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return _applyComposing(children, style);
    }
    
    return TextSpan(style: style, children: children);
  }
  
  /// Merge styles from all active decorations.
  TextStyle? _mergeActiveStyles(List<MarkDecoration> active, TextStyle? baseStyle) {
    if (active.isEmpty) return baseStyle;
    
    TextStyle? result = baseStyle;
    for (final deco in active) {
      final decoStyle = _getStyleForMark(deco, baseStyle);
      if (decoStyle != null && decoStyle != baseStyle) {
        result = result?.merge(decoStyle) ?? decoStyle;
      }
    }
    return result;
  }
  
  /// Apply link underline style.
  TextStyle? _applyLinkStyle(TextStyle? baseStyle) {
    return (baseStyle ?? const TextStyle()).copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
  }
  
  /// Get the TextStyle for a mark decoration.
  TextStyle? _getStyleForMark(MarkDecoration mark, TextStyle? baseStyle) {
    final className = mark.className;
    if (className.isEmpty) return baseStyle;
    
    // Handle multiple space-separated classes
    final classes = className.split(' ');
    TextStyle? result = baseStyle;
    
    for (final cls in classes) {
      final decoStyle = theme.getStyle(cls);
      if (decoStyle != null) {
        result = result?.merge(decoStyle) ?? decoStyle;
      }
    }
    
    return result;
  }
  
  /// Apply composing underline to spans.
  TextSpan _applyComposing(List<TextSpan> children, TextStyle? style) {
    // For now, just return the children as-is
    // A full implementation would apply underline to the composing region
    return TextSpan(style: style, children: children);
  }
}

// ============================================================================
// GitHub Primer Color Palette
// ============================================================================

/// GitHub Primer color palette from @primer/primitives.
///
/// These are the exact hex values used in GitHub's official VS Code theme.
/// Source: https://github.com/primer/github-vscode-theme
abstract final class GitHubColors {
  // ---------------------------------------------------------------------------
  // Light Theme - scale values from primer/primitives
  // ---------------------------------------------------------------------------
  
  /// Comments: scale.gray[5]
  static const lightGray5 = Color(0xFF656d76);
  
  /// Keywords, storage: scale.red[5]
  static const lightRed5 = Color(0xFFcf222e);
  
  /// Strings, regexp: scale.blue[8]
  static const lightBlue8 = Color(0xFF0a3069);
  
  /// Constants, support, properties: scale.blue[6]
  static const lightBlue6 = Color(0xFF0550ae);
  
  /// Functions: scale.purple[5]
  static const lightPurple5 = Color(0xFF8250df);
  
  /// Variable definitions, types: scale.orange[6]
  static const lightOrange6 = Color(0xFF953800);
  
  /// Tags (JSX/HTML): scale.green[6]
  static const lightGreen6 = Color(0xFF116329);
  
  /// Default foreground text: color.fg.default
  static const lightFgDefault = Color(0xFF1f2328);
  
  /// Background: color.canvas.default
  static const lightBackground = Color(0xFFffffff);
  
  // ---------------------------------------------------------------------------
  // Dark Theme - scale values from primer/primitives
  // ---------------------------------------------------------------------------
  
  /// Comments: scale.gray[3]
  static const darkGray3 = Color(0xFF8b949e);
  
  /// Keywords, storage: scale.red[3]
  static const darkRed3 = Color(0xFFff7b72);
  
  /// Strings, regexp: scale.blue[1]
  static const darkBlue1 = Color(0xFFa5d6ff);
  
  /// Constants, support, properties: scale.blue[2]
  static const darkBlue2 = Color(0xFF79c0ff);
  
  /// Functions: scale.purple[2]
  static const darkPurple2 = Color(0xFFd2a8ff);
  
  /// Variable definitions, types: scale.orange[2]
  static const darkOrange2 = Color(0xFFffa657);
  
  /// Tags (JSX/HTML): scale.green[1]
  static const darkGreen1 = Color(0xFF7ee787);
  
  /// Default foreground text: color.fg.default
  static const darkFgDefault = Color(0xFFe6edf3);
  
  /// Background: color.canvas.default
  static const darkBackground = Color(0xFF0d1117);
}

// ============================================================================
// Highlight Theme
// ============================================================================

/// Theme that maps CSS class names to Flutter TextStyles.
///
/// This provides a mapping from CodeMirror-style class names like
/// 'cm-keyword', 'cm-string' to Flutter TextStyles.
///
/// Both syntax highlighting (cm-*) and semantic tokens (cm-sem-*) use
/// the same underlying color palette from GitHub Primer for consistency.
class HighlightTheme {
  /// Map from class name to TextStyle.
  final Map<String, TextStyle> _styles;
  
  /// Create a theme with the given styles.
  const HighlightTheme([this._styles = const {}]);
  
  /// Get the style for a class name.
  TextStyle? getStyle(String className) => _styles[className];
  
  /// Default light theme constant for use as default parameter value.
  static const HighlightTheme defaultLight = _LightTheme();
  
  /// Default dark theme constant for use as default parameter value.
  static const HighlightTheme defaultDark = _DarkTheme();
  
  /// GitHub Light Default theme.
  /// 
  /// Based on GitHub's official VS Code theme using Primer color palette.
  /// Clean, readable colors on a white background.
  static final HighlightTheme light = HighlightTheme({
    // -------------------------------------------------------------------------
    // Syntax Highlighting (Lezer/tree-sitter based)
    // -------------------------------------------------------------------------
    
    // Keywords (if, else, return, const, let, function, class, etc.)
    'cm-keyword': TextStyle(color: GitHubColors.lightRed5),
    'cm-controlKeyword': TextStyle(color: GitHubColors.lightRed5),
    'cm-definitionKeyword': TextStyle(color: GitHubColors.lightRed5),
    'cm-moduleKeyword': TextStyle(color: GitHubColors.lightRed5),
    'cm-operatorKeyword': TextStyle(color: GitHubColors.lightRed5),
    
    // Atoms/booleans/null (true, false, null, undefined)
    'cm-atom': TextStyle(color: GitHubColors.lightBlue6),
    'cm-bool': TextStyle(color: GitHubColors.lightBlue6),
    'cm-null': TextStyle(color: GitHubColors.lightBlue6),
    'cm-self': TextStyle(color: GitHubColors.lightBlue6),
    
    // Numbers and literals
    'cm-number': TextStyle(color: GitHubColors.lightBlue6),
    'cm-literal': TextStyle(color: GitHubColors.lightBlue6),
    
    // Definitions (function names, variable declarations)
    'cm-def': TextStyle(color: GitHubColors.lightOrange6),
    'cm-definition': TextStyle(color: GitHubColors.lightOrange6),
    
    // Variables
    'cm-variable': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-variableName': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-variable-2': TextStyle(color: GitHubColors.lightOrange6),
    'cm-variable-3': TextStyle(color: GitHubColors.lightBlue6),
    
    // Types and classes
    'cm-type': TextStyle(color: GitHubColors.lightOrange6),
    'cm-typeName': TextStyle(color: GitHubColors.lightOrange6),
    'cm-class': TextStyle(color: GitHubColors.lightOrange6),
    'cm-className': TextStyle(color: GitHubColors.lightOrange6),
    'cm-namespace': TextStyle(color: GitHubColors.lightOrange6),
    
    // Properties and labels
    'cm-property': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-propertyName': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-labelName': TextStyle(color: GitHubColors.lightOrange6),
    
    // Functions
    'cm-function': TextStyle(color: GitHubColors.lightPurple5),
    
    // Operators and punctuation
    'cm-operator': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-punctuation': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-paren': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-squareBracket': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-brace': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-derefOperator': TextStyle(color: GitHubColors.lightFgDefault),
    'cm-separator': TextStyle(color: GitHubColors.lightFgDefault),
    
    // Comments
    'cm-comment': TextStyle(color: GitHubColors.lightGray5),
    'cm-lineComment': TextStyle(color: GitHubColors.lightGray5),
    'cm-blockComment': TextStyle(color: GitHubColors.lightGray5),
    
    // Strings
    'cm-string': TextStyle(color: GitHubColors.lightBlue8),
    'cm-string2': TextStyle(color: GitHubColors.lightBlue8),
    
    // Regexp
    'cm-regexp': TextStyle(color: GitHubColors.lightBlue8),
    
    // Meta and modifiers
    'cm-meta': TextStyle(color: GitHubColors.lightGray5),
    'cm-modifier': TextStyle(color: GitHubColors.lightRed5),
    'cm-qualifier': TextStyle(color: GitHubColors.lightRed5),
    
    // Builtins and support
    'cm-builtin': TextStyle(color: GitHubColors.lightBlue6),
    'cm-standard': TextStyle(color: GitHubColors.lightBlue6),
    
    // Tags (JSX/HTML)
    'cm-tag': TextStyle(color: GitHubColors.lightGreen6),
    'cm-tagName': TextStyle(color: GitHubColors.lightGreen6),
    'cm-angleBracket': TextStyle(color: GitHubColors.lightFgDefault),
    
    // Attributes
    'cm-attribute': TextStyle(color: GitHubColors.lightBlue6),
    'cm-attributeName': TextStyle(color: GitHubColors.lightBlue6),
    'cm-attributeValue': TextStyle(color: GitHubColors.lightBlue8),
    
    // JSX content
    'cm-content': TextStyle(color: GitHubColors.lightFgDefault),
    
    // Headers (markdown)
    'cm-header': TextStyle(color: GitHubColors.lightBlue6),
    'cm-hr': TextStyle(color: GitHubColors.lightGray5),
    'cm-link': TextStyle(color: GitHubColors.lightBlue8),
    
    // Errors
    'cm-error': TextStyle(color: GitHubColors.lightRed5),
    'cm-invalid': TextStyle(color: GitHubColors.lightRed5),
    
    // Escape sequences in strings
    'cm-escape': TextStyle(color: GitHubColors.lightRed5),
    
    // Bracket matching
    'cm-matchingBracket': const TextStyle(backgroundColor: Color(0x4034D058)),
    'cm-nonmatchingBracket': const TextStyle(backgroundColor: Color(0x40FF8182)),
    
    // Search matches
    'cm-searchMatch': const TextStyle(backgroundColor: Color(0x80FFF176)),
    'cm-searchMatch-selected': const TextStyle(backgroundColor: Color(0x80FFAB40)),
    
    // Lint underlines
    'cm-lintRange': const TextStyle(),
    'cm-lintRange-error': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFcf222e),
      decorationStyle: TextDecorationStyle.wavy,
    ),
    'cm-lintRange-warning': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFbf8700),
      decorationStyle: TextDecorationStyle.wavy,
    ),
    'cm-lintRange-info': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF0550ae),
      decorationStyle: TextDecorationStyle.solid,
    ),
    'cm-lintRange-hint': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF8250df),
      decorationStyle: TextDecorationStyle.dotted,
    ),
    
    // Document highlights (LSP documentHighlight)
    'cm-documentHighlight': const TextStyle(backgroundColor: Color(0x266E7781)),
    'cm-documentHighlight-text': const TextStyle(backgroundColor: Color(0x266E7781)),
    'cm-documentHighlight-read': const TextStyle(backgroundColor: Color(0x266E7781)),
    'cm-documentHighlight-write': const TextStyle(backgroundColor: Color(0x40D4A72C)),
    
    // -------------------------------------------------------------------------
    // LSP Semantic Tokens
    // Uses SAME colors as syntax highlighting for consistency.
    // Semantic tokens layer on top to add modifiers (bold, italic, etc.)
    // -------------------------------------------------------------------------
    
    // Types and classes - orange (matches cm-type, cm-class)
    'cm-sem-namespace': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-type': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-class': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-enum': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-interface': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-struct': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-typeParameter': TextStyle(color: GitHubColors.lightOrange6),
    
    // Variables and parameters - orange for visibility
    // GitHub uses default text for variable refs, but that makes semantic
    // tokens invisible. Use orange (like definitions) for better visibility.
    'cm-sem-parameter': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-variable': TextStyle(color: GitHubColors.lightOrange6),
    'cm-sem-property': TextStyle(color: GitHubColors.lightBlue6),
    'cm-sem-event': TextStyle(color: GitHubColors.lightBlue6),
    
    // Constants and enum members - blue (matches cm-atom)
    'cm-sem-enumMember': TextStyle(color: GitHubColors.lightBlue6),
    
    // Member (TypeScript LSP uses "member" for methods)
    'cm-sem-member': TextStyle(color: GitHubColors.lightPurple5),
    
    // Functions - purple (matches cm-function)
    'cm-sem-function': TextStyle(color: GitHubColors.lightPurple5),
    'cm-sem-method': TextStyle(color: GitHubColors.lightPurple5),
    'cm-sem-macro': TextStyle(color: GitHubColors.lightPurple5),
    'cm-sem-decorator': TextStyle(color: GitHubColors.lightPurple5),
    
    // Keywords - red (matches cm-keyword)
    'cm-sem-keyword': TextStyle(color: GitHubColors.lightRed5),
    'cm-sem-modifier': TextStyle(color: GitHubColors.lightRed5),
    
    // Comments - gray (matches cm-comment)
    'cm-sem-comment': TextStyle(color: GitHubColors.lightGray5),
    
    // Strings - dark blue (matches cm-string)
    'cm-sem-string': TextStyle(color: GitHubColors.lightBlue8),
    
    // Numbers - blue (matches cm-number)
    'cm-sem-number': TextStyle(color: GitHubColors.lightBlue6),
    
    // Regexp - dark blue (matches cm-regexp)
    'cm-sem-regexp': TextStyle(color: GitHubColors.lightBlue8),
    
    // Operators - default text (matches cm-operator)
    'cm-sem-operator': TextStyle(color: GitHubColors.lightFgDefault),
    
    // -------------------------------------------------------------------------
    // Semantic Token Modifiers (add styling, don't change color)
    // -------------------------------------------------------------------------
    'cm-sem-declaration': const TextStyle(fontWeight: FontWeight.bold),
    'cm-sem-definition': const TextStyle(fontWeight: FontWeight.bold),
    'cm-sem-readonly': const TextStyle(fontStyle: FontStyle.italic),
    'cm-sem-static': const TextStyle(),
    'cm-sem-deprecated': const TextStyle(decoration: TextDecoration.lineThrough),
    'cm-sem-abstract': const TextStyle(fontStyle: FontStyle.italic),
    'cm-sem-async': const TextStyle(),
    'cm-sem-defaultLibrary': const TextStyle(),
    'cm-sem-local': const TextStyle(),
  });

  /// The recommended background color for the GitHub light theme.
  static const Color lightBackground = GitHubColors.lightBackground;
  
  /// GitHub Dark Default theme.
  /// 
  /// Based on GitHub's official VS Code theme using Primer color palette.
  /// Softer colors optimized for dark backgrounds.
  static final HighlightTheme dark = HighlightTheme({
    // -------------------------------------------------------------------------
    // Syntax Highlighting (Lezer/tree-sitter based)
    // -------------------------------------------------------------------------
    
    // Keywords
    'cm-keyword': TextStyle(color: GitHubColors.darkRed3),
    'cm-controlKeyword': TextStyle(color: GitHubColors.darkRed3),
    'cm-definitionKeyword': TextStyle(color: GitHubColors.darkRed3),
    'cm-moduleKeyword': TextStyle(color: GitHubColors.darkRed3),
    'cm-operatorKeyword': TextStyle(color: GitHubColors.darkRed3),
    
    // Atoms/booleans/null
    'cm-atom': TextStyle(color: GitHubColors.darkBlue2),
    'cm-bool': TextStyle(color: GitHubColors.darkBlue2),
    'cm-null': TextStyle(color: GitHubColors.darkBlue2),
    'cm-self': TextStyle(color: GitHubColors.darkBlue2),
    
    // Numbers and literals
    'cm-number': TextStyle(color: GitHubColors.darkBlue2),
    'cm-literal': TextStyle(color: GitHubColors.darkBlue2),
    
    // Definitions
    'cm-def': TextStyle(color: GitHubColors.darkOrange2),
    'cm-definition': TextStyle(color: GitHubColors.darkOrange2),
    
    // Variables
    'cm-variable': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-variableName': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-variable-2': TextStyle(color: GitHubColors.darkOrange2),
    'cm-variable-3': TextStyle(color: GitHubColors.darkBlue2),
    
    // Types and classes
    'cm-type': TextStyle(color: GitHubColors.darkOrange2),
    'cm-typeName': TextStyle(color: GitHubColors.darkOrange2),
    'cm-class': TextStyle(color: GitHubColors.darkOrange2),
    'cm-className': TextStyle(color: GitHubColors.darkOrange2),
    'cm-namespace': TextStyle(color: GitHubColors.darkOrange2),
    
    // Properties and labels
    'cm-property': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-propertyName': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-labelName': TextStyle(color: GitHubColors.darkOrange2),
    
    // Functions
    'cm-function': TextStyle(color: GitHubColors.darkPurple2),
    
    // Operators and punctuation
    'cm-operator': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-punctuation': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-paren': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-squareBracket': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-brace': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-derefOperator': TextStyle(color: GitHubColors.darkFgDefault),
    'cm-separator': TextStyle(color: GitHubColors.darkFgDefault),
    
    // Comments
    'cm-comment': TextStyle(color: GitHubColors.darkGray3),
    'cm-lineComment': TextStyle(color: GitHubColors.darkGray3),
    'cm-blockComment': TextStyle(color: GitHubColors.darkGray3),
    
    // Strings
    'cm-string': TextStyle(color: GitHubColors.darkBlue1),
    'cm-string2': TextStyle(color: GitHubColors.darkBlue1),
    
    // Regexp
    'cm-regexp': TextStyle(color: GitHubColors.darkBlue1),
    
    // Meta and modifiers
    'cm-meta': TextStyle(color: GitHubColors.darkGray3),
    'cm-modifier': TextStyle(color: GitHubColors.darkRed3),
    'cm-qualifier': TextStyle(color: GitHubColors.darkRed3),
    
    // Builtins and support
    'cm-builtin': TextStyle(color: GitHubColors.darkBlue2),
    'cm-standard': TextStyle(color: GitHubColors.darkBlue2),
    
    // Tags (JSX/HTML)
    'cm-tag': TextStyle(color: GitHubColors.darkGreen1),
    'cm-tagName': TextStyle(color: GitHubColors.darkGreen1),
    'cm-angleBracket': TextStyle(color: GitHubColors.darkFgDefault),
    
    // Attributes
    'cm-attribute': TextStyle(color: GitHubColors.darkBlue2),
    'cm-attributeName': TextStyle(color: GitHubColors.darkBlue2),
    'cm-attributeValue': TextStyle(color: GitHubColors.darkBlue1),
    
    // JSX content
    'cm-content': TextStyle(color: GitHubColors.darkFgDefault),
    
    // Headers (markdown)
    'cm-header': TextStyle(color: GitHubColors.darkBlue2),
    'cm-hr': TextStyle(color: GitHubColors.darkGray3),
    'cm-link': TextStyle(color: GitHubColors.darkBlue1),
    
    // Errors
    'cm-error': TextStyle(color: GitHubColors.darkRed3),
    'cm-invalid': TextStyle(color: GitHubColors.darkRed3),
    
    // Escape sequences in strings
    'cm-escape': TextStyle(color: GitHubColors.darkRed3),
    
    // Bracket matching
    'cm-matchingBracket': const TextStyle(backgroundColor: Color(0x4058A6FF)),
    'cm-nonmatchingBracket': const TextStyle(backgroundColor: Color(0x40F85149)),
    
    // Search matches
    'cm-searchMatch': const TextStyle(backgroundColor: Color(0x80BB8009)),
    'cm-searchMatch-selected': const TextStyle(backgroundColor: Color(0x80E3B341)),
    
    // Lint underlines
    'cm-lintRange': const TextStyle(),
    'cm-lintRange-error': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFff7b72),
      decorationStyle: TextDecorationStyle.wavy,
    ),
    'cm-lintRange-warning': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFd29922),
      decorationStyle: TextDecorationStyle.wavy,
    ),
    'cm-lintRange-info': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF79c0ff),
      decorationStyle: TextDecorationStyle.solid,
    ),
    'cm-lintRange-hint': const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFd2a8ff),
      decorationStyle: TextDecorationStyle.dotted,
    ),
    
    // Document highlights (LSP documentHighlight)
    'cm-documentHighlight': const TextStyle(backgroundColor: Color(0x268B949E)),
    'cm-documentHighlight-text': const TextStyle(backgroundColor: Color(0x268B949E)),
    'cm-documentHighlight-read': const TextStyle(backgroundColor: Color(0x268B949E)),
    'cm-documentHighlight-write': const TextStyle(backgroundColor: Color(0x40E3B341)),
    
    // -------------------------------------------------------------------------
    // LSP Semantic Tokens
    // Uses SAME colors as syntax highlighting for consistency.
    // -------------------------------------------------------------------------
    
    // Types and classes - orange (matches cm-type, cm-class)
    'cm-sem-namespace': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-type': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-class': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-enum': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-interface': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-struct': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-typeParameter': TextStyle(color: GitHubColors.darkOrange2),
    
    // Variables and parameters - orange for visibility
    'cm-sem-parameter': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-variable': TextStyle(color: GitHubColors.darkOrange2),
    'cm-sem-property': TextStyle(color: GitHubColors.darkBlue2),
    'cm-sem-event': TextStyle(color: GitHubColors.darkBlue2),
    
    // Constants and enum members - blue (matches cm-atom)
    'cm-sem-enumMember': TextStyle(color: GitHubColors.darkBlue2),
    
    // Member (TypeScript LSP uses "member" for methods)
    'cm-sem-member': TextStyle(color: GitHubColors.darkPurple2),
    
    // Functions - purple (matches cm-function)
    'cm-sem-function': TextStyle(color: GitHubColors.darkPurple2),
    'cm-sem-method': TextStyle(color: GitHubColors.darkPurple2),
    'cm-sem-macro': TextStyle(color: GitHubColors.darkPurple2),
    'cm-sem-decorator': TextStyle(color: GitHubColors.darkPurple2),
    
    // Keywords - red (matches cm-keyword)
    'cm-sem-keyword': TextStyle(color: GitHubColors.darkRed3),
    'cm-sem-modifier': TextStyle(color: GitHubColors.darkRed3),
    
    // Comments - gray (matches cm-comment)
    'cm-sem-comment': TextStyle(color: GitHubColors.darkGray3),
    
    // Strings - light blue (matches cm-string)
    'cm-sem-string': TextStyle(color: GitHubColors.darkBlue1),
    
    // Numbers - blue (matches cm-number)
    'cm-sem-number': TextStyle(color: GitHubColors.darkBlue2),
    
    // Regexp - light blue (matches cm-regexp)
    'cm-sem-regexp': TextStyle(color: GitHubColors.darkBlue1),
    
    // Operators - default text (matches cm-operator)
    'cm-sem-operator': TextStyle(color: GitHubColors.darkFgDefault),
    
    // -------------------------------------------------------------------------
    // Semantic Token Modifiers
    // -------------------------------------------------------------------------
    'cm-sem-declaration': const TextStyle(fontWeight: FontWeight.bold),
    'cm-sem-definition': const TextStyle(fontWeight: FontWeight.bold),
    'cm-sem-readonly': const TextStyle(fontStyle: FontStyle.italic),
    'cm-sem-static': const TextStyle(),
    'cm-sem-deprecated': const TextStyle(decoration: TextDecoration.lineThrough),
    'cm-sem-abstract': const TextStyle(fontStyle: FontStyle.italic),
    'cm-sem-async': const TextStyle(),
    'cm-sem-defaultLibrary': const TextStyle(),
    'cm-sem-local': const TextStyle(),
  });

  /// The recommended background color for the GitHub dark theme.
  static const Color darkBackground = GitHubColors.darkBackground;
}

/// Internal const light theme implementation.
class _LightTheme extends HighlightTheme {
  const _LightTheme() : super(const {});
  
  @override
  TextStyle? getStyle(String className) => HighlightTheme.light._styles[className];
}

/// Internal const dark theme implementation.
class _DarkTheme extends HighlightTheme {
  const _DarkTheme() : super(const {});
  
  @override
  TextStyle? getStyle(String className) => HighlightTheme.dark._styles[className];
}
