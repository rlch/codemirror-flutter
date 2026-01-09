import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates the Facet system for type-safe extension points.
class FacetsDemo extends StatefulWidget {
  const FacetsDemo({super.key});

  @override
  State<FacetsDemo> createState() => _FacetsDemoState();
}

class _FacetsDemoState extends State<FacetsDemo> {
  late EditorState _state;
  final List<String> _log = [];

  // Define custom facets for demonstration
  static final tabSize = Facet.define<int, int>(
    FacetConfig(
      combine: (values) => values.isEmpty ? 4 : values.first,
    ),
  );

  static final indentUnit = Facet.define<String, String>(
    FacetConfig(
      combine: (values) => values.isEmpty ? '    ' : values.first,
    ),
  );

  static final lineWrapping = Facet.define<bool, bool>(
    FacetConfig(
      combine: (values) => values.isNotEmpty && values.any((v) => v),
    ),
  );

  static final editorTheme = Facet.define<String, List<String>>();

  @override
  void initState() {
    super.initState();
    _rebuildState([]);
    _log.add('Created state with default facet values');
  }

  void _rebuildState(List<Extension> extensions) {
    setState(() {
      _state = EditorState.create(
        EditorStateConfig(
          doc: 'function example() {\n  return 42;\n}',
          extensions: extensions.isEmpty ? null : ExtensionList(extensions),
        ),
      );
    });
  }

  void _addTabSize(int size) {
    _log.insert(0, 'Added tabSize.of($size)');
    _rebuildState([
      tabSize.of(size),
    ]);
    setState(() {});
  }

  void _addIndentUnit(String unit) {
    _log.insert(0, 'Added indentUnit.of("${unit.replaceAll(' ', '·')}")');
    _rebuildState([
      indentUnit.of(unit),
    ]);
    setState(() {});
  }

  void _addLineWrapping(bool enabled) {
    _log.insert(0, 'Added lineWrapping.of($enabled)');
    _rebuildState([
      lineWrapping.of(enabled),
    ]);
    setState(() {});
  }

  void _addMultipleThemes() {
    _log.insert(0, 'Added multiple theme values');
    _rebuildState([
      editorTheme.of('dark'),
      editorTheme.of('monokai'),
      editorTheme.of('custom'),
    ]);
    setState(() {});
  }

  void _addCombinedExtensions() {
    _log.insert(0, 'Added combined extensions (tabSize=2, indentUnit=2 spaces, lineWrapping=true)');
    _rebuildState([
      tabSize.of(2),
      indentUnit.of('  '),
      lineWrapping.of(true),
      editorTheme.of('dracula'),
    ]);
    setState(() {});
  }

  void _resetToDefaults() {
    _log.insert(0, 'Reset to default values');
    _rebuildState([]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Read current facet values
    final currentTabSize = _state.facet(tabSize);
    final currentIndentUnit = _state.facet(indentUnit);
    final currentLineWrapping = _state.facet(lineWrapping);
    final currentThemes = _state.facet(editorTheme);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facets',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Facets are type-safe extension points that aggregate values from multiple sources. '
            'They enable configuration and customization without tight coupling.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Current facet values
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Facet Values',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildFacetCard(
                        'tabSize',
                        currentTabSize.toString(),
                        Icons.space_bar,
                        theme,
                        'Combines by taking first value, default: 4',
                      ),
                      _buildFacetCard(
                        'indentUnit',
                        '"${currentIndentUnit.replaceAll(' ', '·')}"',
                        Icons.format_indent_increase,
                        theme,
                        'Combines by taking first value, default: 4 spaces',
                      ),
                      _buildFacetCard(
                        'lineWrapping',
                        currentLineWrapping.toString(),
                        Icons.wrap_text,
                        theme,
                        'Combines with OR logic, default: false',
                      ),
                      _buildFacetCard(
                        'editorTheme',
                        currentThemes.isEmpty
                            ? '[]'
                            : currentThemes.toString(),
                        Icons.palette,
                        theme,
                        'List facet - collects all values',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Text(
            'Configure Facets',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _addTabSize(2),
                icon: const Icon(Icons.looks_two),
                label: const Text('Tab Size = 2'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _addTabSize(8),
                icon: const Icon(Icons.looks_one),
                label: const Text('Tab Size = 8'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addIndentUnit('\t'),
                icon: const Icon(Icons.keyboard_tab),
                label: const Text('Indent = Tab'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addLineWrapping(true),
                icon: const Icon(Icons.wrap_text),
                label: const Text('Line Wrap = On'),
              ),
              OutlinedButton.icon(
                onPressed: _addMultipleThemes,
                icon: const Icon(Icons.layers),
                label: const Text('Multiple Themes'),
              ),
              FilledButton.icon(
                onPressed: _addCombinedExtensions,
                icon: const Icon(Icons.settings),
                label: const Text('Combined Config'),
              ),
              TextButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFacetCard(
    String name,
    String value,
    IconData icon,
    ThemeData theme,
    String description,
  ) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
