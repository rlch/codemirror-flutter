import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' as cm;

/// Demonstrates the B-tree based immutable document model.
class DocumentDemo extends StatefulWidget {
  const DocumentDemo({super.key});

  @override
  State<DocumentDemo> createState() => _DocumentDemoState();
}

class _DocumentDemoState extends State<DocumentDemo> {
  late cm.Text _doc;
  final List<String> _operations = [];
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _doc = cm.Text.of(['Hello, World!', 'This is CodeMirror for Flutter.', 'Line 3']);
    _logOperation('Created document with ${_doc.lines} lines, ${_doc.length} characters');
  }

  void _logOperation(String op) {
    setState(() {
      _operations.insert(0, '[$_version] $op');
      _version++;
      if (_operations.length > 20) {
        _operations.removeLast();
      }
    });
  }

  void _insertText() {
    final pos = _doc.length ~/ 2;
    final newDoc = _doc.replace(pos, pos, cm.Text.of(['[INSERTED]']));
    setState(() => _doc = newDoc);
    _logOperation('Inserted text at position $pos');
  }

  void _deleteText() {
    if (_doc.length < 10) return;
    final from = 5;
    final to = 10;
    final newDoc = _doc.replace(from, to, cm.Text.empty);
    setState(() => _doc = newDoc);
    _logOperation('Deleted characters $from-$to');
  }

  void _appendLine() {
    final newLine = 'Line ${_doc.lines + 1} added at ${DateTime.now().second}s';
    final newDoc = _doc.replace(_doc.length, _doc.length, cm.Text.of(['\n$newLine']));
    setState(() => _doc = newDoc);
    _logOperation('Appended new line');
  }

  void _getLineInfo() {
    final lineNum = 1;
    final line = _doc.line(lineNum);
    _logOperation('Line $lineNum: from=${line.from}, to=${line.to}, text="${line.text}"');
  }

  void _sliceDoc() {
    final from = 0;
    final to = (_doc.length / 2).round();
    final slice = _doc.sliceString(from, to);
    _logOperation('Slice [0-$to]: "$slice"');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Document Model (Text)',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'The Text class provides immutable B-tree based document storage '
            'with O(log n) operations for efficient editing of large documents.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Document display
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Document Content',
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Chip(
                          label: Text('${_doc.lines} lines'),
                          avatar: const Icon(Icons.list, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text('${_doc.length} chars'),
                          avatar: const Icon(Icons.text_fields, size: 16),
                        ),
                      ],
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
                          child: SelectableText(
                            _doc.toString(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Operations
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _insertText,
                icon: const Icon(Icons.add),
                label: const Text('Insert Text'),
              ),
              FilledButton.tonalIcon(
                onPressed: _deleteText,
                icon: const Icon(Icons.remove),
                label: const Text('Delete Text'),
              ),
              OutlinedButton.icon(
                onPressed: _appendLine,
                icon: const Icon(Icons.wrap_text),
                label: const Text('Append Line'),
              ),
              OutlinedButton.icon(
                onPressed: _getLineInfo,
                icon: const Icon(Icons.info_outline),
                label: const Text('Get Line Info'),
              ),
              OutlinedButton.icon(
                onPressed: _sliceDoc,
                icon: const Icon(Icons.content_cut),
                label: const Text('Slice Document'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Operation log
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operation Log',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _operations.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _operations[index],
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: index == 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
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
}
