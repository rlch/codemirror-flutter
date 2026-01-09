/// Placeholder extension for the editor.
///
/// This module provides [placeholder], an extension that shows placeholder
/// text when the editor is empty.
library;

import 'package:flutter/widgets.dart' show Container, Text, TextStyle, Widget, Color;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import 'decoration.dart';
import 'editor_view.dart';
import 'view_plugin.dart';
import 'view_update.dart';

// ============================================================================
// PlaceholderWidget - Widget type for placeholder content
// ============================================================================

const _placeholderColor = Color(0xFF888888);

/// Widget type that renders placeholder text.
class _PlaceholderWidget extends WidgetType {
  /// The placeholder content - either a string or a widget builder.
  final Object content;

  const _PlaceholderWidget(this.content);

  @override
  Widget toWidget(covariant EditorViewState view) {
    if (content is String) {
      return Container(
        child: Text(
          content as String,
          style: const TextStyle(
            color: _placeholderColor,
          ),
        ),
      );
    } else if (content is Widget Function(EditorViewState)) {
      return (content as Widget Function(EditorViewState))(view);
    } else if (content is Widget) {
      return content as Widget;
    }
    return const Text('');
  }

  @override
  bool eq(WidgetType other) {
    return other is _PlaceholderWidget && other.content == content;
  }

  @override
  bool ignoreEvent(dynamic event) => false;
}

// ============================================================================
// PlaceholderPlugin - ViewPlugin for managing placeholder decorations
// ============================================================================

/// Plugin value for the placeholder extension.
class _PlaceholderPluginValue extends PluginValue {
  final EditorViewState _view;
  final RangeSet<Decoration> _placeholder;

  _PlaceholderPluginValue(this._view, Object content)
      : _placeholder = content != ''
            ? Decoration.createSet([
                Decoration.widgetDecoration(WidgetDecorationSpec(
                  widget: _PlaceholderWidget(content),
                  side: 1,
                )).range(0),
              ])
            : Decoration.none;

  RangeSet<Decoration> get decorations {
    return _view.state.doc.length > 0 ? Decoration.none : _placeholder;
  }

  @override
  void update(ViewUpdate update) {
    // Placeholder doesn't need updating - it's either shown or hidden
    // based on document length, which is handled in decorations getter
  }
}

// ============================================================================
// placeholder() - Extension factory
// ============================================================================

/// Extension that enables a placeholder—a piece of example content
/// to show when the editor is empty.
///
/// ## Example
///
/// ```dart
/// EditorState.create(EditorStateConfig(
///   extensions: placeholder('Enter some text...'),
/// ))
/// ```
///
/// The [content] can be:
/// - A [String] that will be displayed as gray placeholder text
/// - A [Widget] that will be cloned and displayed
/// - A function `Widget Function(EditorViewState)` for dynamic content
Extension placeholder(Object content) {
  final plugin = ViewPlugin.define<_PlaceholderPluginValue>(
    (view) => _PlaceholderPluginValue(view, content),
    ViewPluginSpec(
      decorations: (v) => v.decorations,
    ),
  );

  // For string content, also add aria-placeholder attribute
  if (content is String) {
    return ExtensionList([
      plugin.extension,
      contentAttributes.of({'aria-placeholder': content}),
    ]);
  }
  return plugin.extension;
}

/// Facet for content attributes on the editor.
final Facet<Map<String, String>, Map<String, String>> contentAttributes =
    Facet.define(FacetConfig(
  combine: (values) {
    final result = <String, String>{};
    for (final attrs in values) {
      result.addAll(attrs);
    }
    return result;
  },
));
