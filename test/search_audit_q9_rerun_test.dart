import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rerun search audit question 9 without TTS', () async {
    if (Platform.environment['RUN_Q9_AUDIT'] != '1') {
      markTestSkipped('Set RUN_Q9_AUDIT=1 to call remote APIs.');
      return;
    }

    const question = '祥祥，听说在组成MyGO的那段时间，爱音和灯是相互救赎的，你对相关情况有耳闻吗';
    final character = CharacterConfig.getCharacterById('sakiko');
    final logs = <String>[];
    final oldDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.trim().isNotEmpty) {
        logs.add(message);
      }
      oldDebugPrint(message, wrapWidth: wrapWidth);
    };

    String webContext;
    Map<String, String> response;
    try {
      webContext = await WebContextService.buildContext(
        userMessage: question,
        characterId: character.id,
        characterName: character.name,
        conversationHistory: const [],
      );
      response = await ApiService.generateResponse(
        characterPersonality: character.personality,
        conversationHistory: const [],
        userMessage: question,
        webContext: webContext,
        characterId: character.id,
        characterLanguage: character.language,
      );
    } finally {
      debugPrint = oldDebugPrint;
    }

    final report = _formatReport(
      question: question,
      logs: logs,
      webContext: webContext,
      japaneseAnswer: response['japanese'] ?? '',
      chineseAnswer: response['chinese'] ?? '',
    );
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final reportFile = File('reports/search_audit_q9_rerun_$timestamp.md');
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(report, encoding: utf8);
    debugPrint('Q9_AUDIT_REPORT: ${reportFile.absolute.path}');

    expect(webContext, contains('【网页搜索摘要】'));
    expect(response['japanese'] ?? response['chinese'] ?? '', isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

String _formatReport({
  required String question,
  required List<String> logs,
  required String webContext,
  required String japaneseAnswer,
  required String chineseAnswer,
}) {
  final buffer = StringBuffer()
    ..writeln('# 第9题单独复测')
    ..writeln()
    ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
    ..writeln('- 注意：本文件为单题复测，不覆盖原总报告。')
    ..writeln()
    ..writeln('## 问题')
    ..writeln()
    ..writeln(question)
    ..writeln()
    ..writeln('## 搜索/生成日志')
    ..writeln()
    ..writeln('```text')
    ..writeln(_compactLogs(logs).join('\n'))
    ..writeln('```')
    ..writeln()
    ..writeln('## 联网上下文')
    ..writeln()
    ..writeln('```text')
    ..writeln(_extractRelevantContext(webContext))
    ..writeln('```')
    ..writeln()
    ..writeln('## 日语回答')
    ..writeln()
    ..writeln('```text')
    ..writeln(japaneseAnswer.trim())
    ..writeln('```')
    ..writeln()
    ..writeln('## 中文翻译')
    ..writeln()
    ..writeln('```text')
    ..writeln(chineseAnswer.trim())
    ..writeln('```');
  return buffer.toString();
}

List<String> _compactLogs(List<String> logs) {
  final kept = <String>[];
  for (final raw in logs) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(
        r'候选摘要|正文补全|source=|len\(content=|afterUrl=|afterCanon=|raw=|parsed=|host=',
      ).hasMatch(trimmed)) {
        continue;
      }
      if (!kept.contains(trimmed)) kept.add(trimmed);
    }
  }
  return kept;
}

String _extractRelevantContext(String webContext) {
  final marker = RegExp(r'【网页搜索摘要】|【角色设定资料】|【事实时间线】|【网页搜索失败】');
  final first = marker.firstMatch(webContext);
  if (first == null) return webContext.trim();
  var end = webContext.indexOf('\n\n【使用这些信息的规则】', first.start);
  if (end < 0) end = webContext.length;
  return webContext.substring(first.start, end).trim();
}
