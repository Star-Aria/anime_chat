import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/storage_service.dart';
import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter/widgets.dart';

class _AuditQuestion {
  const _AuditQuestion({
    required this.characterId,
    required this.text,
  });

  final String characterId;
  final String text;
}

class _SelectedAuditQuestion {
  const _SelectedAuditQuestion({
    required this.index,
    required this.question,
  });

  final int index;
  final _AuditQuestion question;
}

class _AuditResult {
  _AuditResult({
    required this.index,
    required this.characterName,
    required this.question,
    required this.searchLogs,
    required this.searchExcerpt,
    required this.japaneseAnswer,
    required this.chineseAnswer,
    required this.issues,
  });

  final int index;
  final String characterName;
  final String question;
  final List<String> searchLogs;
  final String searchExcerpt;
  final String japaneseAnswer;
  final String chineseAnswer;
  final List<String> issues;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'characterName': characterName,
      'question': question,
      'searchLogs': searchLogs,
      'searchExcerpt': searchExcerpt,
      'japaneseAnswer': japaneseAnswer,
      'chineseAnswer': chineseAnswer,
      'issues': issues,
    };
  }

  static _AuditResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final index = value['index'];
    if (index is! int) return null;
    List<String> stringList(Object? raw) {
      if (raw is! List) return const [];
      return raw.whereType<String>().toList(growable: false);
    }

    return _AuditResult(
      index: index,
      characterName: value['characterName'] is String
          ? value['characterName'] as String
          : '',
      question: value['question'] is String ? value['question'] as String : '',
      searchLogs: stringList(value['searchLogs']),
      searchExcerpt: value['searchExcerpt'] is String
          ? value['searchExcerpt'] as String
          : '',
      japaneseAnswer: value['japaneseAnswer'] is String
          ? value['japaneseAnswer'] as String
          : '',
      chineseAnswer: value['chineseAnswer'] is String
          ? value['chineseAnswer'] as String
          : '',
      issues: stringList(value['issues']),
    );
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final reportFile = File('reports/search_audit_report.md');
  final stateFile = File('reports/search_audit_results.json');
  final startedAt = DateTime.now();
  final allQuestions = _auditQuestions();
  final questions = _selectAuditQuestions(allQuestions, args);
  final resultsByIndex = await _readCumulativeResults(stateFile);
  final reportOnly = args.contains('--report-only');

  try {
    await reportFile.parent.create(recursive: true);
    await _writeReport(
      reportFile: reportFile,
      startedAt: startedAt,
      results: _sortedResults(resultsByIndex),
      total: allQuestions.length,
      partial: true,
    );
    if (reportOnly) {
      debugPrint('SEARCH_AUDIT report refreshed: ${reportFile.absolute.path}');
      exit(0);
    }

    final histories = <String, List<Message>>{};
    for (var i = 0; i < questions.length; i++) {
      final selected = questions[i];
      final item = selected.question;
      final character = CharacterConfig.getCharacterById(item.characterId);
      final history =
          histories.putIfAbsent(item.characterId, () => <Message>[]);
      final logs = <String>[];

      debugPrint(
        'SEARCH_AUDIT ${selected.index}/${allQuestions.length}: '
        '${character.name} <= ${item.text}',
      );

      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.trim().isNotEmpty) {
          logs.add(message);
        }
        oldDebugPrint(message, wrapWidth: wrapWidth);
      };

      var webContext = '';
      Map<String, String> response = const {'japanese': '', 'chinese': ''};
      Object? error;
      StackTrace? stackTrace;

      try {
        webContext = await WebContextService.buildContext(
          userMessage: item.text,
          characterId: character.id,
          characterName: character.name,
          conversationHistory: history,
        );

        response = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: history,
          userMessage: item.text,
          webContext: webContext,
          characterId: character.id,
          characterLanguage: character.language,
        );
      } catch (e, st) {
        error = e;
        stackTrace = st;
      } finally {
        debugPrint = oldDebugPrint;
      }

      final japanese = response['japanese'] ?? '';
      final chinese = response['chinese'] ?? '';
      final issues = _detectIssues(
        characterId: item.characterId,
        logs: logs,
        webContext: webContext,
        japaneseAnswer: japanese,
        chineseAnswer: chinese,
        error: error,
      );
      if (error != null) {
        issues.add('运行异常：$error');
        issues.add('异常堆栈：${_firstStackLine(stackTrace)}');
      }

      final searchLogs = _compactSearchLogs(logs.where(_isSearchLog));
      resultsByIndex[selected.index] = _AuditResult(
        index: selected.index,
        characterName: character.name,
        question: item.text,
        searchLogs: searchLogs,
        searchExcerpt: _extractSearchExcerpt(webContext),
        japaneseAnswer: japanese,
        chineseAnswer: chinese,
        issues: issues,
      );
      await _writeCumulativeResults(stateFile, resultsByIndex);

      if (error == null) {
        history.add(
          Message(
            role: 'user',
            content: item.text,
            timestamp: DateTime.now(),
          ),
        );
        history.add(
          Message(
            role: 'assistant',
            content: japanese.isNotEmpty ? japanese : chinese,
            timestamp: DateTime.now(),
          ),
        );
      }

      await _writeReport(
        reportFile: reportFile,
        startedAt: startedAt,
        results: _sortedResults(resultsByIndex),
        total: allQuestions.length,
        partial: resultsByIndex.length < allQuestions.length,
      );
    }

    debugPrint('SEARCH_AUDIT report written: ${reportFile.absolute.path}');
    exit(0);
  } catch (e, st) {
    resultsByIndex[0] = _AuditResult(
      index: 0,
      characterName: '脚本自身',
      question: '运行审计脚本',
      searchLogs: const [],
      searchExcerpt: '脚本运行中断。',
      japaneseAnswer: '',
      chineseAnswer: '',
      issues: ['脚本自身异常：$e', '异常堆栈：${_firstStackLine(st)}'],
    );
    await _writeCumulativeResults(stateFile, resultsByIndex);
    await _writeReport(
      reportFile: reportFile,
      startedAt: startedAt,
      results: _sortedResults(resultsByIndex),
      total: allQuestions.length,
      partial: true,
    );
    debugPrint('SEARCH_AUDIT failed: $e');
    exit(1);
  }
}

