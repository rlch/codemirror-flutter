/// Gutter system for displaying line numbers and markers.
///
/// This module provides infrastructure for rendering gutters alongside
/// the editor content, including line numbers, breakpoint markers,
/// fold indicators, and custom markers.
library;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../state/change.dart' show MapMode;
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/state.dart';
import 'block_info.dart' as bi;
import 'decoration.dart';
import 'theme.dart' show getEditorTheme;
import 'view_update.dart';

// ============================================================================
// GutterMarker
// ============================================================================

/// A gutter marker represents a bit of information attached to a line
/// in a specific gutter.
///
/// Custom markers should extend this class.
abstract class GutterMarker extends RangeValue {
  /// Create a gutter marker.
  GutterMarker();

  /// Compare this marker to another marker of the same type.
  ///
  /// Used to determine if markers are equivalent for rendering optimization.
  bool markerEq(GutterMarker other) => false;

  /// Internal comparison that checks both identity and [markerEq].
  @internal
  bool compare(GutterMarker other) {
    return this == other ||
        (runtimeType == other.runtimeType && markerEq(other));
  }

  /// Build the widget for this marker.
  ///
  /// Return `null` if this marker has no visual representation.
  Widget? toWidget(BuildContext context);

  /// CSS class name to add to the gutter element containing this marker.
  ///
  /// This is primarily for compatibility with the TypeScript version's
  /// CSS-based styling. In Flutter, you may want to use [toWidget] instead.
  String get elementClass => '';

  /// Called when the marker's widget representation is removed from the gutter.
  void destroy() {}

  @override
  MapMode get mapMode => MapMode.trackBefore;

  @override
  int get startSide => -1;

  @override
  int get endSide => -1;

  @override
  bool get point => true;
}

// ============================================================================
// Gutter Line Class Facet
// ============================================================================

/// Facet used to add a class to all gutter elements for a given line.
///
/// Markers given to this facet should _only_ define an [elementClass],
/// not a [toWidget] method (or the marker will appear in all gutters
/// for the line).
final Facet<RangeSet<GutterMarker>, List<RangeSet<GutterMarker>>>
    gutterLineClass = Facet.define();

/// Facet used to add a class to all gutter elements next to a widget.
///
/// Should not provide widgets with a [toWidget] method.
final Facet<
        GutterMarker? Function(
            EditorState state, WidgetType widget, bi.BlockInfo block),
        List<
            GutterMarker? Function(
                EditorState state, WidgetType widget, bi.BlockInfo block)>>
    gutterWidgetClass = Facet.define();

// ============================================================================
// Event Handlers Type
// ============================================================================

/// Type for gutter event handlers.
///
/// Returns `true` if the event was handled and should not propagate.
typedef GutterEventHandler = bool Function(
  BuildContext context,
  bi.BlockInfo line,
  Offset localPosition,
);

/// Map of event types to handlers.
typedef GutterEventHandlers = Map<String, GutterEventHandler>;

// ============================================================================
// GutterConfig
// ============================================================================

/// Configuration options for a gutter.
class GutterConfig {
  /// An extra CSS class to be added to the wrapper element.
  ///
  /// In Flutter, this is used as a semantic label or for testing.
  final String? className;

  /// Controls whether empty gutter elements should be rendered.
  ///
  /// Defaults to false.
  final bool renderEmptyElements;

  /// Retrieve a set of markers to use in this gutter.
  ///
  /// Can return a single [RangeSet] or a list of them.
  final Object Function(EditorState state)? markers;

  /// Can be used to optionally add a single marker to every line.
  final GutterMarker? Function(
    EditorState state,
    bi.BlockInfo line,
    List<GutterMarker> otherMarkers,
  )? lineMarker;

  /// Associate markers with block widgets in the document.
  final GutterMarker? Function(
    EditorState state,
    WidgetType widget,
    bi.BlockInfo block,
  )? widgetMarker;

