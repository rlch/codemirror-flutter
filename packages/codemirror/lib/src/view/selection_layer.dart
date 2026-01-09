/// Selection rendering layer.
///
/// This module provides Flutter-native selection and cursor rendering using
/// CustomPainter. It replaces the browser's native selection with custom
/// rendering that supports multiple cursors and selection ranges.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart';
import 'bidi.dart';
import 'view_update.dart';

// ============================================================================
// SelectionConfig - Configuration for selection rendering
// ============================================================================

/// Configuration for selection and cursor rendering.
@immutable
class SelectionConfig {
  /// The duration of a full cursor blink cycle in milliseconds.
  ///
  /// Set to 0 to disable blinking. Defaults to 1200ms.
  final int cursorBlinkRate;

  /// Whether to show a cursor for non-empty (range) selections.
  ///
  /// When true, a cursor is drawn at the head of each selection range,
  /// even when there is selected text. Defaults to true.
  final bool drawRangeCursor;

  /// The cursor width in logical pixels.
  final double cursorWidth;

  /// The cursor radius for rounded corners.
  final Radius? cursorRadius;

  /// The color of the primary cursor.
  ///
  /// If null, uses the theme's cursor color.
  final Color? cursorColor;

  /// The color of secondary cursors (in multi-cursor mode).
  ///
  /// If null, uses a dimmed version of the primary cursor color.
  final Color? secondaryCursorColor;

  /// The selection highlight color.
  ///
  /// If null, uses the theme's selection color.
  final Color? selectionColor;

  const SelectionConfig({
    this.cursorBlinkRate = 1200,
    this.drawRangeCursor = true,
    this.cursorWidth = 2.0,
    this.cursorRadius,
    this.cursorColor,
    this.secondaryCursorColor,
    this.selectionColor,
  });

