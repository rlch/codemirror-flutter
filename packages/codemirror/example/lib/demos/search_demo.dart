import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' as cm hide Text;
import 'package:codemirror/codemirror.dart' hide Text;

/// Demo showcasing search and replace functionality.
class SearchDemo extends StatefulWidget {
  const SearchDemo({super.key});

  @override
  State<SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<SearchDemo> {
  final _editorKey = GlobalKey<EditorViewState>();
  late EditorState _state;

  static const _demoCode = '''// Search and Replace Demo
// Press Cmd/Ctrl+F to open search panel

function findAllMatches(text, pattern) {
  const matches = [];
  const regex = new RegExp(pattern, 'g');
  let match;
  
  while ((match = regex.exec(text)) !== null) {
    matches.push({
      index: match.index,
      value: match[0],
      groups: match.groups
    });
  }
  
  return matches;
}

function replaceAll(text, search, replacement) {
  return text.split(search).join(replacement);
}

// Example usage:
const text = "Hello world, hello universe, hello everyone!";
const pattern = "hello";

// Find all occurrences (case insensitive)
const results = findAllMatches(text.toLowerCase(), pattern);
console.log("Found", results.length, "matches");

// Replace all occurrences
const newText = replaceAll(text.toLowerCase(), pattern, "hi");
console.log("Result:", newText);
''';

  @override
  void initState() {
    super.initState();
    _state = EditorState.create(
      EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript(),
          syntaxHighlighting(defaultHighlightStyle),
          cm.search(),
          keymap.of(cm.searchKeymap),
          keymap.of(standardKeymap),
          allowMultipleSelections.of(true),
        ]),
      ),
    );
  }

  void _handleUpdate(ViewUpdate update) {
    setState(() {
      _state = update.state;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search & Replace',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Full-featured search with regex support, case sensitivity, '
                'whole word matching, and replace functionality.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Keyboard shortcuts info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _shortcutChip(context, 'Cmd/Ctrl+F', 'Open search'),
              _shortcutChip(context, 'F3 / Cmd+G', 'Find next'),
              _shortcutChip(context, 'Shift+F3', 'Find previous'),
              _shortcutChip(context, 'Escape', 'Close panel'),
              _shortcutChip(context, 'Cmd+Shift+L', 'Select all matches'),
            ],
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _openSearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Open Search Panel'),
              ),
              OutlinedButton.icon(
                onPressed: _selectAllMatches,
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Select All "hello"'),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Editor
        Expanded(
          child: Container(
            color: isDark
                ? HighlightTheme.darkBackground
                : HighlightTheme.lightBackground,
            child: EditorView(
              key: _editorKey,
              state: _state,
              onUpdate: _handleUpdate,
              autofocus: true,
              padding: const EdgeInsets.all(16),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? const Color(0xFFC9D1D9)
                    : const Color(0xFF24292F),
              ),
              cursorColor: theme.colorScheme.primary,
              selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              backgroundColor: isDark
                  ? HighlightTheme.darkBackground
                  : HighlightTheme.lightBackground,
              highlightTheme: isDark
                  ? HighlightTheme.dark
                  : HighlightTheme.light,
            ),
          ),
        ),
      ],
    );
  }

  Widget _shortcutChip(BuildContext context, String shortcut, String action) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          ),
          child: Text(
            shortcut,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          action,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  void _openSearch() {
    final view = _editorKey.currentState;
    if (view != null) {
      openSearchPanel(view);
    }
  }

  void _selectAllMatches() {
    final view = _editorKey.currentState;
    if (view == null) return;

    // First, select the word "hello"
    final doc = view.state.doc.toString();
    final firstMatch = doc.toLowerCase().indexOf('hello');
    if (firstMatch == -1) return;

    // Set selection to first "hello" - need to get the updated state after
    view.dispatch([
      TransactionSpec(
        selection: EditorSelection.single(firstMatch, firstMatch + 5),
      ),
    ]);

    // Use a post-frame callback to ensure state has been updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentView = _editorKey.currentState;
      if (currentView == null) return;
      
      // Now select all matches using the updated state
      selectSelectionMatches(
        currentView.state,
        (tr) => currentView.update([tr]),
      );
    });
  }
}
