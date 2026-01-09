import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

class AutocompleteDemo extends StatefulWidget {
  const AutocompleteDemo({super.key});

  @override
  State<AutocompleteDemo> createState() => _AutocompleteDemoState();
}

class _AutocompleteDemoState extends State<AutocompleteDemo> {
  late EditorState _state;
  String _status = 'Ready';

  static const _demoCode = '''// Autocomplete Demo
// Press Ctrl+Space to trigger completion
// Type "gup" to see fuzzy matching for "getUserProfile"

const user = getU

function handleUser() {
  const current = curr
  if (isL) {
    // Try typing "for" and pressing Enter for a snippet
    for
  }
}

class User {
  constructor(name) {
    this.name = name;
  }
}
''';

  static final _keywords = [
    Completion(label: 'if', type: 'keyword', detail: 'conditional'),
    Completion(label: 'else', type: 'keyword', detail: 'conditional'),
    Completion(label: 'for', type: 'keyword', detail: 'loop', apply: _forSnippet),
    Completion(label: 'while', type: 'keyword', detail: 'loop'),
    Completion(label: 'function', type: 'keyword', detail: 'declaration', apply: _functionSnippet),
    Completion(label: 'return', type: 'keyword', detail: 'statement'),
    Completion(label: 'const', type: 'keyword', detail: 'declaration'),
    Completion(label: 'let', type: 'keyword', detail: 'declaration'),
    Completion(label: 'var', type: 'keyword', detail: 'declaration'),
    Completion(label: 'class', type: 'keyword', detail: 'declaration'),
    Completion(label: 'extends', type: 'keyword', detail: 'inheritance'),
    Completion(label: 'import', type: 'keyword', detail: 'module'),
    Completion(label: 'export', type: 'keyword', detail: 'module'),
  ];

  static final _functions = [
    Completion(label: 'getUserProfile', type: 'function', detail: '(id: string) → User'),
    Completion(label: 'getUsers', type: 'function', detail: '() → User[]'),
    Completion(label: 'setUserRole', type: 'function', detail: '(id: string, role: string) → void'),
    Completion(label: 'deleteUser', type: 'function', detail: '(id: string) → boolean'),
    Completion(label: 'createUser', type: 'function', detail: '(data: UserData) → User'),
  ];

  static final _classes = [
    Completion(label: 'User', type: 'class', detail: 'User model'),
    Completion(label: 'UserService', type: 'class', detail: 'Service layer'),
    Completion(label: 'UserRepository', type: 'class', detail: 'Data access'),
  ];

  static final _variables = [
    Completion(label: 'currentUser', type: 'variable', detail: 'User | null'),
    Completion(label: 'userList', type: 'variable', detail: 'User[]'),
    Completion(label: 'isLoggedIn', type: 'variable', detail: 'boolean'),
  ];

  static void _forSnippet(dynamic view, Completion completion, int from, int to) {
    snippet('for (let \${1:i} = 0; \${1:i} < \${2:length}; \${1:i}++) {\n\t\${3:}\n}')(
      (state: (view as EditorViewState).state, dispatch: (tr) => view.dispatchTransaction(tr)),
      completion,
      from,
      to,
    );
  }

  static void _functionSnippet(dynamic view, Completion completion, int from, int to) {
    snippet('function \${1:name}(\${2:params}) {\n\t\${3:}\n}')(
      (state: (view as EditorViewState).state, dispatch: (tr) => view.dispatchTransaction(tr)),
      completion,
      from,
      to,
    );
  }

  static CompletionResult? _completionSource(CompletionContext context) {
    final word = context.matchBefore(RegExp(r'\w*'));
    if (word == null && !context.explicit) return null;

    return CompletionResult(
      from: word?.from ?? context.pos,
      options: [
        ..._keywords,
        ..._functions,
        ..._classes,
        ..._variables,
      ],
      validFor: RegExp(r'^\w*$'),
    );
  }

  @override
  void initState() {
    super.initState();
    ensureSnippetInitialized();
    _initState();
  }

  void _initState() {
    _state = EditorState.create(
      EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript(),
          syntaxHighlighting(defaultHighlightStyle),
          autocompletion(CompletionConfig(
            override: [_completionSource],
            activateOnTyping: true,
          )),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
        ]),
      ),
    );
  }

  void _handleUpdate(ViewUpdate update) {
    setState(() {
      _state = update.state;
      final status = completionStatus(_state);
      if (status == 'pending') {
        _status = 'Loading completions...';
      } else if (status == 'active') {
        final completions = currentCompletions(_state);
        final selected = selectedCompletion(_state);
        _status = '${completions.length} completions${selected != null ? ' • Selected: ${selected.label}' : ''}';
      } else {
        _status = 'Ready • Press Ctrl+Space to complete';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Autocompletion',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Fuzzy matching, type-based icons, snippet completions with tab stops.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _shortcutChip(context, 'Ctrl+Space', 'Trigger'),
              _shortcutChip(context, '↑/↓', 'Navigate'),
              _shortcutChip(context, 'Enter', 'Accept'),
              _shortcutChip(context, 'Escape', 'Close'),
              _shortcutChip(context, 'Tab', 'Next field'),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _typeChip(context, 'function', Icons.functions),
              _typeChip(context, 'class', Icons.class_),
              _typeChip(context, 'variable', Icons.data_object),
              _typeChip(context, 'keyword', Icons.key),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: Container(
            color: isDark
                ? HighlightTheme.darkBackground
                : HighlightTheme.lightBackground,
            child: EditorView(
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

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
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

  Widget _typeChip(BuildContext context, String type, IconData icon) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(type),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}
