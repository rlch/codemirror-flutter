import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';

import 'demos/autocomplete_demo.dart';
import 'demos/basic_editor_demo.dart';
import 'demos/bidi_demo.dart';
import 'demos/decorations_demo.dart';
import 'demos/document_demo.dart';
import 'demos/facets_demo.dart';
import 'demos/gutter_demo.dart';
import 'demos/hover_tooltip_demo.dart';
import 'demos/keymap_demo.dart';
import 'demos/language_features_demo.dart';
import 'demos/lsp_demo.dart';
import 'demos/lint_demo.dart';
import 'demos/search_demo.dart';
import 'demos/selection_demo.dart';
import 'demos/selection_layer_demo.dart';
import 'demos/state_fields_demo.dart';
import 'demos/transactions_demo.dart';
import 'demos/view_plugins_demo.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();
  ensureFoldInitialized();
  ensureLintInitialized();
  runApp(const CodeMirrorExampleApp());
}

/// Main example app demonstrating CodeMirror for Flutter.
class CodeMirrorExampleApp extends StatelessWidget {
  const CodeMirrorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeMirror for Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DemoScaffold(),
    );
  }
}

/// Demo item for navigation.
class DemoItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
  final String category;

  const DemoItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
    required this.category,
  });
}

/// Main scaffold with sidebar navigation.
class DemoScaffold extends StatefulWidget {
  const DemoScaffold({super.key});

  @override
  State<DemoScaffold> createState() => _DemoScaffoldState();
}

class _DemoScaffoldState extends State<DemoScaffold> {
  int _selectedIndex = 0;

  static final List<DemoItem> _demos = [
    // Getting Started
    DemoItem(
      title: 'Basic Editor',
      subtitle: 'EditorView widget with text input',
      icon: Icons.edit,
      builder: () => const BasicEditorDemo(),
      category: 'Getting Started',
    ),
    DemoItem(
      title: 'Keymap & Input',
      subtitle: 'Key bindings and input handling',
      icon: Icons.keyboard,
      builder: () => const KeymapDemo(),
      category: 'Getting Started',
    ),

    // Language
    DemoItem(
      title: 'Language Features',
      subtitle: 'Indentation, bracket matching, folding',
      icon: Icons.layers,
      builder: () => const LanguageFeaturesDemo(),
      category: 'Language',
    ),
    DemoItem(
      title: 'Autocompletion',
      subtitle: 'Fuzzy matching, snippets, type icons',
      icon: Icons.auto_awesome,
      builder: () => const AutocompleteDemo(),
      category: 'Language',
    ),
    DemoItem(
      title: 'Lint Diagnostics',
      subtitle: 'Errors, warnings, hints with gutter markers',
      icon: Icons.bug_report,
      builder: () => const LintDemo(),
      category: 'Language',
    ),
    DemoItem(
      title: 'Hover Tooltips',
      subtitle: 'LSP-style hover with markdown support',
      icon: Icons.info_outline,
      builder: () => const HoverTooltipDemo(),
      category: 'Language',
    ),
    DemoItem(
      title: 'LSP Features',
      subtitle: 'Go to definition, rename, references, etc.',
      icon: Icons.psychology,
      builder: () => const LspDemo(),
      category: 'Language',
    ),

    // Editing
    DemoItem(
      title: 'Selection',
      subtitle: 'Multiple cursors and selection ranges',
      icon: Icons.select_all,
      builder: () => const SelectionDemo(),
      category: 'Editing',
    ),
    DemoItem(
      title: 'Search & Replace',
      subtitle: 'Find, replace, regex, select all matches',
      icon: Icons.search,
      builder: () => const SearchDemo(),
      category: 'Editing',
    ),
    DemoItem(
      title: 'Bidirectional Text',
      subtitle: 'RTL/LTR mixed text support',
      icon: Icons.format_textdirection_r_to_l,
      builder: () => const BidiDemo(),
      category: 'Editing',
    ),

    // Customization
    DemoItem(
      title: 'Decorations',
      subtitle: 'Styling, widgets, and replacements',
      icon: Icons.format_paint,
      builder: () => const DecorationsDemo(),
      category: 'Customization',
    ),
    DemoItem(
      title: 'Gutters',
      subtitle: 'Line numbers, breakpoints, markers',
      icon: Icons.format_list_numbered,
      builder: () => const GutterDemo(),
      category: 'Customization',
    ),
    DemoItem(
      title: 'Selection Layer',
      subtitle: 'Custom cursor and selection rendering',
      icon: Icons.highlight_alt,
      builder: () => const SelectionLayerDemo(),
      category: 'Customization',
    ),
    DemoItem(
      title: 'View Plugins',
      subtitle: 'Extend the view layer',
      icon: Icons.widgets,
      builder: () => const ViewPluginsDemo(),
      category: 'Customization',
    ),

    // Internals
    DemoItem(
      title: 'Document Model',
      subtitle: 'B-tree based immutable text storage',
      icon: Icons.description,
      builder: () => const DocumentDemo(),
      category: 'Internals',
    ),
    DemoItem(
      title: 'Transactions',
      subtitle: 'Immutable state changes with annotations',
      icon: Icons.swap_horiz,
      builder: () => const TransactionsDemo(),
      category: 'Internals',
    ),
    DemoItem(
      title: 'Facets',
      subtitle: 'Type-safe extension points',
      icon: Icons.extension,
      builder: () => const FacetsDemo(),
      category: 'Internals',
    ),
    DemoItem(
      title: 'State Fields',
      subtitle: 'Persistent state attached to editor',
      icon: Icons.storage,
      builder: () => const StateFieldsDemo(),
      category: 'Internals',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeMirror for Flutter'),
        leading: isWide
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'View source',
            onPressed: () => _showSourceInfo(context),
          ),
        ],
      ),
      drawer: isWide ? null : _buildDrawer(),
      body: Row(
        children: [
          if (isWide) _buildSidebar(),
          Expanded(
            child: _demos[_selectedIndex].builder(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: _buildNavList(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'CodeMirror',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: _buildNavList()),
          ],
        ),
      ),
    );
  }

  Widget _buildNavList() {
    String? currentCategory;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _demos.length,
      itemBuilder: (context, index) {
        final demo = _demos[index];
        final showHeader = demo.category != currentCategory;
        currentCategory = demo.category;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              if (index > 0) const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  demo.category,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            ListTile(
              leading: Icon(demo.icon),
              title: Text(demo.title),
              subtitle: Text(
                demo.subtitle,
                style: const TextStyle(fontSize: 12),
              ),
              selected: _selectedIndex == index,
              selectedTileColor:
                  Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () {
                setState(() => _selectedIndex = index);
                if (Scaffold.of(context).isDrawerOpen) {
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showSourceInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About CodeMirror for Flutter'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A native Dart/Flutter port of CodeMirror 6',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('This is NOT a JavaScript wrapper - it\'s a complete '
                'from-scratch implementation using Flutter\'s EditableText '
                'as the low-level foundation.'),
            SizedBox(height: 16),
            Text('Features:'),
            SizedBox(height: 8),
            Text('• B-tree immutable text storage'),
            Text('• Facet-based state management'),
            Text('• Lezer incremental parsing'),
            Text('• Syntax highlighting & folding'),
            Text('• Multi-cursor editing'),
            Text('• Search & replace'),
            Text('• Autocompletion & linting'),
            Text('• Bidirectional text support'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
