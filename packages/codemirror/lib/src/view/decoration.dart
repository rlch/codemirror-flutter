/// Decorations for styling document content.
///
/// This module provides the decoration system for styling text, adding
/// widgets, and modifying line appearance. Decorations are stored in
/// [RangeSet]s and applied during rendering.
library;

import 'package:flutter/widgets.dart' show Widget;
import 'package:meta/meta.dart';

import '../state/change.dart';
import '../state/range_set.dart';

// ============================================================================
// Side Constants - Used for ordering decorations
// ============================================================================

/// Constants for decoration side ordering.
///
/// These values determine how decorations are positioned relative to each
/// other and how they interact with content at their boundaries.
@internal
abstract final class Side {
  /// End of non-inclusive range.
  static const int nonIncEnd = -600000000;

  /// Start of gap decoration.
  static const int gapStart = -500000000;

  /// Block widget before position (+ widget side option).
  static const int blockBefore = -400000000;

  /// Start of inclusive block range.
  static const int blockIncStart = -300000000;

  /// Line decoration.
  static const int line = -200000000;

  /// Inline widget before position (+ widget side).
  static const int inlineBefore = -100000000;

  /// Start of inclusive inline range.
  static const int inlineIncStart = -1;

  /// End of inclusive inline range.
  static const int inlineIncEnd = 1;

  /// Inline widget after position (+ widget side).
  static const int inlineAfter = 100000000;

  /// End of inclusive block range.
  static const int blockIncEnd = 200000000;

  /// Block widget after position (+ widget side).
  static const int blockAfter = 300000000;

  /// End of gap decoration.
  static const int gapEnd = 400000000;

  /// Start of non-inclusive range.
  static const int nonIncStart = 500000000;
}

// ============================================================================
// BlockType - Types of block-level elements
// ============================================================================

/// The different types of blocks that can occur in an editor view.
enum BlockType {
  /// A line of text.
  text,

  /// A block widget associated with the position after it.
  widgetBefore,

  /// A block widget associated with the position before it.
  widgetAfter,

  /// A block widget replacing a range of content.
  widgetRange,
}

// ============================================================================
// Direction - Text direction for BiDi support
// ============================================================================

/// Text direction for bidirectional text support.
enum Direction {
  /// Left-to-right text direction.
  ltr,

  /// Right-to-left text direction.
  rtl,
}

// ============================================================================
// WidgetType - Abstract base for widget decorations
// ============================================================================

/// Base class for widget decorations.
///
/// Widgets added to the content are described by subclasses of this
/// class. Using a description object like this makes it possible to
/// delay creating of the widget until it is needed, and to avoid
/// redrawing widgets even if the decorations that define them are
/// recreated.
///
/// ## Example
///
/// ```dart
/// class PlaceholderWidget extends WidgetType {
///   final String text;
///
///   PlaceholderWidget(this.text);
///
///   @override
///   Widget toWidget(covariant dynamic view) {
///     return Container(
///       padding: EdgeInsets.symmetric(horizontal: 4),
///       decoration: BoxDecoration(
///         color: Colors.grey.shade200,
///         borderRadius: BorderRadius.circular(4),
///       ),
///       child: Text(text, style: TextStyle(color: Colors.grey)),
///     );
///   }
///
///   @override
///   bool eq(WidgetType other) {
///     return other is PlaceholderWidget && other.text == text;
///   }
/// }
/// ```
abstract class WidgetType {
  const WidgetType();

  /// Build the widget for this decoration.
  ///
  /// The `view` parameter is the EditorViewState that contains this widget.
  Widget toWidget(covariant dynamic view);

  /// Compare this instance to another instance of the same type.
  ///
  /// This is used to avoid redrawing widgets when they are replaced by
  /// a new decoration of the same type. The default implementation just
  /// returns `false`, which will cause new instances of the widget to
  /// always be redrawn.
  bool eq(WidgetType other) => false;

  /// Update an existing widget to reflect this widget's state.
  ///
  /// May return true to indicate the update succeeded, false to indicate
  /// the widget needs to be rebuilt. The default returns false.
  bool updateWidget(Widget widget, covariant dynamic view) => false;

