import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';

import 'completion.dart' show Completion, CompletionSource;

class AddToOption {
  final Object? Function(Completion completion, EditorState state) render;
  final int position;

  const AddToOption({required this.render, required this.position});
}

class PositionInfoResult {
  final String? style;
  final String? className;

  const PositionInfoResult({this.style, this.className});
}

class Rect {
  final double left;
  final double right;
  final double top;
  final double bottom;

  const Rect({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
}

class CompletionConfig {
  final bool activateOnTyping;
  final bool Function(Completion completion) activateOnCompletion;
  final int activateOnTypingDelay;
  final bool selectOnOpen;
  final List<CompletionSource>? override;
  final bool closeOnBlur;
  final int maxRenderedOptions;
  final bool defaultKeymap;
  final bool aboveCursor;
  final String Function(EditorState state) tooltipClass;
  final String Function(Completion completion) optionClass;
  final bool icons;
  final List<AddToOption> addToOptions;
  final PositionInfoResult Function(
    Rect list,
    Rect option,
    Rect info,
    Rect space,
  ) positionInfo;
  final int Function(Completion a, Completion b) compareCompletions;
  final bool filterStrict;
  final int interactionDelay;
  final int updateSyncTime;

  const CompletionConfig({
    this.activateOnTyping = true,
    this.activateOnCompletion = _defaultActivateOnCompletion,
    this.activateOnTypingDelay = 100,
    this.selectOnOpen = true,
    this.override,
    this.closeOnBlur = true,
    this.maxRenderedOptions = 100,
    this.defaultKeymap = true,
    this.aboveCursor = false,
    this.tooltipClass = _defaultTooltipClass,
    this.optionClass = _defaultOptionClass,
    this.icons = true,
    this.addToOptions = const [],
    this.positionInfo = _defaultPositionInfo,
    this.compareCompletions = _defaultCompareCompletions,
    this.filterStrict = false,
    this.interactionDelay = 75,
    this.updateSyncTime = 100,
  });

  CompletionConfig copyWith({
    bool? activateOnTyping,
    bool Function(Completion completion)? activateOnCompletion,
    int? activateOnTypingDelay,
    bool? selectOnOpen,
    List<CompletionSource>? override,
    bool? closeOnBlur,
    int? maxRenderedOptions,
    bool? defaultKeymap,
    bool? aboveCursor,
    String Function(EditorState state)? tooltipClass,
    String Function(Completion completion)? optionClass,
    bool? icons,
    List<AddToOption>? addToOptions,
    PositionInfoResult Function(Rect, Rect, Rect, Rect)? positionInfo,
    int Function(Completion, Completion)? compareCompletions,
    bool? filterStrict,
    int? interactionDelay,
    int? updateSyncTime,
  }) {
    return CompletionConfig(
      activateOnTyping: activateOnTyping ?? this.activateOnTyping,
      activateOnCompletion: activateOnCompletion ?? this.activateOnCompletion,
      activateOnTypingDelay:
          activateOnTypingDelay ?? this.activateOnTypingDelay,
      selectOnOpen: selectOnOpen ?? this.selectOnOpen,
      override: override ?? this.override,
      closeOnBlur: closeOnBlur ?? this.closeOnBlur,
      maxRenderedOptions: maxRenderedOptions ?? this.maxRenderedOptions,
      defaultKeymap: defaultKeymap ?? this.defaultKeymap,
      aboveCursor: aboveCursor ?? this.aboveCursor,
      tooltipClass: tooltipClass ?? this.tooltipClass,
      optionClass: optionClass ?? this.optionClass,
      icons: icons ?? this.icons,
      addToOptions: addToOptions ?? this.addToOptions,
      positionInfo: positionInfo ?? this.positionInfo,
      compareCompletions: compareCompletions ?? this.compareCompletions,
      filterStrict: filterStrict ?? this.filterStrict,
      interactionDelay: interactionDelay ?? this.interactionDelay,
      updateSyncTime: updateSyncTime ?? this.updateSyncTime,
    );
  }
}

bool _defaultActivateOnCompletion(Completion _) => false;
String _defaultTooltipClass(EditorState _) => '';
String _defaultOptionClass(Completion _) => '';
int _defaultCompareCompletions(Completion a, Completion b) {
  final aLabel = a.toString();
  final bLabel = b.toString();
  return aLabel.compareTo(bLabel);
}

PositionInfoResult _defaultPositionInfo(
  Rect list,
  Rect option,
  Rect info,
  Rect space,
) {
  const infoWidth = 400;
  const infoMargin = 10;

  var left = true;
  var narrow = false;
  var side = 'top';
  double offset;
  double maxWidth;

  final spaceLeft = list.left - space.left;
  final spaceRight = space.right - list.right;
  final infoWidthValue = info.width;
  final infoHeight = info.height;

  if (spaceLeft < (infoWidthValue < spaceRight ? infoWidthValue : spaceRight)) {
    left = false;
  } else if (spaceRight < (infoWidthValue < spaceLeft ? infoWidthValue : spaceLeft)) {
    left = true;
  }

  if (infoWidthValue <= (left ? spaceLeft : spaceRight)) {
    final minTop = space.top > option.top ? space.top : option.top;
    final maxTop = space.bottom - infoHeight;
    offset = (minTop < maxTop ? minTop : maxTop) - list.top;
    maxWidth = (infoWidth < (left ? spaceLeft : spaceRight))
        ? infoWidth.toDouble()
        : (left ? spaceLeft : spaceRight);
  } else {
    narrow = true;
    maxWidth = (infoWidth < (space.right - list.left - infoMargin))
        ? infoWidth.toDouble()
        : (space.right - list.left - infoMargin);
    final spaceBelow = space.bottom - list.bottom;
    if (spaceBelow >= infoHeight || spaceBelow > list.top) {
      offset = option.bottom - list.top;
    } else {
      side = 'bottom';
      offset = list.bottom - option.top;
    }
  }

  return PositionInfoResult(
    style: '$side: ${offset}px; max-width: ${maxWidth}px',
    className:
        'cm-completionInfo-${narrow ? (left ? "left-narrow" : "right-narrow") : left ? "left" : "right"}',
  );
}

String _joinClass(String a, String b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a $b';
}

CompletionConfig _combineConfigs(List<CompletionConfig> configs) {
  if (configs.isEmpty) return const CompletionConfig();

  var result = const CompletionConfig();
  for (final config in configs) {
    result = CompletionConfig(
      activateOnTyping: config.activateOnTyping,
      activateOnCompletion: config.activateOnCompletion,
      activateOnTypingDelay: config.activateOnTypingDelay,
      selectOnOpen: config.selectOnOpen,
      override: config.override ?? result.override,
      closeOnBlur: result.closeOnBlur && config.closeOnBlur,
      maxRenderedOptions: config.maxRenderedOptions,
      defaultKeymap: result.defaultKeymap && config.defaultKeymap,
      aboveCursor: config.aboveCursor,
      tooltipClass: (state) =>
          _joinClass(result.tooltipClass(state), config.tooltipClass(state)),
      optionClass: (completion) => _joinClass(
          result.optionClass(completion), config.optionClass(completion)),
      icons: result.icons && config.icons,
      addToOptions: [...result.addToOptions, ...config.addToOptions],
      positionInfo: config.positionInfo,
      compareCompletions: config.compareCompletions,
      filterStrict: result.filterStrict || config.filterStrict,
      interactionDelay: config.interactionDelay,
      updateSyncTime: config.updateSyncTime,
    );
  }
  return result;
}

final Facet<CompletionConfig, CompletionConfig> completionConfig = Facet.define(
  FacetConfig(combine: _combineConfigs),
);
