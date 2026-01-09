import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';

/// Demonstrates the gutter system with line numbers, custom markers, and active line highlighting.
class GutterDemo extends StatefulWidget {
  const GutterDemo({super.key});

  @override
  State<GutterDemo> createState() => _GutterDemoState();
}

class _GutterDemoState extends State<GutterDemo> {
  late EditorState _state;
  final _editorKey = GlobalKey<EditorViewState>();

  final String _sampleCode = '''function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

// Calculate first 10 fibonacci numbers
const results = [];
for (let i = 0; i < 10; i++) {
  results.push(fibonacci(i));
}

console.log("Fibonacci sequence:", results);

// Alternative iterative approach
function fibIterative(n) {
  let a = 0, b = 1;
  for (let i = 0; i < n; i++) {
    [a, b] = [b, a + b];
  }
  return a;
}
''';

  // Options
  bool _showLineNumbers = true;
  bool _highlightActiveLine = true;
  bool _showBreakpoints = true;
  bool _showFoldMarkers = false;
  String _numberFormat = 'default';

  // Breakpoint lines (1-indexed for display)
  final Set<int> _breakpoints = {2, 8, 15};

  @override
  void initState() {
    super.initState();
    ensureStateInitialized();
    _initEditor();
  }

  void _initEditor() {
    _state = EditorState.create(
      EditorStateConfig(
        doc: _sampleCode,
        extensions: ExtensionList(_buildExtensions()),
      ),
    );
  }

  List<Extension> _buildExtensions() {
    final extensions = <Extension>[
      javascript(),
      syntaxHighlighting(defaultHighlightStyle),
    ];

    if (_showLineNumbers) {
      extensions.add(lineNumbers(LineNumberConfig(
        formatNumber: _getNumberFormatter(),
        eventHandlers: _showBreakpoints
            ? {
                'click': (context, line, pos) {
                  _toggleBreakpoint(line.from);
                  return true;
                },
              }
            : {},
      )));
    }

    if (_highlightActiveLine) {
      extensions.add(highlightActiveLineGutter());
      extensions.add(highlightActiveLine());
    }

    if (_showBreakpoints) {
      extensions.add(_breakpointGutter());
    }

    if (_showFoldMarkers) {
      extensions.add(_foldGutterExtension());
    }

    return extensions;
  }

  String Function(int, EditorState)? _getNumberFormatter() {
    switch (_numberFormat) {
      case 'hex':
        return (n, _) => '0x${n.toRadixString(16).toUpperCase().padLeft(2, '0')}';
      case 'padded':
        return (n, state) {
          final maxDigits = state.doc.lines.toString().length;
          return n.toString().padLeft(maxDigits, '0');
        };
      case 'roman':
        return (n, _) => _toRoman(n);
      default:
        return null;
    }
  }

  String _toRoman(int num) {
    if (num > 50) return num.toString(); // Fall back for large numbers
    const romanNumerals = [
      (50, 'L'), (40, 'XL'), (10, 'X'), (9, 'IX'),
      (5, 'V'), (4, 'IV'), (1, 'I'),
    ];
    var result = '';
    var n = num;
    for (final (value, symbol) in romanNumerals) {
      while (n >= value) {
        result += symbol;
        n -= value;
      }
    }
    return result;
  }

  void _toggleBreakpoint(int pos) {
    final lineNum = _state.doc.lineAt(pos).number;
    setState(() {
      if (_breakpoints.contains(lineNum)) {
        _breakpoints.remove(lineNum);
      } else {
        _breakpoints.add(lineNum);
      }
      _initEditor();
    });
  }