List<_SelectedAuditQuestion> _selectAuditQuestions(
  List<_AuditQuestion> allQuestions,
  List<String> args,
) {
  if (args.isEmpty) {
    return [
      for (var i = 0; i < allQuestions.length; i++)
        _SelectedAuditQuestion(index: i + 1, question: allQuestions[i]),
    ];
  }
  final selected = <_SelectedAuditQuestion>[];
  for (final arg in args) {
    final index = int.tryParse(arg);
    if (index == null || index < 1 || index > allQuestions.length) continue;
    selected.add(
      _SelectedAuditQuestion(index: index, question: allQuestions[index - 1]),
    );
  }
  return selected.isEmpty
      ? [
          for (var i = 0; i < allQuestions.length; i++)
            _SelectedAuditQuestion(index: i + 1, question: allQuestions[i]),
        ]
      : selected;
}

List<_AuditQuestion> _auditQuestions() {
  return const [
    _AuditQuestion(
      characterId: 'shinobu',
      text: '忍小姐，蝶屋的三个女孩子叫什么呀',
    ),
    _AuditQuestion(
      characterId: 'shinobu',
      text: '忍小姐，有听说过霞柱恢复记忆的经过吗',
    ),
    _AuditQuestion(
      characterId: 'shinobu',
      text: '忍小姐，你当初在那田蜘蛛山是如何支援炭治郎他们的呀',
    ),
    _AuditQuestion(
      characterId: 'shinobu',
      text: '忍小姐，你好像很喜欢养金鱼？我们家也有养鱼，不过我也很喜欢猫猫',
    ),
    _AuditQuestion(
      characterId: 'muichirou',
      text: '透透，你有听说过音柱和炭治郎他们在游郭出任务的事吗',
    ),
    _AuditQuestion(
      characterId: 'muichirou',
      text: '透透，你比较常用霞之呼吸的什么招式呀',
    ),
    _AuditQuestion(
      characterId: 'sakiko',
      text: '祥祥，灯喜欢什么动物呀？闲暇时间常去什么地方呢',
    ),
    _AuditQuestion(
      characterId: 'sakiko',
      text: '祥祥，立希为什么这么在意灯呀',
    ),
    _AuditQuestion(
      characterId: 'sakiko',
      text: '祥祥，听说在组成MyGO的那段时间，爱音和灯是相互救赎的，你对相关情况有耳闻吗',
    ),
    _AuditQuestion(
      characterId: 'sakiko',
      text: '祥祥，KILLKISS真的太燃了，我好喜欢！祥祥觉得你们的这首歌怎么样呢，你比较喜欢mujica的哪些歌呢',
    ),
    _AuditQuestion(
      characterId: 'andy',
      text: '我最近很喜欢看梦限大的番，姐姐应该不太了解番剧什么的吧hh',
    ),
    _AuditQuestion(
      characterId: 'andy',
      text: '姐姐，我最近有好多事情要做啊，好忙...真是力竭了',
    ),
    _AuditQuestion(
      characterId: 'andy',
      text: '听说今年被称为“Agent元年”，姐姐怎么看',
    ),
  ];
}

