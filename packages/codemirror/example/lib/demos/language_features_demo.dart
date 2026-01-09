import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates language features: indentation, bracket matching, and code folding.
class LanguageFeaturesDemo extends StatefulWidget {
  const LanguageFeaturesDemo({super.key});

  @override
  State<LanguageFeaturesDemo> createState() => _LanguageFeaturesDemoState();
}

class _LanguageFeaturesDemoState extends State<LanguageFeaturesDemo> {
  late EditorState _state;
  bool _bracketMatchingEnabled = true;
  bool _foldingEnabled = true;
  bool _indentOnInputEnabled = true;

  final String _sampleCode = '''// JavaScript Example with nested structures
function processData(items) {
  const results = items.map((item) => {
    if (item.value > 10) {
      return {
        id: item.id,
        processed: true,
        data: {
          original: item.value,
          doubled: item.value * 2,
          metadata: {
            timestamp: Date.now(),
            source: "processor"
          }
        }
      };
    }
    return { id: item.id, processed: false };
  });
  
  return results.filter((r) => r.processed);
}

class DataManager {
  constructor(config) {
    this.config = config;
    this.cache = new Map();
  }

  async fetchAll(ids) {
    const promises = ids.map((id) => {
      if (this.cache.has(id)) {
        return Promise.resolve(this.cache.get(id));
      }
      return this.fetch(id);
    });
    return Promise.all(promises);
  }

  fetch(id) {
    return fetch(`/api/data/` + id)
      .then((response) => response.json())
      .then((data) => {
        this.cache.set(id, data);
        return data;
      });
  }
}

// Array with nested brackets
const config = {
  settings: [
    { key: "theme", value: "dark" },
    { key: "fontSize", value: 14 },
    { key: "tabSize", value: 2 }
  ],
  features: {
    autoSave: true,
    linting: ["eslint", "prettier"]
  }
};
''';

  @override
  void initState() {
    super.initState();
    _initState();
  }

  void _initState() {
    final extensions = <Extension>[
      javascript().extension,
      syntaxHighlighting(defaultHighlightStyle),
      // Standard keymap for cursor movement, Enter with smart indent, etc.
      keymap.of(standardKeymap),
      // Enable Tab/Shift-Tab for indentation
      keymap.of([indentWithTab]),
    ];

    if (_bracketMatchingEnabled) {
      extensions.add(bracketMatching());
    }

    if (_foldingEnabled) {
      extensions.add(codeFolding());
      extensions.add(keymap.of(foldKeymap));
    }

    if (_indentOnInputEnabled) {
      extensions.add(indentOnInput());
    }

    _state = EditorState.create(
      EditorStateConfig(
        doc: _sampleCode,
        extensions: ExtensionList(extensions),
      ),
    );
  }

  void _toggleFeature(String feature, bool value) {
    setState(() {
      switch (feature) {
        case 'brackets':
          _bracketMatchingEnabled = value;
        case 'folding':
          _foldingEnabled = value;
        case 'indent':
          _indentOnInputEnabled = value;
      }
      _initState();
    });
  }

  void _handleUpdate(ViewUpdate update) {
    setState(() {
      _state = update.state;
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
          Text(
            'Language Features',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Demonstrates indentation, bracket matching, and code folding. '
            'Try placing your cursor near brackets, pressing Tab to indent, '
            'or using Ctrl+Shift+[ to fold code blocks.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Feature toggles
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Features',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    children: [
                      FilterChip(
                        label: const Text('Bracket Matching'),
                        selected: _bracketMatchingEnabled,
                        onSelected: (v) => _toggleFeature('brackets', v),
                      ),
                      FilterChip(
                        label: const Text('Code Folding'),
                        selected: _foldingEnabled,
                        onSelected: (v) => _toggleFeature('folding', v),
                      ),
                      FilterChip(
                        label: const Text('Auto Indent'),
                        selected: _indentOnInputEnabled,
                        onSelected: (v) => _toggleFeature('indent', v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keyboard shortcuts: Ctrl+Shift+[ fold, Ctrl+Shift+] unfold, '
                    'Ctrl+Alt+[ fold all, Ctrl+Alt+] unfold all',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Editor
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.code,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'example.js',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Chip(
                          avatar: const Icon(Icons.format_line_spacing, size: 16),
                          label: Text('Lines: ${_state.doc.lines}'),
                        ),
                      ],
                    ),
                  ),

                  // Editor content
                  Expanded(
                    child: EditorView(
                      state: _state,
                      onUpdate: _handleUpdate,
                      autofocus: true,
                      padding: const EdgeInsets.all(16),
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontFamilyFallback: const ['monospace'],
                        fontSize: 14,
                        height: 1.5,
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFE3E2E0)
                            : const Color(0xFF37352F),
                      ),
                      cursorColor: theme.colorScheme.primary,
                      selectionColor:
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? HighlightTheme.darkBackground
                          : HighlightTheme.lightBackground,
                      highlightTheme: theme.brightness == Brightness.dark
                          ? HighlightTheme.dark
                          : HighlightTheme.light,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FeatureCard(
                  icon: Icons.format_indent_increase,
                  title: 'Indentation',
                  description: 'Press Tab to indent, Shift+Tab to dedent. '
                      'New lines auto-indent based on context.',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _FeatureCard(
                  icon: Icons.data_array,
                  title: 'Bracket Matching',
                  description: 'Matching brackets highlight when cursor is nearby. '
                      'Works with (), [], and {}.',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _FeatureCard(
                  icon: Icons.unfold_less,
                  title: 'Code Folding',
                  description: 'Collapse/expand code blocks. '
                      'Folded regions show "…" placeholder.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
