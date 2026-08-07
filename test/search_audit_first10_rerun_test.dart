import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/grounding_contract.dart';
import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/grounding_audit_policies.dart';

void main() {
  test('rerun search audit questions 1-13 without TTS', () async {
    if (Platform.environment['RUN_FIRST10_AUDIT'] != '1') {
      markTestSkipped('Set RUN_FIRST10_AUDIT=1 to call remote APIs.');
      return;
    }

    final selectedItems = _selectedAuditItems();
    final reportFile = _reportFile();
    final stateFile = _stateFileFor(reportFile);
    await reportFile.parent.create(recursive: true);
    var records = Platform.environment['AUDIT_RESET'] == '1'
        ? <_AuditRecord>[]
        : await _readSavedRecords(stateFile);
    if (records.isEmpty && Platform.environment['AUDIT_RESET'] != '1') {
      records = await _readLegacyQuestionReports();
    }
    await reportFile.writeAsString(
      _formatReport(records, _auditItems.length),
      encoding: utf8,
    );
    await _writeSavedRecords(stateFile, records);
    if (Platform.environment['AUDIT_SEED_ONLY'] == '1') {
      debugPrint('FIRST10_AUDIT_REPORT: ${reportFile.absolute.path}');
      return;
    }
    final responseOnly = Platform.environment['AUDIT_RESPONSE_ONLY'] == '1';

    for (final item in selectedItems) {
      final character = CharacterConfig.getCharacterById(item.characterId);
      final savedRecord = _recordForIndex(records, item.index);
      final logs = responseOnly && savedRecord != null
          ? _logsBeforeResponseGeneration(savedRecord.logs)
          : <String>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.trim().isNotEmpty) {
          logs.add(message);
        }
        oldDebugPrint(message, wrapWidth: wrapWidth);
      };

      String webContext;
      Map<String, String> response;
      GroundingRunTrace? groundingTrace = savedRecord?.groundingTrace;
      Object? error;
      StackTrace? stackTrace;
      try {
        if (responseOnly) {
          if (savedRecord == null || savedRecord.webContext.trim().isEmpty) {
            throw StateError('仅重生成回答需要已有的联网上下文');
          }
          webContext = savedRecord.webContext;
          groundingTrace = savedRecord.groundingTrace;
          debugPrint('仅重生成回答: 复用第${item.index}题已保存的联网上下文');
        } else {
          final buildResult = await WebContextService.buildContextDetailed(
            userMessage: item.question,
            characterId: character.id,
            characterName: character.name,
            conversationHistory: const [],
          );
          webContext = buildResult.context;
          groundingTrace = buildResult.trace;
        }
        response = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: const [],
          userMessage: item.question,
          webContext: webContext,
          characterId: character.id,
          characterLanguage: character.language,
        );
      } catch (e, st) {
        webContext = '';
        response = const {};
        error = e;
        stackTrace = st;
      } finally {
        debugPrint = oldDebugPrint;
      }

      final record = _AuditRecord(
        item: item,
        logs: logs,
        webContext: webContext,
        japaneseAnswer: response['japanese'] ?? '',
        chineseAnswer: response['chinese'] ?? '',
        groundingTrace: groundingTrace,
        error: error,
        stackTrace: stackTrace,
      );
      records = _replaceRecord(records, record);
      await _writeSavedRecords(stateFile, records);

      await reportFile.writeAsString(
        _formatReport(records, _auditItems.length),
        encoding: utf8,
      );
      debugPrint('FIRST10_AUDIT_PROGRESS_REPORT: ${reportFile.absolute.path}');
    }

    debugPrint('FIRST10_AUDIT_REPORT: ${reportFile.absolute.path}');

    final selectedIndexes = selectedItems.map((item) => item.index).toSet();
    final selectedRecords =
        records.where((record) => selectedIndexes.contains(record.item.index));
    expect(selectedRecords, hasLength(selectedItems.length));
    expect(selectedRecords.where((record) => record.error != null), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

const _auditItems = [
  _AuditItem(
    index: 1,
    characterId: 'shinobu',
    characterName: '蝴蝶忍',
    question: '忍小姐，蝶屋的三个女孩子叫什么呀',
  ),
  _AuditItem(
    index: 2,
    characterId: 'shinobu',
    characterName: '蝴蝶忍',
    question: '忍小姐，有听说过霞柱恢复记忆的经过吗',
  ),
  _AuditItem(
    index: 3,
    characterId: 'shinobu',
    characterName: '蝴蝶忍',
    question: '忍小姐，你当初在那田蜘蛛山是如何支援炭治郎他们的呀',
  ),
  _AuditItem(
    index: 4,
    characterId: 'shinobu',
    characterName: '蝴蝶忍',
    question: '忍小姐，你好像很喜欢养金鱼？我们家也有养鱼，不过我也很喜欢猫猫',
  ),
  _AuditItem(
    index: 5,
    characterId: 'muichirou',
    characterName: '时透无一郎',
    question: '透透，你有听说过音柱和炭治郎他们在游郭出任务的事吗',
  ),
  _AuditItem(
    index: 6,
    characterId: 'muichirou',
    characterName: '时透无一郎',
    question: '透透，你比较常用霞之呼吸的什么招式呀',
  ),
  _AuditItem(
    index: 7,
    characterId: 'sakiko',
    characterName: '丰川祥子',
    question: '祥祥，灯喜欢什么动物呀？闲暇时间常去什么地方呢',
  ),
  _AuditItem(
    index: 8,
    characterId: 'sakiko',
    characterName: '丰川祥子',
    question: '祥祥，立希为什么这么在意灯呀',
  ),
  _AuditItem(
    index: 9,
    characterId: 'sakiko',
    characterName: '丰川祥子',
    question: '祥祥，听说在组成MyGO的那段时间，爱音和灯是相互救赎的，你对相关情况有耳闻吗',
  ),
  _AuditItem(
    index: 10,
    characterId: 'sakiko',
    characterName: '丰川祥子',
    question: '祥祥，KILLKISS真的太燃了，我好喜欢！祥祥觉得你们的这首歌怎么样呢，你比较喜欢mujica的哪些歌呢',
  ),
  _AuditItem(
    index: 11,
    characterId: 'andy',
    characterName: '安迪',
    question: '我最近很喜欢看梦限大的番，姐姐应该不太了解番剧什么的吧hh',
  ),
  _AuditItem(
    index: 12,
    characterId: 'andy',
    characterName: '安迪',
    question: '姐姐，我最近有好多事情要做啊，好忙...真是力竭了',
  ),
  _AuditItem(
    index: 13,
    characterId: 'andy',
    characterName: '安迪',
    question: '听说今年被称为“Agent元年”，姐姐怎么看',
  ),
];

File _reportFile() {
  final explicitPath = Platform.environment['AUDIT_REPORT_PATH']?.trim();
  if (explicitPath != null && explicitPath.isNotEmpty) {
    return File(explicitPath);
  }
  return File('reports/search_audit_first10_rerun_latest.md');
}

File _stateFileFor(File reportFile) {
  return File('${reportFile.path}.state.json');
}

List<_AuditItem> _selectedAuditItems() {
  final rawIndex = Platform.environment['AUDIT_INDEX']?.trim();
  if (rawIndex == null || rawIndex.isEmpty) return _auditItems;
  final index = int.tryParse(rawIndex);
  if (index == null) return _auditItems;
  return _auditItems
      .where((item) => item.index == index)
      .toList(growable: false);
}

String _formatReport(List<_AuditRecord> records, int expectedCount) {
  final sortedRecords = [...records]
    ..sort((a, b) => a.item.index.compareTo(b.item.index));
  final buffer = StringBuffer()
    ..writeln('# 十三题联网搜索与回复复测报告')
    ..writeln()
    ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
    ..writeln('- 范围：原 13 题测试集')
    ..writeln('- 说明：固定总报告；单题重跑时替换对应题目段落，已合格题保留。')
    ..writeln();

  final issueRecords =
      sortedRecords.where((record) => record.issues.isNotEmpty);
  buffer
    ..writeln('## 自动初筛汇总')
    ..writeln()
    ..writeln('- 完成题数：${sortedRecords.length} / $expectedCount')
    ..writeln('- 初筛提示问题：${issueRecords.length}');
  if (issueRecords.isNotEmpty) {
    for (final record in issueRecords) {
      buffer.writeln(
        '- 第 ${record.item.index} 题：${record.issues.join('；')}',
      );
    }
  }

  for (final record in sortedRecords) {
    buffer
      ..writeln()
      ..writeln('## ${record.item.index}. ${record.item.characterName}')
      ..writeln()
      ..writeln('**问题**')
      ..writeln()
      ..writeln(record.item.question)
      ..writeln()
      ..writeln('**搜索/生成日志**')
      ..writeln()
      ..writeln('```text')
      ..writeln(_compactLogs(record.logs).join('\n'))
      ..writeln('```')
      ..writeln()
      ..writeln('**返回给模型的联网上下文**')
      ..writeln()
      ..writeln('```text')
      ..writeln(_extractRelevantContext(record.webContext))
      ..writeln('```');
    if (record.error != null) {
      buffer
        ..writeln()
        ..writeln('**错误**')
        ..writeln()
        ..writeln('```text')
        ..writeln('${record.error}')
        ..writeln(record.stackTrace ?? '')
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('**日语回答**')
      ..writeln()
      ..writeln('```text')
      ..writeln(record.japaneseAnswer.trim())
      ..writeln('```')
      ..writeln()
      ..writeln('**中文回答（DeepSeek原稿）**')
      ..writeln()
      ..writeln('```text')
      ..writeln(record.chineseAnswer.trim())
      ..writeln('```')
      ..writeln()
      ..writeln('**自动初筛**')
      ..writeln()
      ..writeln(record.issues.isEmpty ? '未发现明显问题。' : record.issues.join('\n'));
  }

  return buffer.toString();
}

List<_AuditRecord> _replaceRecord(
  List<_AuditRecord> records,
  _AuditRecord replacement,
) {
  final result = <_AuditRecord>[];
  var replaced = false;
  for (final record in records) {
    if (record.item.index == replacement.item.index) {
      if (!replaced) {
        result.add(replacement);
        replaced = true;
      }
    } else {
      result.add(record);
    }
  }
  if (!replaced) result.add(replacement);
  result.sort((a, b) => a.item.index.compareTo(b.item.index));
  return result;
}

_AuditRecord? _recordForIndex(List<_AuditRecord> records, int index) {
  for (final record in records) {
    if (record.item.index == index) return record;
  }
  return null;
}

List<String> _logsBeforeResponseGeneration(List<String> logs) {
  final result = <String>[];
  final responseLog = RegExp(
    r'^(回复未通过|日语重生成|日语表记|翻译|最终日语|检测到回复|中文角色|仅重生成回答)',
  );
  for (final log in logs) {
    if (responseLog.hasMatch(log.trim())) break;
    result.add(log);
  }
  return result;
}

Future<List<_AuditRecord>> _readSavedRecords(File stateFile) async {
  if (!await stateFile.exists()) return [];
  try {
    final decoded = jsonDecode(await stateFile.readAsString(encoding: utf8));
    if (decoded is! List) return [];
    return decoded
        .map((item) => item is Map ? _AuditRecord.fromJson(item) : null)
        .whereType<_AuditRecord>()
        .toList(growable: false);
  } catch (_) {
    return [];
  }
}

Future<void> _writeSavedRecords(
  File stateFile,
  List<_AuditRecord> records,
) async {
  await stateFile.writeAsString(
    const JsonEncoder.withIndent('  ')
        .convert(records.map((record) => record.toJson()).toList()),
    encoding: utf8,
  );
}

Future<List<_AuditRecord>> _readLegacyQuestionReports() async {
  final records = <_AuditRecord>[];
  for (final item in _auditItems) {
    final file =
        File('reports/search_audit_first10_rerun_q${item.index}_latest.md');
    if (!await file.exists()) continue;
    final text = await file.readAsString(encoding: utf8);
    final record = _recordFromLegacyReport(item, text);
    if (record != null) records.add(record);
  }
  return records;
}

_AuditRecord? _recordFromLegacyReport(_AuditItem item, String text) {
  final question = _legacySection(text, '**问题**', '**搜索/生成日志**');
  final logs = _legacyCodeBlock(text, '**搜索/生成日志**');
  final webContext = _legacyCodeBlock(text, '**返回给模型的联网上下文**');
  final japaneseAnswer = _legacyCodeBlock(text, '**日语回答**');
  final chineseDraft = _legacyCodeBlock(text, '**中文回答（DeepSeek原稿）**');
  final chineseAnswer = chineseDraft.trim().isNotEmpty
      ? chineseDraft
      : _legacyCodeBlock(text, '**中文翻译**');
  if (question.trim().isEmpty &&
      logs.trim().isEmpty &&
      webContext.trim().isEmpty &&
      japaneseAnswer.trim().isEmpty &&
      chineseAnswer.trim().isEmpty) {
    return null;
  }
  return _AuditRecord(
    item: item,
    logs: logs.split('\n').where((line) => line.trim().isNotEmpty).toList(),
    webContext: webContext,
    japaneseAnswer: japaneseAnswer,
    chineseAnswer: chineseAnswer,
  );
}

String _legacySection(String text, String startMarker, String endMarker) {
  final start = text.indexOf(startMarker);
  if (start < 0) return '';
  final contentStart = start + startMarker.length;
  final end = text.indexOf(endMarker, contentStart);
  if (end < 0) return '';
  return text.substring(contentStart, end).trim();
}

String _legacyCodeBlock(String text, String heading) {
  final headingIndex = text.indexOf(heading);
  if (headingIndex < 0) return '';
  final startFence = text.indexOf('```', headingIndex);
  if (startFence < 0) return '';
  var contentStart = text.indexOf('\n', startFence);
  if (contentStart < 0) return '';
  contentStart += 1;
  final endFence = text.indexOf('```', contentStart);
  if (endFence < 0) return '';
  return text.substring(contentStart, endFence).trim();
}

List<String> _compactLogs(List<String> logs) {
  final kept = <String>[];
  final lastMethodByLayer = <String, String>{};
  for (final raw in logs) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(
        r'候选摘要|正文补全|source=|len\(content=|afterUrl=|afterCanon=|raw=|parsed=|host=|过滤诊断',
      ).hasMatch(trimmed)) {
        continue;
      }
      final normalized = _normalizeAuditLogLine(trimmed, lastMethodByLayer);
      if (normalized.isEmpty) continue;
      if (!kept.contains(normalized)) kept.add(normalized);
    }
  }
  return kept;
}

