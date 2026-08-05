import 'package:flutter_test/flutter_test.dart';

import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/emotion_analyzer.dart';

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
}
