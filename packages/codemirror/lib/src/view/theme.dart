/// Editor theming system.
///
/// This module provides the theming infrastructure for the editor,
/// including facets for custom themes and default light/dark themes.
///
/// Unlike the TypeScript version which uses CSS, this Dart port uses
/// Flutter's theming system with `TextStyle`, `Color`, and `BoxDecoration`.
library;

import 'package:flutter/material.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';

// ============================================================================
// Theme Facets
// ============================================================================

/// Facet for additional theme class names.
///
/// In the TypeScript version, this collects CSS class names.
/// In Flutter, we use this to track theme identifiers that can
/// be used to apply theme-specific logic.
final Facet<String, String> theme = Facet.define(
  FacetConfig(combine: (strs) => strs.join(' ')),
);

/// Facet indicating whether the editor should use dark theme styling.
///
/// When any value is `true`, dark theme is active.
final Facet<bool, bool> darkTheme = Facet.define(
  FacetConfig(combine: (values) => values.any((v) => v)),
);

// ============================================================================
// EditorThemeData - Flutter-based theme data
// ============================================================================

/// Theme data for the code editor.
///
/// This is the Flutter equivalent of the CSS-based theming in CodeMirror.
/// It provides all the visual styling options for the editor.
class EditorThemeData {
  // -------------------------
  // General Editor Styling
  // -------------------------

  /// Background color of the editor.
  final Color? backgroundColor;

  /// Default text style for editor content.
  final TextStyle textStyle;

  /// Text style for line numbers in the gutter.
  final TextStyle? lineNumberStyle;

  /// Padding around the editor content.
  final EdgeInsets contentPadding;

  // -------------------------
  // Selection & Cursor
  // -------------------------

  /// Color of the selection background when editor is focused.
  final Color selectionColor;

  /// Color of the selection background when editor is NOT focused.
  final Color inactiveSelectionColor;

  /// Color of the cursor.
  final Color cursorColor;

  /// Width of the cursor line.
  final double cursorWidth;

  /// Cursor blink interval in milliseconds (0 to disable blinking).
  final int cursorBlinkRate;

  // -------------------------
  // Active Line
  // -------------------------

  /// Background color for the active line (line with cursor).
  final Color? activeLineColor;

  /// Background color for active line in gutter.
  final Color? activeLineGutterColor;

  // -------------------------
  // Gutter
  // -------------------------

  /// Background color of the gutter area.
  final Color? gutterBackgroundColor;

  /// Border color between gutter and content.
  final Color? gutterBorderColor;

  /// Text color for gutter content.
  final Color? gutterTextColor;

  // -------------------------
  // Panels
  // -------------------------

  /// Background color for panels (top/bottom).
  final Color? panelBackgroundColor;

  /// Border color for panels.
  final Color? panelBorderColor;

  // -------------------------
  // Tooltips
  // -------------------------

  /// Background color for tooltips.
  final Color? tooltipBackgroundColor;

  /// Text color for tooltips.
  final Color? tooltipTextColor;

  /// Border radius for tooltips.
  final BorderRadius? tooltipBorderRadius;

  // -------------------------
  // Special Characters
  // -------------------------

  /// Color for special/invisible characters.
  final Color? specialCharColor;

  /// Color for trailing whitespace highlight.
  final Color? trailingSpaceColor;

  // -------------------------
  // Dialogs (find/replace, etc.)
  // -------------------------

  /// Text field decoration for dialog inputs.
  final InputDecoration? dialogInputDecoration;

  /// Button style for dialog buttons.
  final ButtonStyle? dialogButtonStyle;

