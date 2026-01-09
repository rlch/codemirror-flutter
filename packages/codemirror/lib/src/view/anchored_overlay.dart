/// Anchored overlay - unified tooltip/popup positioning using follow_the_leader.
///
/// This module provides a consistent way to position overlays (tooltips, popups,
/// menus) relative to anchor positions in the editor. It uses the follow_the_leader
/// package to defer positioning decisions until after layout, when actual sizes
/// are known.
library;

import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';

/// Controller for managing an anchored overlay.
///
/// Provides methods to show, update, and hide an overlay that is positioned
/// relative to an anchor point in the editor.
class AnchoredOverlayController {
  OverlayEntry? _leaderEntry;
  OverlayEntry? _followerEntry;
  final LeaderLink _link = LeaderLink();
  
  // Store current values for rebuilds
  Offset _anchor = Offset.zero;
  Size _anchorSize = Size.zero;
  FollowerAligner _aligner = const BelowFirstAligner();
  Widget _child = const SizedBox();
  VoidCallback? _onHoverEnter;
  VoidCallback? _onHoverExit;

  /// Whether the overlay is currently showing.
  bool get isShowing => _followerEntry != null;

  /// Show an anchored overlay.
  ///
  /// [context] - Build context for inserting into overlay
  /// [anchor] - Global position of the anchor point
  /// [anchorSize] - Size of the anchor (typically Size(1, lineHeight))
  /// [aligner] - How to align the follower relative to the leader
  /// [child] - The overlay content widget
  /// [onHoverEnter] - Called when mouse enters the overlay
  /// [onHoverExit] - Called when mouse exits the overlay
  void show({
    required BuildContext context,
    required Offset anchor,
    required Size anchorSize,
    required FollowerAligner aligner,
    required Widget child,
    VoidCallback? onHoverEnter,
    VoidCallback? onHoverExit,
  }) {
    hide();

    // Get overlay for inserting entries
    final overlay = Overlay.of(context);
    
    // Store values for rebuilds
    _anchor = anchor;
    _anchorSize = anchorSize;
    _aligner = aligner;
    _child = child;
    _onHoverEnter = onHoverEnter;
    _onHoverExit = onHoverExit;

    // Create leader entry - positioned at anchor
    _leaderEntry = OverlayEntry(
      builder: (overlayContext) {
        // Recalculate overlay offset on each build in case it changed
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        final overlayOffset = overlayBox?.localToGlobal(Offset.zero) ?? Offset.zero;
        final localAnchor = _anchor - overlayOffset;
        return Positioned(
          left: localAnchor.dx,
          top: localAnchor.dy,
          child: Leader(
            link: _link,
            child: SizedBox(
              width: _anchorSize.width,
              height: _anchorSize.height,
            ),
          ),
        );
      },
    );

    // Create follower entry - follows the leader with smart positioning
    _followerEntry = OverlayEntry(
      builder: (_) => Follower.withAligner(
        link: _link,
        aligner: _aligner,
        boundary: ScreenFollowerBoundary(),
        child: MouseRegion(
          hitTestBehavior: HitTestBehavior.deferToChild,
          onEnter: _onHoverEnter != null ? (_) => _onHoverEnter!() : null,
          onExit: _onHoverExit != null ? (_) => _onHoverExit!() : null,
          child: _child,
        ),
      ),
    );

    overlay.insertAll([_leaderEntry!, _followerEntry!]);
  }

  /// Update the overlay content and/or position.
  void update({
    Offset? anchor,
    Size? anchorSize,
    FollowerAligner? aligner,
    Widget? child,
  }) {
    if (anchor != null) _anchor = anchor;
    if (anchorSize != null) _anchorSize = anchorSize;
    if (aligner != null) _aligner = aligner;
    if (child != null) _child = child;
    
    _leaderEntry?.markNeedsBuild();
    _followerEntry?.markNeedsBuild();
  }

  /// Hide and dispose the overlay.
  void hide() {
    _leaderEntry?.remove();
    _leaderEntry?.dispose();
    _leaderEntry = null;

    _followerEntry?.remove();
    _followerEntry?.dispose();
    _followerEntry = null;
  }

  /// Dispose the controller.
  void dispose() {
    hide();
  }
}

/// Aligner for tooltips that appear below the anchor, flipping above if needed.
///
/// This is the most common case for hover tooltips and autocomplete.
class BelowFirstAligner implements FollowerAligner {
  final double gap;
  final double viewPadding;

  const BelowFirstAligner({
    this.gap = 4.0,
    this.viewPadding = 8.0,
  });

  @override
  FollowerAlignment align(
    Rect leaderRect,
    Size followerSize, [
    Rect? boundaryRect,
  ]) {
    // Calculate if tooltip fits below
    final belowY = leaderRect.bottom + gap;
    final fitsBelow = boundaryRect != null
        ? (belowY + followerSize.height <= boundaryRect.bottom - viewPadding)
        : true;

    if (fitsBelow) {
      return FollowerAlignment(
        leaderAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        followerOffset: Offset(0, gap),
      );
    }

    // Flip above
    return FollowerAlignment(
      leaderAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      followerOffset: Offset(0, -gap),
    );
  }
}

/// Aligner for tooltips that appear above the anchor, flipping below if needed.
///
/// Used for signature help which conventionally appears above the cursor.
class AboveFirstAligner implements FollowerAligner {
  final double gap;
  final double viewPadding;

  const AboveFirstAligner({
    this.gap = 4.0,
    this.viewPadding = 8.0,
  });

  @override
  FollowerAlignment align(
    Rect leaderRect,
    Size followerSize, [
    Rect? boundaryRect,
  ]) {
    // Calculate if tooltip fits above
    final aboveY = leaderRect.top - gap - followerSize.height;
    final fitsAbove = boundaryRect != null
        ? (aboveY >= boundaryRect.top + viewPadding)
        : true;

    if (fitsAbove) {
      return FollowerAlignment(
        leaderAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        followerOffset: Offset(0, -gap),
      );
    }

    // Flip below
    return FollowerAlignment(
      leaderAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      followerOffset: Offset(0, gap),
    );
  }
}

/// Aligner for center-aligned tooltips (like context menus).
class CenterBelowFirstAligner implements FollowerAligner {
  final double gap;
  final double viewPadding;

  const CenterBelowFirstAligner({
    this.gap = 8.0,
    this.viewPadding = 8.0,
  });

  @override
  FollowerAlignment align(
    Rect leaderRect,
    Size followerSize, [
    Rect? boundaryRect,
  ]) {
    final belowY = leaderRect.bottom + gap;
    final fitsBelow = boundaryRect != null
        ? (belowY + followerSize.height <= boundaryRect.bottom - viewPadding)
        : true;

    if (fitsBelow) {
      return FollowerAlignment(
        leaderAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        followerOffset: Offset(0, gap),
      );
    }

    return FollowerAlignment(
      leaderAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      followerOffset: Offset(0, -gap),
    );
  }
}
