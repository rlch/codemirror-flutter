/// Tooltip system for displaying contextual information.
///
/// This module provides infrastructure for showing tooltips at specific
/// positions in the editor, including hover tooltips that appear when
/// the mouse hovers over text.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../state/change.dart' show MapMode;
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' as txn show Transaction;
import '../state/transaction.dart' show TransactionSpec;
import 'view_update.dart';

// ============================================================================
// Tooltip Configuration
// ============================================================================

/// A rectangle representing available space.
class TooltipRect {
  final double top;
  final double left;
  final double bottom;
  final double right;

  const TooltipRect({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// Configuration for the tooltip system.
class TooltipConfig {
  /// The space available for tooltips.
  ///
  /// By default, uses the full viewport.
  final TooltipRect Function(BuildContext context)? tooltipSpace;

  /// Whether to show arrows connecting tooltips to their anchor positions.
  final bool showArrow;

  /// Duration before hover tooltips appear (in milliseconds).
  final int hoverDelay;

  const TooltipConfig({
    this.tooltipSpace,
    this.showArrow = true,
    this.hoverDelay = 300,
  });
}

/// Facet for tooltip configuration.
final Facet<TooltipConfig, TooltipConfig> _tooltipConfig = Facet.define(
  FacetConfig(
    combine: (configs) {
      if (configs.isEmpty) return const TooltipConfig();
      return TooltipConfig(
        tooltipSpace:
            configs.firstWhere((c) => c.tooltipSpace != null,
                    orElse: () => configs.first)
                .tooltipSpace,
        showArrow: configs.first.showArrow,
        hoverDelay: configs.first.hoverDelay,
      );
    },
  ),
);

/// Creates an extension that configures tooltip behavior.
Extension tooltips([TooltipConfig? config]) {
  return config != null
      ? _tooltipConfig.of(config)
      : const _TooltipsMarker();
}

/// Marker extension indicating tooltips are enabled.
class _TooltipsMarker implements Extension {
  const _TooltipsMarker();
}

// ============================================================================
// Tooltip Types
// ============================================================================

/// Describes a tooltip to be shown (e.g., for autocomplete).
///
/// This is an alias for [HoverTooltip] for backward compatibility.
typedef Tooltip = HoverTooltip;

/// Describes a hover tooltip to be shown.
///
/// Named `HoverTooltip` to avoid collision with Flutter's `Tooltip` widget.
class HoverTooltip {
  /// The document position at which to show the tooltip.
  final int pos;

  /// The end of the range annotated by this tooltip, if different from [pos].
  final int? end;

  /// A function that creates the tooltip's widget.
  final TooltipView Function(BuildContext context) create;

  /// Whether the tooltip should be shown above the target position.
  ///
  /// Defaults to false (below).
  final bool above;

  /// Whether the [above] option should be honored when there isn't enough
  /// space on that side. Defaults to false.
  final bool strictSide;

  /// When set to true, show a triangle connecting the tooltip to the position.
  final bool arrow;

  /// By default, tooltips are hidden when their position is outside the
  /// visible editor content. Set this to false to turn that off.
  final bool clip;

  const HoverTooltip({
    required this.pos,
    this.end,
    required this.create,
    this.above = false,
    this.strictSide = false,
    this.arrow = false,
    this.clip = true,
  });

  /// Create a copy with modified values.
  HoverTooltip copyWith({
    int? pos,
    int? end,
    TooltipView Function(BuildContext context)? create,
    bool? above,
    bool? strictSide,
    bool? arrow,
    bool? clip,
  }) {
    return HoverTooltip(
      pos: pos ?? this.pos,
      end: end ?? this.end,
      create: create ?? this.create,
      above: above ?? this.above,
      strictSide: strictSide ?? this.strictSide,
      arrow: arrow ?? this.arrow,
      clip: clip ?? this.clip,
    );
  }
}

/// Describes the visual representation of a tooltip.
class TooltipView {
  /// The widget to display.
  final Widget widget;

  /// Offset adjustment relative to the anchor position.
  final Offset offset;

  /// Whether this tooltip should not be moved when overlapping others.
  final bool overlap;

  /// Callback when the tooltip is first mounted.
  final void Function()? onMount;

  /// Callback when the view updates.
  final void Function(ViewUpdate update)? onUpdate;

  /// Callback when the tooltip is removed.
  final void Function()? onDestroy;

  /// Called when the tooltip has been (re)positioned.
  final void Function(TooltipRect space)? onPositioned;

  /// Whether the tooltip should be resized to fit available space.
  final bool resize;

  const TooltipView({
    required this.widget,
    this.offset = Offset.zero,
    this.overlap = false,
    this.onMount,
    this.onUpdate,
    this.onDestroy,
    this.onPositioned,
    this.resize = true,
  });
}

// ============================================================================
// Tooltip Facet
// ============================================================================

/// Facet to which an extension can add a value to show a tooltip.
final Facet<HoverTooltip?, List<HoverTooltip?>> showTooltip = Facet.define();

/// Facet for hover tooltips (collected separately for merging).
final Facet<List<HoverTooltip>, List<HoverTooltip>> _showHoverTooltip = Facet.define(
  FacetConfig(
    combine: (inputs) => inputs.expand((i) => i).toList(),
  ),
);

// ============================================================================
// Hover Tooltip Source
// ============================================================================

/// The type of function that can be used as a hover tooltip source.
///
/// Called when the mouse hovers over text in the editor.
/// - [pos] is the document position under the pointer
/// - [side] is -1 if the pointer is before the position, 1 if after
///
/// Should return a [HoverTooltip] or list of tooltips to show, or null if none.
typedef HoverTooltipSource = FutureOr<HoverTooltip?> Function(
  EditorState state,
  int pos,
  int side,
);

/// Configuration options for hover tooltips.
class HoverTooltipOptions {
  /// Controls whether a transaction hides the tooltip.
  final bool Function(txn.Transaction tr, HoverTooltip tooltip)? hideOn;

  /// When enabled, close the tooltip whenever the document changes
  /// or the selection is set.
  final bool hideOnChange;

  /// Hover time after which the tooltip should appear (milliseconds).
  final int hoverTime;

  const HoverTooltipOptions({
    this.hideOn,
    this.hideOnChange = false,
    this.hoverTime = 300,
  });
}

/// Internal configuration for a hover tooltip source.
class HoverTooltipConfig {
  final HoverTooltipSource source;
  final StateField<List<HoverTooltip>> field;
  final StateEffectType<List<HoverTooltip>> setHover;
  final int hoverTime;
  final HoverTooltipOptions options;

  const HoverTooltipConfig({
    required this.source,
    required this.field,
    required this.setHover,
    required this.hoverTime,
    required this.options,
  });
}

/// Facet for collecting hover tooltip configurations.
/// 
/// This allows EditorView to find all registered hover tooltip sources.
final Facet<HoverTooltipConfig, List<HoverTooltipConfig>> hoverTooltipFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up a hover tooltip, which shows up when the pointer hovers over
/// ranges of text.
///
/// The [source] callback is called when the mouse hovers over the document
/// text. It should, if there is a tooltip associated with the position,
/// return the tooltip description (either directly or as a Future).
///
/// The [side] argument indicates on which side of the position the pointer
/// is—it will be -1 if the pointer is before the position, 1 if after.
///
/// Returns an extension that can be added to the editor state.
Extension hoverTooltip(
  HoverTooltipSource source, [
  HoverTooltipOptions options = const HoverTooltipOptions(),
]) {
  final setHover = StateEffect.define<List<HoverTooltip>>();

  final hoverState = StateField.define<List<HoverTooltip>>(
    StateFieldConfig(
      create: (_) => [],
      update: (value, transaction) {
        final tr = transaction as txn.Transaction;
        if (value.isNotEmpty) {
          if (options.hideOnChange && (tr.docChanged || tr.selection != null)) {
            value = [];
          } else if (options.hideOn != null) {
            value = value.where((v) => !options.hideOn!(tr, v)).toList();
          }
          if (tr.docChanged) {
            final mapped = <HoverTooltip>[];
            for (final tooltip in value) {
              final newPos = tr.changes.mapPos(tooltip.pos, -1, MapMode.trackDel);
              if (newPos != null) {
                mapped.add(tooltip.copyWith(
                  pos: newPos,
                  end: tooltip.end != null
                      ? tr.changes.mapPos(tooltip.end!)
                      : null,
                ));
              }
            }
            value = mapped;
          }
        }
        for (final effect in tr.effects) {
          if (effect.is_(setHover)) {
            value = effect.value as List<HoverTooltip>;
          }
          if (effect.is_(_closeHoverTooltipsType)) {
            value = [];
          }
        }
        return value;
      },
    ),
  );

  final config = HoverTooltipConfig(
    source: source,
    field: hoverState,
    setHover: setHover,
    hoverTime: options.hoverTime,
    options: options,
  );

  return ExtensionList([
    hoverState,
    hoverTooltipFacet.of(config),
  ]);
}

/// Effect type to close all hover tooltips.
final StateEffectType<void> _closeHoverTooltipsType = StateEffect.define<void>();

/// Transaction effect that closes all hover tooltips.
final StateEffect<void> closeHoverTooltips = _closeHoverTooltipsType.of(null);

// ============================================================================
// Tooltip Helpers
// ============================================================================

/// Get the active tooltip view for a given tooltip, if available.
TooltipView? getTooltip(EditorState state, HoverTooltip tooltip) {
  return null;
}

/// Returns true if any hover tooltips are currently active.
bool hasHoverTooltips(EditorState state) {
  return state.facet(_showHoverTooltip).isNotEmpty;
}

// ============================================================================
// Hover Tooltip Widget
// ============================================================================

/// Widget for displaying hover tooltip content.
///
/// Supports both plain text and markdown content. When [markdown] is true,
/// the content is rendered as markdown using flutter_markdown.
class HoverTooltipWidget extends StatelessWidget {
  /// The content to display.
  final String content;

  /// Whether to render content as markdown.
  /// 
  /// Defaults to true since most hover documentation (from LSP etc) is markdown.
  final bool markdown;

  /// Maximum width of the tooltip.
  final double maxWidth;

  /// Maximum height of the tooltip.
  final double maxHeight;

  const HoverTooltipWidget({
    super.key,
    required this.content,
    this.markdown = true,
    this.maxWidth = 400,
    this.maxHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3),
        border: Border.all(
          color: isDark ? const Color(0xFF454545) : const Color(0xFFCCCCCC),
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: markdown
            ? MarkdownBody(
                data: content,
                styleSheet: _buildMarkdownStyle(context, isDark),
                shrinkWrap: true,
              )
            : SelectableText(
                content,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333),
                  height: 1.4,
                ),
              ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(BuildContext context, bool isDark) {
    final textColor = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333);
    final codeBackground = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8);
    
    return MarkdownStyleSheet(
      p: TextStyle(
        fontFamily: 'system-ui',
        fontSize: 12,
        color: textColor,
        height: 1.4,
      ),
      code: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 11,
        color: textColor,
        backgroundColor: codeBackground,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(3),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      h1: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      h2: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      h3: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      blockSpacing: 8,
      listBullet: TextStyle(color: textColor),
      a: TextStyle(
        color: isDark ? const Color(0xFF569CD6) : const Color(0xFF0066CC),
        decoration: TextDecoration.underline,
      ),
    );
  }
}

/// Creates a simple text hover tooltip.
HoverTooltip createTextTooltip({
  required int pos,
  required String content,
  int? end,
  bool above = false,
}) {
  return HoverTooltip(
    pos: pos,
    end: end,
    above: above,
    create: (_) => TooltipView(
      widget: HoverTooltipWidget(content: content),
    ),
  );
}

/// Creates a markdown hover tooltip.
HoverTooltip createMarkdownTooltip({
  required int pos,
  required String content,
  int? end,
  bool above = false,
}) {
  return HoverTooltip(
    pos: pos,
    end: end,
    above: above,
    create: (_) => TooltipView(
      widget: HoverTooltipWidget(content: content, markdown: true),
    ),
  );
}

// ============================================================================
// Tooltip Widget (base styling)
// ============================================================================

/// Widget that displays a single tooltip.
class HoverTooltipContainer extends StatelessWidget {
  final HoverTooltip tooltip;
  final TooltipView view;
  final bool above;
  final TooltipRect space;

  const HoverTooltipContainer({
    super.key,
    required this.tooltip,
    required this.view,
    required this.above,
    required this.space,
  });

  @override
  Widget build(BuildContext context) {
    return view.widget;
  }
}

// ============================================================================
// Tooltip Container
// ============================================================================

/// Widget that manages and positions tooltips.
class TooltipContainer extends StatefulWidget {
  /// The editor state.
  final EditorState state;

  /// The child widget (editor content).
  final Widget child;

  /// Function to get coordinates for a document position.
  final Offset? Function(int pos) coordsAtPos;

  const TooltipContainer({
    super.key,
    required this.state,
    required this.child,
    required this.coordsAtPos,
  });

  @override
  State<TooltipContainer> createState() => _TooltipContainerState();
}

class _TooltipContainerState extends State<TooltipContainer> {
  final List<_ActiveTooltip> _activeTooltips = [];

  @override
  void didUpdateWidget(TooltipContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTooltips();
  }

  void _updateTooltips() {
    final tooltips = widget.state.facet(showTooltip);
    final activeTooltips = tooltips.whereType<HoverTooltip>().toList();

    // Update existing tooltips, add new ones, remove old ones
    final newActive = <_ActiveTooltip>[];

    for (final tooltip in activeTooltips) {
      final existing = _activeTooltips
          .where((a) => a.tooltip.create == tooltip.create)
          .firstOrNull;

      if (existing != null) {
        newActive.add(existing.copyWith(tooltip: tooltip));
      } else {
        final view = tooltip.create(context);
        newActive.add(_ActiveTooltip(tooltip: tooltip, view: view));
        view.onMount?.call();
      }
    }

    // Destroy removed tooltips
    for (final active in _activeTooltips) {
      if (!newActive.any((a) => a.tooltip.create == active.tooltip.create)) {
        active.view.onDestroy?.call();
      }
    }

    _activeTooltips
      ..clear()
      ..addAll(newActive);
  }

  @override
  void dispose() {
    for (final active in _activeTooltips) {
      active.view.onDestroy?.call();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.state.facet(_tooltipConfig);
    final size = MediaQuery.of(context).size;
    final space = config.tooltipSpace?.call(context) ??
        TooltipRect(top: 0, left: 0, bottom: size.height, right: size.width);

    if (_activeTooltips.isEmpty) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        ..._activeTooltips.map((active) {
          final pos = widget.coordsAtPos(active.tooltip.pos);
          if (pos == null) return const SizedBox.shrink();

          return Positioned(
            left: pos.dx + active.view.offset.dx,
            top: active.tooltip.above
                ? null
                : pos.dy + 20 + active.view.offset.dy,
            bottom: active.tooltip.above
                ? size.height - pos.dy + active.view.offset.dy
                : null,
            child: HoverTooltipContainer(
              tooltip: active.tooltip,
              view: active.view,
              above: active.tooltip.above,
              space: space,
            ),
          );
        }),
      ],
    );
  }
}

/// Internal: Tracks an active tooltip and its view.
class _ActiveTooltip {
  final HoverTooltip tooltip;
  final TooltipView view;