  const EditorThemeData({
    this.backgroundColor,
    this.textStyle = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.4,
    ),
    this.lineNumberStyle,
    this.contentPadding = const EdgeInsets.symmetric(vertical: 4),
    this.selectionColor = const Color(0xFFD7D4F0),
    this.inactiveSelectionColor = const Color(0xFFD9D9D9),
    this.cursorColor = Colors.black,
    this.cursorWidth = 1.2,
    this.cursorBlinkRate = 1200,
    this.activeLineColor,
    this.activeLineGutterColor,
    this.gutterBackgroundColor,
    this.gutterBorderColor,
    this.gutterTextColor,
    this.panelBackgroundColor,
    this.panelBorderColor,
    this.tooltipBackgroundColor,
    this.tooltipTextColor,
    this.tooltipBorderRadius,
    this.specialCharColor,
    this.trailingSpaceColor,
    this.dialogInputDecoration,
    this.dialogButtonStyle,
  });

  /// Create a copy with modified values.
  EditorThemeData copyWith({
    Color? backgroundColor,
    TextStyle? textStyle,
    TextStyle? lineNumberStyle,
    EdgeInsets? contentPadding,
    Color? selectionColor,
    Color? inactiveSelectionColor,
    Color? cursorColor,
    double? cursorWidth,
    int? cursorBlinkRate,
    Color? activeLineColor,
    Color? activeLineGutterColor,
    Color? gutterBackgroundColor,
    Color? gutterBorderColor,
    Color? gutterTextColor,
    Color? panelBackgroundColor,
    Color? panelBorderColor,
    Color? tooltipBackgroundColor,
    Color? tooltipTextColor,
    BorderRadius? tooltipBorderRadius,
    Color? specialCharColor,
    Color? trailingSpaceColor,
    InputDecoration? dialogInputDecoration,
    ButtonStyle? dialogButtonStyle,
  }) {
    return EditorThemeData(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textStyle: textStyle ?? this.textStyle,
      lineNumberStyle: lineNumberStyle ?? this.lineNumberStyle,
      contentPadding: contentPadding ?? this.contentPadding,
      selectionColor: selectionColor ?? this.selectionColor,
      inactiveSelectionColor:
          inactiveSelectionColor ?? this.inactiveSelectionColor,
      cursorColor: cursorColor ?? this.cursorColor,
      cursorWidth: cursorWidth ?? this.cursorWidth,
      cursorBlinkRate: cursorBlinkRate ?? this.cursorBlinkRate,
      activeLineColor: activeLineColor ?? this.activeLineColor,
      activeLineGutterColor:
          activeLineGutterColor ?? this.activeLineGutterColor,
      gutterBackgroundColor:
          gutterBackgroundColor ?? this.gutterBackgroundColor,
      gutterBorderColor: gutterBorderColor ?? this.gutterBorderColor,
      gutterTextColor: gutterTextColor ?? this.gutterTextColor,
      panelBackgroundColor: panelBackgroundColor ?? this.panelBackgroundColor,
      panelBorderColor: panelBorderColor ?? this.panelBorderColor,
      tooltipBackgroundColor:
          tooltipBackgroundColor ?? this.tooltipBackgroundColor,
      tooltipTextColor: tooltipTextColor ?? this.tooltipTextColor,
      tooltipBorderRadius: tooltipBorderRadius ?? this.tooltipBorderRadius,
      specialCharColor: specialCharColor ?? this.specialCharColor,
      trailingSpaceColor: trailingSpaceColor ?? this.trailingSpaceColor,
      dialogInputDecoration:
          dialogInputDecoration ?? this.dialogInputDecoration,
      dialogButtonStyle: dialogButtonStyle ?? this.dialogButtonStyle,
    );
  }

  /// Merge this theme with another, with the other's values taking precedence
  /// where they are non-null.
  EditorThemeData merge(EditorThemeData? other) {
    if (other == null) return this;
    return copyWith(
      backgroundColor: other.backgroundColor,
      textStyle: textStyle.merge(other.textStyle),
      lineNumberStyle: other.lineNumberStyle ?? lineNumberStyle,
      contentPadding: other.contentPadding,
      selectionColor: other.selectionColor,
      inactiveSelectionColor: other.inactiveSelectionColor,
      cursorColor: other.cursorColor,
      cursorWidth: other.cursorWidth,
      cursorBlinkRate: other.cursorBlinkRate,
      activeLineColor: other.activeLineColor,
      activeLineGutterColor: other.activeLineGutterColor,
      gutterBackgroundColor: other.gutterBackgroundColor,
      gutterBorderColor: other.gutterBorderColor,
      gutterTextColor: other.gutterTextColor,
      panelBackgroundColor: other.panelBackgroundColor,
      panelBorderColor: other.panelBorderColor,
      tooltipBackgroundColor: other.tooltipBackgroundColor,
      tooltipTextColor: other.tooltipTextColor,
      tooltipBorderRadius: other.tooltipBorderRadius,
      specialCharColor: other.specialCharColor,
      trailingSpaceColor: other.trailingSpaceColor,
      dialogInputDecoration: other.dialogInputDecoration,
      dialogButtonStyle: other.dialogButtonStyle,
    );
  }
}

// ============================================================================
// Default Themes
// ============================================================================

/// Default light theme - GitHub Light style.
/// 
/// Colors based on GitHub's design system (Primer).
const EditorThemeData lightEditorTheme = EditorThemeData(
  // GitHub canvas.default
  backgroundColor: Color(0xFFFFFFFF),
  textStyle: TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.4,
    // GitHub fg.default
    color: Color(0xFF1F2328),
  ),
  lineNumberStyle: TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.4,
    // Muted foreground for line numbers
    color: Color(0xFF6E7781),
  ),
  // GitHub accent.fg with ~20% alpha (blue selection)
  selectionColor: Color(0x330969DA),
  inactiveSelectionColor: Color(0x1A6E7781),
  // GitHub accent.fg (blue cursor)
  cursorColor: Color(0xFF0969DA),
  cursorWidth: 1.2,
  cursorBlinkRate: 1200,
  // Active line - subtle but visible highlight
  activeLineColor: Color(0x0F6E7781),
  activeLineGutterColor: Color(0x0F6E7781),
  // Subtle gutter background
  gutterBackgroundColor: Color(0xFFF6F8FA),
  gutterBorderColor: Color(0xFFE1E4E8),
  // Muted foreground for gutter text
  gutterTextColor: Color(0xFF6E7781),
  // GitHub canvas.subtle
  panelBackgroundColor: Color(0xFFF6F8FA),
  panelBorderColor: Color(0xFFD0D7DE),
  // GitHub canvas.overlay
  tooltipBackgroundColor: Color(0xFFFFFFFF),
  tooltipTextColor: Color(0xFF1F2328),
  tooltipBorderRadius: BorderRadius.all(Radius.circular(6)),
  // GitHub danger.fg
  specialCharColor: Color(0xFFCF222E),
  trailingSpaceColor: Color(0x40CF222E),
);

