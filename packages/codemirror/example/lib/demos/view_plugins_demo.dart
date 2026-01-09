import 'package:flutter/material.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates ViewPlugin for extending the editor view.
class ViewPluginsDemo extends StatefulWidget {
  const ViewPluginsDemo({super.key});

  @override
  State<ViewPluginsDemo> createState() => _ViewPluginsDemoState();
}

class _ViewPluginsDemoState extends State<ViewPluginsDemo> {
  late EditorState _state;
  
  // Plugin state that would be tracked by ViewPlugins
  int _updateCount = 0;
  int _keystrokeCount = 0;
  int _docChangeCount = 0;
  int _selectionChangeCount = 0;
  final List<_PluginEvent> _pluginEvents = [];

  @override
  void initState() {
    super.initState();
    _state = EditorState.create(
      EditorStateConfig(
        doc: '''// Type here to see plugins in action!
// Plugins can track updates, handle events,
// and modify the view behavior.

function example() {
  return 42;
}''',
      ),
    );
    _addEvent('Plugin initialized', 'lifecycle');
  }

  void _addEvent(String message, String type) {
    setState(() {
      _pluginEvents.insert(0, _PluginEvent(
        message: message,
        type: type,
        timestamp: DateTime.now(),
      ));
      if (_pluginEvents.length > 20) {
        _pluginEvents.removeLast();
      }
    });
  }

  void _handleUpdate(ViewUpdate update) {
    setState(() {
      _state = update.state;
      _updateCount++;

      if (update.docChanged) {
        _docChangeCount++;
        _addEvent(
          'Document changed: ${_state.doc.length} chars',
          'doc',
        );
      }

      if (update.selectionSet) {
        _selectionChangeCount++;
        final sel = _state.selection.main;
        _addEvent(
          sel.empty
              ? 'Cursor moved to ${sel.head}'
              : 'Selection: ${sel.from}-${sel.to}',
          'selection',
        );
      }
    });
  }

  void _simulateKeystroke() {
    final pos = _state.selection.main.head;
    final tr = _state.update([
      TransactionSpec(
        changes: ChangeSpec(from: pos, insert: 'x'),
        selection: EditorSelection.single(pos + 1),
      ),
    ]);
    setState(() {
      _state = tr.state as EditorState;
      _keystrokeCount++;
      _updateCount++;
      _docChangeCount++;
    });
    _addEvent('Keystroke simulated', 'input');
  }

  void _resetStats() {
    setState(() {
      _updateCount = 0;
      _keystrokeCount = 0;
      _docChangeCount = 0;
      _selectionChangeCount = 0;
      _pluginEvents.clear();
    });
    _addEvent('Stats reset', 'lifecycle');
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
            'View Plugins',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'ViewPlugins extend the editor view by hooking into the update lifecycle. '
            'They can track changes, handle events, and modify view behavior.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Stats cards
          Row(
            children: [
              _buildStatCard(
                'Updates',
                _updateCount.toString(),
                Icons.refresh,
                Colors.blue,
                theme,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Doc Changes',
                _docChangeCount.toString(),
                Icons.edit,
                Colors.green,
                theme,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Selection Changes',
                _selectionChangeCount.toString(),
                Icons.select_all,
                Colors.orange,
                theme,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Keystrokes',
                _keystrokeCount.toString(),
                Icons.keyboard,
                Colors.purple,
                theme,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Editor and plugin events side by side
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Editor
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: theme.dividerColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Editor',
                                style: theme.textTheme.titleSmall,
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _simulateKeystroke,
                                icon: const Icon(Icons.keyboard, size: 16),
                                label: const Text('Simulate Keystroke'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _resetStats,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Reset'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: EditorView(
                            state: _state,
                            onUpdate: _handleUpdate,
                            padding: const EdgeInsets.all(16),
                            autofocus: true,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Plugin events
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
                              Icon(
                                Icons.timeline,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Plugin Events',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _pluginEvents.isEmpty
                                ? Center(
                                    child: Text(
                                      'Edit to see events',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _pluginEvents.length,
                                    itemBuilder: (context, index) {
                                      final event = _pluginEvents[index];
                                      return _buildEventTile(event, index == 0, theme);
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
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventTile(_PluginEvent event, bool isLatest, ThemeData theme) {
    final color = switch (event.type) {
      'doc' => Colors.green,
      'selection' => Colors.orange,
      'input' => Colors.purple,
      'lifecycle' => Colors.blue,
      _ => Colors.grey,
    };

    final icon = switch (event.type) {
      'doc' => Icons.edit,
      'selection' => Icons.select_all,
      'input' => Icons.keyboard,
      'lifecycle' => Icons.play_circle,
      _ => Icons.circle,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLatest
            ? color.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: isLatest
            ? Border.all(color: color.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isLatest ? FontWeight.bold : null,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  _formatTime(event.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${(time.millisecond ~/ 100)}';
  }
}

class _PluginEvent {
  final String message;
  final String type;
  final DateTime timestamp;

  _PluginEvent({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}
