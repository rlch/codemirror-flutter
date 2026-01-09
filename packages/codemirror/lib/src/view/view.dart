/// View module - Flutter widgets for the code editor.
///
/// This module provides the visual components of the editor including
/// the main [EditorView] widget, viewport management, and view plugins.
library;

export 'attributes.dart';
export 'bidi.dart';
export 'block_info.dart' hide BlockType;
export 'content_view.dart'
    show ContentView, ViewFlag, ChildCursor, ChildPos, ContentBounds, noChildren;
export 'cursor.dart';
export 'decoration.dart' hide Direction; // Contains BlockType, Direction is in bidi.dart
export 'doc_view.dart' show DocView, LineView, TextView, MarkView, WidgetView;
export 'editor_view.dart';
export 'gutter.dart';
export 'height_map.dart' show HeightOracle, MeasuredHeights;
export 'highlighting_controller.dart' show HighlightTheme, HighlightingTextEditingController;
export 'input.dart';
export 'keymap.dart';
export 'panel.dart';
export 'selection_layer.dart';
export 'theme.dart';
export 'tooltip.dart';
export 'tooltip_positioning.dart';
export 'view_plugin.dart';
export 'view_state.dart' show ViewState, EditorRect;
export 'view_update.dart';
export 'viewport.dart';

// Additional view features
export 'active_line.dart';
export 'placeholder.dart';
