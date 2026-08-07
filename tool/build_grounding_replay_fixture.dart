import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/grounding_contract.dart';

const _statePath = 'reports/search_audit_first10_rerun_latest.md.state.json';
const _acceptedQ9Path =
    'reports/search_audit_q9_rerun_2026-08-03T21-52-16-270002.md';
const _outputPath = 'test/fixtures/grounding_replay_v1.json';

Future<void> main() async {
  final rawState = jsonDecode(await File(_statePath).readAsString());
  if (rawState is! List) {
    throw StateError('Audit state must be a JSON list.');
  }

  final cases = <Map<String, dynamic>>[];
  for (final raw in rawState.whereType<Map>()) {
    final index = _asInt(raw['index']);
    if (index == null || index < 1 || index > 8) continue;
    final logs = raw['logs'] is List
        ? (raw['logs'] as List).map((value) => '$value').toList()
        : const <String>[];
    final snapshot = GroundingSnapshot.fromAudit(
      logs: logs,
      webContext: '${raw['webContext'] ?? ''}',
      japaneseAnswer: '${raw['japaneseAnswer'] ?? ''}',
      chineseAnswer: '${raw['chineseAnswer'] ?? ''}',
    );
    cases.add({
      'index': index,
      'characterId': '${raw['characterId'] ?? ''}',
      'question': '${raw['question'] ?? ''}',
      'snapshot': snapshot.toJson(),
    });
  }

  final acceptedQ9 = await File(_acceptedQ9Path).readAsString();
  final q9Logs = _codeBlockAfter(acceptedQ9, '## 搜索/生成日志')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  final q9Snapshot = GroundingSnapshot.fromAudit(
    logs: q9Logs,
    webContext: _codeBlockAfter(acceptedQ9, '## 联网上下文'),
    japaneseAnswer: _codeBlockAfter(acceptedQ9, '## 日语回答'),
    chineseAnswer: _codeBlockAfter(acceptedQ9, '## 中文翻译'),
  );
  cases.add({
    'index': 9,
    'characterId': 'sakiko',
    'question': '祥祥，听说在组成MyGO的那段时间，爱音和灯是相互救赎的，你对相关情况有耳闻吗',
    'snapshot': q9Snapshot.toJson(),
  });
  cases.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

  final output = File(_outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'contractVersion': groundingContractVersion,
      'sources': [_statePath, _acceptedQ9Path],
      'cases': cases,
    }),
  );
  stdout.writeln('Wrote ${cases.length} replay cases to ${output.path}.');
}

String _codeBlockAfter(String text, String heading) {
  final headingIndex = text.indexOf(heading);
  if (headingIndex < 0) return '';
  final fenceStart = text.indexOf('```', headingIndex + heading.length);
  if (fenceStart < 0) return '';
  final contentStart = text.indexOf('\n', fenceStart);
  if (contentStart < 0) return '';
  final fenceEnd = text.indexOf('```', contentStart + 1);
  if (fenceEnd < 0) return '';
  return text.substring(contentStart + 1, fenceEnd).trim();
}

int? _asInt(dynamic value) =>
    value is int ? value : int.tryParse('${value ?? ''}');
