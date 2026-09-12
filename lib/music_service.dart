import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'character_config.dart';
import 'name_pronunciation.dart';
import 'path_service.dart';
import 'storage_service.dart';

class MusicService {
  static const String catalogPath = r'music\music_catalog.json';
  static const String _lyricsQuotationRule = '如果引用歌词，只能引用提供的中文翻译；'
      '跳过歌词里的英文单词、英文短语和英文句子。歌名与专有名词不受此限制。';
  static const Set<String> _localOnlyDiscussionBands = {
    'Ave Mujica',
    'MyGO!!!!!',
  };

  static final Random _random = Random();
  static final Map<String, Future<Uint8List?>> _coverCache = {};

  static bool isMusicShareRequest(
    String userText, {
    Iterable<String> knownSongTitles = const [],
  }) {
    final text = userText.trim();
    if (text.isEmpty) return false;
    final clauses = text
        .split(RegExp(r'[，。！？；,!?;\n]+'))
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty);

    // 播放动作和歌曲对象必须在同一个语义分句内。这可以避免
    // “在放暑假……乐队有什么活动吗”把“放”和“乐队”跨分句拼成点歌。
    return clauses.any(
      (clause) =>
          _clauseHasMusicObject(clause, knownSongTitles) &&
          _clauseHasShareIntent(clause),
    );
  }

  static bool _clauseHasMusicObject(
    String clause,
    Iterable<String> knownSongTitles,
  ) {
    final normalized = _normalizeMusicTitleForMatch(clause);
    final mentionsKnownSong = knownSongTitles.any((title) {
      final normalizedTitle = _normalizeMusicTitleForMatch(title);
      return normalizedTitle.isNotEmpty && normalized.contains(normalizedTitle);
    });
    if (mentionsKnownSong) return true;
    return RegExp(
      r'歌|歌曲|曲子|音乐|バンド|music|song|mygo|mujica|crychic',
      caseSensitive: false,
    ).hasMatch(clause);
  }

  static bool _clauseHasShareIntent(String clause) {
    final hasDirectMusicAction = RegExp(
      r'播放|分享|推荐|听听|放(?:一下|下|一首|首|歌|音乐|曲子)|'
      r'听(?:一下|下|一首|首|歌|歌曲|音乐|曲子)|来(?:一)?首|发(?:一)?首',
      caseSensitive: false,
    ).hasMatch(clause);
    if (!hasDirectMusicAction) return false;

    return RegExp(
      r'请|想|要|能|可以|一起|一块|陪|给我|来|放|播|听|分享|推荐|发|吧|呗|嘛|吗|好不好|好吗',
      caseSensitive: false,
    ).hasMatch(clause);
  }

  static Future<MusicAttachment?> pickAttachmentForRequest({
    required String userText,
    required Character character,
    List<Message> conversationHistory = const [],
  }) async {
    final catalog = await loadCatalog();
    if (catalog.isEmpty) return null;
    if (!isMusicShareRequest(
      userText,
      knownSongTitles: catalog.map((song) => song.title),
    )) {
      return null;
    }

    final preferredBand = _preferredBand(userText, character.id);
    final exactTitle = _titleMentionedInText(userText, catalog);
    if (exactTitle != null) return exactTitle;

    final previouslyShared = _previouslySharedMusicKeys(conversationHistory);
    final bandCandidates = catalog
        .where((item) => _sameBand(item.band, preferredBand))
        .toList(growable: false);
    final recentOrNew = _asksForRecentOrNewSong(userText);
    final candidates = recentOrNew
        ? bandCandidates
            .where((item) => !item.appearedInAnimation)
            .toList(growable: false)
        : bandCandidates;
    if (recentOrNew && candidates.isEmpty) {
      debugPrint(
        '音乐分享筛选：用户询问近期/新歌，但 ${preferredBand.isEmpty ? '当前乐队' : preferredBand} '
        '没有可用的动画外曲目，跳过音乐卡片',
      );
      return null;
    }
    if (candidates.isNotEmpty) {
      if (recentOrNew) {
        debugPrint('音乐分享筛选：已排除动画中出现过的曲目');
      }
      return _pickPreferUnshared(candidates, previouslyShared);
    }

    final fallbackCandidates = recentOrNew
        ? catalog.where((item) => !item.appearedInAnimation).toList()
        : catalog;
    if (fallbackCandidates.isEmpty) return null;
    return _pickPreferUnshared(fallbackCandidates, previouslyShared);
  }

  static bool _asksForRecentOrNewSong(String userText) {
    return RegExp(
      r'(最近|近期|这阵子|这段时间).*(排练|练习|创作|写歌|写曲|准备|录音)|'
      r'(新歌|新曲|新作|刚写的歌|刚创作的歌|下一首歌|接下来.*歌)',
      caseSensitive: false,
    ).hasMatch(userText);
  }

  static Set<String> _previouslySharedMusicKeys(List<Message> history) {
    return history
        .where((message) => message.role == 'assistant')
        .map((message) => message.musicAttachment)
        .whereType<MusicAttachment>()
        .map(_musicIdentity)
        .toSet();
  }

  static MusicAttachment _pickPreferUnshared(
    List<MusicAttachment> candidates,
    Set<String> previouslyShared,
  ) {
    final unshared = candidates
        .where((item) => !previouslyShared.contains(_musicIdentity(item)))
        .toList(growable: false);
    final pool = unshared.isNotEmpty ? unshared : candidates;
    return pool[_random.nextInt(pool.length)];
  }

  static String _musicIdentity(MusicAttachment attachment) {
    final id = attachment.id.trim().toLowerCase();
    if (id.isNotEmpty) return 'id:$id';
    return 'song:${attachment.band.trim().toLowerCase()}|'
        '${_normalizeMusicTitleForMatch(attachment.title)}';
  }

  static Future<List<MusicAttachment>> loadCatalog() async {
    final file = File(AppPaths.resolve(catalogPath));
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MusicAttachment.fromJson)
          .map(_loadLyricsFromPath)
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<Uint8List?> loadCoverBytes(MusicAttachment attachment) {
    final coverPath = attachment.coverPath?.trim() ?? '';
    final audioPath = attachment.localAudioPath?.trim() ?? '';
    final cacheKey = '$coverPath|$audioPath';
    if (cacheKey == '|') return Future.value(null);

    return _coverCache.putIfAbsent(
      cacheKey,
      () => _loadCoverBytes(coverPath: coverPath, audioPath: audioPath),
    );
  }

  static Future<Uint8List?> _loadCoverBytes({
    required String coverPath,
    required String audioPath,
  }) async {
    if (coverPath.isNotEmpty) {
      final coverFile = File(AppPaths.resolve(coverPath));
      if (await coverFile.exists()) return coverFile.readAsBytes();
    }

    if (audioPath.isEmpty) return null;
    final audioFile = File(AppPaths.resolve(audioPath));
    if (!await audioFile.exists()) return null;
    return _readEmbeddedId3Cover(audioFile);
  }

  static Future<Uint8List?> _readEmbeddedId3Cover(File audioFile) async {
    RandomAccessFile? handle;
    try {
      handle = await audioFile.open();
      final header = await handle.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }

      final version = header[3];
      if (version != 3 && version != 4) return null;
      final tagSize = _readSynchsafeInt(header, 6);
      if (tagSize <= 0) return null;

      final tagBody = await handle.read(tagSize);
      final tag = Uint8List(10 + tagBody.length)
        ..setRange(0, 10, header)
        ..setRange(10, 10 + tagBody.length, tagBody);
      return _extractApicImage(tag, version, header[5]);
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  static Uint8List? _extractApicImage(
    Uint8List tag,
    int version,
    int tagFlags,
  ) {
    var offset = 10;
    if ((tagFlags & 0x40) != 0 && offset + 4 <= tag.length) {
      final extendedSize = version == 4
          ? _readSynchsafeInt(tag, offset)
          : _readBigEndianInt(tag, offset);
      offset += version == 4 ? extendedSize : extendedSize + 4;
    }

    while (offset + 10 <= tag.length) {
      final frameId = String.fromCharCodes(tag.sublist(offset, offset + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

      final frameSize = version == 4
          ? _readSynchsafeInt(tag, offset + 4)
          : _readBigEndianInt(tag, offset + 4);
      final payloadStart = offset + 10;
      final payloadEnd = payloadStart + frameSize;
      if (frameSize <= 0 || payloadEnd > tag.length) break;

      if (frameId == 'APIC') {
        var payload = Uint8List.sublistView(tag, payloadStart, payloadEnd);
        if ((tagFlags & 0x80) != 0) {
          payload = _removeId3Unsynchronization(payload);
        }
        final imageStart = _findImageSignature(payload);
        if (imageStart >= 0) {
          return Uint8List.fromList(payload.sublist(imageStart));
        }
      }
      offset = payloadEnd;
    }
    return null;
  }

  static int _findImageSignature(Uint8List bytes) {
    const signatures = <List<int>>[
      [0xFF, 0xD8, 0xFF],
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    ];
    for (var index = 0; index < bytes.length; index++) {
      for (final signature in signatures) {
        if (index + signature.length > bytes.length) continue;
        var matches = true;
        for (var i = 0; i < signature.length; i++) {
          if (bytes[index + i] != signature[i]) {
            matches = false;
            break;
          }
        }
        if (matches) return index;
      }
    }
    return -1;
  }

  static Uint8List _removeId3Unsynchronization(Uint8List bytes) {
    final restored = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      restored.add(bytes[i]);
      if (bytes[i] == 0xFF && i + 1 < bytes.length && bytes[i + 1] == 0x00) {
        i++;
      }
    }
    return Uint8List.fromList(restored);
  }

  static int _readSynchsafeInt(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return ((bytes[offset] & 0x7F) << 21) |
        ((bytes[offset + 1] & 0x7F) << 14) |
        ((bytes[offset + 2] & 0x7F) << 7) |
        (bytes[offset + 3] & 0x7F);
  }

  static int _readBigEndianInt(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static MusicAttachment _loadLyricsFromPath(MusicAttachment attachment) {
    final lyricsPath = attachment.lyricsPath?.trim();
    if (lyricsPath == null || lyricsPath.isEmpty) return attachment;

    final file = File(AppPaths.resolve(lyricsPath));
    if (!file.existsSync()) return attachment;

    final lines = _lyricsLinesFromText(file.readAsStringSync());
    if (lines.isEmpty) return attachment;
    return attachment.copyWithLyrics(lines);
  }

  static List<String> _lyricsLinesFromText(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .toList();

    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }
    if (start >= end) return const [];
    return lines.sublist(start, end);
  }

  static String buildPromptContext(MusicAttachment attachment) {
    final playableNote = _hasPlayableSourceNow(attachment)
        ? '程序会在本条消息后附带这首歌的可播放音乐卡片；你只需要自然推荐，不要解释程序实现。'
        : '程序会在本条消息后附带歌曲卡片；如果本地音频暂未放入，卡片会先显示歌曲信息。';
    final note = attachment.note?.trim();
    final description = attachment.description?.trim();
    final lyrics = _lyricsForChineseResponse(attachment);
    final profileLines = _musicProfileLines(attachment);
    return '''
【本轮音乐分享附件】
你准备分享给用户的歌曲是：
- 歌名：${attachment.title}
- 艺术家/演奏：${attachment.artist}
- 所属乐队：${attachment.band}
${note == null || note.isEmpty ? '' : '- 推荐理由素材：$note'}
${profileLines.isEmpty ? '' : '${profileLines.join('\n')}\n'}
${description == null || description.isEmpty ? '' : '【本地歌曲描述】\n$description\n'}
${lyrics.isEmpty ? '' : '【本地歌词】\n$lyrics\n'}

使用规则：
- 必须自然提到这首歌名，不要另选一首。
- 可以用第一人称角色口吻简短说明为什么此刻想分享它。
- 本地歌曲描述、氛围标签和推荐角度是给你组织推荐语的素材，可以吸收其中的观点，但不要整段照搬。
- 如果提供了本地歌词，可以理解歌词意象并概括使用；不要在回复里大段复述歌词。
- $_lyricsQuotationRule
- 不要提到现实发行、榜单、厂牌、OP/ED、商业活动或播放器实现。
- 不要在回复里列出资料来源链接。
- $playableNote
''';
  }

  static Future<String> buildDiscussionContext({
    required String userText,
    required Character character,
  }) async {
    final catalog = await loadCatalog();
    if (catalog.isEmpty) return '';
    final scope = _discussionScope(
      userText: userText,
      character: character,
      catalog: catalog,
    );
    if (scope == null) return '';

    final scopedItems = scope.items;
    final mentioned = scope.mentioned;

    final symbolTitles = scopedItems
        .where((item) => item.title.toLowerCase().startsWith('symbol '))
        .map((item) => item.title)
        .toList(growable: false);
    final trackTitles =
        scopedItems.map((item) => item.title).toList(growable: false);
    final mentionedProfile =
        mentioned == null ? '' : _discussionSongProfile(mentioned);

    return '''
【本地曲库参考】
本轮用户是在聊音乐，不是请求播放或分享音频；不要发送、暗示已附带或准备附带音乐卡片。
这些信息来自本地 music_catalog.json，用于在网页搜索资料不足时限定曲目名、歌曲描述和可聊范围，防止编造。

${mentionedProfile.isEmpty ? '' : '$mentionedProfile\n'}
${scope.band.isEmpty ? '本地曲库曲目' : '${scope.band} 本地曲库曲目'}：
${trackTitles.map((title) => '- $title').join('\n')}

使用规则：
- 对于本地曲库已覆盖的 Ave Mujica / MyGO!!!!! 普通音乐问题，可以直接使用这里的歌曲描述、氛围标签、听感要点、主题素材和曲目表自然聊天。
- 只能提到本地曲库里存在的歌名；不要编造曲目。
- 如果提到 Symbol 系列，必须写清楚具体是哪一首：${symbolTitles.isEmpty ? '按本地曲库中的完整标题表述。' : symbolTitles.join('、')}。不要只说《Symbol》。
- $_lyricsQuotationRule
- 可以用角色口吻表达“我比较喜欢/我会选”，但这是基于角色化表达和本地曲库素材，不要说成网页明确写过角色本人偏好。
- 不要提现实发行、榜单、厂牌、OP/ED、商业活动、播放器实现或链接。
''';
  }

  static Future<bool> shouldUseLocalOnlyForDiscussion({
    required String userText,
    required Character character,
  }) async {
    final catalog = await loadCatalog();
    if (catalog.isEmpty) return false;
    final scope = _discussionScope(
      userText: userText,
      character: character,
      catalog: catalog,
    );
    return scope?.localOnly == true;
  }

  static Future<Map<String, dynamic>?> buildTranslationLyricsReference({
    required String userText,
    required Character character,
    MusicAttachment? selectedAttachment,
  }) async {
    MusicAttachment? song = selectedAttachment;
    if (song == null) {
      final catalog = await loadCatalog();
      if (catalog.isEmpty) return null;
      song = _discussionScope(
        userText: userText,
        character: character,
        catalog: catalog,
      )?.mentioned;
    }
    if (song == null) return null;
    return _translationLyricsReferenceForAttachment(song);
  }

  static Map<String, dynamic>? _translationLyricsReferenceForAttachment(
    MusicAttachment attachment,
  ) {
    final lines = attachment.lyrics;
    final japaneseMarker = lines.indexOf('【日文原词】');
    final chineseMarker = lines.indexOf('【中文翻译】');
    if (japaneseMarker < 0 || chineseMarker <= japaneseMarker) return null;

    final japaneseLines = lines
        .sublist(japaneseMarker + 1, chineseMarker)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final chineseLines = lines
        .sublist(chineseMarker + 1)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (japaneseLines.length != chineseLines.length) return null;

    final pairs = <Map<String, String>>[];
    for (var index = 0; index < japaneseLines.length; index++) {
      final japanese = japaneseLines[index];
      final chinese = chineseLines[index];
      if (_containsEnglishLyrics(japanese) || _containsEnglishLyrics(chinese)) {
        continue;
      }
      pairs.add({'japanese': japanese, 'chinese': chinese});
    }
    if (pairs.isEmpty) return null;
    return {
      'song_title': attachment.title,
      'lyric_pairs': pairs,
    };
  }

  static bool _containsEnglishLyrics(String line) =>
      RegExp(r'[A-Za-z]').hasMatch(line);

  static _MusicDiscussionScope? _discussionScope({
    required String userText,
    required Character character,
    required List<MusicAttachment> catalog,
  }) {
    if (!_looksLikeMusicDiscussion(userText, catalog)) return null;

    final mentioned = _titleMentionedInText(userText, catalog);
    final explicitBand = _explicitLocalBand(userText);
    final characterBand = _characterDefaultBand(character.id);
    final scopedBand = mentioned?.band ??
        (explicitBand.isNotEmpty
            ? explicitBand
            : (_asksCurrentBandMusic(userText) ? characterBand : ''));
    if (scopedBand.isEmpty) return null;

    final scopedItems = catalog
        .where((item) => _sameBand(item.band, scopedBand))
        .toList(growable: false);
    if (scopedItems.isEmpty) return null;

    final localOnly = mentioned != null
        ? _isLocalOnlyDiscussionBand(mentioned.band)
        : _isLocalOnlyDiscussionBand(scopedBand);
    if (!localOnly) return null;

    return _MusicDiscussionScope(
      band: scopedBand,
      items: scopedItems,
      mentioned: mentioned != null && _sameBand(mentioned.band, scopedBand)
          ? mentioned
          : _titleMentionedInText(userText, scopedItems),
      localOnly: true,
    );
  }

  static bool _looksLikeMusicDiscussion(
    String userText,
    List<MusicAttachment> catalog,
  ) {
    if (isMusicShareRequest(userText)) return false;
    final text = userText.trim().toLowerCase();
    if (text.isEmpty) return false;
    if (_titleMentionedInText(userText, catalog) != null) return true;
    return RegExp(
      r'歌|歌曲|曲子|音乐|乐队|バンド|music|song|mygo|mujica|crychic|哪些歌|哪首',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String _discussionSongProfile(MusicAttachment attachment) {
    final note = attachment.note?.trim();
    final description = attachment.description?.trim();
    final lyrics = _lyricsForChineseResponse(attachment);
    final profileLines = _musicProfileLines(attachment);
    return '''
用户提到的本地歌曲：
- 歌名：${attachment.title}
- 艺术家/演奏：${attachment.artist}
- 所属乐队：${attachment.band}
${note == null || note.isEmpty ? '' : '- 推荐/评价素材：$note'}
${profileLines.isEmpty ? '' : '${profileLines.join('\n')}\n'}${description == null || description.isEmpty ? '' : '本地歌曲描述：$description'}
${lyrics.isEmpty ? '' : '本地歌词：\n$lyrics'}
''';
  }

  static List<String> _musicProfileLines(MusicAttachment attachment) {
    String line(String label, List<String> values) {
      final cleaned = values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (cleaned.isEmpty) return '';
      return '- $label：${cleaned.join('、')}';
    }

    return [
      line('氛围标签', attachment.moods),
      line('听感要点', attachment.sound),
      line('主题素材', attachment.themes),
      line('意象素材', attachment.imagery),
      line('推荐角度', attachment.recommendationAngles),
    ].where((line) => line.isNotEmpty).toList(growable: false);
  }

  static String _lyricsForChineseResponse(MusicAttachment attachment) {
    final lines = attachment.lyrics;
    final japaneseMarker = lines.indexOf('【日文原词】');
    final chineseMarker = lines.indexOf('【中文翻译】');
    if (japaneseMarker < 0 || chineseMarker <= japaneseMarker) {
      return attachment.lyricsText;
    }
    return lines
        .sublist(chineseMarker + 1)
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }

  @visibleForTesting
  static String lyricsForChineseResponseForTest(MusicAttachment attachment) =>
      _lyricsForChineseResponse(attachment);

  static String _preferredBand(String userText, String characterId) {
    final normalized = userText.toLowerCase();
    if (normalized.contains('mygo')) return 'MyGO!!!!!';
    if (normalized.contains('mujica') ||
        normalized.contains('ave mujica') ||
        normalized.contains('avemujica')) {
      return 'Ave Mujica';
    }
    if (normalized.contains('crychic')) return 'CRYCHIC';

    return _characterDefaultBand(characterId);
  }

  static String _explicitLocalBand(String userText) {
    final normalized = userText.toLowerCase();
    if (normalized.contains('mygo')) return 'MyGO!!!!!';
    if (normalized.contains('mujica') ||
        normalized.contains('ave mujica') ||
        normalized.contains('avemujica')) {
      return 'Ave Mujica';
    }
    return '';
  }

  static String _characterDefaultBand(String characterId) {
    switch (characterId) {
      case 'tomori':
        return 'MyGO!!!!!';
      case 'sakiko':
        return 'Ave Mujica';
      default:
        return '';
    }
  }

  static bool _asksCurrentBandMusic(String userText) {
    return RegExp(
      r'你们(乐队|的歌|这首歌|曲子)|你自己.*歌|自己的歌',
      caseSensitive: false,
    ).hasMatch(userText);
  }

  static bool _isLocalOnlyDiscussionBand(String band) {
    return _localOnlyDiscussionBands.any(
      (localBand) => _sameBand(localBand, band),
    );
  }

  static MusicAttachment? _titleMentionedInText(
    String userText,
    List<MusicAttachment> catalog,
  ) {
    final normalized = _normalizeMusicTitleForMatch(userText);
    for (final item in catalog) {
      for (final form in _musicTitleForms(item)) {
        final normalizedForm = _normalizeMusicTitleForMatch(form);
        if (normalizedForm.isNotEmpty && normalized.contains(normalizedForm)) {
          return item;
        }
      }
    }
    return null;
  }

  static Set<String> _musicTitleForms(MusicAttachment item) {
    final forms = <String>{item.title, item.id};
    final normalizedTitle = _normalizeMusicTitleForMatch(item.title);

    for (final entry in termNamePronunciations) {
      final termForms = <String>{
        entry.chinese,
        entry.japanese,
        ...entry.aliases.keys,
      };
      if (!termForms.any(
        (form) => _normalizeMusicTitleForMatch(form) == normalizedTitle,
      )) {
        continue;
      }

      forms.add(entry.chinese);
      forms.add(entry.japanese);
      forms.addAll(entry.romanizedReadingVariants);
      if (!_sameBand(item.title, item.band)) {
        forms.addAll(entry.aliases.keys);
      }
    }

    return forms;
  }

  static String _normalizeMusicTitleForMatch(String value) {
    return value.toLowerCase().replaceAll(
          RegExp(
            r'''[\s　'’‘"“”`:：,，.。!！?？~～_\-/\\()（）\[\]{}【】<>《》]''',
          ),
          '',
        );
  }

  static Future<String?> mentionedCatalogTitleForTest(String userText) async {
    final catalog = await loadCatalog();
    return _titleMentionedInText(userText, catalog)?.title;
  }

  static bool _sameBand(String left, String right) {
    if (right.isEmpty) return true;
    return left.toLowerCase().replaceAll('!', '') ==
        right.toLowerCase().replaceAll('!', '');
  }

  static bool _hasPlayableSourceNow(MusicAttachment attachment) {
    final previewUrl = attachment.previewUrl?.trim();
    if (previewUrl != null && previewUrl.isNotEmpty) return true;

    final localPath = attachment.localAudioPath?.trim();
    if (localPath == null || localPath.isEmpty) return false;
    return File(AppPaths.resolve(localPath)).existsSync();
  }
}

class _MusicDiscussionScope {
  final String band;
  final List<MusicAttachment> items;
  final MusicAttachment? mentioned;
  final bool localOnly;

  const _MusicDiscussionScope({
    required this.band,
    required this.items,
    required this.mentioned,
    required this.localOnly,
  });
}
