import 'dart:ui';

import 'package:codemirror/codemirror.dart' hide lessThan;
import 'package:flutter/painting.dart' show Alignment, EdgeInsets;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlignmentExtensions', () {
    test('flipX flips horizontal alignment', () {
      expect(Alignment.topLeft.flipX(), Alignment.topRight);
      expect(Alignment.topRight.flipX(), Alignment.topLeft);
      expect(Alignment.centerLeft.flipX(), Alignment.centerRight);
      expect(Alignment.centerRight.flipX(), Alignment.centerLeft);
      expect(Alignment.bottomLeft.flipX(), Alignment.bottomRight);
      expect(Alignment.bottomRight.flipX(), Alignment.bottomLeft);
      expect(Alignment.topCenter.flipX(), Alignment.topCenter);
      expect(Alignment.center.flipX(), Alignment.center);
    });
    
    test('flipY flips vertical alignment', () {
      expect(Alignment.topLeft.flipY(), Alignment.bottomLeft);
      expect(Alignment.topCenter.flipY(), Alignment.bottomCenter);
      expect(Alignment.topRight.flipY(), Alignment.bottomRight);
      expect(Alignment.bottomLeft.flipY(), Alignment.topLeft);
      expect(Alignment.bottomCenter.flipY(), Alignment.topCenter);
      expect(Alignment.bottomRight.flipY(), Alignment.topRight);
      expect(Alignment.centerLeft.flipY(), Alignment.centerLeft);
      expect(Alignment.center.flipY(), Alignment.center);
    });
    
    test('relative calculates correct offset for Size', () {
      const size = Size(100, 50);
      const origin = Offset.zero;
      
      expect(Alignment.topLeft.relative(to: size, origin: origin), const Offset(0, 0));
      expect(Alignment.topCenter.relative(to: size, origin: origin), const Offset(50, 0));
      expect(Alignment.topRight.relative(to: size, origin: origin), const Offset(100, 0));
      expect(Alignment.centerLeft.relative(to: size, origin: origin), const Offset(0, 25));
      expect(Alignment.center.relative(to: size, origin: origin), const Offset(50, 25));
      expect(Alignment.centerRight.relative(to: size, origin: origin), const Offset(100, 25));
      expect(Alignment.bottomLeft.relative(to: size, origin: origin), const Offset(0, 50));
      expect(Alignment.bottomCenter.relative(to: size, origin: origin), const Offset(50, 50));
      expect(Alignment.bottomRight.relative(to: size, origin: origin), const Offset(100, 50));
    });
    
    test('relative with non-zero origin adds to result', () {
      const size = Size(100, 50);
      const origin = Offset(10, 20);
      
      expect(Alignment.topLeft.relative(to: size, origin: origin), const Offset(10, 20));
      expect(Alignment.topRight.relative(to: size, origin: origin), const Offset(110, 20));
      expect(Alignment.bottomLeft.relative(to: size, origin: origin), const Offset(10, 70));
      expect(Alignment.bottomRight.relative(to: size, origin: origin), const Offset(110, 70));
    });
  });
  
  group('PortalSpacing', () {
    test('applies spacing for opposite anchors (bottom-top)', () {
      const spacing = PortalSpacing(8);
      final offset = spacing(Alignment.bottomCenter, Alignment.topCenter);
      expect(offset, const Offset(0, 8));
    });
    
    test('applies spacing for opposite anchors (top-bottom)', () {
      const spacing = PortalSpacing(8);
      final offset = spacing(Alignment.topCenter, Alignment.bottomCenter);
      expect(offset, const Offset(0, -8));
    });
    
    test('applies spacing for opposite anchors (left-right)', () {
      const spacing = PortalSpacing(8);
      final offset = spacing(Alignment.centerLeft, Alignment.centerRight);
      expect(offset, const Offset(-8, 0));
    });
    
    test('applies spacing for opposite anchors (right-left)', () {
      const spacing = PortalSpacing(8);
      final offset = spacing(Alignment.centerRight, Alignment.centerLeft);
      expect(offset, const Offset(8, 0));
    });
    
    test('no spacing for same-side anchors', () {
      const spacing = PortalSpacing(8);
      expect(spacing(Alignment.topCenter, Alignment.topCenter), Offset.zero);
      expect(spacing(Alignment.bottomCenter, Alignment.bottomCenter), Offset.zero);
      expect(spacing(Alignment.center, Alignment.center), Offset.zero);
    });
    
    test('no spacing for diagonal corners by default', () {
      const spacing = PortalSpacing(8);
      expect(spacing(Alignment.topLeft, Alignment.bottomRight), Offset.zero);
      expect(spacing(Alignment.bottomRight, Alignment.topLeft), Offset.zero);
    });
    
    test('applies spacing for diagonal corners when diagonal=true', () {
      const spacing = PortalSpacing(8, diagonal: true);
      expect(spacing(Alignment.topLeft, Alignment.bottomRight), const Offset(-8, -8));
      expect(spacing(Alignment.bottomRight, Alignment.topLeft), const Offset(8, 8));
    });
    
    test('zero spacing returns Offset.zero', () {
      const spacing = PortalSpacing.zero;
      expect(spacing(Alignment.bottomCenter, Alignment.topCenter), Offset.zero);
    });
  });
  
  group('calculateTooltipPosition', () {
    const viewSize = Size(800, 600);
    
    test('positions tooltip below anchor by default', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 100),
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.below,
      );
      
      // Child bottom center is at (125, 120)
      // Portal top center needs to align there, so top-left is at (25, 128)
      // With 8px spacing, portal moves down by 8
      expect(pos.dx, closeTo(25, 1));
      expect(pos.dy, closeTo(128, 1));
    });
    
    test('positions tooltip above anchor when configured', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 200),
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.above,
      );
      
      // Child top center is at (125, 200)
      // Portal bottom center needs to align there, so top-left is at (25, 92)
      // With 8px spacing, portal moves up by 8
      expect(pos.dx, closeTo(25, 1));
      expect(pos.dy, closeTo(92, 1));
    });
    
    test('respects viewInsets', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 100),
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: const TooltipPositioning(
          childAnchor: Alignment.bottomCenter,
          portalAnchor: Alignment.topCenter,
          viewInsets: EdgeInsets.all(20),
        ),
      );
      
      // Result should account for view insets
      expect(pos.dx, greaterThanOrEqualTo(20));
      expect(pos.dy, greaterThanOrEqualTo(20));
    });
    
    test('flips when overflowing bottom', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 550), // Near bottom of screen
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.below,
      );
      
      // Should flip above since there's not enough room below
      expect(pos.dy, lessThan(550)); // Portal should be above the anchor
    });
    
    test('flips when overflowing top', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 20), // Near top of screen
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.above,
      );
      
      // Should flip below since there's not enough room above
      expect(pos.dy, greaterThan(20)); // Portal should be below the anchor
    });
    
    test('slides horizontally when overflowing right', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(700, 100), // Near right edge
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.below,
      );
      
      // Portal should not overflow right edge
      expect(pos.dx + 200, lessThanOrEqualTo(viewSize.width));
    });
    
    test('slides horizontally when overflowing left', () {
      final pos = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(10, 100), // Near left edge
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: TooltipPositioning.below,
      );
      
      // Portal should not overflow left edge
      expect(pos.dx, greaterThanOrEqualTo(0));
    });
    
    test('applies additional offset', () {
      final posWithOffset = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 100),
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: const TooltipPositioning(
          childAnchor: Alignment.bottomCenter,
          portalAnchor: Alignment.topCenter,
          offset: Offset(10, 5),
        ),
      );
      
      final posWithoutOffset = calculateTooltipPosition(
        viewSize: viewSize,
        childOffset: const Offset(100, 100),
        childSize: const Size(50, 20),
        portalSize: const Size(200, 100),
        config: const TooltipPositioning(
          childAnchor: Alignment.bottomCenter,
          portalAnchor: Alignment.topCenter,
        ),
      );
      
      expect(posWithOffset.dx - posWithoutOffset.dx, closeTo(10, 0.1));
      expect(posWithOffset.dy - posWithoutOffset.dy, closeTo(5, 0.1));
    });
  });
  
  group('positionHoverTooltip', () {
    test('positions tooltip below anchor with spacing', () {
      final pos = positionHoverTooltip(
        viewSize: const Size(800, 600),
        anchorGlobal: const Offset(100, 100),
        lineHeight: 20,
        portalSize: const Size(200, 100),
      );
      
      // Should be below the anchor with spacing
      expect(pos.dy, greaterThan(100 + 20)); // Below anchor + line height
    });
    
    test('uses bottomLeft-topLeft alignment', () {
      final pos = positionHoverTooltip(
        viewSize: const Size(800, 600),
        anchorGlobal: const Offset(100, 100),
        lineHeight: 20,
        portalSize: const Size(200, 100),
      );
      
      // X should be close to anchor X (left alignment)
      expect(pos.dx, closeTo(100, 20)); // Allow for view insets
    });
    
    test('flips above when near bottom of screen', () {
      final pos = positionHoverTooltip(
        viewSize: const Size(800, 600),
        anchorGlobal: const Offset(100, 550),
        lineHeight: 20,
        portalSize: const Size(200, 100),
      );
      
      // Should flip above
      expect(pos.dy, lessThan(550));
    });
  });
  
  group('PortalOverflow strategies', () {
    test('allow strategy does not adjust position', () {
      const child = (
        offset: Offset(100, 100),
        size: Size(50, 20),
        anchor: Alignment.bottomCenter,
      );
      const portal = (
        offset: Offset.zero,
        size: Size(200, 100),
        anchor: Alignment.topCenter,
      );
      
      final offset = PortalOverflow.allow(const Size(800, 600), child, portal);
      
      // Should just calculate basic position without adjustment
      expect(offset, isA<Offset>());
    });
    
    test('slide strategy keeps portal within bounds', () {
      const child = (
        offset: Offset(700, 100),  // Near right edge
        size: Size(50, 20),
        anchor: Alignment.bottomCenter,
      );
      const portal = (
        offset: Offset.zero,
        size: Size(200, 100),
        anchor: Alignment.topCenter,
      );
      
      final offset = PortalOverflow.slide(const Size(800, 600), child, portal);
      
      // Portal position relative to child
      final portalRect = (child.offset + offset) & portal.size;
      expect(portalRect.right, lessThanOrEqualTo(800));
    });
    
    test('flip strategy flips when overflow detected', () {
      // Position child near bottom
      const child = (
        offset: Offset(100, 550),
        size: Size(50, 20),
        anchor: Alignment.bottomCenter,
      );
      const portal = (
        offset: Offset(0, 8), // spacing
        size: Size(200, 100),
        anchor: Alignment.topCenter,
      );
      
      final offset = PortalOverflow.flip(const Size(800, 600), child, portal);
      
      // Should flip to above the child
      final portalTop = child.offset.dy + offset.dy;
      expect(portalTop, lessThan(550));
    });
  });
}
