import 'dart:convert';

const int groundingContractVersion = 1;

class WebContextBuildResult {
  final String context;
  final GroundingRunTrace trace;

  const WebContextBuildResult({
    required this.context,
    required this.trace,
  });
}

class GroundingRunTrace {
  final String userMessage;
  final String characterId;
  final DateTime startedAt;
  DateTime? finishedAt;
  final List<GroundingRemoteCall> remoteCalls = [];

  GroundingRunTrace({
    required this.userMessage,
    required this.characterId,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  void recordRemoteCall({
    required String kind,
    required String provider,
    required String operation,
    String requestLabel = '',
  }) {
    remoteCalls.add(GroundingRemoteCall(
      kind: kind,
      provider: provider,
      operation: operation,
      requestLabel: requestLabel,
    ));
  }

  int get searchApiCalls =>
      remoteCalls.where((call) => call.kind == 'search_api').length;

  int get modelCalls =>
      remoteCalls.where((call) => call.kind == 'model').length;

  int modelCallsFor(String operation) => remoteCalls
      .where((call) => call.kind == 'model' && call.operation == operation)
      .length;

  void finish() {
    finishedAt ??= DateTime.now();
  }

  String get compactSummary => '搜索API=$searchApiCalls，模型=$modelCalls'
      '（规划=${modelCallsFor('planner')}，'
      'facts=${modelCallsFor('facts')}，'
      '时间线=${modelCallsFor('timeline')}）';

  Map<String, dynamic> toJson() => {
        'contractVersion': groundingContractVersion,
        'userMessage': userMessage,
        'characterId': characterId,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        'remoteCalls': remoteCalls.map((call) => call.toJson()).toList(),
      };

  factory GroundingRunTrace.fromJson(Map json) {
    final trace = GroundingRunTrace(
      userMessage: '${json['userMessage'] ?? ''}',
      characterId: '${json['characterId'] ?? ''}',
      startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}'),
    );
    final rawCalls = json['remoteCalls'];
    if (rawCalls is List) {
      trace.remoteCalls.addAll(
        rawCalls.whereType<Map>().map(GroundingRemoteCall.fromJson),
      );
    }
    trace.finishedAt = DateTime.tryParse('${json['finishedAt'] ?? ''}');
    return trace;
  }
}

class GroundingRemoteCall {
  final String kind;
  final String provider;
  final String operation;
  final String requestLabel;

  const GroundingRemoteCall({
    required this.kind,
    required this.provider,
    required this.operation,
    this.requestLabel = '',
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'provider': provider,
        'operation': operation,
        if (requestLabel.isNotEmpty) 'requestLabel': requestLabel,
      };

  factory GroundingRemoteCall.fromJson(Map json) => GroundingRemoteCall(
        kind: '${json['kind'] ?? ''}',
        provider: '${json['provider'] ?? ''}',
        operation: '${json['operation'] ?? ''}',
        requestLabel: '${json['requestLabel'] ?? ''}',
      );
}

class GroundingSnapshot {
  final int contractVersion;
  final List<String> searchObjects;
  final List<GroundingFactSnapshot> facts;
  final List<GroundingTimelineSnapshot> timeline;
  final int searchApiCalls;
  final String japaneseAnswer;
  final String chineseAnswer;

  const GroundingSnapshot({
    this.contractVersion = groundingContractVersion,
    this.searchObjects = const [],
    this.facts = const [],
    this.timeline = const [],
    this.searchApiCalls = 0,
    this.japaneseAnswer = '',
    this.chineseAnswer = '',
  });

  factory GroundingSnapshot.fromAudit({
    required List<String> logs,
    required String webContext,
    String japaneseAnswer = '',
    String chineseAnswer = '',
  }) {
    return GroundingSnapshot(
      searchObjects: _parseSearchObjects(logs),
      facts: _parseFacts(webContext),
      timeline: _parseTimeline(webContext),
      searchApiCalls:
          logs.where((line) => line.trim().startsWith('搜索步骤开始[')).length,
      japaneseAnswer: japaneseAnswer.trim(),
      chineseAnswer: chineseAnswer.trim(),
    );
  }

