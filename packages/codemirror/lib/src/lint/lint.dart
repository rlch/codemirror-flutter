/// Lint diagnostics for CodeMirror.
///
/// This module provides infrastructure for displaying lint diagnostics
/// (errors, warnings, hints, info) in the editor, including markers,
/// tooltips, and navigation commands.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Decoration;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../text/text.dart' as text_lib;
import '../view/decoration.dart';
import '../view/gutter.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/editor_view.dart';
import '../commands/commands.dart' show StateCommandTarget;

// ============================================================================
// Severity
// ============================================================================

/// The severity level of a diagnostic.
enum Severity {
  /// A hint or suggestion.
  hint,

  /// Informational message.
  info,

  /// A warning that doesn't prevent execution.
  warning,

  /// An error that likely prevents correct execution.
  error,
}

int _severityWeight(Severity sev) {
  switch (sev) {
    case Severity.error:
      return 4;
    case Severity.warning:
      return 3;
    case Severity.info:
      return 2;
    case Severity.hint:
      return 1;
  }
}

Severity _maxSeverity(List<Diagnostic> diagnostics) {
  var sev = Severity.hint;
  var weight = 1;
  for (final d in diagnostics) {
    final w = _severityWeight(d.severity);
    if (w > weight) {
      weight = w;
      sev = d.severity;
    }
  }
  return sev;
}

// ============================================================================
// Diagnostic
// ============================================================================

/// Describes a problem or hint for a piece of code.
class Diagnostic {
  /// The start position of the relevant text.
  final int from;

  /// The end position. May be equal to [from], though actually
  /// covering text is preferable.
  final int to;

  /// The severity of the problem.
  final Severity severity;

  /// When given, add an extra CSS class to parts of the code that
  /// this diagnostic applies to.
  final String? markClass;

  /// An optional source string indicating where the diagnostic is
  /// coming from. You can put the name of your linter here.
  final String? source;

  /// The message associated with this diagnostic.
  final String message;

  /// An optional array of actions that can be taken on this diagnostic.
  final List<DiagnosticAction>? actions;

  const Diagnostic({
    required this.from,
    required this.to,
    required this.severity,
    required this.message,
    this.markClass,
    this.source,
    this.actions,
  });
}

/// An action associated with a diagnostic.
class DiagnosticAction {
  /// The label to show to the user. Should be relatively short.
  final String name;

  /// When given, add an extra CSS class to the action button.
  final String? markClass;

  /// The function to call when the user activates this action.
  /// Is given the diagnostic's _current_ position, which may have
  /// changed since the creation of the diagnostic, due to editing.
  final void Function(EditorViewState view, int from, int to) apply;

  const DiagnosticAction({
    required this.name,
    this.markClass,
    required this.apply,
  });
}

// ============================================================================
// Diagnostic Filter
// ============================================================================

/// Type for functions that filter diagnostics.
typedef DiagnosticFilter = List<Diagnostic> Function(
  List<Diagnostic> diagnostics,
  EditorState state,
);

// ============================================================================
// Lint Configuration
// ============================================================================

/// Configuration options for linting.
class LintConfig {
  /// Time to wait (in milliseconds) after a change before running
  /// the linter. Defaults to 750ms.
  final int delay;

  /// Optional predicate that can be used to indicate when diagnostics
  /// need to be recomputed. Linting is always re-done on document changes.
  final bool Function(ViewUpdate update)? needsRefresh;

  /// Optional filter to determine which diagnostics produce markers
  /// in the content.
  final DiagnosticFilter? markerFilter;

  /// Filter applied to a set of diagnostics shown in a tooltip.
  /// No tooltip will appear if the empty set is returned.
  final DiagnosticFilter? tooltipFilter;

  /// Can be used to control what kind of transactions cause lint
  /// hover tooltips associated with the given document range to be
  /// hidden. By default any transaction that changes the line around
  /// the range will hide it. Returning null falls back to this behavior.
  final bool? Function(txn.Transaction tr, int from, int to)? hideOn;

  /// When enabled (defaults to off), this will cause the lint panel
  /// to automatically open when diagnostics are found, and close when
  /// all diagnostics are resolved or removed.
  final bool autoPanel;

