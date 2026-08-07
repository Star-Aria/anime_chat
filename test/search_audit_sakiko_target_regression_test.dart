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
  test('audit Sakiko target selection and song search regression', () async {
    if (Platform.environment['RUN_SAKIKO_TARGET_AUDIT'] != '1') {
      markTestSkipped('Set RUN_SAKIKO_TARGET_AUDIT=1 to call remote APIs.');
      return;
    }

    final character = CharacterConfig.getCharacterById('sakiko');
    final cases = [
      _AuditCase(
        title: 'MyGO 上下文下的爱音喜好',
        question: '祥祥，MyGO的千早爱音有什么喜好？',
        expectsAnonTarget: true,
        expectsMygoIndependentSearch: false,
        expectsSongs: false,
      ),
      _AuditCase(
        title: 'Ave Mujica / MyGO 曲目偏好',
        question: '祥祥，Ave Mujica和MyGO的歌里，你分别比较喜欢哪些歌呀？',
        expectsAnonTarget: false,
        expectsMygoIndependentSearch: true,
        expectsSongs: true,
      ),
    ];

    final runs = <_AuditRun>[];
    for (final auditCase in cases) {
      runs.add(await _runCase(auditCase, character));
    }

    final reportFile = File('reports/search_audit_sakiko_song_rerun_latest.md');
    final existing =
        reportFile.existsSync() ? await reportFile.readAsString() : '';
    final appended = _formatAppendix(runs);
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(
      '${existing.trimRight()}\n\n$appended',
      encoding: utf8,
    );
    debugPrint('SAKIKO_TARGET_AUDIT_REPORT: ${reportFile.absolute.path}');

    expect(runs, hasLength(2));
    for (final run in runs) {
      expect(run.error, isNull);
      expect(run.webContext, contains('【网页搜索摘要】'));
      if (run.auditCase.expectsAnonTarget) {
        expect(run.searchedAnon, isTrue,
            reason: 'Profile-trait question should search Anon, not MyGO.');
        expect(run.searchedMygo, isFalse,
            reason: 'MyGO should stay context-only for Anon profile traits.');
      }
      if (run.auditCase.expectsMygoIndependentSearch) {
        expect(run.searchedMygo, isTrue,
            reason: 'Song preference question must search MyGO independently.');
      }
      if (run.auditCase.expectsSongs) {
        expect(run.detectedAveSongs, isNotEmpty);
        expect(run.detectedMygoSongs, isNotEmpty);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<_AuditRun> _runCase(
  _AuditCase auditCase,
  Character character,
) async {
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
    debugPrint('=== ${auditCase.title} ===');
    buildResult = await WebContextService.buildContextDetailed(
      userMessage: auditCase.question,
      characterId: character.id,
      characterName: character.name,
      conversationHistory: const [],
    );
    response = await ApiService.generateResponse(
      characterPersonality: character.personality,
      conversationHistory: const [],
      userMessage: auditCase.question,
      webContext: buildResult.context,
      characterId: character.id,
      characterLanguage: character.language,
    );
  } catch (e, st) {
    error = e;
    stackTrace = st;
  } finally {
    debugPrint = oldDebugPrint;
  }

  final japaneseAnswer = response['japanese'] ?? '';
  final chineseAnswer = response['chinese'] ?? '';
  return _AuditRun(
    auditCase: auditCase,
    logs: logs,
    webContext: buildResult?.context ?? '',
    japaneseAnswer: japaneseAnswer,
    chineseAnswer: chineseAnswer,
    searchApiCalls: buildResult?.trace.searchApiCalls ?? 0,
    detectedSongs: _extractKnownSongMentions('$japaneseAnswer\n$chineseAnswer'),
    error: error,
    stackTrace: stackTrace,
  );
}

String _formatAppendix(List<_AuditRun> runs) {
  final buffer = StringBuffer()
    ..writeln('## 补充回归：MyGO 上下文与曲目搜索')
    ..writeln()
    ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
    ..writeln('- 说明：本节为追加复测，不覆盖上方既有记录。');

  for (final run in runs) {
    buffer
      ..writeln()
      ..writeln('### ${run.auditCase.title}')
      ..writeln()
      ..writeln('- 问题：${run.auditCase.question}')
      ..writeln('- 搜索 API 调用：${run.searchApiCalls}')
      ..writeln('- 爱音独立搜索：${run.searchedAnon ? '是' : '否'}')
      ..writeln('- MyGO 独立搜索：${run.searchedMygo ? '是' : '否'}')
      ..writeln(
        '- Ave Mujica 命中：${run.detectedAveSongs.isEmpty ? '无' : run.detectedAveSongs.join('、')}',
      )
      ..writeln(
        '- MyGO 命中：${run.detectedMygoSongs.isEmpty ? '无' : run.detectedMygoSongs.join('、')}',
      )
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

  return buffer.toString().trimRight();
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
    '\n\n【明确原作设定优先】',
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

class _AuditCase {
  final String title;
  final String question;
  final bool expectsAnonTarget;
  final bool expectsMygoIndependentSearch;
  final bool expectsSongs;

  const _AuditCase({
    required this.title,
    required this.question,
    required this.expectsAnonTarget,
    required this.expectsMygoIndependentSearch,
    required this.expectsSongs,
  });
}

class _AuditRun {
  final _AuditCase auditCase;
  final List<String> logs;
  final String webContext;
  final String japaneseAnswer;
  final String chineseAnswer;
  final int searchApiCalls;
  final List<_SongMention> detectedSongs;
  final Object? error;
  final StackTrace? stackTrace;

  const _AuditRun({
    required this.auditCase,
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

  bool get searchedAnon {
    final pattern = RegExp(
      r'(原作搜索对象: .*千早 ?爱音|萌娘百科词条全文直达成功: .*千早 ?爱音|'
      r'搜索步骤开始\[.*千早 ?爱音|本地百度/维基直达优先: .*千早 ?爱音)',
      caseSensitive: false,
    );
    return logs.any(pattern.hasMatch);
  }

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