  /// Compare this widget with another for equality.
  ///
  /// Returns true if the widgets are the same instance or if they are
  /// of the same type and [eq] returns true.
  @internal
  bool compare(WidgetType other) {
    return identical(this, other) ||
        (runtimeType == other.runtimeType && eq(other));
  }

  /// The estimated height this widget will have.
  ///
  /// Used when estimating the height of content that hasn't been drawn.
  /// Return -1 to indicate the height is unknown. The default returns -1.
  int get estimatedHeight => -1;

  /// For inline widgets that introduce line breaks, this indicates the
  /// number of line breaks they introduce. Defaults to 0.
  int get lineBreaks => 0;

  /// Whether events inside this widget should be ignored by the editor.
  ///
  /// The default is to ignore all events.
  bool ignoreEvent(dynamic event) => true;

  /// Whether this widget is hidden (takes up no visual space).
  @internal
  bool get isHidden => false;

  /// Whether this widget is editable.
  @internal
  bool get editable => false;

  /// Called when the widget is removed from the view.
  void destroy(Widget widget) {}
}

// ============================================================================
// Decoration Specs - Configuration for creating decorations
// ============================================================================

/// Configuration for creating a mark decoration.
class MarkDecorationSpec {
  /// Whether the mark covers its start and end position.
  ///
  /// This influences whether content inserted at those positions becomes
  /// part of the mark. Defaults to false.
  final bool inclusive;

  /// Whether the start of the mark is inclusive.
  ///
  /// Overrides [inclusive] for the start position when set.
  final bool? inclusiveStart;

  /// Whether the end of the mark is inclusive.
  ///
  /// Overrides [inclusive] for the end position when set.
  final bool? inclusiveEnd;

  /// Attributes to add to the text in the marked range.
  final Map<String, String>? attributes;

  /// CSS class name to add to the marked range.
  ///
  /// Shorthand for `attributes: {'class': value}`.
  final String? className;

  /// Tag name for wrapping element (defaults to 'span').
  final String tagName;

  /// Direction for BiDi isolated ranges.
  final Direction? bidiIsolate;

  /// Additional custom data.
  final Map<String, dynamic>? spec;

  const MarkDecorationSpec({
    this.inclusive = false,
    this.inclusiveStart,
    this.inclusiveEnd,
    this.attributes,
    this.className,
    this.tagName = 'span',
    this.bidiIsolate,
    this.spec,
  });
}

/// Configuration for creating a widget decoration.
class WidgetDecorationSpec {
  /// The widget to display.
  final WidgetType widget;

  /// Which side of the position the widget is on.
  ///
  /// When positive, the widget is drawn after the cursor if the cursor
  /// is on the same position. Otherwise, it's drawn before.
  /// Defaults to 0. Must be between -10000 and 10000.
  final int side;

  /// Whether this widget should be ordered among inline widgets.
  ///
  /// By default, block widgets with positive side are drawn after all
  /// inline widgets, and those with non-positive side before. Setting
  /// this to true causes the widget to be ordered by side value instead.
  final bool inlineOrder;

  /// Whether this is a block widget (drawn between lines).
  ///
  /// When false (the default), the widget is inline and drawn between
  /// the surrounding text.
  final bool block;

  /// Additional custom data.
  final Map<String, dynamic>? spec;

  const WidgetDecorationSpec({
    required this.widget,
    this.side = 0,
    this.inlineOrder = false,
    this.block = false,
    this.spec,
  });
}

/// Configuration for creating a replace decoration.
class ReplaceDecorationSpec {
  /// Optional widget to display in place of the replaced content.
  final WidgetType? widget;

  /// Whether this range covers the positions on its sides.
  ///
  /// This influences whether new content becomes part of the range and
  /// whether the cursor can be drawn on its sides. Defaults to false for
  /// inline replacements, and true for block replacements.
  final bool? inclusive;

  /// Whether the start is inclusive.
  final bool? inclusiveStart;

  /// Whether the end is inclusive.
  final bool? inclusiveEnd;

  /// Whether this is a block-level replacement.
  final bool block;

  /// Additional custom data.
  final Map<String, dynamic>? spec;

