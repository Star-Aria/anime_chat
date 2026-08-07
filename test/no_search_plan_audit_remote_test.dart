import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/web_context_service.dart';

void main() {
  test('remote no-search plan audit', () async {
    final cases = [
      _AuditCase(
        characterId: 'shinobu',
        question: '忍小姐，今天你还好吗，能陪我说说话吗',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'muichirou',
        question: '无一郎，今天训练累不累，陪我发会儿呆吧',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'giyu',
        question: '义勇先生，最近心情怎么样，想随便聊聊吗',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'sakiko',
        question: '小祥，最近乐队里有发生什么有趣的事吗',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'sakiko',
        question: '小祥，最近Mujica有演出安排吗',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'andy',
        question: '姐姐，我今天有点累，可以陪我聊会儿吗',
        expectNoSearch: true,
      ),
      _AuditCase(
        characterId: 'sakiko',
        question: '小祥，听说MyGO曾经在live里突然演奏了《春日影》？',
        expectNoSearch: false,
      ),
      _AuditCase(
        characterId: 'andy',
        question: '姐姐，最近中国股市有什么新政策吗',
        expectNoSearch: false,
      ),
      _AuditCase(
        characterId: 'shinobu',
        question: '忍小姐，今天会下雨吗',
        expectNoSearch: false,
      ),
    ];

    final reportsDir = Directory('reports');
    if (!reportsDir.existsSync()) reportsDir.createSync(recursive: true);
    const reportPath = 'reports/no_search_plan_audit_latest.md';
    final reportFile = File(reportPath);

    final existingReport =
        reportFile.existsSync() ? reportFile.readAsStringSync() : '';
    var report = _AuditReportDocument.read(existingReport);
    report.generatedAt = DateTime.now().toIso8601String();
    final failures = <String>[];

    final selectedIndexes = _selectedIndexesFromEnv();
    final selectedCases = [
      for (var i = 0; i < cases.length; i++)
        if (selectedIndexes == null || selectedIndexes.contains(i + 1))
          MapEntry(i, cases[i]),
    ];

    for (final selected in selectedCases) {
      final i = selected.key;
      final item = selected.value;
      final character = CharacterConfig.getCharacterById(item.characterId);
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.trim().isNotEmpty) {
          logs.add(message);
        }
      };

      var context = '';
      var searchApiCalls = -1;
      var modelCalls = -1;
      Map<String, String> response = const {'japanese': '', 'chinese': ''};
      Object? error;
      StackTrace? stackTrace;
      try {
        final result = await WebContextService.buildContextDetailed(
          userMessage: item.question,
          characterId: character.id,
          characterName: character.name,
        );
        context = result.context;
        searchApiCalls = result.trace.searchApiCalls;
        modelCalls = result.trace.modelCalls;

        response = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: const [],
          userMessage: item.question,
          webContext: context,
          characterId: character.id,
          characterLanguage: character.language,
        );
      } catch (e, st) {
        error = e;
        stackTrace = st;
      } finally {
        debugPrint = previousDebugPrint;
      }

      final planLog = logs.lastWhere(
        (line) => line.startsWith('联网计划:'),
        orElse: () => '联网计划: <missing>',
      );
      final hasWebSummary = context.contains('【网页搜索摘要】');
      final hasSearchFailure = context.contains('【网页搜索失败】');
      final hasWeather = context.contains('【实时天气】');
      final japaneseAnswer = response['japanese'] ?? '';
      final chineseAnswer = response['chinese'] ?? '';
      final hasAnswer =
          japaneseAnswer.trim().isNotEmpty || chineseAnswer.trim().isNotEmpty;
      final hasJapaneseFallback = _looksLikeJapaneseFallback(japaneseAnswer);
      final actualNoSearch = searchApiCalls == 0 && !hasWebSummary;
      final planPassed =
          item.expectNoSearch ? actualNoSearch : !actualNoSearch || hasWeather;
      final passed =
          error == null && hasAnswer && !hasJapaneseFallback && planPassed;
      if (!passed) {
        failures.add('${i + 1}. ${character.name}: ${item.question} -> $planLog'
            '${hasJapaneseFallback ? ' | Japanese fallback' : ''}'
            '${error == null ? '' : ' | error: $error'}');
      }

      final section = StringBuffer()
        ..writeln('## ${i + 1}. ${character.name}')
        ..writeln()
        ..writeln('- Question: ${item.question}')
        ..writeln(
            '- Expected: ${item.expectNoSearch ? 'no search' : 'search/context task'}')
        ..writeln('- Result: ${passed ? 'PASS' : 'FAIL'}')
        ..writeln('- Plan: $planLog')
        ..writeln('- Search API calls: $searchApiCalls')
        ..writeln('- Model calls: $modelCalls')
        ..writeln('- Has web summary: $hasWebSummary')
        ..writeln('- Has search failure: $hasSearchFailure')
        ..writeln('- Has weather context: $hasWeather')
        ..writeln('- Has DeepSeek answer: $hasAnswer')
        ..writeln('- Has Japanese fallback: $hasJapaneseFallback')
        ..writeln()
        ..writeln('### Chinese Answer')
        ..writeln()
        ..writeln(
            chineseAnswer.trim().isEmpty ? '<empty>' : chineseAnswer.trim())
        ..writeln()
        ..writeln('### Japanese Answer')
        ..writeln()
        ..writeln(
            japaneseAnswer.trim().isEmpty ? '<empty>' : japaneseAnswer.trim())
        ..writeln();
      final translationLogs = _translationLogs(logs);
      if (translationLogs.isNotEmpty) {
        section
          ..writeln('### Translation Logs')
          ..writeln()
          ..writeln('```')
          ..writeln(translationLogs.join('\n'))
          ..writeln('```')
          ..writeln();
      }
      if (error != null) {
        section
          ..writeln('### Error')
          ..writeln()
          ..writeln('```')
          ..writeln(error)
          ..writeln(_firstStackLine(stackTrace))
          ..writeln('```')
          ..writeln();
      }
      report.sections[i + 1] = section.toString().trimRight();
      reportFile.writeAsStringSync(report.toMarkdown());

      // ignore: avoid_print
      print(
        '${passed ? 'PASS' : 'FAIL'} ${i + 1}/${cases.length}: '
        '${character.name} | searchApi=$searchApiCalls | $planLog',
      );
    }

    // ignore: avoid_print
    print('Report: $reportPath');

    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 12)));
}

