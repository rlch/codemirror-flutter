import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates the EditorView widget with basic text editing.
class BasicEditorDemo extends StatefulWidget {
  const BasicEditorDemo({super.key});

  @override
  State<BasicEditorDemo> createState() => _BasicEditorDemoState();
}

class _BasicEditorDemoState extends State<BasicEditorDemo> {
  late EditorState _state;
  final List<String> _updateLog = [];
  bool _readOnly = false;
  bool _showPlaceholder = true;
  bool _highlightActiveLine = true;

  final String _sampleCode = '''// Welcome to CodeMirror for Flutter!
// This is a native Dart port, NOT a JS wrapper.

void main() {
  final editor = EditorView(
    state: EditorState.create(
      EditorStateConfig(
        doc: 'Hello, World!',
        extensions: [
          // Add extensions here
        ],
      ),
    ),
    onUpdate: (update) {
      if (update.docChanged) {
        print('Document changed!');
      }
    },
  );
}

// Built on top of Flutter's EditableText
// with immutable state management
''';

  @override
  void initState() {
    super.initState();
    _rebuildState();
  }

  void _rebuildState() {
    final extensions = <Extension>[];
    if (_showPlaceholder) {
      extensions.add(placeholder('Start typing your code here...'));
    }
    if (_highlightActiveLine) {
      extensions.add(highlightActiveLine());
    }

    _state = EditorState.create(
      EditorStateConfig(
        doc: _sampleCode,
        extensions: ExtensionList(extensions),
      ),
    );
  }

  void _handleUpdate(ViewUpdate update) {
    setState(() {
      _state = update.state;

      final changes = <String>[];
      if (update.docChanged) {
        changes.add('doc');
      }
      if (update.selectionSet) {
        changes.add('selection');
      }
      if (update.viewportChanged) {
        changes.add('viewport');
      }

      if (changes.isNotEmpty) {
        _updateLog.insert(
          0,
          '[${DateTime.now().second}s] Changed: ${changes.join(', ')}',
        );
        if (_updateLog.length > 10) {
          _updateLog.removeLast();
        }
      }
    });
  }

  void _insertText(String text) {
    final pos = _state.selection.main.head;
    final tr = _state.update([
      TransactionSpec(
        changes: ChangeSpec(from: pos, insert: text),
        selection: EditorSelection.single(pos + text.length),
      ),
    ]);
    setState(() => _state = tr.state as EditorState);
  }

  void _deleteSelection() {
    final sel = _state.selection.main;
    if (!sel.empty) {
      final tr = _state.update([
        TransactionSpec(
          changes: ChangeSpec(from: sel.from, to: sel.to),
          selection: EditorSelection.single(sel.from),
        ),
      ]);
      setState(() => _state = tr.state as EditorState);
    }
  }

  void _selectAll() {
    final tr = _state.update([
      TransactionSpec(
        selection: EditorSelection.single(0, _state.doc.length),
      ),
    ]);
    setState(() => _state = tr.state as EditorState);
  }

  void _goToLine(int lineNumber) {
    if (lineNumber > 0 && lineNumber <= _state.doc.lines) {
      final line = _state.doc.line(lineNumber);
      final tr = _state.update([
        TransactionSpec(
          selection: EditorSelection.single(line.from),
        ),
      ]);
      setState(() => _state = tr.state as EditorState);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _state.selection.main;
    final currentLine = _state.doc.lineAt(sel.head);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Basic Editor',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'EditorView is the main Flutter widget for rendering the code editor. '
            'It handles text input, selection, and dispatches transactions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Toolbar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Status info
                  Chip(
                    avatar: const Icon(Icons.text_fields, size: 16),
                    label: Text('${_state.doc.length} chars'),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: const Icon(Icons.list, size: 16),
                    label: Text('${_state.doc.lines} lines'),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: const Icon(Icons.my_location, size: 16),
                    label: Text('Ln ${currentLine.number}, Col ${sel.head - currentLine.from + 1}'),
                  ),
                  if (!sel.empty) ...[
                    const SizedBox(width: 8),
                    Chip(
                      avatar: const Icon(Icons.select_all, size: 16),
                      label: Text('${sel.to - sel.from} selected'),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  ],
                  const Spacer(),

                  // Feature toggles
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Active Line'),
                      Switch(
                        value: _highlightActiveLine,
                        onChanged: (v) => setState(() {
                          _highlightActiveLine = v;
                          _rebuildState();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Read-only'),
                      Switch(
                        value: _readOnly,
                        onChanged: (v) => setState(() => _readOnly = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Editor
          Expanded(
            flex: 3,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Mini toolbar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          tooltip: 'Insert text',
                          onPressed: () => _insertText(' /* comment */ '),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          tooltip: 'Delete selection',
                          onPressed: sel.empty ? null : _deleteSelection,
                        ),
                        IconButton(
                          icon: const Icon(Icons.select_all, size: 18),
                          tooltip: 'Select all',
                          onPressed: _selectAll,
                        ),
                        const VerticalDivider(),
                        _buildLineJumpButton(1, theme),
                        _buildLineJumpButton(5, theme),
                        _buildLineJumpButton(10, theme),
                        _buildLineJumpButton(_state.doc.lines, theme),
                      ],
                    ),
                  ),

                  // Editor content
                  Expanded(
                    child: EditorView(
                      state: _state,
                      onUpdate: _handleUpdate,
                      readOnly: _readOnly,
                      autofocus: true,
                      padding: const EdgeInsets.all(16),
                      // Use default style (JetBrainsMono with fixed line height)
                      cursorColor: theme.colorScheme.primary,
                      selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                      backgroundColor: theme.colorScheme.surface,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Update log
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
                          'ViewUpdate Log',
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() => _updateLog.clear()),
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _updateLog.isEmpty
                          ? Center(
                              child: Text(
                                'Edit the document to see updates',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _updateLog.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _updateLog[index],
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: index == 0
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildLineJumpButton(int line, ThemeData theme) {
    return TextButton(
      onPressed: () => _goToLine(line),
      child: Text(
        line == _state.doc.lines ? 'End' : 'Ln $line',
        style: TextStyle(fontSize: 12),
      ),
    );
  }
}