String _normalizeAuditLogLine(
  String line,
  Map<String, String> lastMethodByLayer,
) {
  final moegirlFetch = RegExp(
    r'^萌娘百科词条全文直达(成功|失败|为空或乱码|异常):\s*(.*)$',
  ).firstMatch(line);
  if (moegirlFetch != null) {
    const layer = 'P0 萌娘百科/主站点';
    const method = '直达';
    lastMethodByLayer[layer] = method;
    final status = moegirlFetch.group(1) ?? '';
    final detail = moegirlFetch.group(2) ?? '';
    return '搜索步骤[$layer][$method]: $detail -> $status';
  }

  final moegirlDirectResult = RegExp(r'^萌娘百科词条直达优先:\s*(.*)$').firstMatch(line);
  if (moegirlDirectResult != null) {
    const layer = 'P0 萌娘百科/主站点';
    const method = '直达';
    lastMethodByLayer[layer] = method;
    return '搜索结果[$layer][$method]: ${moegirlDirectResult.group(1)}';
  }

  final localDirectResult = RegExp(r'^本地百度/维基直达优先:\s*(.*)$').firstMatch(line);
  if (localDirectResult != null) {
    const layer = 'P1 百度百科/维基直达解析';
    const method = '直达';
    lastMethodByLayer[layer] = method;
    return '搜索结果[$layer][$method]: ${localDirectResult.group(1)}';
  }

  final baiduDirect =
      RegExp(r'^百度百科搜索(成功|无百科候选|候选正文不可用):\s*(.*)$').firstMatch(line);
  if (baiduDirect != null) {
    const layer = 'P1 百度百科/维基直达解析';
    const method = '百度百科直达';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${baiduDirect.group(2)} -> ${baiduDirect.group(1)}';
  }

  final baiduPcFallback =
      RegExp(r'^百度百科 PC 搜索无百科候选，改用移动搜索:\s*(.*)$').firstMatch(line);
  if (baiduPcFallback != null) {
    const layer = 'P1 百度百科/维基直达解析';
    const method = '百度百科直达';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${baiduPcFallback.group(1)} -> PC无候选，改用移动搜索';
  }

  final wikiDirect = RegExp(r'^(英文)?维基百科词条直达成功:\s*(.*)$').firstMatch(line);
  if (wikiDirect != null) {
    const layer = 'P1 百度百科/维基直达解析';
    final method = wikiDirect.group(1) == null ? '维基百科直达/API' : '英文维基百科直达';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${wikiDirect.group(2)} -> 成功';
  }

  final wikiApiSuccess =
      RegExp(r'^维基百科 API (?:直达|搜索)成功:\s*(.*)$').firstMatch(line);
  if (wikiApiSuccess != null) {
    const layer = 'P1 百度百科/维基直达解析';
    const method = '维基百科直达/API';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${wikiApiSuccess.group(1)} -> 成功';
  }

  if (RegExp(r'^维基百科 API (?:直达|搜索)失败:').hasMatch(line)) {
    return '';
  }

  final siteFailure = RegExp(r'^站点专用搜索失败:\s*(\S+)\s+(.*)$').firstMatch(line);
  if (siteFailure != null) {
    const layer = 'P1 百度百科/维基直达解析';
    const method = '站点直达';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${siteFailure.group(1)} -> 失败: ${siteFailure.group(2)}';
  }

  final stepStart = RegExp(r'^搜索步骤开始\[([^\]]+)\]:\s*(.*)$').firstMatch(line);
  if (stepStart != null) {
    final layer = _auditLayerLabel(stepStart.group(1) ?? '');
    final detail = stepStart.group(2) ?? '';
    final method = detail.startsWith('Global |')
        ? '豆包 Global'
        : detail.startsWith('Custom |')
            ? '豆包 Custom'
            : '搜索API';
    lastMethodByLayer[layer] = method;
    return '搜索步骤[$layer][$method]: ${detail.replaceFirst(RegExp(r'^(Global|Custom)\s*\|\s*'), '')}';
  }

  final stepResult = RegExp(r'^搜索步骤结果\[([^\]]+)\]:\s*(.*)$').firstMatch(line);
  if (stepResult != null) {
    final layer = _auditLayerLabel(stepResult.group(1) ?? '');
    final method = lastMethodByLayer[layer] ?? '搜索API';
    return '搜索结果[$layer][$method]: ${stepResult.group(2)}';
  }

  final adopted = RegExp(r'^采用网页事实\[([^\]]+)\]:\s*(.*)$').firstMatch(line);
  if (adopted != null) {
    final layer = _auditLayerLabel(adopted.group(1) ?? '');
    return '层级判断[$layer]: 采用；${adopted.group(2)}';
  }

  final nextLayer =
      RegExp(r'^当前搜索层未满足，进入下一层:\s*([^，]+)，(.*)$').firstMatch(line);
  if (nextLayer != null) {
    final layer = _auditLayerLabel(nextLayer.group(1) ?? '');
    return '层级判断[$layer]: 未满足，进入下一层；${nextLayer.group(2)}';
  }

  final stopSearch = RegExp(r'^网页事实已足够，停止搜索:\s*(.*)，停在(.+)$').firstMatch(line);
  if (stopSearch != null) {
    final layer = _auditLayerLabel(stopSearch.group(2) ?? '');
    return '层级判断[$layer]: 事实已足够，停止搜索；${stopSearch.group(1)}';
  }

  final usablePartial =
      RegExp(r'^(网页事实不足但可用|网页事实已达上限，使用已收集事实):\s*(.*)$').firstMatch(line);
  if (usablePartial != null) {
    return '层级判断[已收集事实]: ${usablePartial.group(1)}；${usablePartial.group(2)}';
  }

  return line;
}

