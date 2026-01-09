import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates the custom selection rendering layer from Phase 5.
class SelectionLayerDemo extends StatefulWidget {
  const SelectionLayerDemo({super.key});

  @override
  State<SelectionLayerDemo> createState() => _SelectionLayerDemoState();
}

class _SelectionLayerDemoState extends State<SelectionLayerDemo> {
  late SelectionConfig _config;
  late EditorSelection _selection;

  final String _docContent = '''The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump!
The five boxing wizards jump quickly.
Sphinx of black quartz, judge my vow.''';

  @override
  void initState() {
    super.initState();
    _config = const SelectionConfig(
      cursorBlinkRate: 1200,
      drawRangeCursor: true,
      cursorWidth: 2.0,
    );
    _selection = EditorSelection.single(0);
  }

  void _setCursorPosition(int pos) {
    setState(() {
      _selection = EditorSelection.single(pos.clamp(0, _docContent.length));
    });
  }

  void _setSelection(int from, int to) {
    setState(() {
      _selection = EditorSelection.single(
        from.clamp(0, _docContent.length),
        to.clamp(0, _docContent.length),
      );
    });
  }

  void _addCursor() {
    final newPos = (_selection.main.head + 50).clamp(0, _docContent.length);
    final newRange = EditorSelection.cursor(newPos);
    setState(() {
      _selection = EditorSelection.create(
        [..._selection.ranges, newRange],
        _selection.ranges.length,
      );
    });
  }

