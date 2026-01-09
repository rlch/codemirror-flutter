/// Tooltip positioning algorithm ported from forui's FPortal.
///
/// Provides intelligent positioning of tooltips relative to anchor points
/// with support for flipping, sliding, and screen boundary handling.
///
/// Based on: https://github.com/forus-labs/forui/tree/main/forui/lib/src/foundation/portal
library;

import 'dart:ui';

import 'package:flutter/painting.dart' show Alignment, EdgeInsets;

// ============================================================================
// Type definitions matching FPortal
// ============================================================================

/// A child/anchor widget's rectangle for positioning calculations.
typedef PortalChildRect = ({Offset offset, Size size, Alignment anchor});

/// A portal/tooltip's rectangle for positioning calculations.
typedef PortalRect = ({Offset offset, Size size, Alignment anchor});

// ============================================================================
// Alignment Extensions (from forui's rendering.dart)
// ============================================================================

extension AlignmentExtensions on Alignment {
  /// Flip the alignment horizontally.
  Alignment flipX() => switch (this) {
    Alignment.topLeft => Alignment.topRight,
    Alignment.topRight => Alignment.topLeft,
    Alignment.centerLeft => Alignment.centerRight,
    Alignment.centerRight => Alignment.centerLeft,
    Alignment.bottomLeft => Alignment.bottomRight,
    Alignment.bottomRight => Alignment.bottomLeft,
    _ => this,
  };

  /// Flip the alignment vertically.
  Alignment flipY() => switch (this) {
    Alignment.topLeft => Alignment.bottomLeft,
    Alignment.topCenter => Alignment.bottomCenter,
    Alignment.topRight => Alignment.bottomRight,
    Alignment.bottomLeft => Alignment.topLeft,
    Alignment.bottomCenter => Alignment.topCenter,
    Alignment.bottomRight => Alignment.topRight,
    _ => this,
  };

  /// Get the position of this alignment relative to a size.
  /// 
  /// Uses Flutter's Size methods: topLeft, topCenter, topRight, etc.
  /// [origin] is added to the result.
  Offset relative({required Size to, Offset origin = Offset.zero}) => switch (this) {
    Alignment.topLeft => to.topLeft(origin),
    Alignment.topCenter => to.topCenter(origin),
    Alignment.topRight => to.topRight(origin),
    Alignment.centerLeft => to.centerLeft(origin),
    Alignment.center => to.center(origin),
    Alignment.centerRight => to.centerRight(origin),
    Alignment.bottomLeft => to.bottomLeft(origin),
    Alignment.bottomCenter => to.bottomCenter(origin),
    Alignment.bottomRight => to.bottomRight(origin),
    _ => to.topLeft(origin),
  };
}

// ============================================================================
// Portal Spacing (from forui's portal_spacing.dart)
// ============================================================================

/// Calculates spacing between a widget and its portal based on their anchors.
/// 
/// Spacing is applied when anchors are on opposite sides.
/// For example, if childAnchor is bottomLeft and portalAnchor is topLeft,
/// spacing pushes the portal down.
class PortalSpacing {
  /// The amount of spacing to apply.
  final double spacing;
  
  /// Whether to apply spacing to diagonal corners.
  final bool diagonal;
  
  const PortalSpacing(this.spacing, {this.diagonal = false});
  
  /// No spacing.
  static const zero = PortalSpacing(0);
  
  /// Calculate the spacing offset based on anchor alignment relationship.
  Offset call(Alignment child, Alignment portal) {
    // Ignore corners that are diagonal by default
    if (!diagonal && 
        (child.x != 0 && child.y != 0) && 
        (child.x == -portal.x && child.y == -portal.y)) {
      return Offset.zero;
    }
    
    return Offset(
      switch (child.x) {
        -1 when portal.x == 1 => -spacing,  // Child left, portal right: push left
        1 when portal.x == -1 => spacing,   // Child right, portal left: push right
        _ => 0,
      },
      switch (child.y) {
        -1 when portal.y == 1 => -spacing,  // Child top, portal bottom: push up
        1 when portal.y == -1 => spacing,   // Child bottom, portal top: push down
        _ => 0,
      },
    );
  }
}

// ============================================================================
// Portal Overflow Strategies (from forui's portal_overflow.dart)
// ============================================================================

/// Strategy for handling overflow when portal exceeds viewport bounds.
abstract class PortalOverflow {
  const PortalOverflow();
  
