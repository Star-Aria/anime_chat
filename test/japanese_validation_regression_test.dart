import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/storage_service.dart';
import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const birthdayRequest = '小灯小灯，我有个朋友今天过生日，他很希望得到你的祝福，'
    '可以多送点祝福给他吗~直接对他说就行，不用跟我说话，'
    '也不要说“凛野酱的朋友之类”，谢谢小灯呀';

const birthdayExamRequest = '小灯小灯，我有个朋友今天过生日，'
    '他这周还有个很重要的英语考试，他很希望得到你的祝福，'
    '可以多送点祝福给他吗~直接对他说就行，不用跟我说话，'
    '也不要说“凛野酱的朋友之类”，多说几句呀，谢谢小灯';

void main() {
  test('reported birthday and exam request bypasses every remote planning call',
      () async {
    var calls = 0;
    final history = [
      Message(
        role: 'user',
        content: 'tomorin，MyGO的要乐奈和你是什么关系？',
        timestamp: DateTime(2026, 10, 27),
      ),
      Message(
        role: 'assistant',
        content: '刚才说到乐队，还有团圆和月亮。',
        timestamp: DateTime(2026, 10, 27),
      ),
    ];
    final result = await http.runWithClient(
      () => WebContextService.buildContextDetailed(
        userMessage: birthdayExamRequest,
        characterId: 'tomori',
        characterName: '高松灯',
        conversationHistory: history,
      ),
      () => MockClient((request) async {
        calls++;
        return http.Response('closed endpoint must never be contacted', 400);
      }),
    );
    expect(calls, 0);
    expect(result.trace.modelCalls, 0);
    expect(result.trace.searchApiCalls, 0);
    expect(result.context, isEmpty);
  });

  test('self-contained social speech skips planning, not just web execution',
      () async {
    final fixture = jsonDecode(File(
      'test/fixtures/social_request_routing_v1.json',
    ).readAsStringSync()) as Map;
    expect(fixture['version'], 1);
    for (final item in fixture['noExternalInformation'] as List) {
      var calls = 0;
      final result = await http.runWithClient(
        () => WebContextService.buildContextDetailed(
          userMessage: item['message'] as String,
          characterId: item['characterId'] as String,
          characterName: item['characterName'] as String,
        ),
        () => MockClient((request) async {
          calls++;
          return http.Response('unexpected remote request', 400);
        }),
      );
      expect(calls, 0, reason: item['message'] as String);
      expect(result.context, isEmpty);
      expect(result.trace.modelCalls, 0);
      expect(result.trace.searchApiCalls, 0);
    }
  });

  test('social request with a factual ask still reaches the original planner',
      () async {
    final fixture = jsonDecode(File(
      'test/fixtures/social_request_routing_v1.json',
    ).readAsStringSync()) as Map;
    for (final message in fixture['requiresPlanning'] as List) {
      var modelRequests = 0;
      final result = await http.runWithClient(
        () => WebContextService.buildContextDetailed(
          userMessage: message as String,
          characterId: 'tomori',
          characterName: '高松灯',
        ),
        () => MockClient((request) async {
          if (request.url.path.endsWith('/chat/completions')) {
            modelRequests++;
          }
          return http.Response('closed endpoint', 400);
        }),
      );
      expect(modelRequests, 1, reason: message as String);
      expect(result.trace.modelCallsFor('planner'), 1);
      expect(result.trace.modelCallsFor('facts'), 0);
      expect(result.trace.searchApiCalls, 0);
    }
  });

  test('local fallback cannot revive historical canon for a social request',
      () {
    final plan = WebContextService.localSearchPlanSnapshotForTest(
      userText: birthdayExamRequest,
      characterId: 'tomori',
      characterName: '高松灯',
      conversationHistory: [
        Message(
          role: 'user',
          content: 'tomorin，你们MyGO和要乐奈的原作剧情是什么？',
          timestamp: DateTime(2026, 10, 27),
        ),
      ],
    );
    expect(plan['hasAnyTask'], isFalse);
    expect(plan['category'], 'none');
    expect(plan['searchQuery'], isEmpty);
  });

  test('self-contained social request overrides a spurious canon plan', () {
    final plan = WebContextService.simulatedPlannerCanonSnapshotForTest(
      userText: birthdayExamRequest,
      characterId: 'tomori',
      characterName: '高松灯',
      primaryObjects: const ['高松灯', '要乐奈'],
    );
    expect(plan['hasAnyTask'], isFalse);
    expect(plan['category'], 'none');
    expect(plan['answerRequirementCount'], 0);
    expect(plan['primaryObjects'], isEmpty);
  });

  test('full names are protected before overlapping character nicknames', () {
    const cases = [
      (
        characterId: 'sakiko',
        source: '长崎爽世和爽世、祐天寺若麦和若麦、八幡海铃和海铃。',
        expected: '長崎そよ和そよ、祐天寺にゃむ和にゃむ、八幡海鈴和海鈴。',
      ),
      (
        characterId: 'sakiko',
        source: '长崎 爽世和爽世、祐天寺 若麦和若麦、八幡 海铃和海铃。',
        expected: '長崎そよ和そよ、祐天寺にゃむ和にゃむ、八幡海鈴和海鈴。',
      ),
      (
        characterId: 'tomori',
        source: '长崎爽世和爽世酱、丰川祥子和小祥、千早爱音和小爱。',
        expected: '長崎そよ和そよちゃん、豊川祥子和祥ちゃん、千早愛音和あのちゃん。',
      ),
    ];
    for (final item in cases) {
      expect(
        ApiService.applyJapaneseNameMappingsForTest(
          item.source,
          characterId: item.characterId,
        ),
        item.expected,
        reason: '${item.characterId}: ${item.source}',
      );
    }
  });

  test('full names and complete call names keep distinct placeholder contracts',
      () {
    final protected =
        ApiService.protectMappedNamesForJapaneseTranslationForTest(
      '长崎爽世和爽世、小爱和千早爱音。',
      characterId: 'sakiko',
    );
    final placeholders = protected['placeholders'] as Map<String, String>;
    final fullNameKey =
        placeholders.entries.singleWhere((entry) => entry.value == '長崎そよ').key;
    final callNameKey =
        placeholders.entries.singleWhere((entry) => entry.value == 'そよ').key;
    expect(fullNameKey, startsWith('__JP_NAME_'));
    expect(callNameKey, startsWith('__JP_CALL_'));
    expect(protected['text'], startsWith('$fullNameKey和$callNameKey'));

    expect(
      ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['$callNameKey也来了。'],
        placeholders: placeholders,
        response: jsonEncode({
          'translations': [
            {'source_index': 1, 'text': '$callNameKeyさんも来た。'},
          ],
        }),
      ),
      isNull,
    );
  });

  test('reported birthday reply passes the complete local translation gates',
      () {
    final fixture = jsonDecode(File(
      'test/fixtures/japanese_validation_regressions_v1.json',
    ).readAsStringSync()) as Map;
    expect(fixture['version'], 1);
    for (final item in fixture['cases'] as List) {
      final sources = (item['sourceUnits'] as List).cast<String>();
      final units = (item['japaneseUnits'] as List).cast<String>();
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: sources,
        response: jsonEncode({'translations': units}),
      );
      expect(parsed, isNotNull, reason: item['id'] as String);
      expect(ApiService.invalidJapaneseUnitIndexesForTest(units), isEmpty);
      expect(
        ApiService.isAcceptableJapaneseForCharacterForTest(
          parsed!,
          item['characterId'] as String,
        ),
        isTrue,
      );
    }
  });

  test('shared kanji never become Chinese residue based on one character', () {
    const validJapanese = [
      'この日を迎えられたこと自体が、とても大切なことだと思います。',
      '体調に気をつけて、全体の予定は無理せず考えよう。',
      'その提案を却下する理由はありません。',
      '「听」「从」「无」という漢字の字形について話しています。',
      '「東京大学医学部」という名前を聞きました。',
      'ﾀﾞｲｼﾞｮｳﾌﾞ、ﾕｯｸﾘﾃﾞｲｲﾖ。',
    ];
    for (final text in validJapanese) {
      expect(ApiService.isCleanJapaneseForTtsForTest(text), isTrue,
          reason: text);
    }
  });

  test('real Chinese residue is still rejected and its sentence located', () {
    expect(
      ApiService.invalidJapaneseUnitIndexesForTest([
        '自体という言葉は問題ありません。',
        'その人はもう这句话を聞けない。',
        'その案を却下しないでください。',
      ]),
      [1],
    );
    for (final text in ['', '生日快乐。', '今天也要开心呀。', 'ーーー・゛゜']) {
      expect(ApiService.isCleanJapaneseForTtsForTest(text), isFalse,
          reason: text);
    }
  });

  test('Chinese made of shared kanji is checked against its source', () {
    final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
      sourceUnits: ['听到这段旋律，今日心情非常安定。'],
      response: jsonEncode({
        'translations': ['この旋律を聴くと、今日心情非常安定です。'],
      }),
    );
    expect(parsed, isNull);
  });

  test('existing sentence correspondence and punctuation gates remain active',
      () {
    expect(
      ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['生日快乐。', '慢慢来就好。'],
        response: jsonEncode({
          'translations': ['お誕生日おめでとう。']
        }),
      ),
      isNull,
    );
    expect(
      ApiService.isAcceptableJapaneseForCharacterForTest(
        '“お誕生日おめでとう”と伝えたいです。',
        'tomori',
      ),
      isFalse,
    );
  });

  test('birthday statement does not start calendar or web lookup in fallback',
      () {
    final plan = WebContextService.localSearchPlanSnapshotForTest(
      userText: birthdayRequest,
      characterId: 'tomori',
      characterName: '高松灯',
    );
    expect(plan['hasAnyTask'], isFalse, reason: '$plan');
    expect(plan['includeFestivals'], isFalse, reason: '$plan');
    expect(plan['searchQuery'], isEmpty, reason: '$plan');
  });

  test('time words alone do not imply a current-affairs question', () {
    for (final message in [
      '今天是朋友生日，能送他一句祝福吗？',
      '最近很累，想听你安慰一下。',
      '今年过得好快，我现在有点感慨。',
    ]) {
      final plan = WebContextService.localSearchPlanSnapshotForTest(
        userText: message,
        characterId: 'tomori',
        characterName: '高松灯',
      );
      expect(plan['hasAnyTask'], isFalse, reason: '$message: $plan');
    }
  });

  test('explicit calendar questions retain their local calendar data', () {
    for (final message in ['今天是星期几？', '最近有哪些节日？', '离下个节日还有多少天？']) {
      final plan = WebContextService.localSearchPlanSnapshotForTest(
        userText: message,
        characterId: 'tomori',
        characterName: '高松灯',
      );
      expect(plan['includeFestivals'], isTrue, reason: '$message: $plan');
    }
  });

  test('plain birthday request never contacts even a closed planner', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode({
            'error': {'code': 'InvalidEndpoint.ClosedEndpoint'},
          }),
          400);
    });
    final result = await http.runWithClient(
      () => WebContextService.buildContextDetailed(
        userMessage: birthdayRequest,
        characterId: 'tomori',
        characterName: '高松灯',
      ),
      () => client,
    );
    expect(calls, 0);
    expect(result.context, isEmpty);
    expect(result.trace.modelCallsFor('planner'), 0);
    expect(result.trace.searchApiCalls, 0);
    expect(result.trace.modelCallsFor('facts'), 0);
  });

  test('unavailable planner does not fabricate results for factual questions',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode({
            'error': {'code': 'InvalidEndpoint.ClosedEndpoint'},
          }),
          400);
    });
    final result = await http.runWithClient(
      () => WebContextService.buildContextDetailed(
        userMessage: '小灯，请查询MyGO的原作剧情和人物关系。',
        characterId: 'tomori',
        characterName: '高松灯',
      ),
      () => client,
    );
    expect(calls, 1);
    expect(result.trace.searchApiCalls, 0);
    expect(result.trace.modelCallsFor('facts'), 0);
    // 联网失败时允许继续使用本地角色设定，但不得伪造网页摘要或事实。
    expect(result.context, contains('【角色设定资料】'));
    expect(result.context, isNot(contains('【网页搜索摘要】')));
  });

  test('service failure is isolated to one turn; next turn can recover',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) return http.Response('unavailable', 503);
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'weather': false,
                    'festival': false,
                    'phenology': false,
                    'web_search': false,
                    'category': 'none',
                  })
                }
              },
            ],
          }),
          200);
    });
    await http.runWithClient(() async {
      for (var turn = 0; turn < 2; turn++) {
        final result = await WebContextService.buildContextDetailed(
          userMessage: '小灯，请查询MyGO的原作剧情和人物关系。',
          characterId: 'tomori',
          characterName: '高松灯',
        );
        if (turn == 0) {
          expect(result.context, contains('【角色设定资料】'));
        } else {
          expect(result.context, isEmpty);
        }
        expect(result.trace.modelCalls, 1);
      }
    }, () => client);
    expect(calls, 2);
  });
}