bool _isSearchLog(String line) {
  final keywords = <String>[
    '联网计划',
    '原作搜索对象',
    '联网上下文',
    '网页搜索',
    '豆包',
    '火山',
    '方舟',
    '事实提取',
    'provider',
    '搜索词',
    '搜索成功',
    '搜索失败',
    '搜索异常',
    '无可用结果',
    '候选',
    '正文',
    '截取',
    'Tavily',
    'DuckDuckGo',
    '萌娘',
    '维基',
    '百度',
    '天气',
    '节日',
    'canon',
  ];
  return keywords.any(line.contains);
}

List<String> _compactSearchLogs(Iterable<String> rawLogs) {
  final rawLines = <String>[];
  for (final raw in rawLogs) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) rawLines.add(trimmed);
    }
  }

  final summarized = _summarizeSearchLogs(rawLines);
  if (summarized.isNotEmpty) return summarized;

  final compact = <String>[];
  final seen = <String>{};
  for (final trimmed in rawLines) {
    if (_isNoisySearchLog(trimmed)) continue;
    if (seen.contains(trimmed)) continue;
    compact.add(trimmed);
    seen.add(trimmed);
  }
  return compact;
}

List<String> _summarizeSearchLogs(List<String> rawLines) {
  final result = <String>[];
  final plan = rawLines.where((line) => line.startsWith('联网计划:')).firstOrNull;
  if (plan != null) {
    result.add(plan.replaceFirst(RegExp(r', query=.*$'), ''));
  }

  final objectsLine =
      rawLines.where((line) => line.startsWith('原作搜索对象:')).firstOrNull;
  if (objectsLine != null) result.add(objectsLine);

  final layerQueries = <String, List<String>>{};
  final layerHits = <String, int>{};
  final adopted = <String>[];
  final timelineLogs = <String>[];
  for (final line in rawLines) {
    final startMatch = RegExp(r'搜索步骤开始\[(.+?)\]:\s*(.+)$').firstMatch(line);
    if (startMatch != null) {
      final layer = startMatch.group(1) ?? '搜索层';
      final query = _cleanAuditSearchQuery(startMatch.group(2) ?? '');
      if (query.isNotEmpty) {
        layerQueries.putIfAbsent(layer, () => <String>[]);
        if (!layerQueries[layer]!.contains(query)) {
          layerQueries[layer]!.add(query);
        }
      }
      continue;
    }

    final hitMatch = RegExp(r'搜索步骤结果\[(.+?)\]: 命中(\d+)条').firstMatch(line);
    if (hitMatch != null) {
      final layer = hitMatch.group(1) ?? '搜索层';
      final count = int.tryParse(hitMatch.group(2) ?? '') ?? 0;
      layerHits[layer] = (layerHits[layer] ?? 0) + count;
      continue;
    }

    if (line.startsWith('采用网页事实') ||
        line.startsWith('网页事实已足够') ||
        line.startsWith('网页事实已达上限') ||
        line.startsWith('网页事实不足但可用')) {
      final normalized =
          line.replaceAll(RegExp(r'累计事实=(\d+)'), r'抽取事实=$1').trim();
      if (!adopted.contains(normalized)) adopted.add(normalized);
      continue;
    }

    if (line.startsWith('豆包时间线整理结果:')) {
      final normalized = line.replaceFirst('豆包时间线整理结果:', '时间线整理:');
      if (!timelineLogs.contains(normalized)) timelineLogs.add(normalized);
      continue;
    }
    if (line.contains('时间线整理') &&
        (line.contains('跳过') ||
            line.contains('失败') ||
            line.contains('丢弃') ||
            line.contains('保留'))) {
      if (!timelineLogs.contains(line)) timelineLogs.add(line);
    }
  }

  for (final entry in layerQueries.entries) {
    final shownQueries = _formatAuditQueryList(entry.value);
    result.add('搜索步骤[${entry.key}]: 尝试 $shownQueries');
    final hits = layerHits[entry.key] ?? 0;
    result.add(
      hits > 0 ? '搜索结果[${entry.key}]: 合计命中$hits条' : '搜索结果[${entry.key}]: 无可用结果',
    );
  }

  result.addAll(adopted);
  result.addAll(timelineLogs);
  return result;
}

