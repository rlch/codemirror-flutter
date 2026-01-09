import 'package:flutter/material.dart';

/// Demonstrates the Decoration system for styling document content.
class DecorationsDemo extends StatefulWidget {
  const DecorationsDemo({super.key});

  @override
  State<DecorationsDemo> createState() => _DecorationsDemoState();
}

class _DecorationsDemoState extends State<DecorationsDemo> {
  final String _sampleCode = '''function greet(name) {
  // This is a comment
  const message = "Hello, " + name;
  console.log(message);
  return true;
}

// TODO: Add error handling
const result = greet("World");''';

  // Track which decoration types are enabled
  bool _showKeywords = true;
  bool _showStrings = true;
  bool _showComments = true;
  bool _showTodo = true;
  bool _showLineHighlight = false;
  int _highlightedLine = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Build decorations based on enabled types
    final activeDecorations = _buildDecorations(theme);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decorations',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Decorations add visual styling to document content: mark decorations for '
            'inline styles, line decorations for line backgrounds, and widget decorations '
            'for inline widgets.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Decoration toggles
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Decoration Types',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildToggle('Keywords', _showKeywords, (v) {
                        setState(() => _showKeywords = v);
                      }, Colors.purple, theme),
                      _buildToggle('Strings', _showStrings, (v) {
                        setState(() => _showStrings = v);
                      }, Colors.green, theme),
                      _buildToggle('Comments', _showComments, (v) {
                        setState(() => _showComments = v);
                      }, Colors.grey, theme),
                      _buildToggle('TODO markers', _showTodo, (v) {
                        setState(() => _showTodo = v);
                      }, Colors.orange, theme),
                      _buildToggle('Line highlight', _showLineHighlight, (v) {
                        setState(() => _showLineHighlight = v);
                      }, Colors.yellow, theme),
                    ],
                  ),
                  if (_showLineHighlight) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Highlight line: '),
                        Slider(
                          value: _highlightedLine.toDouble(),
                          min: 1,
                          max: _sampleCode.split('\n').length.toDouble(),
                          divisions: _sampleCode.split('\n').length - 1,
                          label: '$_highlightedLine',
                          onChanged: (v) {
                            setState(() => _highlightedLine = v.round());
                          },
                        ),
                        Text('$_highlightedLine'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Document with decorations
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Decorated Document',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: SingleChildScrollView(
                          child: _buildDecoratedText(activeDecorations, theme),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Active decorations list
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Active Decorations',
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Chip(
                          label: Text('${activeDecorations.length} decorations'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: activeDecorations.length,
                        itemBuilder: (context, index) {
                          final dec = activeDecorations[index];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: dec.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(
                              dec.type,
                              style: const TextStyle(fontSize: 12),
                            ),
                            subtitle: Text(
                              '${dec.from}-${dec.to}: "${dec.text.length > 20 ? '${dec.text.substring(0, 20)}...' : dec.text}"',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    String label,
    bool value,
    void Function(bool) onChanged,
    Color color,
    ThemeData theme,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? color.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? color : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: value
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: value ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: value ? color : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  List<_DecorationInfo> _buildDecorations(ThemeData theme) {
    final decorations = <_DecorationInfo>[];

    // Keywords
    if (_showKeywords) {
      final keywords = ['function', 'const', 'return', 'true'];
      for (final keyword in keywords) {
        var pos = 0;
        while (true) {
          final idx = _sampleCode.indexOf(keyword, pos);
          if (idx == -1) break;
          // Check word boundary
          final before = idx > 0 ? _sampleCode[idx - 1] : ' ';
          final after = idx + keyword.length < _sampleCode.length
              ? _sampleCode[idx + keyword.length]
              : ' ';
          if (!RegExp(r'\w').hasMatch(before) && !RegExp(r'\w').hasMatch(after)) {
            decorations.add(_DecorationInfo(
              type: 'Mark: keyword',
              from: idx,
              to: idx + keyword.length,
              text: keyword,
              color: Colors.purple,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ));
          }
          pos = idx + 1;
        }
      }
    }

    // Strings
    if (_showStrings) {
      final regex = RegExp(r'"[^"]*"');
      for (final match in regex.allMatches(_sampleCode)) {
        decorations.add(_DecorationInfo(
          type: 'Mark: string',
          from: match.start,
          to: match.end,
          text: match.group(0)!,
          color: Colors.green,
          style: const TextStyle(color: Colors.green),
        ));
      }
    }

    // Comments
    if (_showComments) {
      final regex = RegExp(r'//.*$', multiLine: true);
      for (final match in regex.allMatches(_sampleCode)) {
        decorations.add(_DecorationInfo(
          type: 'Mark: comment',
          from: match.start,
          to: match.end,
          text: match.group(0)!,
          color: Colors.grey,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ));
      }
    }

    // TODO markers (widget-like highlight)
    if (_showTodo) {
      final regex = RegExp(r'TODO:', caseSensitive: false);
      for (final match in regex.allMatches(_sampleCode)) {
        decorations.add(_DecorationInfo(
          type: 'Mark: TODO',
          from: match.start,
          to: match.end,
          text: match.group(0)!,
          color: Colors.orange,
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x30FFA500),
          ),
        ));
      }
    }

    // Line highlight
    if (_showLineHighlight) {
      final lines = _sampleCode.split('\n');
      var pos = 0;
      for (var i = 0; i < lines.length; i++) {
        if (i + 1 == _highlightedLine) {
          decorations.add(_DecorationInfo(
            type: 'Line: highlight',
            from: pos,
            to: pos + lines[i].length,
            text: 'Line $_highlightedLine',
            color: Colors.yellow,
            style: null,
            isLine: true,
          ));
          break;
        }
        pos += lines[i].length + 1; // +1 for newline
      }
    }

    // Sort by position
    decorations.sort((a, b) => a.from - b.from);

    return decorations;
  }

  Widget _buildDecoratedText(List<_DecorationInfo> decorations, ThemeData theme) {
    final lines = _sampleCode.split('\n');
    final widgets = <Widget>[];

    var charPos = 0;
    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      final lineStart = charPos;
      final lineEnd = charPos + line.length;

      // Check for line decoration
      final lineDecoration = decorations.firstWhere(
        (d) => d.isLine && d.from >= lineStart && d.from < lineEnd,
        orElse: () => _DecorationInfo(
          type: '',
          from: 0,
          to: 0,
          text: '',
          color: Colors.transparent,
          style: null,
        ),
      );

      // Build text spans for this line
      final spans = <TextSpan>[];
      var pos = lineStart;

      for (final dec in decorations) {
        if (dec.isLine) continue;
        if (dec.to <= lineStart) continue;
        if (dec.from >= lineEnd) break;

        // Text before decoration
        if (dec.from > pos && dec.from <= lineEnd) {
          spans.add(TextSpan(
            text: _sampleCode.substring(pos, dec.from.clamp(pos, lineEnd)),
          ));
        }

        // Decorated text
        final decStart = dec.from.clamp(lineStart, lineEnd);
        final decEnd = dec.to.clamp(lineStart, lineEnd);
        if (decStart < decEnd) {
          spans.add(TextSpan(
            text: _sampleCode.substring(decStart, decEnd),
            style: dec.style,
          ));
        }

        pos = dec.to.clamp(lineStart, lineEnd);
      }

      // Remaining text
      if (pos < lineEnd) {
        spans.add(TextSpan(
          text: _sampleCode.substring(pos, lineEnd),
        ));
      }

      // Build line widget
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: lineDecoration.color != Colors.transparent
            ? BoxDecoration(
                color: lineDecoration.color.withValues(alpha: 0.3),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line number
            SizedBox(
              width: 30,
              child: Text(
                '${lineIdx + 1}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // Line content
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                  children: spans.isEmpty ? [TextSpan(text: line)] : spans,
                ),
              ),
            ),
          ],
        ),
      ));

      charPos = lineEnd + 1; // +1 for newline
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _DecorationInfo {
  final String type;
  final int from;
  final int to;
  final String text;
  final Color color;
  final TextStyle? style;
  final bool isLine;

  _DecorationInfo({
    required this.type,
    required this.from,
    required this.to,
    required this.text,
    required this.color,
    required this.style,
    this.isLine = false,
  });
}