  const _ActiveTooltip({required this.tooltip, required this.view});

  _ActiveTooltip copyWith({HoverTooltip? tooltip, TooltipView? view}) {
    return _ActiveTooltip(
      tooltip: tooltip ?? this.tooltip,
      view: view ?? this.view,
    );
  }
}

// ============================================================================
// Hover Tooltip Detector
// ============================================================================

/// Widget that detects hover events and triggers hover tooltips.
///
/// This widget wraps editor content and monitors mouse hover events.
/// When the mouse hovers over text for a configurable duration, it queries
/// all registered hover tooltip sources (via [hoverTooltipFacet]) and
/// dispatches state effects to show the resulting tooltips.
///
/// This is a standalone implementation that can be used outside of EditorView.
/// EditorView has its own integrated hover handling that uses the same
/// [hoverTooltipFacet] mechanism.
///
/// ## Usage
///
/// ```dart
/// HoverTooltipDetector(
///   state: editorState,
///   dispatch: (tr) => setState(() => editorState = editorState.apply(tr)),
///   posAtCoords: (offset) => view.posAtCoords(offset),
///   coordsAtPos: (pos) => view.coordsAtPos(pos),
///   child: editorContent,
/// )
/// ```
class HoverTooltipDetector extends StatefulWidget {
  /// The editor state.
  final EditorState state;