String _cleanAuditSearchQuery(String raw) {
  var query = raw
      .replaceFirst(RegExp(r'^(Custom|Global)\s*\|\s*'), '')
      .replaceFirst(RegExp(r'\s*\|?\s*sites=.*$'), '')
      .replaceFirst(RegExp(r'\s*,\s*authInfoLevel=.*$'), '')
      .replaceFirst(RegExp(r'\s*,\s*engine=.*$'), '')
      .trim();
  query = query.replaceAll(RegExp(r'\s+'), ' ');
  return query;
}

String _formatAuditQueryList(List<String> queries) {
  final clean = <String>[];
  for (final query in queries) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.length > 30 && RegExp(r'[？?。！!]').hasMatch(trimmed)) {
      continue;
    }
    if (!clean.contains(trimmed)) clean.add(trimmed);
  }
  if (clean.isEmpty) return '（无有效精简查询）';
  final head = clean.take(4).join('、');
  if (clean.length <= 4) return head;
  return '$head 等${clean.length}个查询';
}

bool _isNoisySearchLog(String line) {
  final noisyPatterns = <String>[
    '候选摘要',
    '候选过滤诊断',
    '本地来源排序',
    '正文补全',
    '事实抽取输入',
    '事实提取摘要',
    'JSON 不完整，已宽松恢复',
    '跳过重复候选',
    'provider=',
    'host=',
    'source=',
    'len(content=',
    'afterUrl=',
    'afterCanon=',
    'afterSites=',
    'afterTarget=',
    'raw=',
    'parsed=',
    '无 URL 过滤后的候选',
    '豆包/火山方舟搜索计划 成功',
    '豆包/火山方舟事实抽取 成功',
    '豆包/火山方舟时间线整理 成功',
    '豆包搜索 API 查询[',
    '豆包搜索 API 成功[',
    '豆包搜索 API 无结果[',
    '豆包当前优先级层只有部分事实',
    '豆包搜索只有部分事实',
  ];
  return noisyPatterns.any(line.contains);
}

