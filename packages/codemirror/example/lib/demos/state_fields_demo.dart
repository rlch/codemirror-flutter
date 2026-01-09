import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates StateField for persistent state attached to the editor.
class StateFieldsDemo extends StatefulWidget {
  const StateFieldsDemo({super.key});

  @override
  State<StateFieldsDemo> createState() => _StateFieldsDemoState();
}

// Define state effects for our counter
final incrementEffect = StateEffect.define<int>();
final decrementEffect = StateEffect.define<int>();
final resetEffect = StateEffect.define<void>();

// Define a state field that tracks a counter
final counterField = StateField.define<int>(
  StateFieldConfig(
    create: (_) => 0,
    update: (value, tr) {
      var result = value;
      for (final effect in (tr as Transaction).effects) {
        if (effect.is_(incrementEffect)) {
          result += effect.value as int;
        } else if (effect.is_(decrementEffect)) {
          result -= effect.value as int;
        } else if (effect.is_(resetEffect)) {
          result = 0;
        }
      }
      return result;
    },
  ),
);

// Define a state field that tracks edit count
final editCountField = StateField.define<int>(
  StateFieldConfig(
    create: (_) => 0,
    update: (value, tr) => tr.docChanged ? value + 1 : value,
  ),
);

// Define a state field that tracks character count history
final charCountHistoryField = StateField.define<List<int>>(
  StateFieldConfig(
    create: (state) => [(state as EditorState).doc.length],
    update: (history, tr) {
      if (tr.docChanged) {
        // Keep last 10 counts
        final newHistory = [...history, ((tr as Transaction).state as EditorState).doc.length];
        if (newHistory.length > 10) {
          newHistory.removeAt(0);
        }
        return newHistory;
      }
      return history;
    },
  ),
);

// Define a state field that tracks selection changes
final selectionHistoryField = StateField.define<List<String>>(
  StateFieldConfig(
    create: (_) => ['Initial: cursor at 0'],
    update: (history, tr) {
      if (tr.selection != null) {
        final sel = ((tr as Transaction).state as EditorState).selection.main;
        final desc = sel.empty
            ? 'Cursor at ${sel.head}'
            : 'Selection ${sel.from}-${sel.to}';
        final newHistory = [...history, desc];
        if (newHistory.length > 5) {
          newHistory.removeAt(0);
        }
        return newHistory;
      }
      return history;
    },
  ),
);

class _StateFieldsDemoState extends State<StateFieldsDemo> {
  late EditorState _state;

  @override
  void initState() {
    super.initState();
    _state = EditorState.create(
      EditorStateConfig(
        doc: 'Edit this text to see state fields update!',
        extensions: ExtensionList([
          counterField,
          editCountField,
          charCountHistoryField,
          selectionHistoryField,
        ]),
      ),
    );
  }

  void _dispatch(TransactionSpec spec) {
    final tr = _state.update([spec]);
    setState(() {
      _state = tr.state as EditorState;
    });
  }

  void _incrementCounter([int amount = 1]) {
    _dispatch(TransactionSpec(
      effects: [incrementEffect.of(amount)],
    ));
  }

  void _decrementCounter([int amount = 1]) {
    _dispatch(TransactionSpec(
      effects: [decrementEffect.of(amount)],
    ));
  }

  void _resetCounter() {
    _dispatch(TransactionSpec(
      effects: [resetEffect.of(null)],
    ));
  }

  void _insertText() {
    final pos = _state.selection.main.head;
    _dispatch(TransactionSpec(
      changes: ChangeSpec(from: pos, insert: '[NEW]'),
      selection: EditorSelection.single(pos + 5),
    ));
  }

  void _deleteText() {
    final sel = _state.selection.main;
    if (!sel.empty) {
      _dispatch(TransactionSpec(
        changes: ChangeSpec(from: sel.from, to: sel.to),
        selection: EditorSelection.single(sel.from),
      ));
    } else if (sel.head > 0) {
      _dispatch(TransactionSpec(
        changes: ChangeSpec(from: sel.head - 1, to: sel.head),
        selection: EditorSelection.single(sel.head - 1),
      ));
    }
  }