  /// If line or widget markers depend on additional state, and should be
  /// updated when that changes, pass a predicate here that checks whether
  /// a given view update might change the line markers.
  final bool Function(ViewUpdate update)? lineMarkerChange;

  /// Add a hidden spacer element that gives the gutter its base width.
  final GutterMarker? Function(EditorState state)? initialSpacer;

  /// Update the spacer element when the view is updated.
  final GutterMarker? Function(GutterMarker spacer, ViewUpdate update)?
      updateSpacer;

  /// Supply event handlers for tap events on this gutter.
  final GutterEventHandlers eventHandlers;

  /// By default, gutters are shown before the editor content (to the left
  /// in a left-to-right layout). Set this to `after` to show on the other side.
  final GutterSide side;

  const GutterConfig({
    this.className,
    this.renderEmptyElements = false,
    this.markers,
    this.lineMarker,
    this.widgetMarker,
    this.lineMarkerChange,
    this.initialSpacer,
    this.updateSpacer,
    this.eventHandlers = const {},
    this.side = GutterSide.before,
  });
}

/// Which side of the content the gutter appears on.
enum GutterSide {
  /// Before the content (left in LTR, right in RTL).
  before,

  /// After the content (right in LTR, left in RTL).
  after,
}

// ============================================================================
// Gutter Facet
// ============================================================================

/// Internal resolved gutter configuration.
@internal
class ResolvedGutterConfig {
  final String className;
  final bool renderEmptyElements;
  /// Returns either a single RangeSet or List<RangeSet<GutterMarker>>.
  final Object Function(EditorState state) markers;
  final GutterMarker? Function(
    EditorState state,
    bi.BlockInfo line,
    List<GutterMarker> otherMarkers,
  ) lineMarker;
  final GutterMarker? Function(
    EditorState state,
    WidgetType widget,
    bi.BlockInfo block,
  ) widgetMarker;
  final bool Function(ViewUpdate update)? lineMarkerChange;
  final GutterMarker? Function(EditorState state)? initialSpacer;
  final GutterMarker? Function(GutterMarker spacer, ViewUpdate update)?
      updateSpacer;
  final GutterEventHandlers eventHandlers;
  final GutterSide side;

  const ResolvedGutterConfig({
    required this.className,
    required this.renderEmptyElements,
    required this.markers,
    required this.lineMarker,
    required this.widgetMarker,
    this.lineMarkerChange,
    this.initialSpacer,
    this.updateSpacer,
    required this.eventHandlers,
    required this.side,
  });
}

/// Convert markers result to a list of RangeSets.
List<RangeSet<GutterMarker>> _asArray(Object val) {
  if (val is List<RangeSet<GutterMarker>>) return val;
  if (val is RangeSet<GutterMarker>) return [val];
  return [];
}

/// Default configuration values.
ResolvedGutterConfig _resolveConfig(GutterConfig config) {
  return ResolvedGutterConfig(
    className: config.className ?? '',
    renderEmptyElements: config.renderEmptyElements,
    markers: config.markers ?? (_) => RangeSet.empty<GutterMarker>(),
    lineMarker: config.lineMarker ?? (_, __, ___) => null,
    widgetMarker: config.widgetMarker ?? (_, __, ___) => null,
    lineMarkerChange: config.lineMarkerChange,
    initialSpacer: config.initialSpacer,
    updateSpacer: config.updateSpacer,
    eventHandlers: config.eventHandlers,
    side: config.side,
  );
}

/// Facet for active gutters.
final Facet<ResolvedGutterConfig, List<ResolvedGutterConfig>> activeGutters =
    Facet.define();

// ============================================================================
// Scroll Margins for Gutters
// ============================================================================

/// Scroll margins record for gutter offsets.
class GutterScrollMargins {
  final double left;
  final double right;
  final double top;
  final double bottom;

  const GutterScrollMargins({
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.bottom = 0,
  });

