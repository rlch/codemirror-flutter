/// Go to line command.
///
/// This module provides [gotoLine], a command that shows a dialog for
/// navigating to a specific line number.
library;

import 'package:flutter/material.dart';

import '../state/selection.dart';
import '../state/transaction.dart' hide Transaction;
import '../view/editor_view.dart';
import '../view/viewport.dart';

// ============================================================================
// Go to Line Command
// ============================================================================

/// Command that shows a dialog asking for a line number.
///
/// Supports:
/// - Line numbers (e.g., "42")
/// - Relative line offsets (e.g., "+5", "-3")
/// - Document percentages (e.g., "50%")
/// - Column positions (e.g., "42:10" for line 42, column 10)
bool gotoLine(EditorViewState view) {
  // EditorViewState extends State so it has a context
  if (!view.mounted) return false;
  final context = view.context;

  final state = view.state;
  final currentLine = state.doc.lineAt(state.selection.main.head).number;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => _GotoLineDialog(
      view: view,
      initialLine: currentLine.toString(),
    ),
  );

  return true;
}

class _GotoLineDialog extends StatefulWidget {
  final EditorViewState view;
  final String initialLine;

  const _GotoLineDialog({
    required this.view,
    required this.initialLine,
  });

  @override
  State<_GotoLineDialog> createState() => _GotoLineDialogState();
}

class _GotoLineDialogState extends State<_GotoLineDialog> {
  late TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLine);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialLine.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final result = _parseInput(_controller.text);
    if (result == null) {
      setState(() => _error = 'Invalid line number');
      return;
    }

    final state = widget.view.state;
    final startLine = state.doc.lineAt(state.selection.main.head);

    var (sign, lineNum, col, percent) = result;

    // Calculate line number
    int line;
    if (lineNum != null) {
      if (percent) {
        var pc = lineNum / 100;
        if (sign != null) {
          pc = pc * (sign == '-' ? -1 : 1) + (startLine.number / state.doc.lines);
        }
        line = (state.doc.lines * pc).round();
      } else if (sign != null) {
        line = lineNum * (sign == '-' ? -1 : 1) + startLine.number;
      } else {
        line = lineNum;
      }
    } else {
      line = startLine.number;
    }

    // Clamp line to valid range
    line = line.clamp(1, state.doc.lines);

    // Get the target line and position
    final docLine = state.doc.line(line);
    final colOffset = col.clamp(0, docLine.length);
    final pos = docLine.from + colOffset;

    // Update selection
    final cursorRange = EditorSelection.cursor(pos);
    final selection = EditorSelection.single(pos);
    widget.view.dispatch([
      TransactionSpec(
        selection: selection,
        effects: [
          EditorView.scrollIntoView.of(ScrollTarget(
            cursorRange,
            y: 'center',
          )),
        ],
      ),
    ]);

    Navigator.of(context).pop();
  }

  /// Parse input like "42", "+5", "-3", "50%", "42:10"
  (String? sign, int? line, int col, bool percent)? _parseInput(String value) {
    // Pattern: [+-]?[0-9]*[:col]?[%]?
    final match = RegExp(r'^([+-])?(\d+)?(:\d+)?(%)?$').firstMatch(value.trim());
    if (match == null) return null;

    final sign = match.group(1);
    final lineStr = match.group(2);
    final colStr = match.group(3);
    final percent = match.group(4) != null;

    final line = lineStr != null ? int.tryParse(lineStr) : null;
    final col = colStr != null ? int.tryParse(colStr.substring(1)) ?? 0 : 0;

    return (sign, line, col, percent);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to Line'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Line number',
              helperText: 'e.g., 42, +5, -3, 50%, 42:10',
              errorText: _error,
            ),
            keyboardType: TextInputType.text,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}
