import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/character_config.dart';
import 'package:anime_chat_app/api_service.dart';
import 'package:anime_chat_app/emotion_analyzer.dart';
import 'package:anime_chat_app/music_service.dart';
import 'package:anime_chat_app/music_history_migration.dart';
import 'package:anime_chat_app/name_pronunciation.dart';
import 'package:anime_chat_app/storage_service.dart';
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

  test('Sentence splitter isolates and splits Japanese quotations', () {
    final sentences = EmotionAnalyzer.splitSentences(
      'この歌詞が好きです。「壊れぬように。壊さぬように」そう思います。',
    );

    expect(sentences, [
      'この歌詞が好きです。',
      '「壊れぬように。」',
      '「壊さぬように」',
      'そう思います。',
    ]);
  });

  test('Sentence splitter isolates inline Japanese dialogue', () {
    final sentences = EmotionAnalyzer.splitSentences(
      '彼女は「MyGO!!!!!を続けたい」と言いました。',
    );

    expect(sentences, [
      '彼女は',
      '「MyGO!!!!!を続けたい」',
      'と言いました。',
    ]);
  });

  group('Music share trigger', () {
    test('triggers only for explicit share or playback requests', () {
      expect(
        MusicService.isMusicShareRequest('请分享一首最近喜欢的你们乐队的歌'),
        isTrue,
      );
      expect(
        MusicService.isMusicShareRequest('能放一首mujica的歌给我听吗'),
        isTrue,
      );
      expect(MusicService.isMusicShareRequest('我们一起听歌吧'), isTrue);
      expect(MusicService.isMusicShareRequest('陪我听听音乐好吗'), isTrue);
      expect(MusicService.isMusicShareRequest('听歌的话就一起吧'), isTrue);
      expect(
        MusicService.isMusicShareRequest('祥祥，一起听下MyGO的《无路矢》吧'),
        isTrue,
      );
      expect(
        MusicService.isMusicShareRequest(
          '来首《无路矢》吧',
          knownSongTitles: const ['无路矢'],
        ),
        isTrue,
      );
      expect(MusicService.isMusicShareRequest('我们一起听他说完'), isFalse);
    });

    test('does not attach audio for song opinion questions', () {
      expect(
        MusicService.isMusicShareRequest(
          '祥祥，KILLKISS真的太燃了，我好喜欢！祥祥觉得你们的这首歌怎么样呢，你比较喜欢mujica的哪些歌呢',
        ),
        isFalse,
      );
      expect(
        MusicService.isMusicShareRequest('你比较喜欢mujica的哪些歌呢？'),
        isFalse,
      );
    });

    test('selects the requested song for a shared-listening message', () async {
      final selected = await MusicService.pickAttachmentForRequest(
        userText: '祥祥，一起听下MyGO的《无路矢》吧',
        character: CharacterConfig.getCharacterById('sakiko'),
      );

      expect(selected?.title, '无路矢');
      expect(selected?.band, 'MyGO!!!!!');
    });

    test('recognizes a concise request through the catalog song title',
        () async {
      final selected = await MusicService.pickAttachmentForRequest(
        userText: '来首《无路矢》吧',
        character: CharacterConfig.getCharacterById('sakiko'),
      );

      expect(selected?.title, '无路矢');
      expect(selected?.band, 'MyGO!!!!!');
    });

    test('prefers songs not already shared in the conversation', () async {
      final catalog = await MusicService.loadCatalog();
      final mujicaSongs =
          catalog.where((item) => item.band == 'Ave Mujica').toList();
      final remainingSong = mujicaSongs.last;
      final history = mujicaSongs
          .take(mujicaSongs.length - 1)
          .map(
            (song) => Message(
              role: 'assistant',
              content: '推荐过 ${song.title}',
              timestamp: DateTime(2026),
              musicAttachment: song,
            ),
          )
          .toList();

      final selected = await MusicService.pickAttachmentForRequest(
        userText: '请分享一首你们乐队的歌',
        character: CharacterConfig.getCharacterById('sakiko'),
        conversationHistory: history,
      );

      expect(selected?.id, remainingSong.id);
    });

    test('still honors an explicitly requested song already shared', () async {
      final catalog = await MusicService.loadCatalog();
      final killkiss = catalog.firstWhere((item) => item.title == 'KiLLKiSS');
      final history = [
        Message(
          role: 'assistant',
          content: '推荐过 KiLLKiSS',
          timestamp: DateTime(2026),
          musicAttachment: killkiss,
        ),
      ];

      final selected = await MusicService.pickAttachmentForRequest(
        userText: '请再分享KiLLKiSS这首歌',
        character: CharacterConfig.getCharacterById('sakiko'),
        conversationHistory: history,
      );

      expect(selected?.id, killkiss.id);
    });

    test('allows repeats after every preferred-band song was shared', () async {
      final catalog = await MusicService.loadCatalog();
      final mujicaSongs =
          catalog.where((item) => item.band == 'Ave Mujica').toList();
      final history = mujicaSongs
          .map(
            (song) => Message(
              role: 'assistant',
              content: '推荐过 ${song.title}',
              timestamp: DateTime(2026),
              musicAttachment: song,
            ),
          )
          .toList();

      final selected = await MusicService.pickAttachmentForRequest(
        userText: '请分享一首你们乐队的歌',
        character: CharacterConfig.getCharacterById('sakiko'),
        conversationHistory: history,
      );

      expect(selected, isNotNull);
      expect(selected?.band, 'Ave Mujica');
    });

    test('matches catalog songs through pronunciation-table title forms',
        () async {
      expect(
        await MusicService.mentionedCatalogTitleForTest('播放黑色生日'),
        '黒のバースデイ',
      );
      expect(
        await MusicService.mentionedCatalogTitleForTest(
          '我想听Aoi Hitomi no Naka ni',
        ),
        '碧蓝眼瞳之中',
      );
      expect(
        await MusicService.mentionedCatalogTitleForTest(
          '分享Symbol II Air吧',
        ),
        'Symbol II : Air',
      );
      expect(
        await MusicService.mentionedCatalogTitleForTest(
          '播放Masquerade Rhapsody Request',
        ),
        'Mas?uerade Rhapsody Re?uest',
      );
      expect(
        await MusicService.mentionedCatalogTitleForTest('随便分享一首Mujica的歌'),
        isNull,
      );
    });

    test('adds structured local music profile to prompt context', () {
      final context = MusicService.buildPromptContext(
        const MusicAttachment(
          id: 'test_song',
          title: 'Ether',
          artist: 'Ave Mujica',
          band: 'Ave Mujica',
          description: '这首歌像逐渐被光和空气包围，安静但并不轻。',
          lyrics: ['透明な空気に触れて', 'まだ名前のない光へ'],
          moods: ['空灵', '壮大'],
          sound: ['旋律抬升'],
          themes: ['以太', '光'],
          imagery: ['透明空气'],
          recommendationAngles: ['适合安静分享'],
        ),
      );

      expect(context, contains('氛围标签：空灵、壮大'));
      expect(context, contains('听感要点：旋律抬升'));
      expect(context, contains('主题素材：以太、光'));
      expect(context, contains('【本地歌曲描述】'));
      expect(context, contains('这首歌像逐渐被光和空气包围'));
      expect(context, contains('【本地歌词】\n透明な空気に触れて\nまだ名前のない光へ'));
      expect(
        context,
        contains('如果引用歌词，只能引用提供的中文翻译'),
      );
      expect(context, contains('跳过歌词里的英文单词、英文短语和英文句子'));
      expect(context, contains('歌名与专有名词不受此限制'));
    });

    test('adds local catalog boundaries for ordinary song discussion',
        () async {
      final context = await MusicService.buildDiscussionContext(
        userText: '祥祥，KILLKISS真的太燃了，我好喜欢！祥祥觉得你们的这首歌怎么样呢，你比较喜欢mujica的哪些歌呢',
        character: CharacterConfig.getCharacterById('sakiko'),
      );

      expect(context, contains('【本地曲库参考】'));
      expect(context, contains('本轮用户是在聊音乐，不是请求播放或分享音频'));
      expect(context, isNot(contains('【本轮音乐分享附件】')));
      expect(context, contains('歌名：KiLLKiSS'));
      expect(context, contains('Ave Mujica 本地曲库曲目'));
      expect(context, contains('- KiLLKiSS'));
      expect(context, contains('Symbol I'));
      expect(context, contains('Symbol II'));
      expect(context, contains('Symbol III'));
      expect(context, contains('Symbol IV'));
      expect(context, contains('不要只说《Symbol》'));
      expect(context, contains('在命运玩弄下发出无声之音'));
      expect(context, isNot(contains('弄られて垂れ流す 音のない音')));
      expect(context, isNot(contains('【日文原词】')));
      expect(
        context,
        contains('如果引用歌词，只能引用提供的中文翻译'),
      );
      expect(context, contains('跳过歌词里的英文单词、英文短语和英文句子'));
      expect(context, contains('歌名与专有名词不受此限制'));
    });

    test('isolates Chinese lyrics from Japanese lyrics in response prompts',
        () {
      const attachment = MusicAttachment(
        id: 'bilingual_test',
        title: '无路矢',
        artist: 'MyGO!!!!!',
        band: 'MyGO!!!!!',
        lyrics: [
          '【日文原词】',
          '生まれた地球にいるはずなのに',
          '本当は僕だけが違う星から来たみたいなんだ',
          '',
          '【中文翻译】',
          '明明就身处我所诞生的地球',
          '好像只有我从截然不同的星球而来',
        ],
      );

      final lyrics = MusicService.lyricsForChineseResponseForTest(attachment);
      final context = MusicService.buildPromptContext(attachment);

      expect(lyrics, contains('明明就身处我所诞生的地球'));
      expect(lyrics, isNot(contains('生まれた地球')));
      expect(context, contains('好像只有我从截然不同的星球而来'));
      expect(context, isNot(contains('本当は僕だけが')));
      expect(context, isNot(contains('【日文原词】')));
    });

    test('Japanese validation accepts kanji-heavy lyrics but rejects Chinese',
        () {
      expect(
        ApiService.isCleanJapaneseForTtsForTest(
          '歌詞の「生まれた地球にいるはずなのに、本当は僕だけが違う星から来たみたいなんだ」が心に残りますわ。',
        ),
        isTrue,
      );
      expect(
        ApiService.isCleanJapaneseForTtsForTest(
          '歌詞の「生まれた地球にいるはずなのに，可为何好像只有我違う星から来たみたいなんだ」が心に残りますわ。',
        ),
        isFalse,
      );
    });

    test('passes only the current song bilingual lyrics to translation',
        () async {
      final reference = await MusicService.buildTranslationLyricsReference(
        userText: '祥祥觉得KILLKISS这首歌怎么样？',
        character: CharacterConfig.getCharacterById('sakiko'),
      );

      expect(reference, isNotNull);
      expect(reference!['song_title'], 'KiLLKiSS');
      final pairs = (reference['lyric_pairs'] as List).cast<Map>();
      final referenceText = pairs
          .expand((pair) => [pair['japanese'], pair['chinese']])
          .join('\n');
      expect(referenceText, contains('弄られて垂れ流す 音のない音'));
      expect(referenceText, contains('在命运玩弄下发出无声之音'));
      expect(referenceText, isNot(contains('can not')));
      expect(referenceText, isNot(contains('KiLLKiSS judy')));

      final protected =
          ApiService.protectKnownLyricsForJapaneseTranslationForTest(
        '我很喜欢“在命运玩弄下发出无声之音”这句。',
        reference,
      );
      expect(protected['text'], contains('__JP_LYRIC_0__'));
      expect(
        protected['placeholders'],
        containsPair('__JP_LYRIC_0__', '弄られて垂れ流す 音のない音'),
      );

      final promptReference =
          ApiService.japaneseLyricsReferenceForPromptForTest(reference);
      final promptReferenceText = jsonEncode(promptReference);
      expect(promptReferenceText, contains('弄られて垂れ流す 音のない音'));
      expect(promptReferenceText, isNot(contains('在命运玩弄下发出无声之音')));
      expect(promptReferenceText, isNot(contains('chinese')));
    });

    test('does not pass lyrics when no current song is identified', () async {
      final reference = await MusicService.buildTranslationLyricsReference(
        userText: '祥祥比较喜欢mujica的哪些歌？',
        character: CharacterConfig.getCharacterById('sakiko'),
      );

      expect(reference, isNull);
    });

    test('all labeled bilingual lyrics provide translation references',
        () async {
      final catalog = await MusicService.loadCatalog();

      for (final song in catalog.where((song) => song.lyrics.isNotEmpty)) {
        final hasJapaneseHeading = song.lyrics.contains('【日文原词】');
        final hasChineseHeading = song.lyrics.contains('【中文翻译】');
        expect(
          hasJapaneseHeading,
          hasChineseHeading,
          reason: '${song.title} 的双语标题不完整',
        );
        if (!hasJapaneseHeading) continue;

        final reference = await MusicService.buildTranslationLyricsReference(
          userText: song.title,
          character: CharacterConfig.getCharacterById('sakiko'),
          selectedAttachment: song,
        );
        expect(reference, isNotNull, reason: song.title);
        expect(reference!['lyric_pairs'], isNotEmpty, reason: song.title);
      }
    });

    test('uses local-only discussion for covered MyGO or Mujica songs',
        () async {
      final character = CharacterConfig.getCharacterById('sakiko');

      expect(
        await MusicService.shouldUseLocalOnlyForDiscussion(
          userText: '祥祥，KILLKISS真的太燃了，我好喜欢！你比较喜欢mujica的哪些歌呢？',
          character: character,
        ),
        isTrue,
      );
      expect(
        await MusicService.shouldUseLocalOnlyForDiscussion(
          userText: '祥祥，你觉得Roselia的歌怎么样？',
          character: character,
        ),
        isFalse,
      );
      expect(
        await MusicService.buildDiscussionContext(
          userText: '祥祥，你觉得Roselia的歌怎么样？',
          character: character,
        ),
        isEmpty,
      );
    });

    test('catalog includes complete MyGO profiles and external lyrics paths',
        () async {
      final catalog = await MusicService.loadCatalog();
      final titles = catalog.map((item) => item.title).toSet();
      final mygoSongs =
          catalog.where((item) => item.band == 'MyGO!!!!!').toList();

      expect(mygoSongs, hasLength(36));
      expect(
        titles,
        containsAll(['名无声', '猛独侵袭', 'DIVINE', '碧蓝眼瞳之中']),
      );
      final mygoProfileSignatures = <String>{};
      for (final item in mygoSongs) {
        expect(item.description?.trim(), isNotEmpty, reason: item.title);
        expect(item.note?.trim(), isNotEmpty, reason: item.title);
        expect(item.moods, isNotEmpty, reason: item.title);
        expect(item.sound, isNotEmpty, reason: item.title);
        expect(item.themes, isNotEmpty, reason: item.title);
        expect(item.imagery, isNotEmpty, reason: item.title);
        expect(item.recommendationAngles, isNotEmpty, reason: item.title);
        mygoProfileSignatures.add(jsonEncode([
          item.note,
          item.moods,
          item.sound,
          item.themes,
          item.imagery,
          item.recommendationAngles,
        ]));
      }
      expect(mygoProfileSignatures, hasLength(mygoSongs.length));
      for (final item in catalog) {
        expect(
          item.lyricsPath?.trim(),
          isNotEmpty,
          reason: '${item.title} should declare a lyricsPath',
        );
        expect(
          File(item.lyricsPath!).existsSync(),
          isTrue,
          reason: '${item.title} lyrics file should exist',
        );
      }
      for (final title in ['名无声', '猛独侵袭', 'DIVINE', '碧蓝眼瞳之中']) {
        final item = catalog.firstWhere((item) => item.title == title);
        expect(item.lyrics, isA<List<String>>());
        expect(item.moods, isNot(isEmpty),
            reason: '$title moods should not be empty');
        expect(item.sound, isNot(isEmpty),
            reason: '$title sound should not be empty');
        expect(item.themes, isNot(isEmpty),
            reason: '$title themes should not be empty');
        expect(item.imagery, isNot(isEmpty),
            reason: '$title imagery should not be empty');
        expect(
          item.recommendationAngles,
          isNot(isEmpty),
          reason: '$title recommendationAngles should not be empty',
        );
        expect(
          item.note,
          isNot(anyOf(contains('等待补充'), contains('description 和 lyrics'))),
          reason: '$title note should not expose catalog maintenance text',
        );
      }
    });

    test('catalog omits redundant embedded lyrics and source fields', () {
      final decoded = jsonDecode(
        File('music/music_catalog.json').readAsStringSync(),
      ) as List<dynamic>;

      for (final rawEntry in decoded) {
        final entry = rawEntry as Map<String, dynamic>;
        expect(entry, isNot(contains('lyrics')));
        expect(entry, isNot(contains('sourceUrls')));
        expect(entry, isNot(contains('sourceNotes')));
      }
    });

    test('does not serialize loaded lyrics into chat messages', () {
      const attachment = MusicAttachment(
        id: 'serialization_test',
        title: 'KiLLKiSS',
        artist: 'Ave Mujica',
        band: 'Ave Mujica',
        lyricsPath: 'music/lyrics/ave_mujica_killkiss.txt',
        timedLyricsPath: 'music/lyrics/ave_mujica_killkiss.json',
        lyrics: ['第一行', '第二行'],
      );

      final json = attachment.toJson();
      expect(json, isNot(contains('lyrics')));
      expect(json['lyricsPath'], 'music/lyrics/ave_mujica_killkiss.txt');
      expect(
        json['timedLyricsPath'],
        'music/lyrics/ave_mujica_killkiss.json',
      );
    });

    test('migrates old music cards without rebuilding chat messages', () {
      const currentSong = MusicAttachment(
        id: 'ave_mujica_test_song',
        title: '测试曲',
        artist: 'Ave Mujica',
        band: 'Ave Mujica',
        localAudioPath: 'music/audio/current.mp3',
        lyricsPath: 'music/lyrics/ave_mujica_test_song.txt',
        timedLyricsPath: 'music/lyrics/ave_mujica_test_song.json',
      );
      final original = jsonEncode([
        {
          'role': 'assistant',
          'content': '这是原来的聊天正文，不能改。',
          'timestamp': '2026-08-17T12:34:56.000',
          'audioPath': 'tts/original.wav',
          'musicAttachment': {
            'id': 'ave_mujica_test_song',
            'title': '测试曲',
            'artist': 'Ave Mujica',
            'band': 'Ave Mujica',
            'localAudioPath': 'music/audio/old.mp3',
            'lyrics': ['过期歌词'],
          },
        },
        {
          'role': 'user',
          'content': '普通消息也不能改。',
          'timestamp': '2026-08-17T12:35:00.000',
        },
      ]);

      final migrated = MusicHistoryMigration.migrateConversationJson(
        original,
        const [currentSong],
      );
      final messages = jsonDecode(migrated.json) as List<dynamic>;
      final assistant = messages.first as Map<String, dynamic>;
      final attachment = assistant['musicAttachment'] as Map<String, dynamic>;

      expect(migrated.attachmentsUpdated, 1);
      expect(assistant['content'], '这是原来的聊天正文，不能改。');
      expect(assistant['timestamp'], '2026-08-17T12:34:56.000');
      expect(assistant['audioPath'], 'tts/original.wav');
      expect(messages[1]['content'], '普通消息也不能改。');
      expect(attachment['localAudioPath'], 'music/audio/current.mp3');
      expect(
        attachment['timedLyricsPath'],
        'music/lyrics/ave_mujica_test_song.json',
      );
      expect(attachment, isNot(contains('lyrics')));

      final secondRun = MusicHistoryMigration.migrateConversationJson(
        migrated.json,
        const [currentSong],
      );
      expect(secondRun.attachmentsUpdated, 0);
      expect(secondRun.json, migrated.json);
    });

    test('keeps timed display lyrics separate from discussion lyrics',
        () async {
      final catalog = await MusicService.loadCatalog();
      final timedLyricSongs = catalog
          .where(
              (song) => song.band == 'Ave Mujica' || song.band == 'MyGO!!!!!')
          .toList();
      expect(
        timedLyricSongs.where((song) => song.band == 'Ave Mujica'),
        hasLength(25),
      );
      expect(
        timedLyricSongs.where((song) => song.band == 'MyGO!!!!!'),
        hasLength(36),
      );

      for (final song in timedLyricSongs) {
        final basename = song.id;
        expect(song.lyricsPath, 'music/lyrics/$basename.txt');
        expect(song.timedLyricsPath, 'music/lyrics/$basename.json');
        expect(song.lyrics, isNotEmpty, reason: song.title);

        final timedJson = jsonDecode(
          File(song.timedLyricsPath!).readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(
          timedJson.keys,
          unorderedEquals(['lrc', 'tlyric']),
          reason: song.title,
        );
        expect((timedJson['lrc'] as Map)['lyric'], contains(RegExp(r'\[\d')));
        expect(
          (timedJson['tlyric'] as Map)['lyric'],
          contains(RegExp(r'\[\d')),
        );
        final lrcText = (timedJson['lrc'] as Map)['lyric'] as String;
        final translatedText = (timedJson['tlyric'] as Map)['lyric'] as String;
        final timestampPattern = RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]');
        expect(
          timestampPattern.allMatches(translatedText).map((match) => match[0]),
          timestampPattern.allMatches(lrcText).map((match) => match[0]),
          reason: '${song.title} 的日中时间戳必须逐行一致',
        );
        expect(
          '$lrcText\n$translatedText',
          isNot(matches(RegExp(
            r'transUser|lyricUser|\[by:|(?:制作(?:人)?|作[词詞曲]|[编編]曲|词|詞|曲)\s*[:：]',
          ))),
          reason: '${song.title} 不应保留来源账户或制作信息',
        );

        final discussionLyrics = File(song.lyricsPath!).readAsStringSync();
        final translationSections = discussionLyrics.split('【中文翻译】');
        expect(translationSections, hasLength(2), reason: song.title);
        final discussionJapanese = translationSections.first
            .replaceFirst('【日文原词】', '')
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final discussionTranslation = translationSections.last
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        expect(
          discussionTranslation,
          hasLength(discussionJapanese.length),
          reason: '${song.title} 的日文原词与中文翻译必须逐行对应',
        );
      }
    });

    test('lyrics can be stored as editable lines and legacy text', () {
      final attachment = MusicAttachment.fromJson({
        'id': 'lyrics_test',
        'title': '歌词测试',
        'artist': 'Ave Mujica',
        'band': 'Ave Mujica',
        'lyrics': ['第一行', '第二行', '', '第四行'],
      });
      final legacyAttachment = MusicAttachment.fromJson({
        'id': 'legacy_lyrics_test',
        'title': '旧歌词测试',
        'artist': 'Ave Mujica',
        'band': 'Ave Mujica',
        'lyrics': '旧第一行\n旧第二行',
      });

      expect(attachment.lyrics, ['第一行', '第二行', '', '第四行']);
      expect(attachment.lyricsText, '第一行\n第二行\n\n第四行');
      expect(legacyAttachment.lyrics, ['旧第一行', '旧第二行']);
      expect(legacyAttachment.lyricsText, '旧第一行\n旧第二行');
    });

    test('loads lyrics from plain text files', () async {
      final lyricsFile = File('music/lyrics/ave_mujica_killkiss.txt');
      final original = await lyricsFile.readAsString();
      await lyricsFile.writeAsString('  第一行歌词  \n第二行歌词\n\n第四行歌词\n');
      try {
        final catalog = await MusicService.loadCatalog();
        final attachment =
            catalog.firstWhere((item) => item.id == 'ave_mujica_killkiss');
        final context = MusicService.buildPromptContext(attachment);

        expect(attachment.lyrics, ['  第一行歌词', '第二行歌词', '', '第四行歌词']);
        expect(attachment.lyricsText, '第一行歌词\n第二行歌词\n\n第四行歌词');
        expect(context, contains('【本地歌词】\n第一行歌词\n第二行歌词\n\n第四行歌词'));
      } finally {
        await lyricsFile.writeAsString(original);
      }
    });

    test('loads embedded cover art from every local music file', () async {
      final catalog = await MusicService.loadCatalog();

      for (final song in catalog) {
        final cover = await MusicService.loadCoverBytes(song);
        expect(cover, isNotNull, reason: song.title);
        expect(cover, isNotEmpty, reason: song.title);
      }
    });
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
      isTrue,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        'ええ、伺っておりますわ。愛音さんは燈を誘いました。燈は一度拒んでしまった。その後、二人は向き合いました。愛音さんは戻った。大切な関係です。',
        'sakiko',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        '最近は、少しお話しできることがあります。にゃむが練習中に動画を撮って、海鈴が休憩中にマカロンを食べているところまで映ってしまいました。いつも冷静な海鈴が、珍しく慌てていましたね。',
        'sakiko',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        '（そっと手にした紅茶を置いて）最近、確かに新しい公演を準備しておりますの。ただ、具体的な詳細はあまりお話しできませんわ。何と言っても神秘感を保つことが大切ですものね。',
        'sakiko',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseTranslationStyleCompatible(
        '（微かに口元をほころばせて）最近、面白いことが一つありましたの。にゃむが練習中にうっかりドラムスティックを投げ飛ばしてしまい、ちょうど海鈴のベースに当たったんです。彼女はずっとそれが意図的な即興演奏だと言っていますが、あのような慌てた様子は、珍しいものです。',
        'sakiko',
      ),
      isTrue,
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

  test('Japanese style gate keeps per-character self pronouns', () {
    expect(
      ApiService.isJapaneseStyleCompatible(
        'うん、疲れてない。僕も一緒に座ってる。',
        'muichirou',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        'うん、疲れてない。俺も一緒に座ってる。',
        'muichirou',
      ),
      isFalse,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        'うん、疲れてない。私は一緒に座ってる。',
        'muichirou',
      ),
      isFalse,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        '俺には特に何もない。',
        'giyu',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        '僕には特に何もない。',
        'giyu',
      ),
      isFalse,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        '私は大丈夫ですよ。',
        'shinobu',
      ),
      isTrue,
    );
    expect(
      ApiService.isJapaneseStyleCompatible(
        '俺は大丈夫ですよ。',
        'shinobu',
      ),
      isFalse,
    );
  });

  test('Chinese conversation wording stays informal', () {
    expect(
      ApiService.normalizeChineseConversationWordingForTest(
        '您若是出门的话记得多喝水。',
      ),
      '你要是出门的话记得多喝水。',
    );
  });

  test('Japanese replies use Japanese quotation punctuation', () {
    expect(
      ApiService.usesJapaneseQuotationPunctuationForTest(
        '「壊れぬように」という歌詞と、『迷跡波』というアルバムです。',
      ),
      isTrue,
    );
    expect(
      ApiService.usesJapaneseQuotationPunctuationForTest(
        '最近は《Georgette Me, Georgette You》を聴いています。',
      ),
      isFalse,
    );
    expect(
      ApiService.usesJapaneseQuotationPunctuationForTest(
        '彼女は“もう一度始めましょう”と言いました。',
      ),
      isFalse,
    );
  });

  test('Japanese song titles use corner brackets without changing albums', () {
    final normalized = ApiService.normalizeJapaneseSongTitlePunctuationForTest(
      '次は『梵音打』です。アルバムは『迷跡波』です。',
      const ['梵音打', '猛独侵袭'],
    );

    expect(normalized, '次は「梵音打」です。アルバムは『迷跡波』です。');
    expect(
      ApiService.normalizeJapaneseSongTitlePunctuationForTest(
        '「迷うことに迷わないでいいよ」という歌詞です。',
        const ['梵音打'],
      ),
      '「迷うことに迷わないでいいよ」という歌詞です。',
    );
  });

  test('Character name registry resolves stage names to canonical identity',
      () {
    final lock = characterNameByJapaneseForm['LOCK'];
    final shinobu = characterNameByJapaneseForm['しのぶ'];
    final kanao = characterNameByJapaneseForm['カナヲ'];

    expect(lock?.chinese.replaceAll(RegExp(r'[\s　]+'), ''), '朝日六花');
    expect(lock?.compactJapanese, '朝日六花');
    expect(namePronunciationDictionary['LOCK'], 'ろっく');
    expect(shinobu?.chinese.replaceAll(RegExp(r'[\s　]+'), ''), '蝴蝶忍');
    expect(kanao?.chinese.replaceAll(RegExp(r'[\s　]+'), ''), '栗花落香奈乎');
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

  test('General term registry centralizes translation and TTS readings', () {
    expect(termPronunciationDictionary['お館様'], 'おやかたさま');
    expect(termPronunciationDictionary['主公大人'], 'おやかたさま');
    expect(termPronunciationDictionary['鬼殺隊'], 'きさつたい');
    expect(termPronunciationDictionary['CRYCHIC'], 'クライシック');
    expect(
      ApiService.nameTranslationGlossaryForPrompt(),
      containsAll([
        'お館様=主公大人',
        '刀鍛冶の里=锻刀村',
        '蝶屋敷=蝶屋',
      ]),
    );
    expect(
      ApiService.normalizeKnownNamesForChineseText('お館様和刀鍛冶の里。'),
      '主公大人和锻刀村。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest('主公大人提到了锻刀村。'),
      'お館様提到了刀鍛冶の里。',
    );
    expect(
      ApiService.canonicalChineseNamesForSearch(),
      containsAll(['主公大人', '锻刀村']),
    );
  });

  test('Ave Mujica song titles have TTS pronunciations', () {
    expect(
      termNamePronunciations.any(
          (entry) => entry.chinese == '黑色生日' && entry.japanese == '黒のバースデイ'),
      isTrue,
    );
    expect(termPronunciationDictionary['Kuro no Birthday'], 'くろのバースデイ');
    expect(termPronunciationDictionary['KiLLKiSS'], 'キルキス');
    expect(termPronunciationDictionary['Crucifix X'], 'クルシフィックス キス');
    expect(termPronunciationDictionary['天球のMúsica'], 'そらのムジカ');
    expect(termPronunciationDictionary["'S/' The Way"], 'スラッシュ ザ ウェイ');
    expect(termPronunciationDictionary['Symbol II : Air'], 'シンボル ツー エア');
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '黑色生日和天球的Música都很适合Ave Mujica。',
      ),
      '黒のバースデイ和天球のMúsica都很适合Ave Mujica。',
    );
    expect(
      ApiService.nameTranslationGlossaryForPrompt(),
      containsAll([
        '黒のバースデイ=黑色生日',
        '天球のMúsica=天球的Música',
      ]),
    );
    expect(
      ApiService.normalizeKnownNamesForChineseText(
        '黒のバースデイ和天球のMúsica都很适合Ave Mujica。',
      ),
      '黑色生日和天球的Música都很适合Ave Mujica。',
    );
    expect(termPronunciationDictionary['Hachibousei Dance'], 'はちぼうせいダンス');
    expect(termPronunciationDictionary['Aoi Hitomi no Naka ni'], 'あおいひとみのなかに');
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        'Kuro no Birthday和Aoi Hitomi no Naka ni都很适合Ave Mujica。',
      ),
      '黒のバースデイ和碧い瞳の中に都很适合Ave Mujica。',
    );
    expect(
      ApiService.normalizeKnownNamesForChineseText(
        'Kuro no Birthday和Aoi Hitomi no Naka ni都很适合Ave Mujica。',
      ),
      '黑色生日和碧蓝眼瞳之中都很适合Ave Mujica。',
    );
  });

  test('MyGO song titles share translation and TTS pronunciations', () {
    expect(termPronunciationDictionary['春日影'], 'はるひかげ');
    expect(termPronunciationDictionary['Haruhikage'], 'はるひかげ');
    expect(termPronunciationDictionary['迷星叫'], 'まよいうた');
    expect(termPronunciationDictionary['Mayoiuta'], 'まよいうた');
    expect(termPronunciationDictionary['詩超絆'], 'うたことば');
    expect(termPronunciationDictionary['Utakotoba'], 'うたことば');
    expect(termPronunciationDictionary['証命讚歌'], 'しょうめいさんか');
    expect(termPronunciationDictionary['罗永线'], 'らいん');
    expect(termPronunciationDictionary['Sasurai'], 'さすらい');
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '春日影和证命赞歌都很像MyGO会唱的歌。',
      ),
      '春日影和証命讃歌都很像MyGO会唱的歌。',
    );
    expect(
      ApiService.nameTranslationGlossaryForPrompt(),
      containsAll([
        '春日影=春日影',
        '詩超絆=诗超绊',
        '証命讃歌=证命赞歌',
      ]),
    );
    expect(
      ApiService.normalizeKnownNamesForChineseText(
        '詩超絆、証命讚歌和羅永線都在表里。',
      ),
      '诗超绊、证命赞歌和罗永线都在表里。',
    );
    expect(
      ApiService.normalizeKnownNamesForChineseText(
        'Haruhikage, Mayoiuta, and Utakotoba are MyGO songs.',
      ),
      '春日影, 迷星叫, and 诗超绊 are MyGO songs.',
    );
  });

  test('Chinese names map to canonical Japanese and per-character call names',
      () {
    final mapped = ApiService.applyJapaneseNameMappingsForTest(
      '灯和爱音同学提到了长崎爽世和玉壶。',
      characterId: 'sakiko',
    );

    expect(mapped, '燈和愛音さん提到了長崎そよ和ぎょっこ。');
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
    expect(
      ApiService.fixedCharacterCallNameChineseTargets('sakiko')['祐天寺若麦'],
      '若麦',
    );
    expect(
      ApiService.fixedCharacterCallNameChineseTargets('sakiko')['八幡海铃'],
      '海铃',
    );
    expect(
      ApiService.fixedCharacterCallNameChineseTargets('tomori')['丰川祥子'],
      '小祥',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '若麦又在练习室里闹出一点动静。',
        characterId: 'sakiko',
      ),
      'にゃむ又在练习室里闹出一点动静。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '海铃和若麦都在练习室。',
        characterId: 'sakiko',
      ),
      '海鈴和にゃむ都在练习室。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '八幡海铃和祐天寺若麦都在练习室。',
        characterId: 'sakiko',
      ),
      '八幡海鈴和祐天寺にゃむ都在练习室。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        '小祥说她会再试一次。',
        characterId: 'tomori',
      ),
      '祥ちゃん说她会再试一次。',
    );
  });

  test('Character code-name aliases keep their display form', () {
    final glossary = ApiService.nameTranslationGlossaryForPrompt();

    expect(namePronunciationDictionary['Oblivionis'], 'オブリビオニス');
    expect(
      ApiService.normalizeKnownNamesForChineseText('Oblivionis和Mortis同台。'),
      'Oblivionis和Mortis同台。',
    );
    expect(
      ApiService.applyJapaneseNameMappingsForTest(
        'Oblivionis和Mortis同台。',
      ),
      'Oblivionis和Mortis同台。',
    );
    expect(glossary, contains('Oblivionis=Oblivionis'));
    expect(glossary, isNot(contains('Oblivionis=丰川 祥子')));
    expect(ApiService.applyJapaneseNameMappingsForTest('玉壺出现了。'), 'ぎょっこ出现了。');
  });

  test('Character code-name aliases can resolve canon search targets', () {
    final oblivionisTargets = WebContextService.canonSearchTargetsForTest(
      userText: '小祥，Oblivionis以前经历过什么？',
      query: 'BanG Dream Ave Mujica Oblivionis 经历',
      characterId: 'sakiko',
      characterName: '丰川祥子',
    );
    final layerTargets = WebContextService.canonSearchTargetsForTest(
      userText: '小祥，LAYER有什么经历？',
      query: 'BanG Dream RAISE A SUILEN LAYER 经历',
      characterId: 'sakiko',
      characterName: '丰川祥子',
    );

    expect(
      oblivionisTargets.map((target) => target.replaceAll(RegExp(r'\s+'), '')),
      contains('丰川祥子'),
    );
    expect(
      layerTargets.map((target) => target.replaceAll(RegExp(r'\s+'), '')),
      contains('和奏瑞依'),
    );
  });

  test('Character search aliases do not affect translation display', () {
    final searchAliases = ApiService.characterSearchAliasesForSearch();

    expect(searchAliases['虫柱'], '蝴蝶忍');
    expect(searchAliases['主公大人'], '产屋敷耀哉');
    expect(
        ApiService.normalizeKnownNamesForChineseText('虫柱和主公大人。'), '虫柱和主公大人。');
    expect(
      ApiService.applyJapaneseNameMappingsForTest('虫柱和主公大人。'),
      '蟲柱和お館様。',
    );

    final pillarTargets = WebContextService.canonSearchTargetsForTest(
      userText: '无一郎，你知道虫柱小时候发生过什么事吗？',
      query: '鬼灭之刃 虫柱 小时候 经历',
      characterId: 'muichirou',
      characterName: '时透无一郎',
    );
    final leaderTargets = WebContextService.canonSearchTargetsForTest(
      userText: '忍小姐，主公大人以前对柱们做过什么安排吗？',
      query: '鬼灭之刃 主公大人 柱 安排',
      characterId: 'shinobu',
      characterName: '蝴蝶忍',
    );

    expect(
      pillarTargets.map((target) => target.replaceAll(RegExp(r'\s+'), '')),
      contains('蝴蝶忍'),
    );
    expect(
      leaderTargets.map((target) => target.replaceAll(RegExp(r'\s+'), '')),
      contains('产屋敷耀哉'),
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

    test('keeps protected lyric placeholders in their source sentence', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['我喜欢“__JP_LYRIC_0__”这句。'],
        placeholders: const {
          '__JP_LYRIC_0__': '弄られて垂れ流す 音のない音',
        },
        response: '''
{"translations":[
  {"source_index":1,"text":"「__JP_LYRIC_0__」という一節が好きです。"}
]}
''',
      );

      expect(parsed, '「__JP_LYRIC_0__」という一節が好きです。');
    });

    test('rejects a shared-kanji Chinese source fragment left untranslated',
        () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['听到这段旋律，今日心情非常安定。'],
        response: '''
{"translations":[
  {"source_index":1,"text":"この旋律を聴くと、今日心情非常安定です。"}
]}
''',
      );

      expect(parsed, isNull);
    });

    test('does not treat a protected song title as untranslated Chinese', () {
      final parsed = ApiService.parseAlignedJapaneseTranslationsForTest(
        sourceUnits: ['我想听__JP_TITLE_0__。'],
        placeholders: const {'__JP_TITLE_0__': '一同歌唱一同奏响'},
        response: '''
{"translations":[
  {"source_index":1,"text":"__JP_TITLE_0__を聴きたいです。"}
]}
''',
      );

      expect(parsed, '__JP_TITLE_0__を聴きたいです。');
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

    test('prioritizes character target over band context for profile traits',
        () {
      final targets = WebContextService.canonSearchTargetsForTest(
        userText: 'MyGO的千早爱音有什么喜好？',
        query: 'BanG Dream MyGO 千早爱音 喜好',
        characterId: 'sakiko',
        characterName: '丰川祥子',
        primaryObjects: const ['MyGO'],
        secondaryObjects: const ['千早爱音'],
      );
      final compactTargets =
          targets.map((target) => target.replaceAll(RegExp(r'\s+'), ''));

      expect(compactTargets.first, '千早爱音');
      expect(compactTargets, isNot(contains('MyGO')));
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

      expect(attempts.any((attempt) => attempt.startsWith('0:')), isTrue);
      expect(attempts.any((attempt) => attempt.contains('zh.moegirl.org.cn')),
          isTrue);
      expect(p1Queries, ['KILLKISS', 'AveMujica']);
      expect(p1Queries.any((query) => query.contains('KILLKISS Ave')), isFalse);
    });

    test('keeps Moegirl P0 for non-music canon questions', () {
      final attempts = WebContextService.doubaoCanonAttemptQueriesForTest(
        userText: '灯喜欢什么动物？',
        characterId: 'sakiko',
        characterName: '丰川祥子',
        searchTargets: const ['高松灯'],
      );

      expect(attempts.any((attempt) => attempt.startsWith('0:')), isTrue);
      expect(attempts.any((attempt) => attempt.contains('zh.moegirl.org.cn')),
          isTrue);
    });

    test('uses ordinary source target for music canon chat questions', () {
      expect(
        WebContextService.minimumDoubaoSourceTargetForTest(
          userText: 'KILLKISS怎么样，你比较喜欢mujica的哪些歌？',
          characterId: 'sakiko',
          characterName: '丰川祥子',
        ),
        1,
      );
      expect(
        WebContextService.minimumDoubaoSourceTargetForTest(
          userText: '灯喜欢什么动物？',
          characterId: 'sakiko',
          characterName: '丰川祥子',
        ),
        1,
      );

      final oneSourceFacts = [
        for (var i = 1; i <= 3; i++)
          {
            'text': '音乐事实$i',
            'sourceTitle': '页面A',
            'sourceUrl': 'https://example.com/a',
            'sourceExcerpt': '音乐事实$i',
          },
      ];

      expect(
        WebContextService.doubaoFactsMeetStopConditionForTest(
          facts: oneSourceFacts,
          factLimit: 10,
          minimumFactTarget: 3,
          minimumSourceTarget: 1,
        ),
        isTrue,
      );
    });

    test('keeps same-title facts from different web sources separate', () {
      final lines = WebContextService.formatDoubaoFactsForTest(
        maxFacts: 10,
        facts: const [
          {
            'text': '音乐事实1',
            'sourceTitle': 'KiLLKiSS',
            'sourceUrl': 'https://example.com/a',
            'sourceExcerpt': '音乐事实1',
          },
          {
            'text': '音乐事实2',
            'sourceTitle': 'KiLLKiSS',
            'sourceUrl': 'https://example.com/b',
            'sourceExcerpt': '音乐事实2',
          },
          {
            'text': '音乐事实3',
            'sourceTitle': 'Ave Mujica',
            'sourceUrl': 'https://example.com/c',
            'sourceExcerpt': '音乐事实3',
          },
        ],
      );

      expect(lines, hasLength(3));
      expect(lines[0], contains('https://example.com/a'));
      expect(lines[1], contains('https://example.com/b'));
      expect(lines[2], contains('https://example.com/c'));
    });

    test('dedupes duplicate lyric excerpts across music sources', () {
      final lines = WebContextService.formatDoubaoFactsForTest(
        maxFacts: 10,
        facts: const [
          {
            'text': '歌词页给出《KiLLKiSS》的日文歌词正文，可作为歌词主题和氛围参考',
            'sourceTitle': 'KiLLKiSS - BanG Dream! Wiki',
            'sourceUrl': 'https://bandori.miraheze.org/wiki/KiLLKiSS',
            'sourceExcerpt':
                '弄られて垂れ流す 音のない音 遍く 名前を捨てたのね あなたのモザイクが泣いてる can not deny',
          },
          {
            'text': '歌词页给出《KiLLKiSS》的日文歌词正文，可作为歌词主题和氛围参考',
            'sourceTitle': 'KiLLKiSS',
            'sourceUrl':
                'https://www.animesonglyrics.com/bang-dream-ave-mujica/killkiss',
            'sourceExcerpt':
                'Lyrics バージョン 弄られて垂れ流す 音のない音 あまねく 名前を捨てたのね あなたのモザイクが泣いてる',
          },
        ],
      );

      expect(lines, hasLength(1));
      expect(lines.single, contains('歌词片段：'));
      expect(lines.single, isNot(contains('can not deny')));
      expect(lines.single, contains('bandori.miraheze.org'));
    });

    test('does not label Chinese interpretation as lyric excerpt', () {
      final lines = WebContextService.formatDoubaoFactsForTest(
        maxFacts: 10,
        facts: const [
          {
            'text': '《KiLLKiSS》的歌词主题涉及孤独和挣扎中的自立',
            'sourceTitle': 'KiLLKiSS',
            'sourceUrl': 'https://wapbaike.baidu.com/item/KiLLKiSS/65216268',
            'sourceExcerpt':
                '它层层揭开那些无法磨灭的过往、人类与生俱来且无处可逃的孤独，以及那份在挣扎中被迫寻求自立、已然破碎的内心。',
          },
        ],
      );

      expect(lines.single, contains('原文证据：'));
      expect(lines.single, isNot(contains('歌词片段：')));
    });

    test('keeps music catalog candidate label in fact context', () {
      final lines = WebContextService.formatDoubaoFactsForTest(
        maxFacts: 10,
        facts: const [
          {
            'text': '资料页面列出的曲目候选：KiLLKiSS、Ether',
            'sourceTitle': 'KiLLKiSS',
            'sourceUrl': 'https://example.com/killkiss',
            'sourceExcerpt': 'KiLLKiSS Ave Mujica Ether',
          },
        ],
      );

      expect(lines.single, contains('曲目候选：'));
      expect(lines.single, contains('资料页面列出的曲目候选：KiLLKiSS、Ether'));
      expect(lines.single, contains('原文证据：KiLLKiSS Ave Mujica Ether'));
    });

    test('music candidate extraction only keeps local catalog song titles', () {
      expect(
        WebContextService.musicTitleCandidatesForTest(
          'BanG Dream Ave Mujica CRYCHIC Morfonica MyGO!!!!! 羽丘',
        ),
        ['Ave Mujica'],
      );
      expect(
        WebContextService.musicTitleCandidatesForTest(
          'KiLLKiSS Ave Mujica Ether',
        ),
        ['KiLLKiSS', 'Ave Mujica', 'Ether'],
      );
    });

    test('extracts uta-net lyrics area and rejects challenge pages', () {
      final readable = WebContextService.lyricsPageReadableTextForTest('''
<html><body>
<nav>作曲者名インデックス検索 レーベル名インデックス検索</nav>
<div id="kashi_area">弄られて垂れ流す<br>音のない音<br>遍く 名前を捨てたのね</div>
</body></html>
''');

      expect(readable, contains('弄られて垂れ流す'));
      expect(readable, contains('音のない音'));
      expect(readable, isNot(contains('インデックス検索')));
      expect(
        WebContextService.blockedPageContentForTest(
          'Just a moment Enable JavaScript and cookies to continue cf_chl_',
        ),
        isTrue,
      );
    });

    test('rejects music facts that only prove identity or catalog presence',
        () {
      const userText = '请查询 BanG Dream 作品内歌曲资料：歌名《KiLLKiSS》，所属乐队 Ave Mujica。';

      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: 'KiLLKiSS is a song by Ave Mujica',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://example.com/song',
          sourceExcerpt: 'KiLLKiSS is a song by Ave Mujica',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '资料页面列出的曲目包括 KiLLKiSS',
          sourceTitle: 'Ave Mujica',
          sourceUrl: 'https://example.com/band',
          sourceExcerpt:
              'Kuro no Birthday Ether KiLLKiSS Masquerade Rhapsody Request',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '歌词页给出《KiLLKiSS》的罗马音歌词正文',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://example.com/killkiss',
          sourceExcerpt:
              'Lyrics Romaji English Kanji Masagurarete tare nagasu Oto no nai oto amaneku Namae suteta no ne',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '歌词页给出《KiLLKiSS》的歌词正文',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://example.com/killkiss',
          sourceExcerpt:
              'Romaji Japanese Translation Masagurarete tarenagasu oto no nai oto Amaneku namae wo suteta no ne',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '《KiLLKiSS》附带商品和游戏收录信息',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://zh.wikipedia.org/wiki/KiLLKiSS',
          sourceExcerpt:
              '演唱会“Veritas”全场影像的蓝光光盘，两版本首批出货皆随机附赠一张交换卡片，歌曲亦作为手机节奏游戏收录歌曲。',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '《KiLLKiSS》的 BPM 为 200',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://bandori.fandom.com/wiki/KiLLKiSS',
          sourceExcerpt: 'Beats per minute 200 BPM',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '歌词页给出《KiLLKiSS》的日文歌词正文，可作为歌词主题和氛围参考',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://ikuina.com/lyrics/ave-mujica/killkiss-ave-mujica',
          sourceExcerpt: 'Search for 歌詞検索 Ave Mujica KiLLKiSS – Ave Mujica',
        ),
        isFalse,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '歌词页给出《KiLLKiSS》的日文歌词正文，可作为歌词主题和氛围参考',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://example.com/killkiss',
          sourceExcerpt: '弄られて垂れ流す 音のない音 遍く 名前を捨てたのね あなたのモザイクが泣いてる',
        ),
        isTrue,
      );
      expect(
        WebContextService.usefulMusicCanonFactForTest(
          userText: userText,
          text: '《KiLLKiSS》拥有强烈的节奏感，保留了 Ave Mujica 乐队特有的强烈风格',
          sourceTitle: 'KiLLKiSS',
          sourceUrl: 'https://example.com/rich',
          sourceExcerpt: '《KiLLKiSS》拥有强烈的节奏感，保留了Ave Mujica乐队特有的强烈风格',
        ),
        isTrue,
      );
    });

    test(
      'Bandori Wiki direct fetch debug',
      () async {
        final result =
            await WebContextService.bandoriWikiFetchDebugForTest('KiLLKiSS');
        // ignore: avoid_print
        print(result);
        expect(result['status'], '200');
        expect(int.parse(result['cleanLength'] ?? '0'), greaterThan(160));
        expect(result['preview'], contains('Lyrics'));
      },
      skip: !const bool.fromEnvironment('RUN_NETWORK_MUSIC_SOURCE_DEBUG'),
    );

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