String _auditLayerLabel(String raw) {
  var layer = raw.trim();
  layer = layer
      .replaceAll('最高优先级来源 - ', '')
      .replaceAll('补充来源 - ', '')
      .replaceAll('全网兜底 - ', '');
  layer = layer
      .replaceAll('百度百科/维基/官方/资料站', '百度百科/维基/官方/资料站')
      .replaceAll('开放全网', '开放全网');
  return layer;
}

String _extractRelevantContext(String webContext) {
  final marker = RegExp(r'【网页搜索摘要】|【事实时间线】|【网页搜索失败】');
  final first = marker.firstMatch(webContext);
  if (first == null) return webContext.trim();
  var end = webContext.indexOf('\n\n【使用这些信息的规则】', first.start);
  if (end < 0) end = webContext.length;
  final withoutRoleBlock = _removeContextBlock(
    webContext.substring(first.start, end).trim(),
    '角色设定资料',
  );
  return withoutRoleBlock
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('本地角色设定：'))
      .join('\n')
      .trim();
}

String _removeContextBlock(String text, String title) {
  final pattern = RegExp(
    '(?:^|\\n)【${RegExp.escape(title)}】[\\s\\S]*?(?=\\n\\n【|\$)',
  );
  return text.replaceAll(pattern, '').trim();
}