  /// Function to dispatch transactions.
  final void Function(txn.Transaction tr) dispatch;

  /// Function to get the document position at a point.
  final int? Function(Offset position) posAtCoords;
  
  /// Function to get coordinates for a document position.
  /// Used to compute the tooltip anchor position.
  final Offset? Function(int pos) coordsAtPos;

  /// The child widget.
  final Widget child;

  const HoverTooltipDetector({
    super.key,
    required this.state,
    required this.dispatch,
    required this.posAtCoords,
    required this.coordsAtPos,
    required this.child,
  });

  @override
  State<HoverTooltipDetector> createState() => _HoverTooltipDetectorState();
}

class _HoverTooltipDetectorState extends State<HoverTooltipDetector> {
  Timer? _hoverTimer;
  Offset? _lastPosition;
  int? _lastHoverPos;
  List<Future<HoverTooltip?>>? _pendingTooltips;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _onHover(PointerHoverEvent event) {
    _lastPosition = event.localPosition;
    _hoverTimer?.cancel();

    // Get hover delay from registered configs
    final hoverConfigs = widget.state.facet(hoverTooltipFacet);
    final hoverTime = hoverConfigs.isNotEmpty 
        ? hoverConfigs.first.hoverTime 
        : 300;

    _hoverTimer = Timer(Duration(milliseconds: hoverTime), _checkHover);
  }