  /// Flip to opposite side if overflow, then slide if still overflows.
  static const flip = _FlipOverflow();
  
  /// Slide along edge to stay within viewport.
  static const slide = _SlideOverflow();
  
  /// Allow overflow without adjustment.
  static const allow = _AllowOverflow();
  
  /// Calculate the position offset for the portal.
  /// 
  /// Returns offset relative to child's top-left (0, 0).
  Offset call(Size view, PortalChildRect child, PortalRect portal);
}

/// Calculate base position (allow strategy).
Offset _allow(Size view, PortalChildRect child, PortalRect portal) {
  final childAnchor = child.anchor.relative(to: child.size);
  final portalAnchor = portal.anchor.relative(to: portal.size, origin: -portal.offset);
  return childAnchor - portalAnchor;
}

/// Slide the anchor position to keep portal within viewport.
Offset _slide(Offset anchor, Rect viewRect, Rect portalRect) {
  // Slide horizontally
  anchor = switch ((viewRect, portalRect)) {
    _ when portalRect.left < viewRect.left => 
      Offset(anchor.dx + (viewRect.left - portalRect.left), anchor.dy),
    _ when viewRect.right < portalRect.right => 
      Offset(anchor.dx - portalRect.right + viewRect.right, anchor.dy),
    _ => anchor,
  };
  
  // Slide vertically
  anchor = switch ((viewRect, portalRect)) {
    _ when portalRect.top < viewRect.top => 
      Offset(anchor.dx, anchor.dy + (viewRect.top - portalRect.top)),
    _ when viewRect.bottom < portalRect.bottom => 
      Offset(anchor.dx, anchor.dy - portalRect.bottom + viewRect.bottom),
    _ => anchor,
  };
  
  return anchor;
}

/// Calculate position with flipped anchors.
Offset _flip(PortalChildRect child, PortalRect portal, {required bool x}) {
  final (childAnchor, portalAnchor, portalOffset) = x
      ? (child.anchor.flipX(), portal.anchor.flipX(), Offset(portal.offset.dx, -portal.offset.dy))
      : (child.anchor.flipY(), portal.anchor.flipY(), Offset(-portal.offset.dx, portal.offset.dy));
  
  final anchor = childAnchor.relative(to: child.size) - 
                 portalAnchor.relative(to: portal.size, origin: portalOffset);
  
  return anchor.translate(child.offset.dx, child.offset.dy);
}

class _FlipOverflow extends PortalOverflow {
  const _FlipOverflow();
  
  @override
  Offset call(Size view, PortalChildRect child, PortalRect portal) {
    var anchor = _allow(view, child, portal).translate(child.offset.dx, child.offset.dy);
    final viewRect = Offset.zero & view;
    var portalRect = anchor & portal.size;
    
    // Try horizontal flip if overflowing
    switch ((viewRect, portalRect)) {
      case _ when portalRect.left < viewRect.left:
        final flipped = _flip(child, portal, x: true);
        if ((flipped & portal.size).right <= viewRect.right) {
          anchor = flipped;
          portalRect = anchor & portal.size;
        }
      case _ when viewRect.right < portalRect.right:
        final flipped = _flip(child, portal, x: true);
        if (viewRect.left <= (flipped & portal.size).left) {
          anchor = flipped;
          portalRect = anchor & portal.size;
        }
    }
    
    // Try vertical flip if overflowing
    switch ((viewRect, portalRect)) {
      case _ when portalRect.top < viewRect.top:
        final flipped = _flip(child, portal, x: false);
        if ((flipped & portal.size).bottom <= viewRect.bottom) {
          anchor = flipped;
          portalRect = anchor & portal.size;
        }
      case _ when viewRect.bottom < portalRect.bottom:
        final flipped = _flip(child, portal, x: false);
        if (viewRect.top <= (flipped & portal.size).top) {
          anchor = flipped;
          portalRect = anchor & portal.size;
        }
    }
    
    // Apply slide for any remaining overflow
    final adjustedAnchor = _slide(anchor, viewRect, portalRect);
    return adjustedAnchor.translate(-child.offset.dx, -child.offset.dy);
  }
}

class _SlideOverflow extends PortalOverflow {
  const _SlideOverflow();
  