  List<GroundingValidationIssue> validate(
    GroundingAcceptancePolicy policy,
  ) {
    final issues = <GroundingValidationIssue>[];
    final effectiveFacts = _dedupeFacts(facts);
    if (effectiveFacts.length < policy.minimumFacts) {
      issues.add(GroundingValidationIssue(
        code: 'facts_too_few',
        message:
            '有效 facts 只有 ${effectiveFacts.length} 条，要求至少 ${policy.minimumFacts} 条',
      ));
    }
    if (policy.maximumFacts != null &&
        effectiveFacts.length > policy.maximumFacts!) {
      issues.add(GroundingValidationIssue(
        code: 'facts_too_many',
        message:
            '有效 facts 有 ${effectiveFacts.length} 条，超过上限 ${policy.maximumFacts} 条',
      ));
    }
    final sourceCount = _uniqueFactSourceCount(effectiveFacts);
    if (sourceCount < policy.minimumSources) {
      issues.add(GroundingValidationIssue(
        code: 'sources_too_few',
        message: '网页来源只有 $sourceCount 个，要求至少 ${policy.minimumSources} 个',
      ));
    }
    if (policy.requireTimeline && timeline.isEmpty) {
      issues.add(const GroundingValidationIssue(
        code: 'timeline_missing',
        message: '该题需要时间线，但快照中没有时间线',
      ));
    }
    if (searchApiCalls > policy.maximumSearchApiCalls) {
      issues.add(GroundingValidationIssue(
        code: 'search_api_budget_exceeded',
        message: '搜索 API 调用了 $searchApiCalls 次，上限为 '
            '${policy.maximumSearchApiCalls} 次',
      ));
    }

    final normalizedObjects = searchObjects.map(_matchKey).toSet();
    for (final requiredObject in policy.requiredSearchObjects) {
      if (!normalizedObjects.contains(_matchKey(requiredObject))) {
        issues.add(GroundingValidationIssue(
          code: 'search_object_missing',
          message: '搜索对象缺少“$requiredObject”',
        ));
      }
    }

    final factText = effectiveFacts.map((fact) => fact.text).join('\n');
    for (final requiredText in policy.requiredFactText) {
      if (!_containsLoose(factText, requiredText)) {
        issues.add(GroundingValidationIssue(
          code: 'fact_anchor_missing',
          message: 'facts 没有覆盖“$requiredText”',
        ));
      }
    }

    final timelineText = timeline.map((step) => step.text).join('\n');
    var previousIndex = -1;
    for (final anchor in policy.orderedTimelineAnchors) {
      final index = _matchKey(timelineText).indexOf(_matchKey(anchor));
      if (index < 0) {
        issues.add(GroundingValidationIssue(
          code: 'timeline_anchor_missing',
          message: '时间线没有覆盖“$anchor”',
        ));
      } else if (index < previousIndex) {
        issues.add(GroundingValidationIssue(
          code: 'timeline_order_wrong',
          message: '时间线中“$anchor”的位置早于已经确认的前置事件',
        ));
      } else {
        previousIndex = index;
      }
    }

    final allOutput = '$factText\n$timelineText\n$chineseAnswer';
    for (final forbiddenText in policy.forbiddenText) {
      if (_containsLoose(allOutput, forbiddenText)) {
        issues.add(GroundingValidationIssue(
          code: 'forbidden_text_present',
          message: '输出中出现不应出现的内容“$forbiddenText”',
        ));
      }
    }
    return issues;
  }

