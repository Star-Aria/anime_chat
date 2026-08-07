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
}
