import 'package:flutter_test/flutter_test.dart';

import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/emotion_analyzer.dart';
import 'package:anime_chat_app/name_pronunciation.dart';

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
}