List<String> _detectIssues({
  required String characterId,
  required List<String> logs,
  required String webContext,
  required String japaneseAnswer,
  required String chineseAnswer,
  required Object? error,
}) {
  final issues = <String>[];
  final logText = logs.join('\n');

  if (error != null) return issues;
  if (webContext.trim().isEmpty) {
    issues.add('本轮没有生成联网上下文，可能是联网计划判断为无需搜索。');
  }
  if (webContext.contains('【网页搜索失败】')) {
    issues.add('网页搜索最终失败。');
  }
  if (logText.contains('异常')) {
    issues.add('搜索或生成日志中出现异常。');
  }
  if (logText.contains('无可用结果')) {
    issues.add('至少一层搜索返回无可用结果。');
  }
  if (logText.contains('候选正文不可用')) {
    issues.add('搜索候选命中后正文抓取或清洗不可用。');
  }
  if (japaneseAnswer.trim().isEmpty && chineseAnswer.trim().isEmpty) {
    issues.add('大模型没有返回可记录的回复。');
  }
  if (japaneseAnswer.contains(RegExp(r'[，；]'))) {
    issues.add('日语回复里出现中文逗号或分号，可能有中日混杂或格式未规范化。');
  }
  issues.addAll(
    _detectFixedCallNameIssues(
      characterId: characterId,
      japaneseAnswer: japaneseAnswer,
      chineseAnswer: chineseAnswer,
    ),
  );

  return issues;
}

List<String> _detectFixedCallNameIssues({
  required String characterId,
  required String japaneseAnswer,
  required String chineseAnswer,
}) {
  final issues = <String>[];
  final callNames = ApiService.fixedCharacterCallNamesForCharacter(characterId);
  if (callNames.isEmpty) return issues;

  final chineseTargets =
      ApiService.fixedCharacterCallNameChineseTargets(characterId);
  const suffixes = ['さん', 'ちゃん', 'くん', '君', '様', 'さま', '先生', '先輩'];

  for (final entry in callNames.entries) {
    final displayName = entry.key.trim();
    final callName = entry.value.trim();
    if (displayName.isEmpty || callName.isEmpty) continue;

    if (japaneseAnswer.contains(displayName)) {
      issues.add('日语回答未按固定称呼：出现“$displayName”，应使用“$callName”。');
    }
    if (!_endsWithKnownAuditSuffix(callName)) {
      for (final suffix in suffixes) {
        if (japaneseAnswer.contains('$callName$suffix')) {
          issues.add('日语回答给固定称呼乱加后缀：出现“$callName$suffix”，应使用“$callName”。');
          break;
        }
      }
    }

    final target = chineseTargets[displayName]?.trim();
    if (target == null || target.isEmpty) continue;
    if (_hasSecondPersonConfusion(chineseAnswer, target)) {
      issues.add('中文译文疑似把第三人称“$target”误译成正在对话的“你”。');
    }
  }

  return issues;
}

bool _endsWithKnownAuditSuffix(String text) {
  const suffixes = ['さん', 'ちゃん', 'くん', '君', '様', 'さま', '先生', '先輩'];
  return suffixes.any(text.endsWith);
}

bool _hasSecondPersonConfusion(String text, String target) {
  final sentencePattern = RegExp(r'[^。！？!?]+[。！？!?]?');
  final explicitSecondPerson = RegExp(
    r'[你您](?:的|喜欢|常去|经常|会去|去过|拿|给|带|邀请|在意|珍视|救赎)',
  );
  for (final match in sentencePattern.allMatches(text)) {
    final sentence = match.group(0) ?? '';
    if (!sentence.contains(target)) continue;
    if (explicitSecondPerson.hasMatch(sentence)) {
      return true;
    }
  }
  return false;
}

String _extractSearchExcerpt(String webContext) {
  final text = webContext.trim();
  if (text.isEmpty) return '无联网上下文。';

  final marker = RegExp(r'【网页搜索摘要】|【角色设定资料】|【网页搜索失败】');
  final match = marker.firstMatch(text);
  if (match == null) return text;

  var end = text.indexOf('\n\n【使用这些信息的规则】', match.start);
  if (end < 0) end = text.length;
  return text.substring(match.start, end).trim();
}

String _firstStackLine(StackTrace? stackTrace) {
  if (stackTrace == null) return '';
  final lines = stackTrace.toString().trim().split('\n');
  return lines.isEmpty ? '' : lines.first;
}