  const LintConfig({
    this.delay = 750,
    this.needsRefresh,
    this.markerFilter,
    this.tooltipFilter,
    this.hideOn,
    this.autoPanel = false,
  });
}

/// Configuration for the lint gutter.
class LintGutterConfig {
  /// The delay before showing a tooltip when hovering over a lint gutter marker.
  final int hoverTime;

  /// Optional filter determining which diagnostics show a marker in the gutter.
  final DiagnosticFilter? markerFilter;

  /// Optional filter for diagnostics displayed in a tooltip.
  final DiagnosticFilter? tooltipFilter;

  const LintGutterConfig({
    this.hoverTime = 300,
    this.markerFilter,
    this.tooltipFilter,
  });
}

// ============================================================================
// Lint Source
// ============================================================================

/// The type of a function that produces diagnostics.
typedef LintSource = FutureOr<List<Diagnostic>> Function(EditorViewState view);

// ============================================================================
// Selected Diagnostic
// ============================================================================

/// Represents a selected diagnostic with its current position.
class SelectedDiagnostic {
  final int from;
  final int to;
  final Diagnostic diagnostic;

  const SelectedDiagnostic(this.from, this.to, this.diagnostic);
}

// ============================================================================
// Lint State
// ============================================================================

/// Internal state for lint decorations and panel.
class LintState {
  /// The decoration set containing lint markers.
  final RangeSet<Decoration> diagnostics;

  /// The currently selected diagnostic.
  final SelectedDiagnostic? selected;

  const LintState._({
    required this.diagnostics,
    this.selected,
  });

  static LintState _init(
    List<Diagnostic> diagnostics,
    EditorState state,
  ) {
    var filtered = diagnostics;
    final markerFilter = state.facet(_lintConfig).config.markerFilter;
    if (markerFilter != null) {
      filtered = markerFilter(diagnostics, state);
    }

    final sorted = List<Diagnostic>.from(filtered)
      ..sort((a, b) {
        final cmp = a.from - b.from;
        return cmp != 0 ? cmp : a.to - b.to;
      });

    final builder = RangeSetBuilder<Decoration>();
    final List<Diagnostic> active = [];
    var pos = 0;
    final docLen = state.doc.length;

    for (var i = 0;;) {
      final next = i == sorted.length ? null : sorted[i];
      if (next == null && active.isEmpty) break;

      int from, to;
      if (active.isNotEmpty) {
        from = pos;
        to = active.fold<int>(
          next != null && next.from > from ? next.from : 100000000,
          (p, d) => math.min(p, d.to),
        );
      } else {
        from = next!.from;
        if (from > docLen) break;
        to = next.to;
        active.add(next);
        i++;
      }

      while (i < sorted.length) {
        final nextD = sorted[i];
        if (nextD.from == from && (nextD.to > nextD.from || nextD.to == from)) {
          active.add(nextD);
          i++;
          to = math.min(nextD.to, to);
        } else {
          to = math.min(nextD.from, to);
          break;
        }
      }

      to = math.min(to, docLen);

      final isWidget = from == to;
      final sev = _maxSeverity(active);

      if (isWidget) {
        builder.add(
          from,
          from,
          Decoration.widgetDecoration(WidgetDecorationSpec(
            widget: _DiagnosticWidget(sev),
            spec: {'diagnostics': List<Diagnostic>.from(active)},
          )),
        );
      } else {
        final markClass = active.fold<String>(
          '',
          (c, d) => d.markClass != null ? '$c ${d.markClass}' : c,
        );
        builder.add(
          from,
          to,
          Decoration.mark(MarkDecorationSpec(
            className: 'cm-lintRange cm-lintRange-${sev.name}$markClass',
            inclusiveEnd: active.any((a) => a.to > to),
            spec: {'diagnostics': List<Diagnostic>.from(active)},
          )),
        );
      }

      pos = to;
      if (pos == docLen) break;
      active.removeWhere((d) => d.to <= pos);
    }

    final set = builder.finish();
    return LintState._(
      diagnostics: set,
      selected: _findDiagnostic(set, null, 0),
    );
  }
}