  Map<String, dynamic> toJson() => {
        'contractVersion': contractVersion,
        'searchObjects': searchObjects,
        'facts': facts.map((fact) => fact.toJson()).toList(),
        'timeline': timeline.map((step) => step.toJson()).toList(),
        'searchApiCalls': searchApiCalls,
        'japaneseAnswer': japaneseAnswer,
        'chineseAnswer': chineseAnswer,
      };

  factory GroundingSnapshot.fromJson(Map json) => GroundingSnapshot(
        contractVersion: _asInt(json['contractVersion']) ?? 0,
        searchObjects: _stringList(json['searchObjects']),
        facts: (json['facts'] is List)
            ? (json['facts'] as List)
                .whereType<Map>()
                .map(GroundingFactSnapshot.fromJson)
                .toList()
            : const [],
        timeline: (json['timeline'] is List)
            ? (json['timeline'] as List)
                .whereType<Map>()
                .map(GroundingTimelineSnapshot.fromJson)
                .toList()
            : const [],
        searchApiCalls: _asInt(json['searchApiCalls']) ?? 0,
        japaneseAnswer: '${json['japaneseAnswer'] ?? ''}',
        chineseAnswer: '${json['chineseAnswer'] ?? ''}',
      );

  static List<String> _parseSearchObjects(List<String> logs) {
    for (final raw in logs) {
      final match = RegExp(r'原作搜索对象:\s*(.+)').firstMatch(raw);
      if (match == null) continue;
      return match
          .group(1)!
          .split(RegExp(r'\s*->\s*'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static List<GroundingFactSnapshot> _parseFacts(String context) {
    final start = context.indexOf('【网页搜索摘要】');
    if (start < 0) return const [];
    var end = context.length;
    for (final marker in ['【事实时间线】', '【角色设定资料】', '【使用这些信息的规则】']) {
      final index = context.indexOf(marker, start + 1);
      if (index >= 0 && index < end) end = index;
    }

    final result = <GroundingFactSnapshot>[];
    final lines = context.substring(start, end).split('\n');
    final linePattern = RegExp(r'^\d+\.\s*(.+?)：相关事实：(.*)$');
    final urlPattern = RegExp(r'（来源：(https?://[^）]+)）\s*$');
    for (final rawLine in lines) {
      final match = linePattern.firstMatch(rawLine.trim());
      if (match == null) continue;
      final sourceTitle = match.group(1)!.trim();
      var body = match.group(2)!.trim();
      final urlMatch = urlPattern.firstMatch(body);
      final sourceUrl = urlMatch?.group(1)?.trim() ?? '';
      if (urlMatch != null) body = body.substring(0, urlMatch.start).trim();
      final parts = body
          .split(RegExp(r'\s+/\s+'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty);
      for (final part in parts) {
        final evidenceStart = part.indexOf('（原文证据：');
        var text = part;
        var excerpt = '';
        if (part.startsWith('原文证据：')) {
          var evidenceBody = part.substring('原文证据：'.length).trim();
          final genderStart = evidenceBody.lastIndexOf('（人物性别参考：');
          if (genderStart >= 0 && evidenceBody.endsWith('）')) {
            evidenceBody = evidenceBody.substring(0, genderStart).trim();
          }
          text = evidenceBody;
          excerpt = evidenceBody;
        } else if (evidenceStart >= 0 && part.endsWith('）')) {
          text = part.substring(0, evidenceStart).trim();
          excerpt = part
              .substring(evidenceStart + '（原文证据：'.length, part.length - 1)
              .trim();
        }
        if (text.isEmpty) continue;
        result.add(GroundingFactSnapshot(
          index: result.length + 1,
          text: text,
          sourceTitle: sourceTitle,
          sourceUrl: sourceUrl,
          sourceExcerpt: excerpt,
        ));
      }
    }
    return result;
  }

  static List<GroundingTimelineSnapshot> _parseTimeline(String context) {
    final start = context.indexOf('【时间线】');
    if (start < 0) return const [];
    final result = <GroundingTimelineSnapshot>[];
    final lines = context.substring(start + '【时间线】'.length).split('\n');
    final linePattern = RegExp(r'^(\d+)\.\s*(.+)$');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('【') && result.isNotEmpty) break;
      final match = linePattern.firstMatch(line);
      if (match == null) continue;
      var text = match.group(2)!.trim();
      final referenceMatch = RegExp(
        r'（依据事实：((?:#\d+)(?:、#\d+)*)）$',
      ).firstMatch(text);
      final factIndexes = referenceMatch == null
          ? const <int>[]
          : referenceMatch
              .group(1)!
              .split('、')
              .map((value) => int.tryParse(value.replaceFirst('#', '')))
              .whereType<int>()
              .toList(growable: false);
      if (referenceMatch != null) {
        text = text.substring(0, referenceMatch.start).trim();
      }
      result.add(GroundingTimelineSnapshot(
        index: int.parse(match.group(1)!),
        text: text,
        factIndexes: factIndexes,
      ));
    }
    return result;
  }

  static int _uniqueFactSourceCount(List<GroundingFactSnapshot> facts) {
    final sources = <String>{};
    for (final fact in facts) {
      final url = fact.sourceUrl.trim().toLowerCase();
      if (url.isNotEmpty) {
        sources.add(url);
        continue;
      }
      final title = fact.sourceTitle.trim().toLowerCase();
      if (title.isNotEmpty) sources.add(title);
    }
    return sources.length;
  }

  static List<GroundingFactSnapshot> _dedupeFacts(
    List<GroundingFactSnapshot> facts,
  ) {
    final result = <GroundingFactSnapshot>[];
    final seen = <String>{};
    for (final fact in facts) {
      final key = _factIdentityKey(fact);
      if (key.isEmpty || !seen.add(key)) continue;
      result.add(fact);
    }
    return result;
  }

  static String _factIdentityKey(GroundingFactSnapshot fact) {
    final source = fact.sourceUrl.trim().toLowerCase().isNotEmpty
        ? fact.sourceUrl.trim().toLowerCase()
        : fact.sourceTitle.trim().toLowerCase();
    final evidence =
        fact.sourceExcerpt.trim().isNotEmpty ? fact.sourceExcerpt : fact.text;
    final textKey = _matchKey(fact.text);
    final evidenceKey = _matchKey(evidence);
    if (textKey.isEmpty || evidenceKey.isEmpty) return '';
    return '$source::$textKey::$evidenceKey';
  }
}

class GroundingFactSnapshot {
  final int index;
  final String text;
  final String sourceTitle;
  final String sourceUrl;
  final String sourceExcerpt;
  final int eventOrder;
  final String chronologyScope;

  const GroundingFactSnapshot({
    required this.index,
    required this.text,
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.sourceExcerpt = '',
    this.eventOrder = 0,
    this.chronologyScope = '',
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'sourceTitle': sourceTitle,
        'sourceUrl': sourceUrl,
        'sourceExcerpt': sourceExcerpt,
        'eventOrder': eventOrder,
        'chronologyScope': chronologyScope,
      };

  factory GroundingFactSnapshot.fromJson(Map json) => GroundingFactSnapshot(
        index: _asInt(json['index']) ?? 0,
        text: '${json['text'] ?? ''}',
        sourceTitle: '${json['sourceTitle'] ?? ''}',
        sourceUrl: '${json['sourceUrl'] ?? ''}',
        sourceExcerpt: '${json['sourceExcerpt'] ?? ''}',
        eventOrder: _asInt(json['eventOrder']) ?? 0,
        chronologyScope: '${json['chronologyScope'] ?? ''}',
      );
}

class GroundingTimelineSnapshot {
  final int index;
  final String text;
  final List<int> factIndexes;

  const GroundingTimelineSnapshot({
    required this.index,
    required this.text,
    this.factIndexes = const [],
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'factIndexes': factIndexes,
      };

  factory GroundingTimelineSnapshot.fromJson(Map json) =>
      GroundingTimelineSnapshot(
        index: _asInt(json['index']) ?? 0,
        text: '${json['text'] ?? ''}',
        factIndexes: (json['factIndexes'] is List)
            ? (json['factIndexes'] as List)
                .map(_asInt)
                .whereType<int>()
                .toList()
            : const [],
      );
}

class GroundingAcceptancePolicy {
  final int minimumFacts;
  final int? maximumFacts;
  final int minimumSources;
  final bool requireTimeline;
  final int maximumSearchApiCalls;
  final List<String> requiredSearchObjects;
  final List<String> requiredFactText;
  final List<String> orderedTimelineAnchors;
  final List<String> forbiddenText;

  const GroundingAcceptancePolicy({
    this.minimumFacts = 1,
    this.maximumFacts,
    this.minimumSources = 0,
    this.requireTimeline = false,
    this.maximumSearchApiCalls = 3,
    this.requiredSearchObjects = const [],
    this.requiredFactText = const [],
    this.orderedTimelineAnchors = const [],
    this.forbiddenText = const [],
  });
}

class GroundingValidationIssue {
  final String code;
  final String message;

  const GroundingValidationIssue({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '$code: $message';
}

class GroundingContractValidator {
  static List<GroundingValidationIssue> validateTimeline({
    required List<GroundingFactSnapshot> facts,
    required List<GroundingTimelineSnapshot> timeline,
  }) {
    final issues = <GroundingValidationIssue>[];
    final lastOrderByScope = <String, int>{};
    for (final step in timeline) {
      if (step.factIndexes.isEmpty) {
        issues.add(GroundingValidationIssue(
          code: 'timeline_reference_missing',
          message: '时间线第 ${step.index} 步没有引用 fact',
        ));
        continue;
      }

      final ordersByScope = <String, List<int>>{};
      for (final factIndex in step.factIndexes) {
        if (factIndex <= 0 || factIndex > facts.length) {
          issues.add(GroundingValidationIssue(
            code: 'timeline_reference_invalid',
            message: '时间线第 ${step.index} 步引用了不存在的 fact #$factIndex',
          ));
          continue;
        }
        final fact = facts[factIndex - 1];
        if (fact.eventOrder <= 0 || fact.chronologyScope.isEmpty) continue;
        ordersByScope
            .putIfAbsent(fact.chronologyScope, () => <int>[])
            .add(fact.eventOrder);
      }

      for (final entry in ordersByScope.entries) {
        final currentMinimum = entry.value.reduce((a, b) => a < b ? a : b);
        final currentMaximum = entry.value.reduce((a, b) => a > b ? a : b);
        final previousOrder = lastOrderByScope[entry.key];
        if (previousOrder != null && currentMinimum < previousOrder) {
          issues.add(GroundingValidationIssue(
            code: 'timeline_order_regressed',
            message: '时间线第 ${step.index} 步在同一批资料中从顺序 '
                '$previousOrder 倒退到了 $currentMinimum',
          ));
        }
        lastOrderByScope[entry.key] = currentMaximum;
      }
    }
    return issues;
  }
}

String encodeGroundingSnapshot(GroundingSnapshot snapshot) =>
    const JsonEncoder.withIndent('  ').convert(snapshot.toJson());

List<String> _stringList(dynamic value) => value is List
    ? value.map((item) => '$item').where((item) => item.isNotEmpty).toList()
    : const [];

int? _asInt(dynamic value) =>
    value is int ? value : int.tryParse('${value ?? ''}');

String _matchKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s　，。！？、,.!?；;：:()（）「」『』“”"《》]+'), '');

bool _containsLoose(String source, String target) {
  final needle = _matchKey(target);
  return needle.isNotEmpty && _matchKey(source).contains(needle);
}