  GutterScrollMargins copyWith({
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    return GutterScrollMargins(
      left: left ?? this.left,
      right: right ?? this.right,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
    );
  }
}

/// Facet for providing scroll margins from various sources.
///
/// Functions receive gutter width info and return margin contributions.
final Facet<GutterScrollMargins? Function(GutterWidthInfo info),
        List<GutterScrollMargins? Function(GutterWidthInfo info)>>
    gutterScrollMargins = Facet.define();

/// Information about gutter widths for scroll margin calculation.
class GutterWidthInfo {
  /// Width of gutters before the content (left in LTR).
  final double beforeWidth;

  /// Width of gutters after the content (right in LTR).
  final double afterWidth;

  /// Whether gutters are fixed (sticky).
  final bool fixed;

  /// Text direction (affects which side "before" means).
  final Direction textDirection;

  const GutterWidthInfo({
    required this.beforeWidth,
    required this.afterWidth,
    required this.fixed,
    required this.textDirection,
  });
}

/// Calculate combined scroll margins from all gutter sources.
GutterScrollMargins getGutterScrollMargins(
  EditorState state,
  GutterWidthInfo info,
) {
  var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0;

  for (final source in state.facet(gutterScrollMargins)) {
    final m = source(info);
    if (m != null) {
      if (m.left > left) left = m.left;
      if (m.right > right) right = m.right;
      if (m.top > top) top = m.top;
      if (m.bottom > bottom) bottom = m.bottom;
    }
  }

  // Add gutter widths based on text direction if fixed
  if (info.fixed) {
    if (info.textDirection == Direction.ltr) {
      left += info.beforeWidth;
      right += info.afterWidth;
    } else {
      right += info.beforeWidth;
      left += info.afterWidth;
    }
  }

  return GutterScrollMargins(left: left, right: right, top: top, bottom: bottom);
}

/// Define an editor gutter.
///
/// The order in which gutters appear is determined by their extension priority.
Extension gutter(GutterConfig config) {
  return ExtensionList([
    gutters(),
    activeGutters.of(_resolveConfig(config)),
  ]);
}

// ============================================================================
// Gutters Extension
// ============================================================================

/// Facet to control whether gutters should be fixed (sticky) or scroll.
final Facet<bool, bool> _unfixGutters = Facet.define(
  FacetConfig(combine: (values) => values.any((x) => x)),
);

/// Internal marker facet to indicate gutters are enabled.
final Facet<bool, bool> _guttersEnabled = Facet.define(
  FacetConfig(combine: (values) => values.any((v) => v)),
);

/// The gutter-drawing extension is automatically enabled when you add a
/// gutter, but you can use this function to explicitly configure it.
///
/// Unless `fixed` is explicitly set to `false`, the gutters are fixed,
/// meaning they don't scroll along with the content horizontally.
Extension gutters({bool fixed = true}) {
  final extensions = <Extension>[
    _guttersEnabled.of(true),
  ];
  if (!fixed) {
    extensions.add(_unfixGutters.of(true));
  }
  return ExtensionList(extensions);
}

// ============================================================================
// Line Number Gutter
// ============================================================================

/// Configuration for the line number gutter.
class LineNumberConfig {
  /// How to display line numbers.
  ///
  /// Defaults to simply converting them to string.
  final String Function(int lineNo, EditorState state)? formatNumber;

  /// Supply event handlers for tap events on line numbers.
  final GutterEventHandlers eventHandlers;