  @override
  Offset call(Size view, PortalChildRect child, PortalRect portal) {
    final anchor = _allow(view, child, portal).translate(child.offset.dx, child.offset.dy);
    final viewRect = Offset.zero & view;
    final portalRect = anchor & portal.size;
    return _slide(anchor, viewRect, portalRect).translate(-child.offset.dx, -child.offset.dy);
  }
}

class _AllowOverflow extends PortalOverflow {
  const _AllowOverflow();
  
  @override
  Offset call(Size view, PortalChildRect child, PortalRect portal) => 
    _allow(view, child, portal);
}

// ============================================================================
// Main Positioning API
// ============================================================================

/// Configuration for tooltip positioning.
class TooltipPositioning {
  /// The anchor point on the child/target widget.
  final Alignment childAnchor;
  
  /// The anchor point on the tooltip/portal widget.
  final Alignment portalAnchor;
  
  /// Spacing calculator.
  final PortalSpacing spacing;
  
  /// Overflow handling strategy.
  final PortalOverflow overflow;
  
  /// Additional offset applied after positioning.
  final Offset offset;
  
  /// Insets to avoid (e.g., safe area, screen edges).
  final EdgeInsets viewInsets;
  
  const TooltipPositioning({
    this.childAnchor = Alignment.bottomCenter,
    this.portalAnchor = Alignment.topCenter,
    this.spacing = const PortalSpacing(8),
    this.overflow = PortalOverflow.flip,
    this.offset = Offset.zero,
    this.viewInsets = EdgeInsets.zero,
  });
  
  /// Preset for showing tooltip below the target.
  static const below = TooltipPositioning(
    childAnchor: Alignment.bottomCenter,
    portalAnchor: Alignment.topCenter,
  );
  
  /// Preset for showing tooltip above the target.
  static const above = TooltipPositioning(
    childAnchor: Alignment.topCenter,
    portalAnchor: Alignment.bottomCenter,
  );
}

/// Calculate the position for a tooltip relative to an anchor.
///
/// [viewSize] - The viewport/screen size.
/// [childOffset] - The global position of the child/anchor widget.
/// [childSize] - The size of the child/anchor widget.
/// [portalSize] - The size of the tooltip/portal widget.
/// [config] - Positioning configuration.
///
/// Returns the global position for the tooltip's top-left corner.
Offset calculateTooltipPosition({
  required Size viewSize,
  required Offset childOffset,
  required Size childSize,
  required Size portalSize,
  TooltipPositioning config = TooltipPositioning.below,
}) {
  final viewInsets = config.viewInsets;
  
  // Effective viewport after insets
  final effectiveView = Size(
    viewSize.width - viewInsets.left - viewInsets.right,
    viewSize.height - viewInsets.top - viewInsets.bottom,
  );
  
  // Child position relative to effective viewport
  final childInView = Offset(
    childOffset.dx - viewInsets.left,
    childOffset.dy - viewInsets.top,
  );
  
  // Calculate spacing offset
  final spacingOffset = config.spacing(config.childAnchor, config.portalAnchor);
  
  // Build child and portal rect descriptors
  final child = (
    offset: childInView,
    size: childSize,
    anchor: config.childAnchor,
  );
  
  final portal = (
    offset: spacingOffset,
    size: portalSize,
    anchor: config.portalAnchor,
  );
  
  // Calculate position using overflow strategy
  final localOffset = config.overflow(effectiveView, child, portal);
  
  // Convert back to global coordinates and apply final offset
  return Offset(
    childInView.dx + localOffset.dx + viewInsets.left + config.offset.dx,
    childInView.dy + localOffset.dy + viewInsets.top + config.offset.dy,
  );
}

/// Simplified positioning for hover tooltips.
/// 
/// Positions a tooltip below an anchor point (typically a text position),
/// with automatic flipping above if needed.
Offset positionHoverTooltip({
  required Size viewSize,
  required Offset anchorGlobal,
  required double lineHeight,
  required Size portalSize,
  double spacing = 8.0,
  EdgeInsets viewInsets = const EdgeInsets.all(8.0),
}) {
  return calculateTooltipPosition(
    viewSize: viewSize,
    childOffset: anchorGlobal,
    childSize: Size(0, lineHeight),
    portalSize: portalSize,
    config: TooltipPositioning(
      childAnchor: Alignment.bottomLeft,
      portalAnchor: Alignment.topLeft,
      spacing: PortalSpacing(spacing),
      overflow: PortalOverflow.flip,
      viewInsets: viewInsets,
    ),
  );
}