class _AuditItem {
  final int index;
  final String characterId;
  final String characterName;
  final String question;

  const _AuditItem({
    required this.index,
    required this.characterId,
    required this.characterName,
    required this.question,
  });
}

class _AuditRecord {
  final _AuditItem item;
  final List<String> logs;
  final String webContext;
  final String japaneseAnswer;
  final String chineseAnswer;
  final GroundingRunTrace? groundingTrace;
  final Object? error;
  final StackTrace? stackTrace;

  const _AuditRecord({
    required this.item,
    required this.logs,
    required this.webContext,
    required this.japaneseAnswer,
    required this.chineseAnswer,
    this.groundingTrace,
    this.error,
    this.stackTrace,
  });

  factory _AuditRecord.fromJson(Map json) {
    final index = json['index'] is int
        ? json['index'] as int
        : int.tryParse('${json['index']}') ?? -1;
    final item = _auditItems.firstWhere(
      (candidate) => candidate.index == index,
      orElse: () => _AuditItem(
        index: index,
        characterId: '${json['characterId'] ?? ''}',
        characterName: '${json['characterName'] ?? ''}',
        question: '${json['question'] ?? ''}',
      ),
    );
    return _AuditRecord(
      item: item,
      logs: (json['logs'] is List)
          ? (json['logs'] as List).map((line) => '$line').toList()
          : const [],
      webContext: '${json['webContext'] ?? ''}',
      japaneseAnswer: '${json['japaneseAnswer'] ?? ''}',
      chineseAnswer: '${json['chineseAnswer'] ?? ''}',
      groundingTrace: json['groundingTrace'] is Map
          ? GroundingRunTrace.fromJson(json['groundingTrace'] as Map)
          : null,
      error: json['error'],
      stackTrace: json['stackTrace'] == null
          ? null
          : StackTrace.fromString('${json['stackTrace']}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'index': item.index,
        'characterId': item.characterId,
        'characterName': item.characterName,
        'question': item.question,
        'logs': logs,
        'webContext': webContext,
        'japaneseAnswer': japaneseAnswer,
        'chineseAnswer': chineseAnswer,
        if (groundingTrace != null) 'groundingTrace': groundingTrace!.toJson(),
        if (error != null) 'error': '$error',
        if (stackTrace != null) 'stackTrace': '$stackTrace',
      };

  List<String> get issues {
    final result = <String>[];
    if (error != null) result.add('运行异常');
    if (webContext.trim().isEmpty) result.add('联网上下文为空');
    if (webContext.contains('【网页搜索失败】')) result.add('网页搜索失败');
    if (japaneseAnswer.trim().isEmpty) result.add('日语回答为空');
    if (chineseAnswer.trim().isEmpty) result.add('中文回答为空');
    if (_containsObviousChinese(japaneseAnswer)) {
      result.add('日语回答疑似残留中文');
    }
    if (japaneseAnswer.trim().isNotEmpty &&
        !ApiService.isJapaneseStyleCompatible(
          japaneseAnswer,
          item.characterId,
        )) {
      result.add('日语回答不符合角色语体');
    }
    if (item.index == 9 && !webContext.contains('【事实时间线】')) {
      result.add('关系/经过题缺少事实时间线');
    }
    if (webContext.trim().isNotEmpty) {
      final parsed = GroundingSnapshot.fromAudit(
        logs: logs,
        webContext: webContext,
        japaneseAnswer: japaneseAnswer,
        chineseAnswer: chineseAnswer,
      );
      final snapshot = GroundingSnapshot(
        contractVersion: parsed.contractVersion,
        searchObjects: parsed.searchObjects,
        facts: parsed.facts,
        timeline: parsed.timeline,
        searchApiCalls: groundingTrace?.searchApiCalls ?? parsed.searchApiCalls,
        japaneseAnswer: parsed.japaneseAnswer,
        chineseAnswer: parsed.chineseAnswer,
      );
      for (final issue in snapshot.validate(
        groundingAuditPolicyFor(item.index),
      )) {
        result.add(issue.message);
      }
    }
    return result;
  }
}

bool _containsObviousChinese(String text) {
  return RegExp(
    r'(?:他们|她们|我们|你们|这个|那个|这些|那些|因为|所以|但是|如果|不是|没有|什么|怎么|为什么|真的吗|可以吗|的话)',
  ).hasMatch(text);
}