  const LineNumberConfig({
    this.formatNumber,
    this.eventHandlers = const {},
  });
}

/// Facet for line number configuration.
final Facet<LineNumberConfig, LineNumberConfig> _lineNumberConfig =
    Facet.define(
  FacetConfig(
    combine: (values) {
      if (values.isEmpty) return const LineNumberConfig();

      // Combine event handlers
      final handlers = <String, GutterEventHandler>{};
      for (final config in values) {
        for (final entry in config.eventHandlers.entries) {
          final existing = handlers[entry.key];
          if (existing != null) {
            handlers[entry.key] = (ctx, line, pos) =>
                existing(ctx, line, pos) || entry.value(ctx, line, pos);
          } else {
            handlers[entry.key] = entry.value;
          }
        }
      }

      return LineNumberConfig(
        formatNumber: values.first.formatNumber,
        eventHandlers: handlers,
      );
    },
  ),
);

/// Facet used to provide markers to the line number gutter.
final Facet<RangeSet<GutterMarker>, List<RangeSet<GutterMarker>>>
    lineNumberMarkers = Facet.define();

/// Facet used to create markers in the line number gutter next to widgets.
final Facet<
        GutterMarker? Function(
            EditorState state, WidgetType widget, bi.BlockInfo block),
        List<
            GutterMarker? Function(
                EditorState state, WidgetType widget, bi.BlockInfo block)>>
    lineNumberWidgetMarker = Facet.define();

/// A marker that displays a line number.
class NumberMarker extends GutterMarker {
  /// The formatted number string.
  final String number;
  
  /// The text style for the line number (from theme).
  final TextStyle? style;

  NumberMarker(this.number, {this.style});

  @override
  bool markerEq(GutterMarker other) =>
      other is NumberMarker && number == other.number;

  /// Fixed line height matching EditorViewState.fixedLineHeight
  static const double _lineHeight = 20.0;
  
  @override
  Widget? toWidget(BuildContext context) {
    final effectiveStyle = style ?? const TextStyle(
      fontFamily: 'JetBrainsMono',
      package: 'codemirror',
      fontSize: 14,
      height: _lineHeight / 14,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
    );
    
    return Text(
      number,
      style: effectiveStyle.copyWith(
        height: _lineHeight / (effectiveStyle.fontSize ?? 14),
      ),
      strutStyle: StrutStyle(
        fontFamily: effectiveStyle.fontFamily ?? 'JetBrainsMono',
        package: effectiveStyle.fontFamily == null ? 'codemirror' : null,
        fontSize: effectiveStyle.fontSize ?? 14,
        height: _lineHeight / (effectiveStyle.fontSize ?? 14),
        forceStrutHeight: true,
      ),
    );
  }
}

/// Format a line number using the configured formatter.
String _formatNumber(EditorState state, int number) {
  final config = state.facet(_lineNumberConfig);
  if (config.formatNumber != null) {
    return config.formatNumber!(number, state);
  }
  return number.toString();
}

/// Calculate the maximum line number for width estimation.
int _maxLineNumber(int lines) {
  var last = 9;
  while (last < lines) {
    last = last * 10 + 9;
  }
  return last;
}

/// Create a line number gutter extension.
Extension lineNumbers([LineNumberConfig config = const LineNumberConfig()]) {
  return ExtensionList([
    _lineNumberConfig.of(config),
    gutters(),
    activeGutters.compute(
      [_lineNumberConfig],
      (facetState) {
        final state = facetState as EditorState;
        
        return ResolvedGutterConfig(
          className: 'cm-lineNumbers',
          renderEmptyElements: false,
          markers: (state) {
            final markerSets = state.facet(lineNumberMarkers);
            return markerSets.isEmpty
                ? RangeSet.empty()
                : RangeSet.join(markerSets);
          },
          lineMarker: (state, line, others) {
            // If there's already a NumberMarker (e.g. custom line number), don't add
            if (others.any((m) => m is NumberMarker)) return null;
            final lineNum = state.doc.lineAt(line.from).number;
            // Get style from theme for this state
            final currentTheme = getEditorTheme(state);
            return NumberMarker(
              _formatNumber(state, lineNum),
              style: currentTheme.lineNumberStyle,
            );
          },
          widgetMarker: (state, widget, block) {
            for (final m in state.facet(lineNumberWidgetMarker)) {
              final result = m(state, widget, block);
              if (result != null) return result;
            }
            return null;
          },
          lineMarkerChange: (update) =>
              update.startState.facet(_lineNumberConfig) !=
              update.state.facet(_lineNumberConfig),
          initialSpacer: (state) {
            final currentTheme = getEditorTheme(state);
            return NumberMarker(
              _formatNumber(state, _maxLineNumber(state.doc.lines)),
              style: currentTheme.lineNumberStyle,
            );
          },
          updateSpacer: (spacer, update) {
            final max = _formatNumber(
              update.state,
              _maxLineNumber(update.state.doc.lines),
            );
            final currentTheme = getEditorTheme(update.state);
            return max == (spacer as NumberMarker).number
                ? spacer
                : NumberMarker(max, style: currentTheme.lineNumberStyle);
          },
          eventHandlers: state.facet(_lineNumberConfig).eventHandlers,
          side: GutterSide.before,
        );
      },
    ),
  ]);
}

// ============================================================================
// Active Line Gutter
// ============================================================================

/// Marker for the active line in the gutter.
class _ActiveLineGutterMarker extends GutterMarker {
  _ActiveLineGutterMarker();

