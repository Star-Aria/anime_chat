import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/grounding_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/grounding_audit_policies.dart';

void main() {
  group('grounding contract', () {
    test('records remote call types without credentials or request bodies', () {
      final trace = GroundingRunTrace(
        userMessage: 'test',
        characterId: 'shinobu',
      )
        ..recordRemoteCall(
          kind: 'model',
          provider: '豆包/火山方舟搜索计划',
          operation: 'planner',
        )
        ..recordRemoteCall(
          kind: 'model',
          provider: '豆包/火山方舟事实抽取',
          operation: 'facts',
        )
        ..recordRemoteCall(
          kind: 'search_api',
          provider: 'Doubao Global',
          operation: 'web_search',
          requestLabel: '角色词条',
        )
        ..finish();

      expect(trace.searchApiCalls, 1);
      expect(trace.modelCalls, 2);
      expect(trace.modelCallsFor('planner'), 1);
      expect(trace.modelCallsFor('facts'), 1);
      expect(jsonEncode(trace.toJson()), isNot(contains('apiKey')));
    });

    test('parses fact references attached to timeline nodes', () {
      const context = '''
【网页搜索摘要】
搜索词：测试
1. 页面：相关事实：甲先完成第一件事（原文证据：甲先完成第一件事。）（来源：https://example.com/a）
2. 页面：相关事实：乙随后完成第二件事（原文证据：乙随后完成第二件事。）（来源：https://example.com/a）

【事实时间线】
【时间线】
1. 甲完成第一件事（依据事实：#1）
2. 乙完成第二件事（依据事实：#2）
''';
      final snapshot = GroundingSnapshot.fromAudit(
        logs: const ['原作搜索对象: 甲 -> 乙'],
        webContext: context,
      );

      expect(snapshot.facts, hasLength(2));
      expect(snapshot.timeline, hasLength(2));
      expect(snapshot.timeline.first.text, '甲完成第一件事');
      expect(snapshot.timeline.first.factIndexes, [1]);
    });

    test('rejects chronology regression inside the same extraction batch', () {
      const facts = [
        GroundingFactSnapshot(
          index: 1,
          text: '第一阶段',
          eventOrder: 1,
          chronologyScope: 'batch-a',
        ),
        GroundingFactSnapshot(
          index: 2,
          text: '第二阶段',
          eventOrder: 2,
          chronologyScope: 'batch-a',
        ),
        GroundingFactSnapshot(
          index: 3,
          text: '第三阶段',
          eventOrder: 3,
          chronologyScope: 'batch-a',
        ),
      ];
      const correct = [
        GroundingTimelineSnapshot(index: 1, text: '第一阶段', factIndexes: [1]),
        GroundingTimelineSnapshot(index: 2, text: '第二阶段', factIndexes: [2]),
        GroundingTimelineSnapshot(index: 3, text: '第三阶段', factIndexes: [3]),
      ];
      const reversed = [
        GroundingTimelineSnapshot(index: 1, text: '第一阶段', factIndexes: [1]),
        GroundingTimelineSnapshot(index: 2, text: '第三阶段', factIndexes: [3]),
        GroundingTimelineSnapshot(index: 3, text: '第二阶段', factIndexes: [2]),
      ];

      expect(
        GroundingContractValidator.validateTimeline(
          facts: facts,
          timeline: correct,
        ),
        isEmpty,
      );
      expect(
        GroundingContractValidator.validateTimeline(
          facts: facts,
          timeline: reversed,
        ).map((issue) => issue.code),
        contains('timeline_order_regressed'),
      );
    });
  });

  group('accepted grounding replay baseline', () {
    late List<Map> cases;

    setUpAll(() async {
      final decoded = jsonDecode(
        await File('test/fixtures/grounding_replay_v1.json').readAsString(),
      );
      expect(decoded['contractVersion'], groundingContractVersion);
      cases = (decoded['cases'] as List).whereType<Map>().toList();
    });

    test('contains one immutable case for every accepted question 1-9', () {
      expect(
          cases.map((item) => item['index']),
          orderedEquals(<int>[
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
          ]));
    });

    test('all accepted cases satisfy their release policies', () {
      final failures = <String>[];
      for (final item in cases) {
        final index = item['index'] as int;
        final snapshot = GroundingSnapshot.fromJson(item['snapshot'] as Map);
        final issues = snapshot.validate(groundingAuditPolicyFor(index));
        if (snapshot.japaneseAnswer.isEmpty) {
          failures.add('Q$index: 日语回答为空');
        }
        if (snapshot.chineseAnswer.isEmpty) {
          failures.add('Q$index: 中文回答为空');
        }
        if (!ApiService.isJapaneseStyleCompatible(
          snapshot.japaneseAnswer,
          '${item['characterId'] ?? ''}',
        )) {
          failures.add('Q$index: 日语回答不符合角色语体');
        }
        failures.addAll(issues.map((issue) => 'Q$index: $issue'));
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}