  /// Create a copy with modified values.
  SelectionConfig copyWith({
    int? cursorBlinkRate,
    bool? drawRangeCursor,
    double? cursorWidth,
    Radius? cursorRadius,
    Color? cursorColor,
    Color? secondaryCursorColor,
    Color? selectionColor,
  }) {
    return SelectionConfig(
      cursorBlinkRate: cursorBlinkRate ?? this.cursorBlinkRate,
      drawRangeCursor: drawRangeCursor ?? this.drawRangeCursor,
      cursorWidth: cursorWidth ?? this.cursorWidth,
      cursorRadius: cursorRadius ?? this.cursorRadius,
      cursorColor: cursorColor ?? this.cursorColor,
      secondaryCursorColor: secondaryCursorColor ?? this.secondaryCursorColor,
      selectionColor: selectionColor ?? this.selectionColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionConfig &&
          cursorBlinkRate == other.cursorBlinkRate &&
          drawRangeCursor == other.drawRangeCursor &&
          cursorWidth == other.cursorWidth &&
          cursorRadius == other.cursorRadius &&
          cursorColor == other.cursorColor &&
          secondaryCursorColor == other.secondaryCursorColor &&
          selectionColor == other.selectionColor;

  @override
  int get hashCode => Object.hash(
        cursorBlinkRate,
        drawRangeCursor,
        cursorWidth,
        cursorRadius,
        cursorColor,
        secondaryCursorColor,
        selectionColor,
      );
}

/// Facet for selection configuration.
final selectionConfig = Facet.define<SelectionConfig, SelectionConfig>(
  FacetConfig(
    combine: (values) {
      if (values.isEmpty) return const SelectionConfig();

      // Combine configs: use minimum blink rate, OR drawRangeCursor
      var blinkRate = values.first.cursorBlinkRate;
      var drawRange = values.first.drawRangeCursor;

      for (final config in values.skip(1)) {
        if (config.cursorBlinkRate > 0) {
          blinkRate = blinkRate == 0
              ? config.cursorBlinkRate
              : (config.cursorBlinkRate < blinkRate
                  ? config.cursorBlinkRate
                  : blinkRate);
        }
        drawRange = drawRange || config.drawRangeCursor;
      }

      return values.first.copyWith(
        cursorBlinkRate: blinkRate,
        drawRangeCursor: drawRange,
      );
    },
  ),
);

/// Get the selection configuration from state.
SelectionConfig getSelectionConfig(EditorState state) {
  return state.facet(selectionConfig);
}

// ============================================================================
// RectangleMarker - A positioned rectangle for selection/cursor
// ============================================================================

/// A marker representing a rectangle at a specific position.
///
/// Used for both cursors (width == null or small) and selection backgrounds.
@immutable
class RectangleMarker {
  /// CSS class name (used for styling context).
  final String className;

  /// Left position in logical pixels (relative to content).
  final double left;

  /// Top position in logical pixels.
  final double top;

  /// Width, or null for line-width.
  final double? width;

  /// Height in logical pixels.
  final double height;

  const RectangleMarker({
    required this.className,
    required this.left,
    required this.top,
    this.width,
    required this.height,
  });

  /// Create markers for a selection range.
  ///
  /// For cursors (empty range), creates a single marker at the cursor position.
  /// For selections, creates rectangles covering the selected text.
  static List<RectangleMarker> forRange({
    required TextPainter textPainter,
    required String className,
    required SelectionRange range,
    required Offset contentOffset,
    double lineHeight = 20.0,
  }) {
    if (range.empty) {
      // Cursor: single marker at head position
      final caretOffset = _getCaretOffset(textPainter, range.head);
      if (caretOffset == null) return [];

      return [
        RectangleMarker(
          className: className,
          left: caretOffset.dx - contentOffset.dx,
          top: caretOffset.dy - contentOffset.dy,
          width: null, // Cursor width determined by painter
          height: lineHeight,
        ),
      ];
    } else {
      // Selection: get boxes for the range
      return _rectanglesForRange(
        textPainter: textPainter,
        className: className,
        range: range,
        contentOffset: contentOffset,
        lineHeight: lineHeight,
      );
    }
  }

  /// Get the caret offset for a position.
  static Offset? _getCaretOffset(TextPainter textPainter, int pos) {
    if (textPainter.text == null) return null;

    try {
      final offset = textPainter.getOffsetForCaret(
        TextPosition(offset: pos),
        Rect.zero,
      );
      return offset;
    } catch (_) {
      return null;
    }
  }

  /// Create rectangles for a non-empty selection range.
  static List<RectangleMarker> _rectanglesForRange({
    required TextPainter textPainter,
    required String className,
    required SelectionRange range,
    required Offset contentOffset,
    required double lineHeight,
  }) {
    final boxes = textPainter.getBoxesForSelection(
      TextSelection(baseOffset: range.from, extentOffset: range.to),
    );

    return boxes.map((box) {
      return RectangleMarker(
        className: className,
        left: box.left - contentOffset.dx,
        top: box.top - contentOffset.dy,
        width: box.right - box.left,
        height: box.bottom - box.top,
      );
    }).toList();
  }

  /// Check if this marker equals another.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RectangleMarker &&
          className == other.className &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(className, left, top, width, height);

  @override
  String toString() =>
      'RectangleMarker($className, $left, $top, ${width ?? 'cursor'}, $height)';
}

// ============================================================================
// SelectionPainter - CustomPainter for selection background
// ============================================================================

/// Paints selection backgrounds.
class SelectionPainter extends CustomPainter {
  /// The markers to paint.
  final List<RectangleMarker> markers;

  /// The selection color.
  final Color color;

  SelectionPainter({
    required this.markers,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (markers.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final marker in markers) {
      final rect = Rect.fromLTWH(
        marker.left,
        marker.top,
        marker.width ?? size.width - marker.left,
        marker.height,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(SelectionPainter oldDelegate) {
    return markers != oldDelegate.markers || color != oldDelegate.color;
  }
}

// ============================================================================
// CursorPainter - CustomPainter for cursor
// ============================================================================

/// Paints cursors with blinking support.
class CursorPainter extends CustomPainter {
  /// The cursor markers to paint.
  final List<RectangleMarker> markers;

  /// The primary cursor color.
  final Color primaryColor;

  /// The secondary cursor color.
  final Color secondaryColor;

  /// The cursor width.
  final double cursorWidth;

  /// The cursor radius.
  final Radius? cursorRadius;

  /// Whether the cursor is visible (for blinking).
  final bool visible;

  /// Index of the primary cursor.
  final int primaryIndex;

  CursorPainter({
    required this.markers,
    required this.primaryColor,
    required this.secondaryColor,
    required this.cursorWidth,
    this.cursorRadius,
    this.visible = true,
    this.primaryIndex = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || markers.isEmpty) return;

    for (var i = 0; i < markers.length; i++) {
      final marker = markers[i];
      final isPrimary = i == primaryIndex;

      final paint = Paint()
        ..color = isPrimary ? primaryColor : secondaryColor
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(
        marker.left,
        marker.top,
        cursorWidth,
        marker.height,
      );

      if (cursorRadius != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, cursorRadius!),
          paint,
        );
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) {
    return markers != oldDelegate.markers ||
        primaryColor != oldDelegate.primaryColor ||
        secondaryColor != oldDelegate.secondaryColor ||
        cursorWidth != oldDelegate.cursorWidth ||
        cursorRadius != oldDelegate.cursorRadius ||
        visible != oldDelegate.visible ||
        primaryIndex != oldDelegate.primaryIndex;
  }
}

// ============================================================================
// SelectionLayerController - Manages selection layer state
// ============================================================================

/// Controller for the selection layer.
///
/// Manages cursor blinking and selection rendering updates.
class SelectionLayerController extends ChangeNotifier {
  /// Current configuration.
  SelectionConfig _config;

  /// Current selection.
  EditorSelection _selection;

  /// Text direction.
  Direction _textDirection;

  /// Whether the cursor is currently visible.
  bool _cursorVisible = true;

  /// Timer for cursor blinking.
  Timer? _blinkTimer;

  /// Animation name for blink reset (toggles on selection change).
  int _blinkPhase = 0;

  SelectionLayerController({
    SelectionConfig config = const SelectionConfig(),
    required EditorSelection selection,
    Direction textDirection = Direction.ltr,
  })  : _config = config,
        _selection = selection,
        _textDirection = textDirection {
    _startBlinkTimer();
  }

  /// Get the current configuration.
  SelectionConfig get config => _config;

  /// Get the current selection.
  EditorSelection get selection => _selection;

  /// Get the text direction.
  Direction get textDirection => _textDirection;

  /// Whether the cursor should be visible right now.
  bool get cursorVisible => _cursorVisible;

  /// Get the blink phase (for animation reset).
  int get blinkPhase => _blinkPhase;

  /// Update the configuration.
  set config(SelectionConfig value) {
    if (_config != value) {
      final rateChanged = _config.cursorBlinkRate != value.cursorBlinkRate;
      _config = value;
      if (rateChanged) {
        _startBlinkTimer();
      }
      notifyListeners();
    }
  }

  /// Update the selection.
  set selection(EditorSelection value) {
    if (!_selection.eq(value)) {
      _selection = value;
      _resetBlink();
      notifyListeners();
    }
  }

  /// Update the text direction.
  set textDirection(Direction value) {
    if (_textDirection != value) {
      _textDirection = value;
      notifyListeners();
    }
  }

  /// Handle a view update.
  void handleUpdate(ViewUpdate update) {
    // Check if selection changed
    if (update.selectionSet) {
      selection = update.state.selection;
    }

    // Check if config changed
    final newConfig = getSelectionConfig(update.state);
    if (newConfig != _config) {
      config = newConfig;
    }
  }

  /// Reset the blink timer (show cursor immediately).
  void _resetBlink() {
    _cursorVisible = true;
    _blinkPhase = (_blinkPhase + 1) % 2;
    _startBlinkTimer();
  }

  /// Start or restart the blink timer.
  void _startBlinkTimer() {
    _blinkTimer?.cancel();

    if (_config.cursorBlinkRate <= 0) {
      _cursorVisible = true;
      return;
    }

    final halfPeriod = Duration(milliseconds: _config.cursorBlinkRate ~/ 2);

    _blinkTimer = Timer.periodic(halfPeriod, (_) {
      _cursorVisible = !_cursorVisible;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// SelectionLayer - Widget for rendering selection
// ============================================================================

/// A widget that renders the selection layer.
///
/// This should be positioned behind the text content (for selection background)
/// and in front of it (for cursors).
class SelectionLayer extends StatefulWidget {
  /// The editor state.
  final EditorState state;

  /// The text painter used for position calculations.
  final TextPainter textPainter;

  /// Content offset for coordinate translation.
  final Offset contentOffset;

  /// The line height.
  final double lineHeight;

  /// Whether this is the cursor layer (true) or selection layer (false).
  final bool isCursorLayer;

  /// Theme data for colors.
  final ThemeData theme;

  const SelectionLayer({
    super.key,
    required this.state,
    required this.textPainter,
    this.contentOffset = Offset.zero,
    this.lineHeight = 20.0,
    required this.isCursorLayer,
    required this.theme,
  });

  @override
  State<SelectionLayer> createState() => _SelectionLayerState();
}

class _SelectionLayerState extends State<SelectionLayer> {
  late SelectionLayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SelectionLayerController(
      config: getSelectionConfig(widget.state),
      selection: widget.state.selection,
    );
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SelectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.state.selection != oldWidget.state.selection) {
      _controller.selection = widget.state.selection;
    }

    final newConfig = getSelectionConfig(widget.state);
    if (newConfig != _controller.config) {
      _controller.config = newConfig;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final config = _controller.config;
    final selection = _controller.selection;

    if (widget.isCursorLayer) {
      // Build cursor markers
      final cursorMarkers = <RectangleMarker>[];
      var primaryIndex = 0;

      for (var i = 0; i < selection.ranges.length; i++) {
        final range = selection.ranges[i];
        final isPrimary = i == selection.mainIndex;

        // Show cursor if empty or if drawRangeCursor is true
        if (range.empty || config.drawRangeCursor) {
          if (isPrimary) {
            primaryIndex = cursorMarkers.length;
          }

          final cursor = range.empty
              ? range
              : EditorSelection.cursor(
                  range.head,
                  assoc: range.head > range.anchor ? -1 : 1,
                );

          final markers = RectangleMarker.forRange(
            textPainter: widget.textPainter,
            className: isPrimary ? 'cm-cursor cm-cursor-primary' : 'cm-cursor cm-cursor-secondary',
            range: cursor,
            contentOffset: widget.contentOffset,
            lineHeight: widget.lineHeight,
          );

          cursorMarkers.addAll(markers);
        }
      }

      final primaryColor =
          config.cursorColor ?? widget.theme.colorScheme.primary;
      final secondaryColor = config.secondaryCursorColor ??
          primaryColor.withAlpha((primaryColor.a * 0.5).round());

      return CustomPaint(
        painter: CursorPainter(
          markers: cursorMarkers,
          primaryColor: primaryColor,
          secondaryColor: secondaryColor,
          cursorWidth: config.cursorWidth,
          cursorRadius: config.cursorRadius,
          visible: _controller.cursorVisible,
          primaryIndex: primaryIndex,
        ),
        size: Size.infinite,
      );
    } else {
      // Build selection markers
      final selectionMarkers = <RectangleMarker>[];

      for (final range in selection.ranges) {
        if (!range.empty) {
          final markers = RectangleMarker.forRange(
            textPainter: widget.textPainter,
            className: 'cm-selectionBackground',
            range: range,
            contentOffset: widget.contentOffset,
            lineHeight: widget.lineHeight,
          );
          selectionMarkers.addAll(markers);
        }
      }

      final selectionColor = config.selectionColor ??
          widget.theme.colorScheme.primary.withAlpha(77);

      return CustomPaint(
        painter: SelectionPainter(
          markers: selectionMarkers,
          color: selectionColor,
        ),
        size: Size.infinite,
      );
    }
  }
}

// ============================================================================
// Extension Factory
// ============================================================================

/// Extension that enables custom selection rendering.
///
/// This replaces Flutter's default selection with custom rendering that
/// supports:
/// - Multiple cursors
/// - Custom cursor blinking rate
/// - Custom selection colors
/// - Cursor for range selections
///
/// ```dart
/// EditorView(
///   state: EditorState.create(
///     EditorStateConfig(
///       doc: 'Hello, World!',
///       extensions: [
///         drawSelection(
///           const SelectionConfig(
///             cursorBlinkRate: 1000,
///             cursorColor: Colors.blue,
///           ),
///         ),
///       ],
///     ),
///   ),
/// )
/// ```
Extension drawSelection([SelectionConfig config = const SelectionConfig()]) {
  return selectionConfig.of(config);
}

/// Facet that indicates whether native selection should be hidden.
///
/// When true, the editor should hide Flutter's native selection and
/// use the custom selection layer instead.
final nativeSelectionHidden = Facet.define<bool, bool>(
  FacetConfig(
    combine: (values) => values.isNotEmpty && values.any((v) => v),
  ),
);