  @override
  String get elementClass => 'cm-activeLineGutter';

  @override
  Widget? toWidget(BuildContext context) => null;
}

/// The singleton active line gutter marker.
final _activeLineGutterMarker = _ActiveLineGutterMarker();

/// Returns an extension that adds a `cm-activeLineGutter` class to
/// all gutter elements on the active line (line with cursor).
Extension highlightActiveLineGutter() {
  return gutterLineClass.compute(
    [selectionSlot],
    (facetState) {
      final state = facetState as EditorState;
      final marks = <Range<GutterMarker>>[];
      var last = -1;
      for (final range in state.selection.ranges) {
        final linePos = state.doc.lineAt(range.head).from;
        if (linePos > last) {
          last = linePos;
          marks.add(Range.create(linePos, linePos, _activeLineGutterMarker));
        }
      }
      return RangeSet.of<GutterMarker>(marks);
    },
  );
}

// ============================================================================
// Gutter View Widget
// ============================================================================

/// Advance a cursor through markers, collecting those at position [pos].
void _advanceCursor(
  RangeCursor<GutterMarker> cursor,
  List<GutterMarker> collect,
  int pos,
) {
  while (cursor.value != null && cursor.from <= pos) {
    if (cursor.from == pos) collect.add(cursor.value!);
    cursor.next();
  }
}

/// Represents a single gutter element with positioning info.
class _GutterElementData {
  final double height;
  final double above;
  final List<GutterMarker> markers;
  final bi.BlockInfo block;

  _GutterElementData({
    required this.height,
    required this.above,
    required this.markers,
    required this.block,
  });
}

/// Widget that renders a single gutter.
class GutterView extends StatelessWidget {
  /// The gutter configuration.
  final ResolvedGutterConfig config;

  /// The editor state.
  final EditorState state;

  /// The visible line blocks.
  final List<bi.BlockInfo> lineBlocks;

  /// Height of the content.
  final double contentHeight;

  /// Document top padding offset.
  final double documentPaddingTop;

  const GutterView({
    super.key,
    required this.config,
    required this.state,
    required this.lineBlocks,
    required this.contentHeight,
    this.documentPaddingTop = 0,
  });

