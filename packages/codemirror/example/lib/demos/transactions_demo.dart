import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates transactions and state changes.
class TransactionsDemo extends StatefulWidget {
  const TransactionsDemo({super.key});

  @override
  State<TransactionsDemo> createState() => _TransactionsDemoState();
}

class _TransactionsDemoState extends State<TransactionsDemo> {
  late EditorState _state;
  final List<_TransactionRecord> _history = [];
  static final _userEvent = Annotation.define<String>();

  @override
  void initState() {
    super.initState();
    _state = EditorState.create(
      EditorStateConfig(doc: 'Hello, World!'),
    );
  }

  void _applyTransaction(String description, TransactionSpec spec) {
    final tr = _state.update([spec]);
    final newState = tr.state as EditorState;
    final record = _TransactionRecord(
      description: description,
      docChanged: tr.docChanged,
      selectionChanged: tr.selection != null,
      oldLength: _state.doc.length,
      newLength: newState.doc.length,
      effects: tr.effects.length,
    );

    setState(() {
      _state = newState;
      _history.insert(0, record);
      if (_history.length > 15) {
        _history.removeLast();
      }
    });
  }

  void _insertAtCursor() {
    _applyTransaction(
      'Insert " [INSERTED]" at cursor',
      _state.replaceSelection(' [INSERTED]'),
    );
  }

  void _deleteSelection() {
    if (_state.selection.main.empty) {
      // Delete character before cursor
      final pos = _state.selection.main.head;
      if (pos > 0) {
        _applyTransaction(
          'Delete char at ${pos - 1}',
          TransactionSpec(
            changes: ChangeSpec(from: pos - 1, to: pos),
            selection: EditorSelection.single(pos - 1),
          ),
        );
      }
    } else {
      _applyTransaction(
        'Delete selection',
        _state.replaceSelection(''),
      );
    }
  }

  void _moveCursor(int delta) {
    final newPos =
        (_state.selection.main.head + delta).clamp(0, _state.doc.length);
    _applyTransaction(
      'Move cursor to $newPos',
      TransactionSpec(
        selection: EditorSelection.single(newPos),
      ),
    );
  }

  void _replaceAll() {
    _applyTransaction(
      'Replace all content',
      TransactionSpec(
        changes: ChangeSpec(
          from: 0,
          to: _state.doc.length,
          insert: 'New content at ${DateTime.now().second}s',
        ),
        selection: EditorSelection.single(0),
        annotations: [_userEvent.of('replace.all')],
      ),
    );
  }

  void _multipleChanges() {
    // Insert at beginning and end
    _applyTransaction(
      'Multiple changes (begin + end)',
      TransactionSpec(
        changes: [
          ChangeSpec(from: 0, insert: '[START] '),
          ChangeSpec(from: _state.doc.length, insert: ' [END]'),
        ],
      ),
    );
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
            'Transactions',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Transactions are immutable state changes. They can contain '
            'document changes, selection changes, effects, and annotations.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Current state
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Current State',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Chip(
                        label: Text('Doc: ${_state.doc.length} chars'),
                        avatar: const Icon(Icons.description, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text('Cursor: ${_state.selection.main.head}'),
                        avatar: const Icon(Icons.my_location, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: _buildDocWithCursor(theme),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _insertAtCursor,
                icon: const Icon(Icons.add),
                label: const Text('Insert Text'),
              ),
              FilledButton.tonalIcon(
                onPressed: _deleteSelection,
                icon: const Icon(Icons.backspace),
                label: const Text('Delete'),
              ),
              OutlinedButton.icon(
                onPressed: () => _moveCursor(-1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Move Left'),
              ),
              OutlinedButton.icon(
                onPressed: () => _moveCursor(1),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Move Right'),
              ),
              OutlinedButton.icon(
                onPressed: _replaceAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Replace All'),
              ),
              OutlinedButton.icon(
                onPressed: _multipleChanges,
                icon: const Icon(Icons.layers),
                label: const Text('Multiple Changes'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Transaction history
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transaction History',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _history.isEmpty
                          ? Center(
                              child: Text(
                                'No transactions yet',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final record = _history[index];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    record.docChanged
                                        ? Icons.edit
                                        : Icons.touch_app,
                                    color: record.docChanged
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.secondary,
                                    size: 20,
                                  ),
                                  title: Text(
                                    record.description,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'Doc: ${record.oldLength}→${record.newLength} | '
                                    'Changed: ${record.docChanged} | '
                                    'Effects: ${record.effects}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: index == 0
                                      ? Chip(
                                          label: const Text('Latest'),
                                          labelStyle:
                                              const TextStyle(fontSize: 10),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        )
                                      : null,
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

  Widget _buildDocWithCursor(ThemeData theme) {
    final doc = _state.doc.toString();
    final cursor = _state.selection.main.head;

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: theme.colorScheme.onSurface,
        ),
        children: [
          TextSpan(text: doc.substring(0, cursor)),
          TextSpan(
            text: '│',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: doc.substring(cursor)),
        ],
      ),
    );
  }
}

class _TransactionRecord {
  final String description;
  final bool docChanged;
  final bool selectionChanged;
  final int oldLength;
  final int newLength;
  final int effects;

  _TransactionRecord({
    required this.description,
    required this.docChanged,
    required this.selectionChanged,
    required this.oldLength,
    required this.newLength,
    required this.effects,
  });
}