  Future<void> _checkHover() async {
    if (_lastPosition == null) return;

    final pos = widget.posAtCoords(_lastPosition!);
    if (pos == null) return;

    // If already showing tooltip for this position, skip
    if (_lastHoverPos == pos) return;
    _lastHoverPos = pos;

    // Get registered hover tooltip sources
    final hoverConfigs = widget.state.facet(hoverTooltipFacet);
    if (hoverConfigs.isEmpty) return;

    // Determine side (-1 if before position, 1 if after)
    // This requires coordsAtPos to determine pointer position relative to character
    final posCoords = widget.coordsAtPos(pos);
    final side = (posCoords != null && _lastPosition!.dx < posCoords.dx) ? -1 : 1;

    // Query all registered hover sources
    final tooltips = <HoverTooltip>[];
    final futures = <Future<HoverTooltip?>>[];

    for (final config in hoverConfigs) {
      final result = config.source(widget.state, pos, side);
      if (result is Future) {
        futures.add(Future.value(result).then((v) => v as HoverTooltip?));
      } else if (result != null) {
        tooltips.add(result);
      }
    }

    // Handle async results
    if (futures.isNotEmpty) {
      _pendingTooltips = futures;
      final results = await Future.wait(futures);

      // Check if we're still at the same position (user might have moved)
      if (_lastHoverPos != pos || _pendingTooltips != futures) {
        return;
      }
      _pendingTooltips = null;

      for (final tooltip in results) {
        if (tooltip != null) {
          tooltips.add(tooltip);
        }
      }
    }

    if (tooltips.isEmpty) return;

    // Dispatch effects to show tooltips
    // Each config has its own setHover effect type
    for (var i = 0; i < hoverConfigs.length && i < tooltips.length; i++) {
      final config = hoverConfigs[i];
      final tooltip = tooltips[i];
      
      widget.dispatch(widget.state.update([
        TransactionSpec(
          effects: [config.setHover.of([tooltip])],
        ),
      ]));
    }
  }

  void _onExit(PointerExitEvent event) {
    _hoverTimer?.cancel();
    _lastPosition = null;
    _pendingTooltips = null;
    
    // Dispatch effects to hide all tooltips after a short delay
    // (allows user to move mouse to the tooltip)
    _hoverTimer = Timer(const Duration(milliseconds: 100), () {
      final hoverConfigs = widget.state.facet(hoverTooltipFacet);
      for (final config in hoverConfigs) {
        widget.dispatch(widget.state.update([
          TransactionSpec(
            effects: [config.setHover.of([])],
          ),
        ]));
      }
      _lastHoverPos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _onHover,
      onExit: _onExit,
      child: widget.child,
    );
  }
}