  @override
  Widget build(BuildContext context) {
    final elements = _buildElements(context);
    
    // Build spacer widget if configured (hidden, establishes minimum width)
    Widget? spacerWidget;
    if (config.initialSpacer != null) {
      final spacer = config.initialSpacer!(state);
      if (spacer != null) {
        spacerWidget = Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: spacer.toWidget(context) ?? const SizedBox.shrink(),
        );
      }
    }
    
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final elem in elements) _buildGutterElement(context, elem),
      ],
    );

    // Use a Row to establish minimum width from spacer without affecting 
    // vertical layout. The spacer is wrapped in SizedBox with zero height
    // so it only contributes to width.
    final content = spacerWidget != null
        ? Stack(
            children: [
              // Spacer with zero height - only contributes to width
              SizedBox(
                height: 0,
                child: spacerWidget,
              ),
              column,
            ],
          )
        : column;

    return IntrinsicWidth(
      child: Container(
        color: const Color(0x00000000), // Explicitly transparent
        constraints: BoxConstraints(minHeight: contentHeight),
        child: content,
      ),
    );
  }

  /// Build all gutter elements, handling composite blocks and widgets.
  List<_GutterElementData> _buildElements(BuildContext context) {
    final markerSets = _asArray(config.markers(state));
    final lineClassSets = state.facet(gutterLineClass);

    // Create cursor over joined marker sets
    final markers = markerSets.isEmpty
        ? RangeSet.empty<GutterMarker>()
        : RangeSet.join(markerSets);

    // Create cursor over line class markers
    final lineClasses = lineClassSets.isEmpty
        ? RangeSet.empty<GutterMarker>()
        : RangeSet.join(lineClassSets);

    final cursor = markers.iter(lineBlocks.isEmpty ? 0 : lineBlocks.first.from);
    final lineClassCursor =
        lineClasses.iter(lineBlocks.isEmpty ? 0 : lineBlocks.first.from);

    final elements = <_GutterElementData>[];
    // Track the bottom of the last rendered element for gap calculation
    var lastBottom = -documentPaddingTop;

    for (final line in lineBlocks) {
      final lineType = line.type;

      // Handle composite blocks (line with multiple sub-blocks)
      if (lineType is List<bi.BlockInfo>) {
        var first = true;
        for (final b in lineType) {
          if (b.type == bi.BlockType.text && first) {
            final added = _addLineElement(
                elements, b, cursor, lineClassCursor, lastBottom);
            if (added) lastBottom = b.bottom;
            first = false;
          } else if (b.widget != null) {
            final added = _addWidgetElement(elements, b, lastBottom);
            if (added) lastBottom = b.bottom;
          }
        }
      } else if (lineType == bi.BlockType.text) {
        final added = _addLineElement(
            elements, line, cursor, lineClassCursor, lastBottom);
        if (added) lastBottom = line.bottom;
      } else if (line.widget != null) {
        final added = _addWidgetElement(elements, line, lastBottom);
        if (added) lastBottom = line.bottom;
      }
    }

    return elements;
  }

  /// Add a gutter element for a text line.
  /// Returns true if an element was added.
  bool _addLineElement(
    List<_GutterElementData> elements,
    bi.BlockInfo line,
    RangeCursor<GutterMarker> cursor,
    RangeCursor<GutterMarker> lineClassCursor,
    double lastBottom,
  ) {
    final localMarkers = <GutterMarker>[];

    // Collect markers at this position
    _advanceCursor(cursor, localMarkers, line.from);

    // Collect line class markers
    final classMarkers = <GutterMarker>[];
    _advanceCursor(lineClassCursor, classMarkers, line.from);

    // Combine with class markers
    if (classMarkers.isNotEmpty) {
      localMarkers.addAll(classMarkers);
    }

    // Add line marker from config
    final forLine = config.lineMarker(state, line, localMarkers);
    if (forLine != null) {
      localMarkers.insert(0, forLine);
    }

    // If no markers and not rendering empty elements, still add a spacer
    // to maintain proper vertical alignment
    final above = line.top - lastBottom;
    if (localMarkers.isEmpty && !config.renderEmptyElements) {
      // Add empty element to maintain spacing
      elements.add(_GutterElementData(
        height: line.height,
        above: above > 0 ? above : 0,
        markers: const [],
        block: line,
      ));
      return true;
    }

    elements.add(_GutterElementData(
      height: line.height,
      above: above > 0 ? above : 0,
      markers: localMarkers,
      block: line,
    ));
    return true;
  }

  /// Add a gutter element for a widget block.
  /// Returns true if an element was added.
  bool _addWidgetElement(
    List<_GutterElementData> elements,
    bi.BlockInfo block,
    double lastBottom,
  ) {
    final widget = block.widget;
    if (widget == null) return false;

    // Get markers from config's widgetMarker
    final marker = config.widgetMarker(
      state,
      widget is WidgetType ? widget : _PlaceholderWidget(),
      block,
    );

    // Also check gutterWidgetClass facet
    final widgetClassFuncs = state.facet(gutterWidgetClass);
    final markers = marker != null ? [marker] : <GutterMarker>[];

    for (final fn in widgetClassFuncs) {
      final m = fn(
        state,
        widget is WidgetType ? widget : _PlaceholderWidget(),
        block,
      );
      if (m != null) markers.add(m);
    }

    if (markers.isEmpty) return false;

    final above = block.top - lastBottom;
    elements.add(_GutterElementData(
      height: block.height,
      above: above > 0 ? above : 0,
      markers: markers,
      block: block,
    ));
    return true;
  }

  Widget _buildGutterElement(BuildContext context, _GutterElementData elem) {
    // Build the element class string
    final classes = <String>['cm-gutterElement'];
    for (final marker in elem.markers) {
      final cls = marker.elementClass;
      if (cls.isNotEmpty) {
        classes.add(cls);
      }
    }

    // Build marker widgets
    final widgets = <Widget>[];
    for (final marker in elem.markers) {
      final widget = marker.toWidget(context);
      if (widget != null) widgets.add(widget);
    }

    final child = widgets.isEmpty
        ? null
        : widgets.length == 1
            ? widgets.first
            : Row(mainAxisSize: MainAxisSize.min, children: widgets);

    // Use the actual line height from the block (supports soft-wrapped lines)
    // Note: Don't paint active line color here - let ActiveLineBackground show through
    // For wrapped lines, align to top-right so number sits at the first visual line
    const singleLineHeight = 20.0;
    Widget element = SizedBox(
      height: elem.height,
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          height: singleLineHeight,
          child: Align(
            alignment: Alignment.centerRight,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    // Add event handlers
    if (config.eventHandlers.isNotEmpty) {
      element = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: config.eventHandlers['click'] != null
            ? () => config.eventHandlers['click']!(context, elem.block, Offset.zero)
            : null,
        child: element,
      );
    }

    return element;
  }
}