  void _moveSelection() {
    final newPos = (_state.selection.main.head + 5) % (_state.doc.length + 1);
    _dispatch(TransactionSpec(
      selection: EditorSelection.single(newPos),
    ));
  }

  void _selectRange() {
    final from = 0;
    final to = (_state.doc.length / 2).round();
    _dispatch(TransactionSpec(
      selection: EditorSelection.single(from, to),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Read field values
    final counter = _state.field(counterField) ?? 0;
    final editCount = _state.field(editCountField) ?? 0;
    final charHistory = _state.field(charCountHistoryField) ?? <int>[];
    final selHistory = _state.field(selectionHistoryField) ?? <String>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'State Fields',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'StateFields store persistent data in the editor state. They update '
            'in response to transactions and can react to document changes, '
            'selection changes, or custom StateEffects.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // State field values
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Counter field (effect-based)
              Expanded(
                child: _buildFieldCard(
                  title: 'Counter Field',
                  subtitle: 'Updated via StateEffects',
                  icon: Icons.add_circle_outline,
                  theme: theme,
                  content: Column(
                    children: [
                      Text(
                        counter.toString(),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filled(
                            onPressed: () => _decrementCounter(),
                            icon: const Icon(Icons.remove),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _resetCounter,
                            icon: const Icon(Icons.refresh),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () => _incrementCounter(),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _incrementCounter(10),
                        icon: const Icon(Icons.add),
                        label: const Text('+10'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Edit count field (doc-change based)
              Expanded(
                child: _buildFieldCard(
                  title: 'Edit Count Field',
                  subtitle: 'Increments on doc changes',
                  icon: Icons.edit_note,
                  theme: theme,
                  content: Column(
                    children: [
                      Text(
                        editCount.toString(),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _insertText,
                            icon: const Icon(Icons.add),
                            label: const Text('Insert'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _deleteText,
                            icon: const Icon(Icons.backspace),
                            label: const Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // History fields
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Char count history
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
                                Icons.show_chart,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Character Count History',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _buildCharHistoryChart(charHistory, theme),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Values: ${charHistory.join(' → ')}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Selection history
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
                                Icons.history,
                                color: theme.colorScheme.secondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Selection History',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _moveSelection,
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('Move +5'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _selectRange,
                                icon: const Icon(Icons.select_all),
                                label: const Text('Select Half'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              itemCount: selHistory.length,
                              itemBuilder: (context, index) {
                                final isLast = index == selHistory.length - 1;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isLast
                                            ? Icons.arrow_right
                                            : Icons.circle,
                                        size: isLast ? 20 : 8,
                                        color: isLast
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        selHistory[index],
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          fontWeight:
                                              isLast ? FontWeight.bold : null,
                                          color: isLast
                                              ? theme.colorScheme.onSurface
                                              : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
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
          ),

          const SizedBox(height: 16),

          // Document display
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Document',
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Chip(
                        label: Text('${_state.doc.length} chars'),
                        avatar: const Icon(Icons.text_fields, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text('Cursor: ${_state.selection.main.head}'),
                        avatar: const Icon(Icons.my_location, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _state.doc.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
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

  Widget _buildFieldCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeData theme,
    required Widget content,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildCharHistoryChart(List<int> history, ThemeData theme) {
    if (history.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final maxVal = history.reduce((a, b) => a > b ? a : b).toDouble();
    final minVal = history.reduce((a, b) => a < b ? a : b).toDouble();
    final range = maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _ChartPainter(
            values: history.map((v) => v.toDouble()).toList(),
            minVal: minVal,
            maxVal: maxVal,
            range: range,
            color: theme.colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final double range;
  final Color color;

  _ChartPainter({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.range,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;

    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalizedY = range > 0 ? (values[i] - minVal) / range : 0.5;
      final y = size.height - (normalizedY * size.height * 0.8 + size.height * 0.1);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      // Draw dot
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) {
    return values != oldDelegate.values;
  }
}