SelectedDiagnostic? _findDiagnostic(
  RangeSet<Decoration> diagnostics,
  Diagnostic? diagnostic,
  int after,
) {
  SelectedDiagnostic? found;
  diagnostics.between(after, 1000000000, (from, to, value) {
    final spec = value.spec;
    if (spec == null) return true;
    final diags = spec['diagnostics'] as List<Diagnostic>?;
    if (diags == null || diags.isEmpty) return true;

    if (diagnostic != null && !diags.contains(diagnostic)) return true;

    if (found == null) {
      found = SelectedDiagnostic(from, to, diagnostic ?? diags[0]);
    } else if (!diags.contains(found!.diagnostic)) {
      return false;
    } else {
      found = SelectedDiagnostic(found!.from, to, found!.diagnostic);
    }
    return true;
  });
  return found;
}

// ============================================================================
// Diagnostic Widget
// ============================================================================

/// Widget decoration for zero-length diagnostics.
class _DiagnosticWidget extends WidgetType {
  final Severity severity;

  const _DiagnosticWidget(this.severity);

  @override
  bool eq(WidgetType other) {
    return other is _DiagnosticWidget && other.severity == severity;
  }

  @override
  Widget toWidget(covariant dynamic view) {
    // Returns a small indicator dot for zero-length diagnostics
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _severityColor(severity),
      ),
    );
  }
}

Color _severityColor(Severity sev) {
  switch (sev) {
    case Severity.error:
      return const Color(0xFFDD1111);
    case Severity.warning:
      return const Color(0xFFFFA500);
    case Severity.info:
      return const Color(0xFF999999);
    case Severity.hint:
      return const Color(0xFF6666DD);
  }
}

// ============================================================================
// Diagnostic Tooltip
// ============================================================================

/// A lean VSCode-style diagnostic tooltip.
class DiagnosticTooltip extends StatelessWidget {
  final List<Diagnostic> diagnostics;