  /// Internal flag for gap decorations.
  @internal
  final bool isBlockGap;

  const ReplaceDecorationSpec({
    this.widget,
    this.inclusive,
    this.inclusiveStart,
    this.inclusiveEnd,
    this.block = false,
    this.spec,
    this.isBlockGap = false,
  });
}

/// Configuration for creating a line decoration.
class LineDecorationSpec {
  /// Attributes to add to the line element.
  final Map<String, String>? attributes;

  /// CSS class name to add to the line.
  ///
  /// Shorthand for `attributes: {'class': value}`.
  final String? className;

  /// Additional custom data.
  final Map<String, dynamic>? spec;

  const LineDecorationSpec({
    this.attributes,
    this.className,
    this.spec,
  });
}

// ============================================================================
// Decoration - Base class for all decorations
// ============================================================================

/// A decoration provides information on how to draw or style a piece
/// of content.
///
/// You'll usually use it wrapped in a [Range], which adds a start and
/// end position. Decorations are stored in [RangeSet]s.
///
/// ## Types of Decorations
///
/// - **Mark** - Styles a range of text (bold, color, etc.)
/// - **Widget** - Displays a widget at a position
/// - **Replace** - Replaces content with a widget or hides it
/// - **Line** - Adds attributes to an entire line
///
/// ## Example
///
/// ```dart
/// // Create a mark decoration for highlighting
/// final highlight = Decoration.mark(
///   MarkDecorationSpec(
///     className: 'highlight',
///     attributes: {'style': 'background-color: yellow'},
///   ),
/// );
///
/// // Create a widget decoration
/// final button = Decoration.widget(
///   WidgetDecorationSpec(widget: MyButtonWidget()),
/// );
///
/// // Build a decoration set
/// final decorations = Decoration.set([
///   highlight.range(10, 20),
///   button.range(50),
/// ]);
/// ```
abstract class Decoration extends RangeValue {
  /// The side bias at the start of the range.
  @internal
  final int startSideValue;

  /// The side bias at the end of the range.
  @internal
  final int endSideValue;

  /// The widget for this decoration (if any).
  @internal
  final WidgetType? widget;

  /// The spec object used to create this decoration.
  ///
  /// You can include additional properties in the spec to store
  /// metadata about your decoration.
  final Map<String, dynamic>? spec;

  /// Whether this decoration is a point (zero-length) decoration.
  @internal
  bool get isPoint;

  Decoration._({
    required this.startSideValue,
    required this.endSideValue,
    this.widget,
    this.spec,
  });

  @override
  int get startSide => startSideValue;

  @override
  int get endSide => endSideValue;

  /// Whether this decoration affects height calculations.
  @internal
  bool get heightRelevant => false;

  /// Check if two decorations are equivalent.
  @override
  bool eq(RangeValue other);

  /// Create a mark decoration for styling content in a range.
  ///
  /// Nested mark decorations will cause nested styling. Nesting order
  /// is determined by precedence, with higher-precedence decorations
  /// creating the inner elements.
  static MarkDecoration mark(MarkDecorationSpec spec) {
    return MarkDecoration._(spec);
  }

  /// Create a widget decoration at a position.
  static PointDecoration widgetDecoration(WidgetDecorationSpec spec) {
    final clampedSide = spec.side.clamp(-10000, 10000);
    int side = clampedSide;

    if (spec.block && !spec.inlineOrder) {
      side += clampedSide > 0 ? Side.blockAfter : Side.blockBefore;
    } else {
      side += clampedSide > 0 ? Side.inlineAfter : Side.inlineBefore;
    }

    return PointDecoration._(
      spec: spec.spec,
      startSide: side,
      endSide: side,
      block: spec.block,
      widget: spec.widget,
      isReplace: false,
    );
  }

