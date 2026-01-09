import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';

/// Demonstrates the Hover Tooltip system for LSP-style hover information.
class HoverTooltipDemo extends StatefulWidget {
  const HoverTooltipDemo({super.key});

  @override
  State<HoverTooltipDemo> createState() => _HoverTooltipDemoState();
}

class _HoverTooltipDemoState extends State<HoverTooltipDemo> {
  late EditorState _state;
  final _editorKey = GlobalKey<EditorViewState>();
  
  bool _enableMarkdown = true;
  bool _enableTypeInfo = true;
  bool _enableDocumentation = true;
  int _hoverDelay = 300;

  final String _sampleCode = '''// Hover over symbols to see type info and docs
interface User {
  id: number;
  name: string;
  email: string;
  createdAt: Date;
}

function greet(user: User): string {
  const message = `Hello, \${user.name}!`;
  console.log(message);
  return message;
}

const users: User[] = [
  { id: 1, name: "Alice", email: "alice@example.com", createdAt: new Date() },
  { id: 2, name: "Bob", email: "bob@example.com", createdAt: new Date() },
];

// Process each user
users.forEach((user) => {
  greet(user);
});
''';

  // Simulated symbol database (like what an LSP would provide)
  final Map<String, _SymbolInfo> _symbolDatabase = {
    'User': _SymbolInfo(
      kind: 'interface',
      type: 'interface User',
      documentation: '''A user entity representing a registered user in the system.

## Properties
- `id`: Unique identifier
- `name`: Display name
- `email`: Contact email
- `createdAt`: Registration timestamp''',
    ),
    'id': _SymbolInfo(
      kind: 'property',
      type: 'number',
      documentation: 'Unique identifier for the user.',
    ),
    'name': _SymbolInfo(
      kind: 'property',
      type: 'string',
      documentation: 'Display name of the user.',
    ),
    'email': _SymbolInfo(
      kind: 'property',
      type: 'string',
      documentation: 'Contact email address.',
    ),
    'createdAt': _SymbolInfo(
      kind: 'property',
      type: 'Date',
      documentation: 'Timestamp when the user was registered.',
    ),
    'greet': _SymbolInfo(
      kind: 'function',
      type: '(user: User) => string',
      documentation: '''Generates a greeting message for the given user.

## Parameters
- `user`: The user to greet

## Returns
A greeting string in the format "Hello, {name}!"''',
    ),
    'message': _SymbolInfo(
      kind: 'const',
      type: 'string',
      documentation: 'The formatted greeting message.',
    ),
    'users': _SymbolInfo(
      kind: 'const',
      type: 'User[]',
      documentation: 'Array of registered users.',
    ),
    'console': _SymbolInfo(
      kind: 'object',
      type: 'Console',
      documentation: '''The console object provides access to the browser\'s debugging console.

Common methods:
- `log()`: Outputs a message
- `error()`: Outputs an error
- `warn()`: Outputs a warning''',
    ),
    'log': _SymbolInfo(
      kind: 'method',
      type: '(...data: any[]) => void',
      documentation: 'Outputs a message to the console.',
    ),
    'forEach': _SymbolInfo(
      kind: 'method',
      type: '(callback: (value: T) => void) => void',
      documentation: 'Calls the provided function once for each element in the array.',
    ),
    'Date': _SymbolInfo(
      kind: 'class',
      type: 'DateConstructor',
      documentation: '''Represents a single moment in time in a platform-independent format.

## Constructor
- `new Date()`: Current date/time
- `new Date(value)`: From timestamp
- `new Date(dateString)`: From ISO string''',
    ),
    'string': _SymbolInfo(
      kind: 'type',
      type: 'string',
      documentation: 'Primitive type representing textual data.',
    ),
    'number': _SymbolInfo(
      kind: 'type',
      type: 'number',
      documentation: 'Primitive type representing numeric values (64-bit floating point).',
    ),
  };

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
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(typescript: true)),
          syntaxHighlighting(defaultHighlightStyle),
          // Register our custom hover tooltip source
          hoverTooltip(
            _hoverSource,
            HoverTooltipOptions(hoverTime: _hoverDelay),
          ),
        ]),
      ),
    );
  }

  /// Hover tooltip source - simulates an LSP hover request.
  Future<HoverTooltip?> _hoverSource(EditorState state, int pos, int side) async {
    // Simulate network delay (like a real LSP request)
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Get the word at position
    final doc = state.doc.toString();
    if (pos >= doc.length) return null;
    
    // Find word boundaries
    var start = pos;
    var end = pos;
    
    while (start > 0 && _isWordChar(doc[start - 1])) {
      start--;
    }
    while (end < doc.length && _isWordChar(doc[end])) {
      end++;
    }
    
    if (start == end) return null;
    
    final word = doc.substring(start, end);
    final info = _symbolDatabase[word];
    
    if (info == null) return null;
    
    // Build tooltip content
    final buffer = StringBuffer();
    
    if (_enableTypeInfo) {
      buffer.writeln('```typescript');
      buffer.writeln('(${info.kind}) ${info.type}');
      buffer.writeln('```');
    }
    
    if (_enableDocumentation && info.documentation.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(info.documentation);
    }
    
    if (buffer.isEmpty) return null;
    
    return _enableMarkdown
        ? createMarkdownTooltip(
            pos: start,
            end: end,
            content: buffer.toString(),
          )
        : createTextTooltip(
            pos: start,
            end: end,
            content: buffer.toString().replaceAll('```typescript\n', '').replaceAll('```', ''),
          );
  }

  bool _isWordChar(String char) {
    return RegExp(r'[a-zA-Z0-9_$]').hasMatch(char);
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
            'Hover Tooltips',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Hover over symbols to see type information and documentation. '
            'This demonstrates the extensible hover tooltip system designed for LSP integration.',
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
                  Text('Tooltip Options', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Markdown'),
                        selected: _enableMarkdown,
                        onSelected: (v) {
                          setState(() {
                            _enableMarkdown = v;
                            _initEditor();
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Type Info'),
                        selected: _enableTypeInfo,
                        onSelected: (v) {
                          setState(() {
                            _enableTypeInfo = v;
                            _initEditor();
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Documentation'),
                        selected: _enableDocumentation,
                        onSelected: (v) {
                          setState(() {
                            _enableDocumentation = v;
                            _initEditor();
                          });
                        },
                      ),
                      const SizedBox(width: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Delay: ', style: theme.textTheme.bodySmall),
                          DropdownButton<int>(
                            value: _hoverDelay,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 100, child: Text('100ms')),
                              DropdownMenuItem(value: 300, child: Text('300ms')),
                              DropdownMenuItem(value: 500, child: Text('500ms')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _hoverDelay = v;
                                  _initEditor();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Try hovering over: User, greet, message, users, console, forEach, Date, string, number',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

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

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LSP Integration', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'This demo simulates LSP hover responses. In a real integration, '
                    'the hover source would make textDocument/hover requests to a language server.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFeatureChip('Async sources', Icons.schedule, theme),
                      _buildFeatureChip('Markdown', Icons.text_format, theme),
                      _buildFeatureChip('Multiple sources', Icons.layers, theme),
                      _buildFeatureChip('Position tracking', Icons.gps_fixed, theme),
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

  Widget _buildFeatureChip(String label, IconData icon, ThemeData theme) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// Simulated symbol information (like LSP Hover response).
class _SymbolInfo {
  final String kind;
  final String type;
  final String documentation;

  const _SymbolInfo({
    required this.kind,
    required this.type,
    this.documentation = '',
  });
}