/// Default dark theme - GitHub Dark style.
/// 
/// Colors based on GitHub's design system (Primer).
const EditorThemeData darkEditorTheme = EditorThemeData(
  // GitHub dark canvas.default
  backgroundColor: Color(0xFF0D1117),
  textStyle: TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.4,
    // GitHub dark fg.default
    color: Color(0xFFE6EDF3),
  ),
  lineNumberStyle: TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.4,
    // Muted foreground for line numbers
    color: Color(0xFF8B949E),
  ),
  // GitHub dark accent.fg with ~20% alpha (blue selection)
  selectionColor: Color(0x332F81F7),
  inactiveSelectionColor: Color(0x1A8B949E),
  // GitHub dark accent.fg (blue cursor)
  cursorColor: Color(0xFF2F81F7),
  cursorWidth: 1.2,
  cursorBlinkRate: 1200,
  // Active line - subtle but visible highlight
  activeLineColor: Color(0x188B949E),
  activeLineGutterColor: Color(0x188B949E),
  // Subtle gutter background
  gutterBackgroundColor: Color(0xFF161B22),
  gutterBorderColor: Color(0xFF30363D),
  // Muted foreground for gutter text
  gutterTextColor: Color(0xFF8B949E),
  // GitHub dark canvas.subtle
  panelBackgroundColor: Color(0xFF161B22),
  panelBorderColor: Color(0xFF30363D),
  // GitHub dark canvas.overlay
  tooltipBackgroundColor: Color(0xFF161B22),
  tooltipTextColor: Color(0xFFE6EDF3),
  tooltipBorderRadius: BorderRadius.all(Radius.circular(6)),
  // GitHub dark danger.fg
  specialCharColor: Color(0xFFFF7B72),
  trailingSpaceColor: Color(0x40FF7B72),
);

// ============================================================================
// Theme Facet
// ============================================================================

/// Facet for the editor theme data.
///
/// Use `editorTheme.of(myTheme)` to provide a custom theme.
final Facet<EditorThemeData, EditorThemeData> editorTheme = Facet.define(
  FacetConfig(
    combine: (themes) {
      if (themes.isEmpty) return lightEditorTheme;
      // Merge all themes, later ones override earlier ones
      var result = lightEditorTheme;
      for (final t in themes) {
        result = result.merge(t);
      }
      return result;
    },
  ),
);

// ============================================================================
// Helper Functions
// ============================================================================

/// Get the effective theme for an editor state.
///
/// This considers the [darkTheme] facet to choose between light and dark
/// base themes, then merges any custom theme data on top.
EditorThemeData getEditorTheme(EditorState state) {
  final isDark = state.facet(darkTheme);
  final baseTheme = isDark ? darkEditorTheme : lightEditorTheme;
  final customTheme = state.facet(editorTheme);
  return baseTheme.merge(customTheme);
}

/// Create an extension that sets the editor to dark mode.
Extension enableDarkTheme([bool enabled = true]) {
  return darkTheme.of(enabled);
}

/// Create an extension with custom theme data.
Extension customTheme(EditorThemeData themeData) {
  return editorTheme.of(themeData);
}

// ============================================================================
// InheritedWidget for Theme Access
// ============================================================================

/// Widget that provides editor theme data to descendants.
///
/// This is similar to Flutter's [Theme] widget but specific to the editor.
class EditorTheme extends InheritedWidget {
  /// The theme data.
  final EditorThemeData data;

  const EditorTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// Get the nearest [EditorThemeData] from the widget tree.
  ///
  /// Returns `null` if no [EditorTheme] is found.
  static EditorThemeData? maybeOf(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<EditorTheme>();
    return widget?.data;
  }

  /// Get the nearest [EditorThemeData] from the widget tree.
  ///
  /// Throws if no [EditorTheme] is found.
  static EditorThemeData of(BuildContext context) {
    final data = maybeOf(context);
    assert(data != null, 'No EditorTheme found in context');
    return data!;
  }

  @override
  bool updateShouldNotify(EditorTheme oldWidget) {
    return data != oldWidget.data;
  }
}
