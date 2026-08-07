import 'package:flutter_test/flutter_test.dart';

import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/emotion_analyzer.dart';
import 'package:anime_chat_app/name_pronunciation.dart';
import 'package:anime_chat_app/web_context_service.dart';

void main() {
  test('Character config includes playable characters', () {
    expect(CharacterConfig.characters, isNotEmpty);
    expect(
      CharacterConfig.characters.map((character) => character.id),
      contains('shinobu'),
    );
  });

  test('Sentence splitter keeps exclamation-mark names together', () {
    final sentences =
        EmotionAnalyzer.splitSentences('彼女がMyGO!!!!!のライブに誘ってくれたんです。');

    expect(sentences, [
      '彼女がMyGO!!!!!のライブに誘ってくれたんです。',
    ]);
  });

  test('TTS input removes displayed action descriptions', () {
    expect(
      ApiService.stripActionDescriptionsForTest(
        '（そっと微笑む）そうですわね。(少し間を置く)大切なことですの。',
      ),
      'そうですわね。大切なことですの。',
    );
  });

  test('Japanese style gate rejects casual Sakiko speech', () {
    expect(
      ApiService.isJapaneseStyleCompatible(
        '愛音さんと燈は、お互いを支えてきた関係なんだ。とても大切なんだよ。',
        'sakiko',
      ),
      isFalse,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        '愛音さんと燈は、互いを支えてきた関係ですわ。とても大切なことだと思います。',
        'sakiko',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        '愛音さんと燈は、互いを支えてきた関係です。最初は不安もありました。それでも、二人は向き合いました。大切なことだと思います。',
        'sakiko',
      ),
      isFalse,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        'ええ、伺っておりますわ。愛音さんは燈を誘いました。燈は一度拒んでしまった。その後、二人は向き合いました。愛音さんは戻った。大切な関係です。',
        'sakiko',
      ),
      isFalse,
    );
  });

  test('Japanese style gate keeps Shinobu polite and composed', () {
    expect(
      ApiService.isJapaneseStyleCompatible(
        'そうですね。金魚を見ていると、心が穏やかになります。',
        'shinobu',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        'そうだね。金魚って可愛いんだよ。',
        'shinobu',
      ),
      isFalse,
    );
  });

  test('Character name registry resolves stage names to canonical identity',
      () {
    final lock = characterNameByJapaneseForm['LOCK'];
    final shinobu = characterNameByJapaneseForm['しのぶ'];
    final kanao = characterNameByJapaneseForm['カナヲ'];

    expect(lock?.chinese, '朝日六花');
    expect(lock?.compactJapanese, '朝日六花');
    expect(namePronunciationDictionary['LOCK'], 'ろっく');
    expect(shinobu?.chinese, '蝴蝶忍');
    expect(kanao?.chinese, '栗花落香奈乎');
  });

  test('Character registry keeps configured kana display names and readings',
      () {
    final hantengu = characterNameByJapaneseForm['はんてんぐ'];
    final gyokko = characterNameByJapaneseForm['ぎょっこ'];
    final tsugumi = characterNameByChineseForm['羽泽鸫'];

    expect(hantengu?.compactJapanese, 'はんてんぐ');
    expect(gyokko?.compactJapanese, 'ぎょっこ');
    expect(tsugumi?.compactJapanese, '羽沢つぐみ');
    expect(namePronunciationDictionary['はんてんぐ'], 'はんてんぐ');
    expect(namePronunciationDictionary['玉壺'], 'ぎょっこ');
    expect(ApiService.normalizeKnownNamesForChineseText('玉壺'), '玉壶');
  });

  test('Chinese names map to canonical Japanese and per-character call names',
      () {
    final mapped = ApiService.applyJapaneseNameMappingsForTest(
      '灯和爱音同学提到了长崎爽世和玉壶。',
      characterId: 'sakiko',
    );

    expect(mapped, '燈和愛音さん提到了そよ和ぎょっこ。');
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        'もう一度灯さんの歌を聞きます。',
        characterId: 'sakiko',
      ),
      'もう一度燈の歌を聞きます。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '爱音同学さんの話です。',
        characterId: 'sakiko',
      ),
      '愛音さんの話です。',
    );
  });

  test('Broad fact sampling keeps the beginning and end of each source', () {
    expect(
      WebContextService.spreadSampleIndexesForTest(6, 5),
      [0, 1, 3, 4, 5],
    );
  });

  group('Timeline answer contract', () {
    const webContext = '''
【事实时间线】
【时间线】
1. 先发生水族馆的谈话（依据事实：#1）
2. 随后经历其他转折（依据事实：#2）
3. 后来在天台重新谈清楚（依据事实：#3）
''';

    test('recovers malformed jsonish timeline output', () {
      final promptText = WebContextService.parseDoubaoTimelineTextForTest(
        content: '''
{
  "timeline": [
    {
      "text": "爱音在水族馆谈心",
      "fact_indexes": [1]
    },
    {
      "text": "灯在全班面前请求爱音回到乐队，追到天台上以"让我们一起迷失吧"说服爱音",
      "fact_indexes": [2]
    }
  ],
  "constraints": [
    "不要把不连续事件直接拼接"
  ]
}
''',
        factTexts: const [
          '在水族馆，爱音交代了留学失败的经历并自嘲又在逃避与失败，而灯则跑去拿了一张访客问卷在上面涂鸦，肯定了爱音的鼓励与坚持并鼓励爱音在迷茫中也要前进。',
          '因此，次日灯在全班面前请求爱音回到乐队大声表白我需要爱音，追到天台上后以一句“让我们一起迷失吧”成功说服爱音。',
        ],
        sourceExcerpts: const [
          '在水族馆，爱音交代了留学失败的经历并自嘲又在逃避与失败，而灯则跑去拿了一张访客问卷在上面涂鸦，肯定了爱音的鼓励与坚持并鼓励爱音在迷茫中也要前进。',
          '因此，次日灯在全班面前请求爱音回到乐队大声表白我需要爱音，追到天台上后以一句“让我们一起迷失吧”成功说服爱音。',
        ],
      );

      expect(promptText, isNotNull);
      expect(promptText, contains('爱音在水族馆谈心'));
      expect(promptText, contains('让我们一起迷失吧'));
      expect(promptText, contains('不要把不连续事件直接拼接'));
    });

    test('keeps natural text when references move forward', () {
      final parsed = ApiService.parseTimelineAnswerForTest(
        webContext: webContext,
        response: '''
{"sentences":[
  {"text":"嗯，我听说过这件事","timeline_refs":[]},
  {"text":"她们先在水族馆谈过","timeline_refs":[1]},
  {"text":"后来又在天台把话说开了","timeline_refs":[3]}
]}
''',
      );

      expect(parsed, '嗯，我听说过这件事。她们先在水族馆谈过。后来又在天台把话说开了。');
    });

    test('rejects reversed references', () {
      final parsed = ApiService.parseTimelineAnswerForTest(
        webContext: webContext,
        response: '''
{"sentences":[
  {"text":"先说天台","timeline_refs":[3]},
  {"text":"再说水族馆","timeline_refs":[1]}
]}
''',
      );

      expect(parsed, isNull);
    });

    test('rejects invalid references', () {
      final parsed = ApiService.parseTimelineAnswerForTest(
        webContext: webContext,
        response: '{"sentences":[{"text":"引用不存在的阶段","timeline_refs":[4]}]}',
      );

      expect(parsed, isNull);
    });

    test('rejects nonadjacent stages merged into one sentence', () {
      final parsed = ApiService.parseTimelineAnswerForTest(
        webContext: webContext,
        response: '{"sentences":[{"text":"把相隔阶段压成一件事","timeline_refs":[1,3]}]}',
      );

      expect(parsed, isNull);
    });
  });

  group('Aligned Japanese translation contract', () {
    test('keeps MyGO!!!!! inside one source sentence', () {
      expect(
        ApiService.splitChineseTranslationUnitsForTest(
          '她加入了MyGO!!!!!真的很开心！后来又去练习。',
        ),
        ['她加入了MyGO!!!!!真的很开心！', '后来又去练习。'],
      );
    });

    test('joins translations with matching source indexes', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['先发生第一件事。', '后来发生第二件事。'],
        response: '''
{"translations":[
  {"source_index":1,"text":"先に一つ目のことが起きました。"},
  {"source_index":2,"text":"その後、二つ目のことが起きました。"}
]}
''',
      );

      expect(parsed, '先に一つ目のことが起きました。その後、二つ目のことが起きました。');
    });

    test('rejects reordered source indexes', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['第一句。', '第二句。'],
        response: '''
{"translations":[
  {"source_index":2,"text":"二文目です。"},
  {"source_index":1,"text":"一文目です。"}
]}
''',
      );

      expect(parsed, isNull);
    });

    test('rejects name placeholders moved across sentences', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['__JP_NAME_0__来了。', '大家开始聊天。'],
        placeholders: const {'__JP_NAME_0__': '燈'},
        response: '''
{"translations":[
  {"source_index":1,"text":"やって来ました。"},
  {"source_index":2,"text":"__JP_NAME_0__と皆で話し始めました。"}
]}
''',
      );

      expect(parsed, isNull);
    });

    test('rejects an unsupported passive voice shift', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['__JP_NAME_0__拒绝了邀请。'],
        placeholders: const {'__JP_NAME_0__': '燈'},
        response: '''
{"translations":[
  {"source_index":1,"text":"__JP_NAME_0__は招待を拒否されました。"}
]}
''',
      );

      expect(parsed, isNull);
    });

    test('keeps passive voice when the source is also passive', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['__JP_NAME_0__被拒绝了。'],
        placeholders: const {'__JP_NAME_0__': '燈'},
        response: '''
{"translations":[
  {"source_index":1,"text":"__JP_NAME_0__は拒否されました。"}
]}
''',
      );

      expect(parsed, '__JP_NAME_0__は拒否されました。');
    });
  });

  group('Canon secondary search objects', () {
    test('keeps a planned Latin work or group title needed by another ask', () {
      final targets = WebContextService.canonSearchTargetsForTest(
        userText: 'KILLKISS这首歌怎么样，你比较喜欢mujica的哪些歌？',
        query: 'BanG Dream Ave Mujica KILLKiSS 丰川祥子看法',
        characterId: 'sakiko',
        characterName: '丰川祥子',
        primaryObjects: const ['丰川祥子', 'KILLKiSS'],
        secondaryObjects: const ['AveMujica'],
      );

      expect(targets, containsAll(['KILLKISS', '丰川祥子', 'AveMujica']));
    });

    test('still avoids treating an ordinary preference object as its page', () {
      final targets = WebContextService.canonSearchTargetsForTest(
        userText: '灯喜欢什么动物？',
        query: 'BanG Dream 高松灯 喜欢的动物',
        characterId: 'sakiko',
        characterName: '丰川祥子',
        primaryObjects: const ['高松灯'],
        secondaryObjects: const ['企鹅'],
      );

      expect(targets, contains('高松灯'));
      expect(targets, isNot(contains('企鹅')));
    });

    test('does not classify a song opinion as an event process', () {
      expect(
        WebContextService.isEventProcessCanonQuestionForTest(
          '你觉得这首歌怎么样？',
        ),
        isFalse,
      );
      expect(
        WebContextService.isEventProcessCanonQuestionForTest(
          '你当时是如何支援他们的？',
        ),
        isTrue,
      );
    });

    test('keeps P1 searches as separate clean objects', () {
      final attempts = WebContextService.doubaoCanonAttemptQueriesForTest(
        userText: 'KILLKISS怎么样，你比较喜欢mujica的哪些歌？',
        characterId: 'sakiko',
        characterName: '丰川祥子',
        searchTargets: const ['KILLKISS', '丰川祥子', 'AveMujica'],
      );
      final p1Queries = attempts
          .where((attempt) => attempt.startsWith('1:'))
          .map((attempt) => attempt.substring(2))
          .toList();

      expect(p1Queries, ['KILLKISS', 'AveMujica']);
      expect(p1Queries.any((query) => query.contains('KILLKISS Ave')), isFalse);
    });

    test('closes the Doubao search budget after six calls', () {
      expect(
        WebContextService.isDoubaoSearchBudgetAvailableForTest(5),
        isTrue,
      );
      expect(
        WebContextService.isDoubaoSearchBudgetAvailableForTest(6),
        isFalse,
      );
    });

    test('requires three source pages for current affairs stop condition', () {
      expect(
        WebContextService.textLooksLikeCurrentAffairsQuestionForTest(
          '听说今年被称为“Agent元年”，姐姐怎么看',
        ),
        isTrue,
      );
      expect(
        WebContextService.textLooksLikeCurrentAffairsQuestionForTest(
          '我最近很喜欢看梦限大的番',
        ),
        isFalse,
      );

      final oneSourceFacts = [
        for (var i = 1; i <= 5; i++)
          {
            'text': '事实$i',
            'sourceTitle': '页面A',
            'sourceUrl': 'https://example.com/a',
            'sourceExcerpt': '事实$i',
          },
      ];
      expect(
        WebContextService.doubaoFactsMeetStopConditionForTest(
          facts: oneSourceFacts,
          factLimit: 10,
          minimumFactTarget: 5,
          minimumSourceTarget: 3,
        ),
        isFalse,
      );

      final threeSourceFacts = [
        for (var i = 1; i <= 5; i++)
          {
            'text': '事实$i',
            'sourceTitle': '页面${(i % 3) + 1}',
            'sourceUrl': 'https://example.com/${(i % 3) + 1}',
            'sourceExcerpt': '事实$i',
          },
      ];
      expect(
        WebContextService.doubaoFactsMeetStopConditionForTest(
          facts: threeSourceFacts,
          factLimit: 10,
          minimumFactTarget: 5,
          minimumSourceTarget: 3,
        ),
        isTrue,
      );

      final duplicateFacts = [
        ...threeSourceFacts.take(4),
        {
          'text': '事实1',
          'sourceTitle': '页面2',
          'sourceUrl': 'https://example.com/2',
          'sourceExcerpt': '事实1',
        },
      ];
      expect(
        WebContextService.doubaoFactsMeetStopConditionForTest(
          facts: duplicateFacts,
          factLimit: 10,
          minimumFactTarget: 5,
          minimumSourceTarget: 3,
        ),
        isFalse,
      );
    });
  });

  group('Raw source evidence handoff', () {
    test('sends source text instead of the model summary', () {
      final context = WebContextService.factContextTextForTest(
        factText: '爱音带灯去了水族馆',
        sourceExcerpt: '追上来的灯一把把爱音拉走。在水族馆，爱音交代了留学失败的经历。',
      );

      expect(context, startsWith('原文证据：追上来的灯一把把爱音拉走'));
      expect(context, isNot(contains('爱音带灯去了水族馆')));
    });

    test('does not let a wrong summary ground a timeline node', () {
      final grounded = WebContextService.timelineNodeGroundedForTest(
        timelineText: '千早爱音去了水族馆。',
        factText: '千早爱音去了水族馆。',
        sourceExcerpt: '高松灯去了水族馆。',
      );

      expect(grounded, isFalse);
    });

    test('keeps an in-story Live event grounded by the source excerpt', () {
      const evidence = '在水族馆，爱音交代了留学失败的经历，灯在访客问卷上涂鸦鼓励爱音，二人牵着手下定决心继续开Live。';
      final grounded = WebContextService.timelineNodeGroundedForTest(
        timelineText: evidence,
        factText: '上游概括不参与校验',
        sourceExcerpt: evidence,
      );

      expect(grounded, isTrue);
    });

    test('reports the exact reason for an unsupported timeline person', () {
      final reason = WebContextService.timelineNodeGroundingFailureForTest(
        timelineText: '千早爱音去了水族馆。',
        factText: '千早爱音去了水族馆。',
        sourceExcerpt: '高松灯去了水族馆。',
      );

      expect(reason, contains('千早爱音'));
      expect(reason, contains('未出现在引用原文'));
    });
  });
}