Future<Map<int, _AuditResult>> _readCumulativeResults(File stateFile) async {
  if (!await stateFile.exists()) return <int, _AuditResult>{};
  try {
    final decoded = jsonDecode(await stateFile.readAsString());
    if (decoded is! List) return <int, _AuditResult>{};
    final results = <int, _AuditResult>{};
    for (final item in decoded) {
      final result = _AuditResult.fromJson(item);
      if (result == null) continue;
      results[result.index] = result;
    }
    return results;
  } catch (_) {
    return <int, _AuditResult>{};
  }
}

Future<void> _writeCumulativeResults(
  File stateFile,
  Map<int, _AuditResult> resultsByIndex,
) async {
  await stateFile.parent.create(recursive: true);
  final results = _sortedResults(resultsByIndex)
      .map((result) => result.toJson())
      .toList(growable: false);
  await stateFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(results),
  );
}

List<_AuditResult> _sortedResults(Map<int, _AuditResult> resultsByIndex) {
  final entries = resultsByIndex.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => entry.value).toList(growable: false);
}

Future<void> _writeReport({
  required File reportFile,
  required DateTime startedAt,
  required List<_AuditResult> results,
  required int total,
  required bool partial,
}) async {
  final buffer = StringBuffer();
  buffer.writeln('# 联网搜索与回复审计报告');
  buffer.writeln();
  buffer.writeln('- 开始时间：${startedAt.toIso8601String()}');
  buffer.writeln('- 更新时间：${DateTime.now().toIso8601String()}');
  buffer.writeln('- 进度：${results.length} / $total');
  buffer.writeln('- 状态：${partial ? '进行中' : '已完成'}');
  buffer.writeln('- 说明：本脚本只调用联网检索与大模型回复生成，不执行分句、情绪分析或 TTS。');
  buffer.writeln();

  for (final result in results) {
    buffer.writeln('## ${result.index}. ${result.characterName}');
    buffer.writeln();
    buffer.writeln('**问题**');
    buffer.writeln();
    buffer.writeln(result.question);
    buffer.writeln();
    buffer.writeln('**搜索情况**');
    buffer.writeln();
    final displaySearchLogs = _compactSearchLogs(result.searchLogs);
    if (displaySearchLogs.isEmpty) {
      buffer.writeln('未捕获到搜索相关日志。');
    } else {
      buffer.writeln('```text');
      buffer.writeln(displaySearchLogs.join('\n').trim());
      buffer.writeln('```');
    }
    buffer.writeln();
    buffer.writeln('**返回的联网事实/上下文**');
    buffer.writeln();
    buffer.writeln('```text');
    buffer.writeln(result.searchExcerpt.trim());
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('**大模型日语回答**');
    buffer.writeln();
    buffer.writeln(result.japaneseAnswer.trim().isEmpty
        ? '（无，通常表示中文角色或生成失败）'
        : result.japaneseAnswer.trim());
    buffer.writeln();
    buffer.writeln('**中文翻译/中文回答**');
    buffer.writeln();
    buffer.writeln(result.chineseAnswer.trim().isEmpty
        ? '（无）'
        : result.chineseAnswer.trim());
    buffer.writeln();
    buffer.writeln('**本轮问题记录**');
    buffer.writeln();
    if (result.issues.isEmpty) {
      buffer.writeln('未自动检测到明显问题。');
    } else {
      for (final issue in result.issues) {
        buffer.writeln('- $issue');
      }
    }
    buffer.writeln();
  }

  buffer.writeln('## 汇总');
  buffer.writeln();
  if (results.isEmpty) {
    buffer.writeln('尚未完成任何问题。');
  } else {
    final allIssues = <String, int>{};
    for (final result in results) {
      for (final issue in result.issues) {
        allIssues[issue] = (allIssues[issue] ?? 0) + 1;
      }
    }

    if (allIssues.isEmpty) {
      buffer.writeln('已完成的问题中，未自动检测到明显搜索或生成漏洞。');
    } else {
      buffer.writeln('自动检测到的问题类型：');
      for (final entry in allIssues.entries) {
        buffer.writeln('- ${entry.key}（${entry.value} 次）');
      }
    }
  }

  await reportFile.writeAsString(buffer.toString());
}
