import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates the EditorSelection and SelectionRange classes.
class SelectionDemo extends StatefulWidget {
  const SelectionDemo({super.key});

  @override
  State<SelectionDemo> createState() => _SelectionDemoState();
}

class _SelectionDemoState extends State<SelectionDemo> {
  late EditorSelection _selection;
  final String _docContent = '''function greet(name) {
  console.log("Hello, " + name);
  return true;
}

greet("World");''';

  @override
  void initState() {
    super.initState();
    _selection = EditorSelection.single(0);
  }

  void _setCursor(int pos) {
    setState(() {
      _selection = EditorSelection.single(pos.clamp(0, _docContent.length));
    });
  }

  void _setRange(int anchor, int head) {
    setState(() {
      _selection = EditorSelection.single(
        anchor.clamp(0, _docContent.length),
        head.clamp(0, _docContent.length),
      );
    });
  }

  void _addRange() {
    // Add another selection range
    final newRange = EditorSelection.range(
      (_selection.main.to + 10).clamp(0, _docContent.length),
      (_selection.main.to + 20).clamp(0, _docContent.length),
    );
    setState(() {
      _selection = EditorSelection.create(
        [..._selection.ranges, newRange],
        _selection.ranges.length,
      );
    });
  }

  void _selectWord() {
    // Simple word selection at cursor
    final pos = _selection.main.head;
    var start = pos;
    var end = pos;

    while (start > 0 && _isWordChar(_docContent[start - 1])) {
      start--;
    }
    while (end < _docContent.length && _isWordChar(_docContent[end])) {
      end++;
    }

    setState(() {
      _selection = EditorSelection.single(start, end);
    });
  }

  void _selectLine() {
    final pos = _selection.main.head;
    var start = pos;
    var end = pos;

    while (start > 0 && _docContent[start - 1] != '\n') {
      start--;
    }
    while (end < _docContent.length && _docContent[end] != '\n') {
      end++;
    }

    setState(() {
      _selection = EditorSelection.single(start, end);
    });
  }

  void _selectAll() {
    setState(() {
      _selection = EditorSelection.single(0, _docContent.length);
    });
  }

  bool _isWordChar(String char) {
    return RegExp(r'[\w]').hasMatch(char);
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
            'Editor Selection',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'EditorSelection supports multiple cursors and selection ranges, '
            'with anchor (start) and head (end) positions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Document with visual selection
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document with Selection',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: SingleChildScrollView(
                          child: _buildHighlightedText(theme),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Selection controls
          Row(
            children: [
              Expanded(
                child: Card(
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
                          onChanged: (value) => _setCursor(value.toInt()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          labels: RangeLabels(
                            '${_selection.main.from}',
                            '${_selection.main.to}',
                          ),
                          onChanged: (values) => _setRange(
                            values.start.toInt(),
                            values.end.toInt(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _selectWord,
                icon: const Icon(Icons.text_fields),
                label: const Text('Select Word'),
              ),
              FilledButton.tonalIcon(
                onPressed: _selectLine,
                icon: const Icon(Icons.wrap_text),
                label: const Text('Select Line'),
              ),
              OutlinedButton.icon(
                onPressed: _selectAll,
                icon: const Icon(Icons.select_all),
                label: const Text('Select All'),
              ),
              OutlinedButton.icon(
                onPressed: _addRange,
                icon: const Icon(Icons.add),
                label: const Text('Add Selection'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Selection info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selection Info',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    children: [
                      _buildInfoChip(
                        'Ranges',
                        '${_selection.ranges.length}',
                        Icons.layers,
                        theme,
                      ),
                      _buildInfoChip(
                        'Main Anchor',
                        '${_selection.main.anchor}',
                        Icons.anchor,
                        theme,
                      ),
                      _buildInfoChip(
                        'Main Head',
                        '${_selection.main.head}',
                        Icons.my_location,
                        theme,
                      ),
                      _buildInfoChip(
                        'Empty',
                        '${_selection.main.empty}',
                        Icons.check_box_outline_blank,
                        theme,
                      ),
                      if (!_selection.main.empty)
                        _buildInfoChip(
                          'Selected',
                          '"${_docContent.substring(_selection.main.from, _selection.main.to).replaceAll('\n', '↵').take(20)}..."',
                          Icons.format_quote,
                          theme,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(ThemeData theme) {
    final spans = <TextSpan>[];
    var lastEnd = 0;

    // Sort ranges by position
    final ranges = [..._selection.ranges]..sort((a, b) => a.from - b.from);

    for (final range in ranges) {
      // Text before selection
      if (range.from > lastEnd) {
        spans.add(TextSpan(
          text: _docContent.substring(lastEnd, range.from),
        ));
      }

      // Selected text
      if (range.from < range.to) {
        spans.add(TextSpan(
          text: _docContent.substring(range.from, range.to),
          style: TextStyle(
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        ));
      }

      // Cursor indicator
      if (range.empty) {
        spans.add(TextSpan(
          text: '│',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ));
      }

      lastEnd = range.to;
    }

    // Remaining text
    if (lastEnd < _docContent.length) {
      spans.add(TextSpan(
        text: _docContent.substring(lastEnd),
      ));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: theme.colorScheme.onSurface,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildInfoChip(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text('$label: $value'),
    );
  }
}

extension TakeString on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