class _AuditCase {
  final String characterId;
  final String question;
  final bool expectNoSearch;

  const _AuditCase({
    required this.characterId,
    required this.question,
    required this.expectNoSearch,
  });
}

Set<int>? _selectedIndexesFromEnv() {
  final raw = Platform.environment['NO_SEARCH_AUDIT_CASES']?.trim();
  if (raw == null || raw.isEmpty) return null;
  final result = <int>{};
  for (final part in raw.split(RegExp(r'[,，\s]+'))) {
    if (part.trim().isEmpty) continue;
    final value = int.tryParse(part.trim());
    if (value != null) result.add(value);
  }
  return result.isEmpty ? null : result;
}

bool _looksLikeJapaneseFallback(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '');
  return normalized.contains('うまく言葉にできませんでした') ||
      normalized.contains('うまく言葉にできなかった') ||
      normalized.contains('うまく言えなかった') ||
      normalized.contains('言葉が出てこなかった');
}

List<String> _translationLogs(List<String> logs) {
  return logs
      .where((line) => RegExp(
            r'日语|日文|翻译|変換|中文角色|DeepSeek API 错误|请求失败',
          ).hasMatch(line))
      .toList(growable: false);
}

String _firstStackLine(StackTrace? stackTrace) {
  if (stackTrace == null) return '<no stack>';
  final text = stackTrace.toString().trim();
  if (text.isEmpty) return '<empty stack>';
  return text.split('\n').first;
}

class _AuditReportDocument {
  String generatedAt;
  final Map<int, String> sections;

  _AuditReportDocument({
    required this.generatedAt,
    required this.sections,
  });

  factory _AuditReportDocument.read(String markdown) {
    final generatedAt = RegExp(r'^Generated at: (.+)$', multiLine: true)
            .firstMatch(markdown)
            ?.group(1)
            ?.trim() ??
        DateTime.now().toIso8601String();
    final sections = <int, String>{};
    final matches = RegExp(r'^## (\d+)\. .*$', multiLine: true)
        .allMatches(markdown)
        .toList(growable: false);
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final index = int.tryParse(match.group(1) ?? '');
      if (index == null) continue;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : markdown.length;
      sections[index] = markdown.substring(match.start, end).trimRight();
    }
    return _AuditReportDocument(
      generatedAt: generatedAt,
      sections: sections,
    );
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# No-search Plan Remote Audit')
      ..writeln()
      ..writeln('Generated at: $generatedAt')
      ..writeln();
    for (final index in sections.keys.toList()..sort()) {
      buffer
        ..writeln(sections[index])
        ..writeln();
    }
    return buffer.toString();
  }
}
