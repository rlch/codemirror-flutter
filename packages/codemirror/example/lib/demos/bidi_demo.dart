import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates bidirectional text support from Phase 5.
class BidiDemo extends StatefulWidget {
  const BidiDemo({super.key});

  @override
  State<BidiDemo> createState() => _BidiDemoState();
}

class _BidiDemoState extends State<BidiDemo> {
  String _inputText = 'Hello שלום World مرحبا!';
  Direction _baseDirection = Direction.ltr;
  List<BidiSpan> _spans = [];

  @override
  void initState() {
    super.initState();
    _computeOrder();
  }

  void _computeOrder() {
    setState(() {
      _spans = computeOrder(_inputText, _baseDirection);
    });
  }

  void _setInputText(String text) {
    _inputText = text;
    _computeOrder();
  }

  void _setDirection(Direction dir) {
    _baseDirection = dir;
    _computeOrder();
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
            'Bidirectional Text (BiDi)',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Implementation of the Unicode Bidirectional Algorithm (UBA) for '
            'handling mixed left-to-right and right-to-left text.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Input section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Input Text',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: _inputText),
                    onChanged: _setInputText,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter text with mixed directions...',
                    ),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Base Direction: '),
                      const SizedBox(width: 16),
                      SegmentedButton<Direction>(
                        segments: const [
                          ButtonSegment(
                            value: Direction.ltr,
                            label: Text('LTR'),
                            icon: Icon(Icons.format_textdirection_l_to_r),
                          ),
                          ButtonSegment(
                            value: Direction.rtl,
                            label: Text('RTL'),
                            icon: Icon(Icons.format_textdirection_r_to_l),
                          ),
                        ],
                        selected: {_baseDirection},
                        onSelectionChanged: (s) => _setDirection(s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('English'),
                        onPressed: () => _setInputText('Hello World!'),
                      ),
                      ActionChip(
                        label: const Text('Hebrew'),
                        onPressed: () => _setInputText('שלום עולם!'),
                      ),
                      ActionChip(
                        label: const Text('Arabic'),
                        onPressed: () => _setInputText('مرحبا بالعالم!'),
                      ),
                      ActionChip(
                        label: const Text('Mixed'),
                        onPressed: () =>
                            _setInputText('Hello שלום World مرحبا!'),
                      ),
                      ActionChip(
                        label: const Text('Numbers'),
                        onPressed: () =>
                            _setInputText('Price: 123 שקלים (456 NIS)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Visual order section
          Expanded(
            child: Row(
              children: [
                // Logical order
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sort_by_alpha,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Logical Order',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Characters in memory order',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildLogicalOrder(theme),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Visual order
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                color: theme.colorScheme.tertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Visual Order',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Characters in display order (BiDi applied)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildVisualOrder(theme),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Span details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BidiSpan Details',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _spans.isEmpty
                      ? Text(
                          'No spans computed',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _spans.asMap().entries.map((entry) {
                            final i = entry.key;
                            final span = entry.value;
                            final color = _getSpanColor(span.level, theme);

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: color.withAlpha(50),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Span $i',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${span.from}-${span.to}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Level: ${span.level} (${span.dir.name.toUpperCase()})',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  if (span.from < _inputText.length)
                                    Text(
                                      '"${_inputText.substring(span.from, span.to.clamp(0, _inputText.length))}"',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogicalOrder(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_inputText.length, (i) {
            final char = _inputText[i];
            final span = _spans.firstWhere(
              (s) => i >= s.from && i < s.to,
              orElse: () => BidiSpan(0, _inputText.length, 0),
            );
            final color = _getSpanColor(span.level, theme);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withAlpha(100)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    char == ' ' ? '␣' : char,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    '$i',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildVisualOrder(ThemeData theme) {
    // Build visual order based on spans
    final visualChars = <({String char, int logicalIndex, int level})>[];

    for (final span in _spans) {
      final isRtl = span.level.isOdd;
      final chars = <({String char, int logicalIndex, int level})>[];

      for (var i = span.from; i < span.to && i < _inputText.length; i++) {
        chars.add((char: _inputText[i], logicalIndex: i, level: span.level));
      }

      if (isRtl) {
        visualChars.addAll(chars.reversed);
      } else {
        visualChars.addAll(chars);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: visualChars.map((item) {
            final color = _getSpanColor(item.level, theme);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withAlpha(100)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.char == ' ' ? '␣' : item.char,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    '${item.logicalIndex}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getSpanColor(int level, ThemeData theme) {
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.secondary,
      Colors.orange,
    ];
    return colors[level % colors.length];
  }
}