  /// Create a replace decoration that replaces content with a widget
  /// or hides it entirely.
  static PointDecoration replace(ReplaceDecorationSpec spec) {
    final block = spec.block;
    int startSide;
    int endSide;

    if (spec.isBlockGap) {
      startSide = Side.gapStart;
      endSide = Side.gapEnd;
    } else {
      final inclusive = _getInclusive(
        inclusive: spec.inclusive,
        inclusiveStart: spec.inclusiveStart,
        inclusiveEnd: spec.inclusiveEnd,
        defaultValue: block,
      );

      startSide = (inclusive.start
              ? (block ? Side.blockIncStart : Side.inlineIncStart)
              : Side.nonIncStart) -
          1;
      endSide = (inclusive.end
              ? (block ? Side.blockIncEnd : Side.inlineIncEnd)
              : Side.nonIncEnd) +
          1;
    }

    return PointDecoration._(
      spec: spec.spec,
      startSide: startSide,
      endSide: endSide,
      block: block,
      widget: spec.widget,
      isReplace: true,
    );
  }

  /// Create a line decoration that adds attributes to a line.
  static LineDecoration line(LineDecorationSpec spec) {
    return LineDecoration._(spec);
  }

  /// Build a [DecorationSet] from decorated ranges.
  ///
  /// If the ranges aren't already sorted, pass `sort: true`.
  static DecorationSet createSet(
    List<Range<Decoration>> ranges, {
    bool sort = false,
  }) {
    return RangeSet.of(ranges, sort);
  }

  /// The empty set of decorations.
  static final DecorationSet none = RangeSet.empty<Decoration>();

  /// Whether this decoration has a widget with a known height.
  @internal
  bool hasHeight() {
    return widget != null && widget!.estimatedHeight > -1;
  }
}

/// A decoration set is a collection of decorated ranges.
typedef DecorationSet = RangeSet<Decoration>;

// ============================================================================
// MarkDecoration - For styling ranges of text
// ============================================================================

/// A decoration that styles a range of text.
///
/// Mark decorations add styling to the text content within their range.
/// They can specify CSS classes, inline attributes, and wrapping tags.
class MarkDecoration extends Decoration {
  /// The tag name for the wrapping element.
  final String tagName;

  /// The CSS class name.
  final String className;

  /// Additional attributes.
  final Map<String, String>? attributes;

  MarkDecoration._(MarkDecorationSpec spec)
      : tagName = spec.tagName,
        className = spec.className ?? '',
        attributes = spec.attributes,
        super._(
          startSideValue: _getInclusive(
            inclusive: spec.inclusive,
            inclusiveStart: spec.inclusiveStart,
            inclusiveEnd: spec.inclusiveEnd,
          ).start
              ? Side.inlineIncStart
              : Side.nonIncStart,
          endSideValue: _getInclusive(
            inclusive: spec.inclusive,
            inclusiveStart: spec.inclusiveStart,
            inclusiveEnd: spec.inclusiveEnd,
          ).end
              ? Side.inlineIncEnd
              : Side.nonIncEnd,
          widget: null,
          spec: spec.spec,
        );

  @override
  bool get isPoint => false;

  @override
  bool get point => false;

  @override
  bool eq(RangeValue other) {
    if (identical(this, other)) return true;
    if (other is! MarkDecoration) return false;

    return tagName == other.tagName &&
        (className.isNotEmpty ? className : attributes?['class']) ==
            (other.className.isNotEmpty
                ? other.className
                : other.attributes?['class']) &&
        _attrsEq(attributes, other.attributes, 'class');
  }

  @override
  Range<Decoration> range(int from, [int? to]) {
    final toPos = to ?? from;
    if (from >= toPos) {
      throw RangeError('Mark decorations may not be empty');
    }
    return Range.create(from, toPos, this);
  }
}

// ============================================================================
// LineDecoration - For styling entire lines
// ============================================================================

/// A decoration that adds attributes to an entire line.
///
/// Line decorations affect the line element that wraps the text content.
/// They can only be placed at the start of a line (zero-length range).
class LineDecoration extends Decoration {
  /// The CSS class name.
  final String? className;

  /// Additional attributes.
  final Map<String, String>? attributes;

  LineDecoration._(LineDecorationSpec spec)
      : className = spec.className,
        attributes = spec.attributes,
        super._(
          startSideValue: Side.line,
          endSideValue: Side.line,
          widget: null,
          spec: spec.spec,
        );

  @override
  bool get isPoint => true;

  @override
  bool get point => true;