  Extension _breakpointGutter() {
    return gutter(GutterConfig(
      className: 'cm-breakpoint-gutter',
      markers: (state) {
        final builder = RangeSetBuilder<GutterMarker>();
        final sortedBreakpoints = _breakpoints.toList()..sort();
        for (final lineNum in sortedBreakpoints) {
          if (lineNum <= state.doc.lines) {
            final line = state.doc.line(lineNum);
            builder.add(line.from, line.from, _BreakpointMarker());
          }
        }
        return builder.finish();
      },
      lineMarker: (state, line, others) {
        // Show empty circle if no breakpoint
        if (others.isEmpty) {
          return _EmptyBreakpointMarker();
        }
        return null;
      },
    ));
  }

  Extension _foldGutterExtension() {
    // Use the real foldGutter() from fold.dart which integrates with syntax tree
    return foldGutter();
  }

  void _rebuildEditor() {
    setState(() {
      _initEditor();
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
          Text('Gutters', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Gutters display line numbers, breakpoints, fold markers, and other indicators '
            'alongside the editor content. Click line numbers to toggle breakpoints.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gutter Options', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Line Numbers'),
                        selected: _showLineNumbers,
                        onSelected: (v) {
                          _showLineNumbers = v;
                          _rebuildEditor();
                        },
                      ),
                      FilterChip(
                        label: const Text('Active Line'),
                        selected: _highlightActiveLine,
                        onSelected: (v) {
                          _highlightActiveLine = v;
                          _rebuildEditor();
                        },
                      ),
                      FilterChip(
                        label: const Text('Breakpoints'),
                        selected: _showBreakpoints,
                        onSelected: (v) {
                          _showBreakpoints = v;
                          _rebuildEditor();
                        },
                      ),
                      FilterChip(
                        label: const Text('Fold Markers'),
                        selected: _showFoldMarkers,
                        onSelected: (v) {
                          _showFoldMarkers = v;
                          _rebuildEditor();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Number Format:', style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'default', label: Text('Default')),
                          ButtonSegment(value: 'padded', label: Text('Padded')),
                          ButtonSegment(value: 'hex', label: Text('Hex')),
                          ButtonSegment(value: 'roman', label: Text('Roman')),
                        ],
                        selected: {_numberFormat},
                        onSelectionChanged: (v) {
                          _numberFormat = v.first;
                          _rebuildEditor();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Breakpoints info
          if (_showBreakpoints && _breakpoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  Text('Breakpoints:', style: theme.textTheme.labelMedium),
                  for (final bp in _breakpoints.toList()..sort())
                    Chip(
                      label: Text('Line $bp'),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        _breakpoints.remove(bp);
                        _rebuildEditor();
                      },
                      backgroundColor: Colors.red.shade100,
                      labelStyle: TextStyle(color: Colors.red.shade900),
                    ),
                ],
              ),
            ),

          // Editor
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: EditorView(
                  key: _editorKey,
                  state: _state,
                  onUpdate: (update) {
                    setState(() {
                      _state = update.state;
                    });
                  },
                  backgroundColor: theme.brightness == Brightness.dark
                      ? HighlightTheme.darkBackground
                      : HighlightTheme.lightBackground,
                  highlightTheme: theme.brightness == Brightness.dark
                      ? HighlightTheme.dark
                      : HighlightTheme.light,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Legend
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('Legend: ', style: theme.textTheme.labelMedium),
                  const SizedBox(width: 16),
                  _buildLegendItem(Icons.circle, Colors.red, 'Breakpoint', theme),
                  const SizedBox(width: 16),
                  _buildLegendItem(Icons.circle_outlined, Colors.grey, 'Click to add', theme),
                  const SizedBox(width: 16),
                  Container(
                    width: 24,
                    height: 16,
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 4),
                  Text('Active line', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Breakpoint marker (filled red circle).
class _BreakpointMarker extends GutterMarker {
  @override
  Widget? toWidget(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.circle, size: 12, color: Colors.red),
    );
  }

  @override
  String get elementClass => 'cm-breakpoint';
}

/// Empty breakpoint marker (hollow circle for click target).
class _EmptyBreakpointMarker extends GutterMarker {
  @override
  Widget? toWidget(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.circle_outlined, size: 12, color: Colors.grey.shade400),
    );
  }
}


