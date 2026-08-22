import 'package:flutter_test/flutter_test.dart';

import 'package:anime_chat_app/web_context_service.dart';

void main() {
  group('No-search local plan audit', () {
    const noSearchCases = [
      _PlanAuditCase(
        characterId: 'shinobu',
        characterName: '蝴蝶忍',
        question: '忍小姐，今天你还好吗，能陪我说说话吗',
      ),
      _PlanAuditCase(
        characterId: 'muichirou',
        characterName: '时透无一郎',
        question: '无一郎，今天训练累不累，陪我发会儿呆吧',
      ),
      _PlanAuditCase(
        characterId: 'giyu',
        characterName: '富冈义勇',
        question: '义勇先生，最近心情怎么样，想随便聊聊吗',
      ),
      _PlanAuditCase(
        characterId: 'sakiko',
        characterName: '丰川祥子',
        question: '小祥，最近乐队里有发生什么有趣的事吗',
      ),
      _PlanAuditCase(
        characterId: 'sakiko',
        characterName: '丰川祥子',
        question: '小祥，最近Mujica有演出安排吗',
      ),
      _PlanAuditCase(
        characterId: 'tomori',
        characterName: '高松灯',
        question: '小灯也在放暑假吧，最近有收集小物件吗，或者乐队有什么活动吗？',
      ),
      _PlanAuditCase(
        characterId: 'andy',
        characterName: '安迪',
        question: '姐姐，我今天有点累，可以陪我聊会儿吗',
      ),
    ];

    for (final item in noSearchCases) {
      test('${item.characterId}: ${item.question}', () {
        final plan = WebContextService.simulatedPlannerNoSearchSnapshotForTest(
          userText: item.question,
          characterId: item.characterId,
          characterName: item.characterName,
        );

        expect(plan['hasAnyTask'], isFalse, reason: '$plan');
        expect(plan['includeWeather'], isFalse, reason: '$plan');
        expect(plan['includeFestivals'], isFalse, reason: '$plan');
        expect(plan['includePhenology'], isFalse, reason: '$plan');
        expect(plan['searchQuery'], isEmpty, reason: '$plan');
        expect(plan['category'], 'none', reason: '$plan');
      });
    }
  });

  group('No-search audit keeps verifiable questions searchable', () {
    const searchableCases = [
      _PlanAuditCase(
        characterId: 'sakiko',
        characterName: '丰川祥子',
        question: '小祥，听说MyGO曾经在live里突然演奏了《春日影》？',
      ),
      _PlanAuditCase(
        characterId: 'andy',
        characterName: '安迪',
        question: '姐姐，最近中国股市有什么新政策吗',
      ),
      _PlanAuditCase(
        characterId: 'shinobu',
        characterName: '蝴蝶忍',
        question: '忍小姐，今天会下雨吗',
      ),
    ];

    for (final item in searchableCases) {
      test('${item.characterId}: ${item.question}', () {
        final plan = WebContextService.localSearchPlanSnapshotForTest(
          userText: item.question,
          characterId: item.characterId,
          characterName: item.characterName,
        );

        expect(plan['hasAnyTask'], isTrue, reason: '$plan');
      });
    }
  });

  test('overrides a mistaken canon plan for Tomori present-day chat', () {
    final plan = WebContextService.simulatedPlannerCanonSnapshotForTest(
      userText: '小灯也在放暑假吧，最近有收集小物件吗，或者乐队有什么活动吗？',
      characterId: 'tomori',
      characterName: '高松灯',
      primaryObjects: const ['高松灯', 'AveMujica'],
      presentDayRoleplay: true,
    );

    expect(plan['hasAnyTask'], isFalse, reason: '$plan');
    expect(plan['category'], 'none', reason: '$plan');
    expect(plan['searchQuery'], isEmpty, reason: '$plan');
    expect(plan['answerRequirementCount'], 0, reason: '$plan');
    expect(plan['primaryObjects'], isEmpty, reason: '$plan');
  });
}

class _PlanAuditCase {
  final String characterId;
  final String characterName;
  final String question;

  const _PlanAuditCase({
    required this.characterId,
    required this.characterName,
    required this.question,
  });
}