  void _updateConfig(SelectionConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selection Layer',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Custom selection and cursor rendering using CustomPainter. '
            'Supports multiple cursors, configurable blink rate, and custom colors.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              children: [
                // Editor preview
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selection Preview',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildEditorPreview(theme, constraints);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Controls
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Cursor controls
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cursor Position',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Slider(
                                  value: _selection.main.head.toDouble(),
                                  min: 0,
                                  max: _docContent.length.toDouble(),
                                  divisions: _docContent.length,
                                  label: '${_selection.main.head}',
                                  onChanged: (v) => _setCursorPosition(v.toInt()),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Selection Range',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                RangeSlider(
                                  values: RangeValues(
                                    _selection.main.from.toDouble(),
                                    _selection.main.to.toDouble(),
                                  ),
                                  min: 0,
                                  max: _docContent.length.toDouble(),
                                  divisions: _docContent.length,
                                  onChanged: (v) => _setSelection(
                                    v.start.toInt(),
                                    v.end.toInt(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonalIcon(
                                  onPressed: _addCursor,
                                  icon: const Icon(Icons.add),
                                  label: Text('Add Cursor (${_selection.ranges.length})'),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Config controls
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SelectionConfig',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 16),

                                // Blink rate
                                Row(
                                  children: [
                                    const Text('Blink Rate:'),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Slider(
                                        value: _config.cursorBlinkRate.toDouble(),
                                        min: 0,
                                        max: 2000,
                                        divisions: 20,
                                        label: '${_config.cursorBlinkRate}ms',
                                        onChanged: (v) => _updateConfig(
                                          _config.copyWith(cursorBlinkRate: v.toInt()),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Cursor width
                                Row(
                                  children: [
                                    const Text('Cursor Width:'),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Slider(
                                        value: _config.cursorWidth,
                                        min: 1,
                                        max: 6,
                                        divisions: 10,
                                        label: '${_config.cursorWidth}px',
                                        onChanged: (v) => _updateConfig(
                                          _config.copyWith(cursorWidth: v),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Draw range cursor
                                SwitchListTile(
                                  title: const Text('Draw Range Cursor'),
                                  subtitle: const Text(
                                    'Show cursor at selection head',
                                  ),
                                  value: _config.drawRangeCursor,
                                  onChanged: (v) => _updateConfig(
                                    _config.copyWith(drawRangeCursor: v),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Color picker
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Colors',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _colorButton('Blue', Colors.blue, theme),
                                    _colorButton('Green', Colors.green, theme),
                                    _colorButton('Orange', Colors.orange, theme),
                                    _colorButton('Purple', Colors.purple, theme),
                                    _colorButton('Red', Colors.red, theme),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Info bar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _infoChip('Cursors', '${_selection.ranges.length}', theme),
                  const SizedBox(width: 16),
                  _infoChip('Blink', '${_config.cursorBlinkRate}ms', theme),
                  const SizedBox(width: 16),
                  _infoChip('Width', '${_config.cursorWidth}px', theme),
                  const Spacer(),
                  Text(
                    'Phase 5: Selection & Decorations',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPreview(ThemeData theme, BoxConstraints constraints) {
    final cursorColor = _config.cursorColor ?? theme.colorScheme.primary;
    final selectionColor = _config.selectionColor ??
        theme.colorScheme.primary.withAlpha(77);

    const padding = EdgeInsets.all(12);
    const textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.4, // Consistent line height
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Use a fixed width for consistent layout between text and painters
              final textWidth = constraints.maxWidth;
              
              return Stack(
                children: [
                  // Selection background layer (behind text)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SelectionBackgroundPainter(
                        text: _docContent,
                        selection: _selection,
                        selectionColor: selectionColor,
                        style: textStyle,
                        maxWidth: textWidth,
                      ),
                    ),
                  ),

                  // Text layer - use SizedBox to ensure consistent width
                  SizedBox(
                    width: textWidth,
                    child: Text(
                      _docContent,
                      style: textStyle.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),

                  // Cursor layer (in front of text)
                  Positioned.fill(
                    child: _CursorLayer(
                      text: _docContent,
                      selection: _selection,
                      config: _config,
                      cursorColor: cursorColor,
                      maxWidth: textWidth,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _colorButton(String label, Color color, ThemeData theme) {
    final isSelected = _config.cursorColor == color;
    return ActionChip(
      avatar: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      label: Text(label),
      backgroundColor: isSelected ? color.withAlpha(50) : null,
      onPressed: () => _updateConfig(
        _config.copyWith(
          cursorColor: color,
          selectionColor: color.withAlpha(77),
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Paints selection backgrounds.
class _SelectionBackgroundPainter extends CustomPainter {
  final String text;
  final EditorSelection selection;
  final Color selectionColor;
  final TextStyle style;
  final double maxWidth;

  _SelectionBackgroundPainter({
    required this.text,
    required this.selection,
    required this.selectionColor,
    required this.style,
    required this.maxWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);

    final paint = Paint()..color = selectionColor;

    for (final range in selection.ranges) {
      if (!range.empty) {
        final boxes = textPainter.getBoxesForSelection(
          TextSelection(baseOffset: range.from, extentOffset: range.to),
        );
        for (final box in boxes) {
          canvas.drawRect(
            Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SelectionBackgroundPainter oldDelegate) {
    return text != oldDelegate.text ||
        selection != oldDelegate.selection ||
        selectionColor != oldDelegate.selectionColor ||
        maxWidth != oldDelegate.maxWidth;
  }
}

/// Animated cursor layer with blinking.
class _CursorLayer extends StatefulWidget {
  final String text;
  final EditorSelection selection;
  final SelectionConfig config;
  final Color cursorColor;
  final double maxWidth;

  const _CursorLayer({
    required this.text,
    required this.selection,
    required this.config,
    required this.cursorColor,
    required this.maxWidth,
  });

  @override
  State<_CursorLayer> createState() => _CursorLayerState();
}

class _CursorLayerState extends State<_CursorLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  void _setupAnimation() {
    final rate = widget.config.cursorBlinkRate;
    if (rate > 0) {
      _controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: rate),
      )..addListener(() {
          final newVisible = _controller.value < 0.5;
          if (newVisible != _visible) {
            setState(() => _visible = newVisible);
          }
        });
      _controller.repeat();
    } else {
      _controller = AnimationController(vsync: this);
      _visible = true;
    }
  }

  @override
  void didUpdateWidget(_CursorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config.cursorBlinkRate != oldWidget.config.cursorBlinkRate) {
      _controller.dispose();
      _setupAnimation();
    }
    if (widget.selection != oldWidget.selection) {
      // Reset blink on selection change
      _visible = true;
      if (widget.config.cursorBlinkRate > 0) {
        _controller.reset();
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CursorPainter(
        text: widget.text,
        selection: widget.selection,
        config: widget.config,
        cursorColor: widget.cursorColor,
        visible: _visible,
        maxWidth: widget.maxWidth,
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final String text;
  final EditorSelection selection;
  final SelectionConfig config;
  final Color cursorColor;
  final bool visible;
  final double maxWidth;

  _CursorPainter({
    required this.text,
    required this.selection,
    required this.config,
    required this.cursorColor,
    required this.visible,
    required this.maxWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);

    final paint = Paint()..color = cursorColor;
    final lineHeight = textPainter.preferredLineHeight;

    for (var i = 0; i < selection.ranges.length; i++) {
      final range = selection.ranges[i];
      final isPrimary = i == selection.mainIndex;

      if (range.empty || config.drawRangeCursor) {
        final pos = range.head;
        final offset = textPainter.getOffsetForCaret(
          TextPosition(offset: pos),
          Rect.zero,
        );

        final cursorRect = Rect.fromLTWH(
          offset.dx,
          offset.dy,
          config.cursorWidth,
          lineHeight,
        );

        paint.color = isPrimary
            ? cursorColor
            : cursorColor.withAlpha((cursorColor.a * 0.5).round());

        canvas.drawRect(cursorRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) {
    return text != oldDelegate.text ||
        selection != oldDelegate.selection ||
        config != oldDelegate.config ||
        cursorColor != oldDelegate.cursorColor ||
        visible != oldDelegate.visible ||
        maxWidth != oldDelegate.maxWidth;
  }
}