  const DiagnosticTooltip({super.key, required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final borderColor = isDark ? const Color(0xFF454545) : const Color(0xFFCCCCCC);
    
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final diagnostic in diagnostics)
            _DiagnosticRow(diagnostic: diagnostic),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final Diagnostic diagnostic;

  const _DiagnosticRow({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SeverityIcon(severity: diagnostic.severity),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              diagnostic.message,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                package: 'codemirror',
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Color(0xFFCCCCCC),
                height: 1.4,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (diagnostic.source != null) ...[
            const SizedBox(width: 8),
            Text(
              diagnostic.source!,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                package: 'codemirror',
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Color(0xFF808080),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeverityIcon extends StatelessWidget {
  final Severity severity;

  const _SeverityIcon({required this.severity});

  @override
  Widget build(BuildContext context) {
    // Use Nerd Font icons for severity
    final (icon, color) = switch (severity) {
      Severity.error => ('\uf00d', const Color(0xFFDD1111)),     // nf-fa-times / 
      Severity.warning => ('\uf071', const Color(0xFFFFA500)),   // nf-fa-exclamation_triangle / 
      Severity.info => ('\uf05a', const Color(0xFF999999)),      // nf-fa-info_circle / 
      Severity.hint => ('\uf0eb', const Color(0xFF6666DD)),      // nf-fa-lightbulb / 
    };
    
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: Text(
          icon,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            package: 'codemirror',
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: color,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Get diagnostics at a specific position.
List<Diagnostic> diagnosticsAtPos(EditorState state, int pos) {
  _ensureLintInitialized();
  final result = <Diagnostic>[];
  forEachDiagnostic(state, (d, from, to) {
    if (pos >= from && pos <= to) {
      result.add(d);
    }
  });
  return result;
}

// ============================================================================
// State Effects and Fields
// ============================================================================

/// State effect that updates the set of active diagnostics.
final StateEffectType<List<Diagnostic>> setDiagnosticsEffect =
    StateEffect.define<List<Diagnostic>>();

// ignore: unused_element
final StateEffectType<bool> _togglePanel = StateEffect.define<bool>();

final StateEffectType<SelectedDiagnostic> _movePanelSelection =
    StateEffect.define<SelectedDiagnostic>();

/// The lint state field.
late final StateField<LintState> _lintState;

/// Facet for lint configuration.
late final Facet<
    ({LintSource? source, LintConfig config}),
    ({List<LintSource> sources, LintConfig config})> _lintConfig;

/// Facet for lint gutter configuration.
late final Facet<LintGutterConfig, LintGutterConfig> _lintGutterConfig;

bool _lintInitialized = false;

void _ensureLintInitialized() {
  if (_lintInitialized) return;
  _lintInitialized = true;

  _lintConfig = Facet.define(FacetConfig(
    combine: (input) {
      final sources = input
          .map((i) => i.source)
          .where((s) => s != null)
          .cast<LintSource>()
          .toList();

      LintConfig combined = const LintConfig();
      for (final i in input) {
        final c = i.config;
        combined = LintConfig(
          delay: math.max(combined.delay, c.delay),
          markerFilter: _combineFilter(combined.markerFilter, c.markerFilter),
          tooltipFilter: _combineFilter(combined.tooltipFilter, c.tooltipFilter),
          needsRefresh: combined.needsRefresh ?? c.needsRefresh,
          hideOn: combined.hideOn ?? c.hideOn,
          autoPanel: combined.autoPanel || c.autoPanel,
        );
      }

      return (sources: sources, config: combined);
    },
  ));

  _lintGutterConfig = Facet.define(FacetConfig(
    combine: (configs) {
      if (configs.isEmpty) return const LintGutterConfig();
      return configs.first;
    },
  ));

  _lintState = StateField.define(StateFieldConfig(
    create: (_) => LintState._(diagnostics: RangeSet.empty<Decoration>()),
    update: (value, tr) {
      final transaction = tr as txn.Transaction;

      if (transaction.docChanged && value.diagnostics.size > 0) {
        final mapped = value.diagnostics.map(transaction.changes);
        SelectedDiagnostic? selected;
        if (value.selected != null) {
          final selPos = transaction.changes.mapPos(value.selected!.from, 1) ?? 0;
          selected = _findDiagnostic(mapped, value.selected!.diagnostic, selPos) ??
              _findDiagnostic(mapped, null, selPos);
        }
        value = LintState._(diagnostics: mapped, selected: selected);
      }

      for (final effect in transaction.effects) {
        if (effect.is_(setDiagnosticsEffect)) {
          final diagnostics = effect.value as List<Diagnostic>;
          value = LintState._init(diagnostics, transaction.state as EditorState);
        } else if (effect.is_(_movePanelSelection)) {
          value = LintState._(
            diagnostics: value.diagnostics,
            selected: effect.value as SelectedDiagnostic,
          );
        }
      }

      return value;
    },
  ));
}

DiagnosticFilter? _combineFilter(DiagnosticFilter? a, DiagnosticFilter? b) {
  if (a == null) return b;
  if (b == null) return a;
  return (d, s) => b(a(d, s), s);
}

// ============================================================================
// Public API
// ============================================================================

/// Returns a transaction spec which updates the current set of
/// diagnostics, and enables the lint extension if it wasn't already active.
TransactionSpec setDiagnostics(EditorState state, List<Diagnostic> diagnostics) {
  _ensureLintInitialized();
  return TransactionSpec(
    effects: [setDiagnosticsEffect.of(diagnostics)],
  );
}

/// Returns the number of active lint diagnostics in the given state.
int diagnosticCount(EditorState state) {
  _ensureLintInitialized();
  final lint = state.field(_lintState, false);
  return lint?.diagnostics.size ?? 0;
}

/// Given a diagnostic source, this function returns an extension that
/// enables linting with that source. It will be called whenever the
/// editor is idle (after its content changed).
///
/// Note that settings given here will apply to all linters active in
/// the editor. If `null` is given as source, this only configures the
/// lint extension.
Extension linter(LintSource? source, [LintConfig config = const LintConfig()]) {
  _ensureLintInitialized();
  _initLintExtensions();
  return ExtensionList([
    _lintConfig.of((source: source, config: config)),
    _lintPlugin.extension,
    _lintExtensions,
  ]);
}

/// Forces any linters configured to run when the editor is idle to run right away.
void forceLinting(EditorViewState view) {
  final plugin = view.plugin(_lintPlugin);
  if (plugin != null) {
    plugin.force();
  }
}

// ============================================================================
// Commands
// ============================================================================

/// Move the selection to the next diagnostic.
bool nextDiagnostic(StateCommandTarget target) {
  _ensureLintInitialized();
  final field = target.state.field(_lintState, false);
  if (field == null) return false;

  final sel = target.state.selection.main;
  final iter = field.diagnostics.iter(sel.to + 1);
  if (iter.value == null) {
    final iter2 = field.diagnostics.iter(0);
    if (iter2.value == null ||
        (iter2.from == sel.from && iter2.to == sel.to)) {
      return false;
    }
    target.dispatch(target.state.update([
      TransactionSpec(
        selection: EditorSelection.single(iter2.from),
        scrollIntoView: true,
      ),
    ]));
    return true;
  }

  target.dispatch(target.state.update([
    TransactionSpec(
      selection: EditorSelection.single(iter.from),
      scrollIntoView: true,
    ),
  ]));
  return true;
}

/// Move the selection to the previous diagnostic.
bool previousDiagnostic(StateCommandTarget target) {
  _ensureLintInitialized();
  final field = target.state.field(_lintState, false);
  if (field == null) return false;

  final sel = target.state.selection.main;
  int? prevFrom, lastFrom;

  field.diagnostics.between(0, target.state.doc.length, (from, to, _) {
    if (to < sel.to && (prevFrom == null || prevFrom! < from)) {
      prevFrom = from;
    }
    if (lastFrom == null || from > lastFrom!) {
      lastFrom = from;
    }
    return true;
  });

  if (lastFrom == null || (prevFrom == null && lastFrom == sel.from)) {
    return false;
  }

  target.dispatch(target.state.update([
    TransactionSpec(
      selection: EditorSelection.single(prevFrom ?? lastFrom!),
      scrollIntoView: true,
    ),
  ]));
  return true;
}

// ============================================================================
// Lint Plugin
// ============================================================================

late final ViewPlugin<_LintPluginValue> _lintPlugin;

class _LintPluginValue extends PluginValue {
  final EditorViewState view;
  int _lintTime;
  Timer? _timeout;
  bool _set = true;

  _LintPluginValue(this.view)
      : _lintTime = DateTime.now().millisecondsSinceEpoch +
            view.state.facet(_lintConfig).config.delay {
    developer.log('LintPlugin created, scheduling run', name: 'Lint');
    _scheduleRun();
  }

  void _scheduleRun() {
    final delay = view.state.facet(_lintConfig).config.delay;
    developer.log('Scheduling lint run in ${delay}ms', name: 'Lint');
    _timeout?.cancel();
    _timeout = Timer(Duration(milliseconds: delay), _run);
  }

  void _run() {
    _timeout?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _lintTime - 10) {
      developer.log('Lint delayed, rescheduling', name: 'Lint');
      _timeout = Timer(Duration(milliseconds: _lintTime - now), _run);
    } else {
      _set = false;
      final state = view.state;
      final sources = state.facet(_lintConfig).sources;
      developer.log('Running lint with ${sources.length} sources', name: 'Lint');

      if (sources.isNotEmpty) {
        final futures = sources.map((s) => Future.value(s(view)));
        Future.wait(futures).then((results) {
          developer.log('Lint sources returned ${results.map((r) => r.length).join(', ')} diagnostics', name: 'Lint');
          if (view.state.doc == state.doc) {
            final allDiagnostics = results.expand((d) => d).toList();
            developer.log('Dispatching ${allDiagnostics.length} total diagnostics', name: 'Lint');
            view.dispatch([setDiagnostics(view.state, allDiagnostics)]);
          } else {
            developer.log('Doc changed, skipping dispatch', name: 'Lint');
          }
        }).catchError((error) {
          developer.log('Lint error: $error', name: 'Lint');
          logException(view.state, error);
        });
      } else {
        developer.log('No lint sources registered', name: 'Lint');
      }
    }
  }

  @override
  void update(ViewUpdate update) {
    final config = update.state.facet(_lintConfig);
    if (update.docChanged ||
        config != update.startState.facet(_lintConfig) ||
        (config.config.needsRefresh?.call(update) ?? false)) {
      _lintTime = DateTime.now().millisecondsSinceEpoch + config.config.delay;
      if (!_set) {
        _set = true;
        _scheduleRun();
      }
    }
  }

  void force() {
    if (_set) {
      _lintTime = DateTime.now().millisecondsSinceEpoch;
      _run();
    }
  }

  @override
  void destroy(EditorViewState view) {
    _timeout?.cancel();
  }
}

// ============================================================================
// Lint Gutter
// ============================================================================

/// Gutter marker for lint diagnostics.
class LintGutterMarker extends GutterMarker {
  final Severity severity;
  final List<Diagnostic> diagnosticList;

  LintGutterMarker(this.diagnosticList) : severity = _maxSeverity(diagnosticList);

  @override
  bool markerEq(GutterMarker other) {
    return other is LintGutterMarker && other.severity == severity;
  }

  /// Fixed line height matching EditorViewState.fixedLineHeight
  static const double _lineHeight = 20.0;
  static const double _fontSize = 12.0;
  
  @override
  Widget? toWidget(BuildContext context) {
    // Use Nerd Font icons for severity markers
    // These require a Nerd Font to be installed (e.g., JetBrainsMono Nerd Font)
    final (icon, color) = switch (severity) {
      Severity.error => ('\uf00d', const Color(0xFFDD1111)),     // nf-fa-times / 
      Severity.warning => ('\uf071', const Color(0xFFFFA500)),   // nf-fa-exclamation_triangle / 
      Severity.info => ('\uf05a', const Color(0xFF999999)),      // nf-fa-info_circle / 
      Severity.hint => ('\uf0eb', const Color(0xFF6666DD)),      // nf-fa-lightbulb / 
    };
    
    // Use StrutStyle like NumberMarker to ensure consistent vertical alignment
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        icon,
        style: TextStyle(
          fontFamily: 'JetBrainsMono Nerd Font',
          fontFamilyFallback: const ['JetBrainsMono NF', 'Symbols Nerd Font', 'monospace'],
          fontSize: _fontSize,
          color: color,
          height: _lineHeight / _fontSize,
        ),
        strutStyle: const StrutStyle(
          fontFamily: 'JetBrainsMono Nerd Font',
          fontSize: _fontSize,
          height: _lineHeight / _fontSize,
          forceStrutHeight: true,
        ),
      ),
    );
  }

  @override
  String get elementClass => 'cm-lint-marker cm-lint-marker-${severity.name}';
}

late final StateField<RangeSet<GutterMarker>> _lintGutterMarkers;

RangeSet<GutterMarker> _markersForDiagnostics(
  text_lib.Text doc,
  List<Diagnostic> diagnostics,
) {
  final byLine = <int, List<Diagnostic>>{};
  for (final diagnostic in diagnostics) {
    final line = doc.lineAt(diagnostic.from);
    (byLine[line.from] ??= []).add(diagnostic);
  }

  final builder = RangeSetBuilder<GutterMarker>();
  final sortedPositions = byLine.keys.toList()..sort();
  for (final pos in sortedPositions) {
    final marker = LintGutterMarker(byLine[pos]!);
    builder.add(pos, pos, marker);
  }
  return builder.finish();
}

/// Returns an extension that installs a gutter showing markers for
/// each line that has diagnostics, which can be hovered over to see
/// the diagnostics.
Extension lintGutter([LintGutterConfig config = const LintGutterConfig()]) {
  _ensureLintInitialized();
  _ensureLintGutterInitialized();
  return ExtensionList([
    _lintGutterConfig.of(config),
    _lintGutterMarkers,
    gutter(GutterConfig(
      className: 'cm-gutter-lint',
      markers: (state) => state.field(_lintGutterMarkers, false) ?? RangeSet.empty<GutterMarker>(),
      initialSpacer: (_) => _LintGutterSpacer(),
    )),
  ]);
}

/// Spacer marker to maintain consistent gutter width even with no diagnostics.
class _LintGutterSpacer extends GutterMarker {
  @override
  Widget? toWidget(BuildContext context) {
    // Render an invisible version of the icon to get exact same width
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Opacity(
        opacity: 0,
        child: Text(
          '\uf00d', // Same icon as error marker
          style: TextStyle(
            fontFamily: 'JetBrainsMono Nerd Font',
            fontFamilyFallback: const ['JetBrainsMono NF', 'Symbols Nerd Font', 'monospace'],
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    );
  }

  @override
  bool markerEq(GutterMarker other) => other is _LintGutterSpacer;
}

bool _lintGutterInitialized = false;

void _ensureLintGutterInitialized() {
  if (_lintGutterInitialized) return;
  _lintGutterInitialized = true;

  _lintGutterMarkers = StateField.define(StateFieldConfig(
    create: (_) => RangeSet.empty<GutterMarker>(),
    update: (markers, tr) {
      final transaction = tr as txn.Transaction;
      RangeSet<GutterMarker> result = markers.map(transaction.changes);

      for (final effect in transaction.effects) {
        if (effect.is_(setDiagnosticsEffect)) {
          var diagnostics = effect.value as List<Diagnostic>;
          final state = transaction.state as EditorState;
          final filter = state.facet(_lintGutterConfig).markerFilter;
          if (filter != null) {
            diagnostics = filter(diagnostics, state);
          }
          result = _markersForDiagnostics(state.doc, diagnostics);
        }
      }
      return result;
    },
  ));
}

// ============================================================================
// Iterate Diagnostics
// ============================================================================

/// Iterate over the marked diagnostics for the given editor state,
/// calling [f] for each of them.
///
/// Note that, if the document changed since the diagnostics were created,
/// the [Diagnostic] object will hold the original outdated position,
/// whereas the `to` and `from` arguments hold the diagnostic's current position.
void forEachDiagnostic(
  EditorState state,
  void Function(Diagnostic d, int from, int to) f,
) {
  _ensureLintInitialized();
  final lState = state.field(_lintState, false);
  if (lState == null || lState.diagnostics.size == 0) return;

  final pending = <Diagnostic>[];
  final pendingStart = <int>[];
  var lastEnd = -1;

  final iter = lState.diagnostics.iter();
  // iter() already positions at first element via goto() which calls next()
  while (iter.value != null) {
    // Check if any pending diagnostics ended at this point
    for (var i = 0; i < pending.length; i++) {
      final spec = iter.value?.spec;
      final diags = spec?['diagnostics'] as List<Diagnostic>?;
      if (diags == null || !diags.contains(pending[i])) {
        f(pending[i], pendingStart[i], lastEnd);
        pending.removeAt(i);
        pendingStart.removeAt(i);
        i--;
      }
    }
    
    // Add new diagnostics from current position
    final spec = iter.value!.spec;
    final diags = spec?['diagnostics'] as List<Diagnostic>?;
    if (diags != null) {
      for (final d in diags) {
        if (!pending.contains(d)) {
          pending.add(d);
          pendingStart.add(iter.from);
        }
      }
    }
    lastEnd = iter.to;
    iter.next();
  }
  
  // Flush remaining pending diagnostics
  for (var i = 0; i < pending.length; i++) {
    f(pending[i], pendingStart[i], lastEnd);
  }
}

// ============================================================================
// Extensions Setup
// ============================================================================

late final Extension _lintExtensions;
bool _lintExtensionsInitialized = false;

void _initLintExtensions() {
  if (_lintExtensionsInitialized) return;
  _lintExtensionsInitialized = true;

  _lintPlugin = ViewPlugin.define((view) => _LintPluginValue(view));

  _lintExtensions = ExtensionList([
    _lintState,
    decorationsFacet.of((EditorViewState view) {
      final field = view.state.field(_lintState, false);
      return field?.diagnostics ?? Decoration.none;
    }),
  ]);
}

/// Ensure lint module is initialized.
void ensureLintInitialized() {
  _ensureLintInitialized();
  _initLintExtensions();
}