  @override
  MapMode get mapMode => MapMode.trackBefore;

  @override
  bool eq(RangeValue other) {
    if (other is! LineDecoration) return false;
    return className == other.className &&
        _attrsEq(attributes, other.attributes);
  }

  @override
  Range<Decoration> range(int from, [int? to]) {
    final toPos = to ?? from;
    if (toPos != from) {
      throw RangeError('Line decoration ranges must be zero-length');
    }
    return Range.create(from, toPos, this);
  }
}

// ============================================================================
// PointDecoration - For widgets and replacements
// ============================================================================

/// A decoration that places a widget at a position or replaces content.
///
/// Point decorations are used for:
/// - Widget decorations (inline or block widgets at a position)
/// - Replace decorations (hide or replace a range of content)
class PointDecoration extends Decoration {
  /// Whether this is a block-level decoration.
  final bool block;

  /// Whether this is a replacement decoration.
  final bool isReplace;

  PointDecoration._({
    required int startSide,
    required int endSide,
    required this.block,
    required super.widget,
    required this.isReplace,
    super.spec,
  }) : super._(
          startSideValue: startSide,
          endSideValue: endSide,
        ) {
    // Set mapMode based on block and side
    _mapMode = !block
        ? MapMode.trackDel
        : startSide <= 0
            ? MapMode.trackBefore
            : MapMode.trackAfter;
  }

  late final MapMode _mapMode;

  @override
  MapMode get mapMode => _mapMode;

  @override
  bool get isPoint => true;

  @override
  bool get point => true;

  /// The type of block this decoration represents.
  BlockType get type {
    if (startSideValue != endSideValue) {
      return BlockType.widgetRange;
    }
    return startSideValue <= 0 ? BlockType.widgetBefore : BlockType.widgetAfter;
  }

  @override
  bool get heightRelevant {
    return block ||
        (widget != null &&
            (widget!.estimatedHeight >= 5 || widget!.lineBreaks > 0));
  }

  @override
  bool eq(RangeValue other) {
    if (other is! PointDecoration) return false;
    return _widgetsEq(widget, other.widget) &&
        block == other.block &&
        startSideValue == other.startSideValue &&
        endSideValue == other.endSideValue;
  }

  @override
  Range<Decoration> range(int from, [int? to]) {
    final toPos = to ?? from;

    if (isReplace) {
      if (from > toPos ||
          (from == toPos && startSideValue > 0 && endSideValue <= 0)) {
        throw RangeError('Invalid range for replacement decoration');
      }
    } else {
      if (toPos != from) {
        throw RangeError('Widget decorations can only have zero-length ranges');
      }
    }

    return Range.create(from, toPos, this);
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get inclusive start/end from a spec.
({bool start, bool end}) _getInclusive({
  bool? inclusive,
  bool? inclusiveStart,
  bool? inclusiveEnd,
  bool defaultValue = false,
}) {
  final start = inclusiveStart ?? inclusive ?? defaultValue;
  final end = inclusiveEnd ?? inclusive ?? defaultValue;
  return (start: start, end: end);
}

/// Compare two widgets for equality.
bool _widgetsEq(WidgetType? a, WidgetType? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.compare(b);
}

/// Compare two attribute maps for equality.
bool _attrsEq(Map<String, String>? a, Map<String, String>? b,
    [String? ignore]) {
  if (identical(a, b)) return true;
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;

  // Get keys, excluding the ignored key
  final aKeys =
      ignore != null ? a.keys.where((k) => k != ignore).toList() : a.keys;
  final bKeys =
      ignore != null ? b.keys.where((k) => k != ignore).toList() : b.keys;

  if (aKeys.length != bKeys.length) return false;

  for (final key in aKeys) {
    if (a[key] != b[key]) return false;
  }

  return true;
}

/// Add a range to a list of ranges, merging overlapping ones.
void addRange(int from, int to, List<int> ranges, [int margin = 0]) {
  final last = ranges.length - 1;
  if (last >= 0 && ranges[last] + margin >= from) {
    ranges[last] = ranges[last] > to ? ranges[last] : to;
  } else {
    ranges.add(from);
    ranges.add(to);
  }
}