/// Placeholder widget type for non-WidgetType widgets.
class _PlaceholderWidget extends WidgetType {
  @override
  Widget toWidget(dynamic view) => const SizedBox.shrink();
}

/// Widget that renders all gutters.
class GuttersView extends StatelessWidget {
  /// The editor state.
  final EditorState state;

  /// The visible line blocks.
  final List<bi.BlockInfo> lineBlocks;

  /// Height of the content.
  final double contentHeight;

  /// Whether gutters are fixed (sticky).
  final bool fixed;

  const GuttersView({
    super.key,
    required this.state,
    required this.lineBlocks,
    required this.contentHeight,
    this.fixed = true,
  });

  @override
  Widget build(BuildContext context) {
    final configs = state.facet(activeGutters);
    if (configs.isEmpty) return const SizedBox.shrink();

    final beforeGutters =
        configs.where((c) => c.side == GutterSide.before).toList();
    final afterGutters =
        configs.where((c) => c.side == GutterSide.after).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (beforeGutters.isNotEmpty)
          _buildGutterContainer(context, beforeGutters, 'before'),
        Expanded(child: Container()), // Placeholder for content
        if (afterGutters.isNotEmpty)
          _buildGutterContainer(context, afterGutters, 'after'),
      ],
    );
  }

  Widget _buildGutterContainer(
    BuildContext context,
    List<ResolvedGutterConfig> configs,
    String position,
  ) {
    return Container(
      decoration: BoxDecoration(
        // Border on the content-facing side
        border: Border(
          left: position == 'after'
              ? const BorderSide(color: Color(0xFFDDDDDD))
              : BorderSide.none,
          right: position == 'before'
              ? const BorderSide(color: Color(0xFFDDDDDD))
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final config in configs)
            GutterView(
              config: config,
              state: state,
              lineBlocks: lineBlocks,
              contentHeight: contentHeight,
            ),
        ],
      ),
    );
  }
}
