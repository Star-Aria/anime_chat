import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/grounding_contract.dart';
import 'package:anime_chat_app/name_pronunciation.dart';
import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rerun sakiko song preference audit twice without TTS', () async {
    if (Platform.environment['RUN_SAKIKO_MUSIC_AUDIT'] != '1') {
      markTestSkipped('Set RUN_SAKIKO_MUSIC_AUDIT=1 to call remote APIs.');
      return;
    }

    const question = '祥祥，Ave Mujica和MyGO的歌里，你分别比较喜欢哪些歌呀？';
    final character = CharacterConfig.getCharacterById('sakiko');
    final runs = <_AuditRun>[];

    for (var runIndex = 1; runIndex <= 2; runIndex++) {
      final logs = <String>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.trim().isNotEmpty) {
          logs.add(message);
        }
        oldDebugPrint(message, wrapWidth: wrapWidth);
      };

      WebContextBuildResult? buildResult;
      Map<String, String> response = const {};
      Object? error;
      StackTrace? stackTrace;
      try {
        debugPrint('=== 运行 $runIndex / 2 ===');
        buildResult = await WebContextService.buildContextDetailed(
          userMessage: question,
          characterId: character.id,
          characterName: character.name,
          conversationHistory: const [],
        );
        response = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: const [],
          userMessage: question,
          webContext: buildResult.context,
          characterId: character.id,
          characterLanguage: character.language,
        );
      } catch (e, st) {
        response = const {};
        error = e;
        stackTrace = st;
      } finally {
        debugPrint = oldDebugPrint;
      }

      final japaneseAnswer = response['japanese'] ?? '';
      final chineseAnswer = response['chinese'] ?? '';
      final detectedSongs =
          _extractKnownSongMentions('$japaneseAnswer\n$chineseAnswer');
      runs.add(
        _AuditRun(
          runIndex: runIndex,
          logs: logs,
          webContext: buildResult?.context ?? '',
          japaneseAnswer: japaneseAnswer,
          chineseAnswer: chineseAnswer,
          searchApiCalls: buildResult?.trace.searchApiCalls ?? 0,
          detectedSongs: detectedSongs,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }

    final report = _formatReport(question: question, runs: runs);
    final reportFile = File('reports/search_audit_sakiko_song_rerun_latest.md');
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(report, encoding: utf8);
    debugPrint('SAKIKO_MUSIC_AUDIT_REPORT: ${reportFile.absolute.path}');

    expect(runs, hasLength(2));
    for (final run in runs) {
      expect(run.error, isNull);
      expect(run.webContext, contains('【网页搜索摘要】'));
      expect(run.searchedMygo, isTrue,
          reason: 'MyGO must be searched or fetched as its own canon target.');
      expect(run.detectedAveSongs, isNotEmpty);
      expect(run.detectedMygoSongs, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _formatReport({
  required String question,
  required List<_AuditRun> runs,
}) {
  final buffer = StringBuffer()
    ..writeln('# 祥子曲目偏好双跑复测')
    ..writeln()
    ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
    ..writeln('- 说明：本文件为双跑复测，不覆盖原总报告。')
    ..writeln('- 目标：确认祥子回答 Ave Mujica 与 MyGO 曲目时能给出正确曲名。')
    ..writeln()
    ..writeln('## 问题')
    ..writeln()
    ..writeln(question);

  for (final run in runs) {
    buffer
      ..writeln()
      ..writeln('## 第 ${run.runIndex} 次')
      ..writeln()
      ..writeln('- 搜索 API 调用：${run.searchApiCalls}')
      ..writeln('- MyGO 独立搜索：${run.searchedMygo ? '是' : '否'}')
      ..writeln(
          '- Ave Mujica 命中：${run.detectedAveSongs.isEmpty ? '无' : run.detectedAveSongs.join('、')}')
      ..writeln(
          '- MyGO 命中：${run.detectedMygoSongs.isEmpty ? '无' : run.detectedMygoSongs.join('、')}')
      ..writeln()
      ..writeln('**搜索/生成日志**')
      ..writeln()
      ..writeln('```text')
      ..writeln(_compactLogs(run.logs).join('\n'))
      ..writeln('```')
      ..writeln()
      ..writeln('**联网上下文**')
      ..writeln()
      ..writeln('```text')
      ..writeln(_extractRelevantContext(run.webContext))
      ..writeln('```')
      ..writeln()
      ..writeln('**日语回答**')
      ..writeln()
      ..writeln('```text')
      ..writeln(run.japaneseAnswer.trim())
      ..writeln('```')
      ..writeln()
      ..writeln('**中文回答**')
      ..writeln()
      ..writeln('```text')
      ..writeln(run.chineseAnswer.trim())
      ..writeln('```');

    if (run.error != null) {
      buffer
        ..writeln()
        ..writeln('**错误**')
        ..writeln()
        ..writeln('```text')
        ..writeln('${run.error}')
        ..writeln(run.stackTrace ?? '')
        ..writeln('```');
    }
  }

  buffer
    ..writeln()
    ..writeln('## 汇总')
    ..writeln()
    ..writeln('| 轮次 | Ave Mujica | MyGO |')
    ..writeln('| --- | --- | --- |');
  for (final run in runs) {
    buffer.writeln(
      '| ${run.runIndex} | ${run.detectedAveSongs.isEmpty ? '无' : run.detectedAveSongs.join('、')} | ${run.detectedMygoSongs.isEmpty ? '无' : run.detectedMygoSongs.join('、')} |',
    );
  }

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
  final startMarkers = ['【网页搜索摘要】', '【网页搜索失败】'];
  final starts = startMarkers
      .map(webContext.indexOf)
      .where((index) => index >= 0)
      .toList(growable: false)
    ..sort();
  if (starts.isEmpty) return '';

  final start = starts.first;
  final stopMarkers = [
    '\n\n【角色设定资料】',
    '\n\n【事实时间线】',
    '\n\n【有限角色发挥】',
    '\n\n【使用这些信息的规则】',
  ];
  final stops = stopMarkers
      .map((marker) => webContext.indexOf(marker, start + 1))
      .where((index) => index >= 0)
      .toList(growable: false)
    ..sort();
  var end = stops.isEmpty ? webContext.length : stops.first;
  if (end < start) end = webContext.length;
  return webContext.substring(start, end).trim();
}

List<_SongMention> _extractKnownSongMentions(String text) {
  final mentions = <_SongMention>[];
  for (final entry in _mygoSongEntries) {
    if (_entryMatchesText(entry, text)) {
      mentions.add(_SongMention(entry.chinese, 'MyGO'));
    }
  }
  for (final entry in _aveMujicaSongEntries) {
    if (_entryMatchesText(entry, text)) {
      mentions.add(_SongMention(entry.chinese, 'Ave Mujica'));
    }
  }
  return mentions;
}

bool _entryMatchesText(TermNamePronunciation entry, String text) {
  final variants = <String>{
    entry.chinese,
    entry.japanese,
    entry.compactJapanese,
    entry.reading,
    ...entry.romanizedReadingVariants,
    ...entry.aliases.keys,
  }.where((value) => value.trim().isNotEmpty);
  for (final variant in variants) {
    if (text.contains(variant)) return true;
  }
  return false;
}

Iterable<TermNamePronunciation> get _mygoSongEntries {
  final start =
      termNamePronunciations.indexWhere((entry) => entry.chinese == 'MyGO');
  final ave = termNamePronunciations
      .indexWhere((entry) => entry.chinese == 'Ave Mujica');
  if (start < 0 || ave < 0 || ave <= start + 1) return const [];
  return termNamePronunciations.sublist(start + 1, ave);
}

Iterable<TermNamePronunciation> get _aveMujicaSongEntries {
  final ave = termNamePronunciations
      .indexWhere((entry) => entry.chinese == 'Ave Mujica');
  if (ave < 0 || ave + 1 >= termNamePronunciations.length) return const [];
  return termNamePronunciations.sublist(ave + 1);
}

class _AuditRun {
  final int runIndex;
  final List<String> logs;
  final String webContext;
  final String japaneseAnswer;
  final String chineseAnswer;
  final int searchApiCalls;
  final List<_SongMention> detectedSongs;
  final Object? error;
  final StackTrace? stackTrace;

  const _AuditRun({
    required this.runIndex,
    required this.logs,
    required this.webContext,
    required this.japaneseAnswer,
    required this.chineseAnswer,
    required this.searchApiCalls,
    required this.detectedSongs,
    this.error,
    this.stackTrace,
  });

  List<String> get detectedAveSongs => detectedSongs
      .where((song) => song.band == 'Ave Mujica')
      .map((song) => song.title)
      .toList(growable: false);

  List<String> get detectedMygoSongs => detectedSongs
      .where((song) => song.band == 'MyGO')
      .map((song) => song.title)
      .toList(growable: false);

  bool get searchedMygo {
    final pattern = RegExp(
      r'(萌娘百科词条全文直达成功: .*MyGO|'
      r'搜索步骤开始\[.*MyGO|'
      r'搜索步骤结果\[.*MyGO|'
      r'本地百度/维基直达优先: .*MyGO)',
      caseSensitive: false,
    );
    return logs.any(pattern.hasMatch);
  }
}

class _SongMention {
  final String title;
  final String band;

  const _SongMention(this.title, this.band);
}
