class CharacterNamePronunciation {
  final String chinese;
  final String japanese;
  final String reading;
  final List<String> chineseAliases;
  // Nicknames/forms used by the user to refer to this person. They are only
  // identity hints: do not rewrite the user's text, drive TTS, or change how
  // the speaking character addresses this person.
  final List<String> userMentionAliases;
  // Extra identity forms mapped to their TTS reading. Latin/code-name aliases
  // keep their display form during translation; CJK variants can still map to
  // the canonical Japanese spelling.
  final Map<String, String> aliases;
  // Search-only aliases that point to this character, but must not change
  // translation, Chinese normalization, or TTS display.
  final List<String> searchAliases;

  const CharacterNamePronunciation({
    required this.chinese,
    required this.japanese,
    required this.reading,
    this.chineseAliases = const [],
    this.userMentionAliases = const [],
    this.aliases = const {},
    this.searchAliases = const [],
  });

  String get compactJapanese => japanese.replaceAll(RegExp(r'[\s　]+'), '');
}

class TermNamePronunciation {
  final String chinese;
  final String japanese;
  final String reading;
  final Map<String, String> aliases;

  const TermNamePronunciation({
    required this.chinese,
    required this.japanese,
    required this.reading,
    this.aliases = const {},
  });

  String get compactJapanese => japanese.replaceAll(RegExp(r'[\s　]+'), '');

  String get romanizedReading {
    return _titleCaseRomaji(_romanizeJapaneseText(reading));
  }

  Set<String> get romanizedReadingVariants {
    final titleCase = romanizedReading.trim();
    if (titleCase.isEmpty) return const {};
    final lowerCase = titleCase.toLowerCase();
    final compactLowerCase = lowerCase.replaceAll(RegExp(r'\s+'), '');
    return {
      titleCase,
      lowerCase,
      compactLowerCase,
    };
  }
}

String _romanizeJapaneseText(String text) {
  if (text.trim().isEmpty) return '';

  final normalized = text.replaceAllMapped(RegExp(r'[ァ-ヶ]'), (match) {
    final char = match.group(0)!;
    if (char == 'ヶ') return 'け';
    return String.fromCharCode(char.codeUnitAt(0) - 0x60);
  }).replaceAll('ヴ', 'ゔ');

  const digraphs = {
    'きゃ': 'kya',
    'きゅ': 'kyu',
    'きょ': 'kyo',
    'ぎゃ': 'gya',
    'ぎゅ': 'gyu',
    'ぎょ': 'gyo',
    'しゃ': 'sha',
    'しゅ': 'shu',
    'しょ': 'sho',
    'じゃ': 'ja',
    'じゅ': 'ju',
    'じょ': 'jo',
    'ちゃ': 'cha',
    'ちゅ': 'chu',
    'ちょ': 'cho',
    'にゃ': 'nya',
    'にゅ': 'nyu',
    'にょ': 'nyo',
    'ひゃ': 'hya',
    'ひゅ': 'hyu',
    'ひょ': 'hyo',
    'みゃ': 'mya',
    'みゅ': 'myu',
    'みょ': 'myo',
    'りゃ': 'rya',
    'りゅ': 'ryu',
    'りょ': 'ryo',
    'びゃ': 'bya',
    'びゅ': 'byu',
    'びょ': 'byo',
    'ぴゃ': 'pya',
    'ぴゅ': 'pyu',
    'ぴょ': 'pyo',
    'ゔぁ': 'va',
    'ゔぃ': 'vi',
    'ゔぇ': 've',
    'ゔぉ': 'vo',
    'ゔゅ': 'vyu',
    'てぃ': 'ti',
    'でぃ': 'di',
    'とぅ': 'tu',
    'どぅ': 'du',
    'しぇ': 'she',
    'じぇ': 'je',
    'ちぇ': 'che',
    'つぁ': 'tsa',
    'つぃ': 'tsi',
    'つぇ': 'tse',
    'つぉ': 'tso',
    'ふぁ': 'fa',
    'ふぃ': 'fi',
    'ふぇ': 'fe',
    'ふぉ': 'fo',
    'うぃ': 'wi',
    'うぇ': 'we',
    'うぉ': 'wo',
  };

  const syllables = {
    'あ': 'a',
    'い': 'i',
    'う': 'u',
    'え': 'e',
    'お': 'o',
    'か': 'ka',
    'き': 'ki',
    'く': 'ku',
    'け': 'ke',
    'こ': 'ko',
    'さ': 'sa',
    'し': 'shi',
    'す': 'su',
    'せ': 'se',
    'そ': 'so',
    'た': 'ta',
    'ち': 'chi',
    'つ': 'tsu',
    'て': 'te',
    'と': 'to',
    'な': 'na',
    'に': 'ni',
    'ぬ': 'nu',
    'ね': 'ne',
    'の': 'no',
    'は': 'ha',
    'ひ': 'hi',
    'ふ': 'fu',
    'へ': 'he',
    'ほ': 'ho',
    'ま': 'ma',
    'み': 'mi',
    'む': 'mu',
    'め': 'me',
    'も': 'mo',
    'や': 'ya',
    'ゆ': 'yu',
    'よ': 'yo',
    'ら': 'ra',
    'り': 'ri',
    'る': 'ru',
    'れ': 're',
    'ろ': 'ro',
    'わ': 'wa',
    'ゐ': 'wi',
    'ゑ': 'we',
    'を': 'o',
    'ん': 'n',
    'が': 'ga',
    'ぎ': 'gi',
    'ぐ': 'gu',
    'げ': 'ge',
    'ご': 'go',
    'ざ': 'za',
    'じ': 'ji',
    'ず': 'zu',
    'ぜ': 'ze',
    'ぞ': 'zo',
    'だ': 'da',
    'ぢ': 'ji',
    'づ': 'zu',
    'で': 'de',
    'ど': 'do',
    'ば': 'ba',
    'び': 'bi',
    'ぶ': 'bu',
    'べ': 'be',
    'ぼ': 'bo',
    'ぱ': 'pa',
    'ぴ': 'pi',
    'ぷ': 'pu',
    'ぺ': 'pe',
    'ぽ': 'po',
    'ゔ': 'vu',
    'ぁ': 'a',
    'ぃ': 'i',
    'ぅ': 'u',
    'ぇ': 'e',
    'ぉ': 'o',
  };

  final buffer = StringBuffer();
  var doubleNext = false;
  var index = 0;
  while (index < normalized.length) {
    final char = normalized[index];
    if (char == ' ' || char == '\u3000') {
      buffer.write(' ');
      doubleNext = false;
      index += 1;
      continue;
    }
    if (char == 'っ') {
      doubleNext = true;
      index += 1;
      continue;
    }
    if (char == 'ー') {
      final lastVowel = _lastRomajiVowel(buffer.toString());
      if (lastVowel.isNotEmpty) buffer.write(lastVowel);
      index += 1;
      continue;
    }

    String romaji = '';
    if (index + 1 < normalized.length) {
      final pair = normalized.substring(index, index + 2);
      romaji = digraphs[pair] ?? '';
      if (romaji.isNotEmpty) {
        index += 2;
      }
    }
    if (romaji.isEmpty) {
      romaji = syllables[char] ?? char;
      index += 1;
    }

    if (doubleNext && romaji.isNotEmpty) {
      final lead = romaji[0];
      if (RegExp(r'[bcdfghjklmnpqrstvwxyz]', caseSensitive: false)
          .hasMatch(lead)) {
        romaji = '$lead$romaji';
      }
      doubleNext = false;
    }
    buffer.write(romaji);
  }

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _lastRomajiVowel(String text) {
  for (var i = text.length - 1; i >= 0; i--) {
    final char = text[i].toLowerCase();
    if ('aeiou'.contains(char)) return char;
    if (char == ' ') break;
  }
  return '';
}

String _titleCaseRomaji(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  return normalized.split(' ').map((token) {
    if (token.isEmpty) return token;
    final lower = token.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

const List<CharacterNamePronunciation> characterNamePronunciations = [
  CharacterNamePronunciation(
    chinese: '灶门 炭治郎',
    japanese: '竈門 炭治郎',
    reading: 'かまど たんじろう',
  ),
  CharacterNamePronunciation(
    chinese: '灶门 祢豆子',
    japanese: '竈門 禰豆子',
    reading: 'かまど ねずこ',
  ),
  CharacterNamePronunciation(
    chinese: '我妻 善逸',
    japanese: '我妻 善逸',
    reading: 'あがつま ぜんいつ',
  ),
  CharacterNamePronunciation(
    chinese: '嘴平 伊之助',
    japanese: '嘴平 伊之助',
    reading: 'はしびら いのすけ',
  ),
  CharacterNamePronunciation(
    chinese: '栗花落 香奈乎',
    japanese: '栗花落 カナヲ',
    reading: 'つゆり カナヲ',
  ),
  CharacterNamePronunciation(
    chinese: '富冈 义勇',
    japanese: '冨岡 義勇',
    reading: 'とみおか ぎゆう',
    searchAliases: ['水柱'],
  ),
  CharacterNamePronunciation(
    chinese: '蝴蝶 忍',
    japanese: '胡蝶 しのぶ',
    reading: 'こちょう しのぶ',
    searchAliases: ['虫柱', '蟲柱'],
  ),
  CharacterNamePronunciation(
    chinese: '悲鸣屿 行冥',
    japanese: '悲鳴嶼 行冥',
    reading: 'ひめじま ぎょうめい',
    searchAliases: ['岩柱'],
  ),
  CharacterNamePronunciation(
    chinese: '不死川 实弥',
    japanese: '不死川 実弥',
    reading: 'しなずがわ さねみ',
    searchAliases: ['风柱', '風柱'],
  ),
  CharacterNamePronunciation(
    chinese: '伊黑 小芭内',
    japanese: '伊黒 小芭内',
    reading: 'いぐろ おばない',
    searchAliases: ['蛇柱'],
  ),
  CharacterNamePronunciation(
    chinese: '甘露寺 蜜璃',
    japanese: '甘露寺 蜜璃',
    reading: 'かんろじ みつり',
    searchAliases: ['恋柱'],
  ),
  CharacterNamePronunciation(
    chinese: '宇髄 天元',
    japanese: '宇髄 天元',
    reading: 'うずい てんげん',
    searchAliases: ['音柱'],
  ),
  CharacterNamePronunciation(
    chinese: '炼狱 杏寿郎',
    japanese: '煉獄 杏寿郎',
    reading: 'れんごく きょうじゅろう',
    searchAliases: ['炎柱'],
  ),
  CharacterNamePronunciation(
    chinese: '时透 无一郎',
    japanese: '時透 無一郎',
    reading: 'ときとう むいちろう',
    searchAliases: ['霞柱'],
  ),
  CharacterNamePronunciation(
    chinese: '不死川 玄弥',
    japanese: '不死川 玄弥',
    reading: 'しなずがわ げんや',
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷 耀哉',
    japanese: '産屋敷 耀哉',
    reading: 'うぶやしき かがや',
    searchAliases: ['主公', '主公大人', 'お館様'],
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷 天音',
    japanese: '産屋敷 あまね',
    reading: 'うぶやしき あまね',
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷 辉利哉',
    japanese: '産屋敷 輝利哉',
    reading: 'うぶやしき きりや',
  ),
  CharacterNamePronunciation(
    chinese: '鬼舞辻 无惨',
    japanese: '鬼舞辻 無惨',
    reading: 'きぶつじ むざん',
  ),
  CharacterNamePronunciation(
    chinese: '童磨',
    japanese: '童磨',
    reading: 'どうま',
  ),
  CharacterNamePronunciation(
    chinese: '猗窝座',
    japanese: '猗窩座',
    reading: 'あかざ',
  ),
  CharacterNamePronunciation(
    chinese: '黑死牟',
    japanese: '黒死牟',
    reading: 'こくしぼう',
  ),
  CharacterNamePronunciation(
    chinese: '半天狗',
    japanese: 'はんてんぐ',
    reading: 'はんてんぐ',
  ),
  CharacterNamePronunciation(
    chinese: '玉壶',
    japanese: 'ぎょっこ',
    reading: 'ぎょっこ',
    aliases: {'玉壺': 'ぎょっこ'},
  ),
  CharacterNamePronunciation(
    chinese: '狯岳',
    japanese: '獪岳',
    reading: 'かいがく',
  ),
  CharacterNamePronunciation(
    chinese: '堕姬',
    japanese: '堕姫',
    reading: 'だき',
  ),
  CharacterNamePronunciation(
    chinese: '妓夫太郎',
    japanese: '妓夫太郎',
    reading: 'ぎゅうたろう',
  ),
  CharacterNamePronunciation(
    chinese: '累',
    japanese: '累',
    reading: 'るい',
  ),
  CharacterNamePronunciation(
    chinese: '珠世',
    japanese: '珠世',
    reading: 'たまよ',
  ),
  CharacterNamePronunciation(
    chinese: '愈史郎',
    japanese: '愈史郎',
    reading: 'ゆしろう',
  ),
  CharacterNamePronunciation(
    chinese: '蝴蝶 香奈惠',
    japanese: '胡蝶 カナエ',
    reading: 'こちょう かなえ',
    searchAliases: ['花柱'],
  ),
  CharacterNamePronunciation(
    chinese: '神崎 葵',
    japanese: '神崎 アオイ',
    reading: 'かんざき あおい',
  ),
  CharacterNamePronunciation(
    chinese: '寺内 清',
    japanese: '寺内 きよ',
    reading: 'てらうち きよ',
  ),
  CharacterNamePronunciation(
    chinese: '中原 澄',
    japanese: '中原 すみ',
    reading: 'なかはら すみ',
  ),
  CharacterNamePronunciation(
    chinese: '高田 奈穗',
    japanese: '高田 なほ',
    reading: 'たかだ なほ',
    chineseAliases: ['高田 奈穂'],
  ),
  CharacterNamePronunciation(
    chinese: '锖兔',
    japanese: '錆兎',
    reading: 'さびと',
  ),
  CharacterNamePronunciation(
    chinese: '鳞泷 左近次',
    japanese: '鱗滝 左近次',
    reading: 'うろこだき さこんじ',
  ),
  CharacterNamePronunciation(
    chinese: '啾太郎',
    japanese: 'チュン太郎',
    reading: 'チュンたろう',
  ),
  CharacterNamePronunciation(
    chinese: '银子',
    japanese: '銀子',
    reading: 'ぎんこ',
  ),
  CharacterNamePronunciation(
    chinese: '丰川 祥子',
    japanese: '豊川 祥子',
    reading: 'とがわ さきこ',
    userMentionAliases: ['saki', 'sakiko', '祥祥', '小祥'],
    aliases: {'Oblivionis': 'オブリビオニス'},
  ),
  CharacterNamePronunciation(
    chinese: '若叶 睦',
    japanese: '若葉 睦',
    reading: 'わかば むつみ',
    userMentionAliases: ['mutsumi', 'mtm', '睦子米', '木子米', '小睦'],
    aliases: {'Mortis': 'モーティス'},
  ),
  CharacterNamePronunciation(
    chinese: '三角 初音',
    japanese: '三角 初音',
    userMentionAliases: ['uika', 'hatsune'],
    reading: 'みすみ はつね',
  ),
  CharacterNamePronunciation(
    chinese: '三角 初华',
    japanese: '三角 初華',
    reading: 'みすみ ういか',
    userMentionAliases: ['uika', 'hatsune'],
    aliases: {'Doloris': 'ドロリス'},
  ),
  CharacterNamePronunciation(
    chinese: '八幡 海铃',
    japanese: '八幡 海鈴',
    reading: 'やはた うみり',
    userMentionAliases: ['umiri', 'umr', '乌咪铃', '乌米铃'],
    aliases: {'Timoris': 'ティモリス'},
  ),
  CharacterNamePronunciation(
    chinese: '祐天寺 若麦',
    japanese: '祐天寺 にゃむ',
    reading: 'ゆうてんじ にゃむ',
    userMentionAliases: ['nyamu', 'nym', '喵梦', '喵姆', '大喵', '大喵老师', '大猫'],
    aliases: {'Amoris': 'アモーリス'},
  ),
  CharacterNamePronunciation(
    chinese: '高松 灯',
    japanese: '高松 燈',
    reading: 'たかまつ ともり',
    userMentionAliases: ['tomori', 'tomorin', 'tmr', '灯灯', '小灯'],
  ),
  CharacterNamePronunciation(
    chinese: '千早 爱音',
    japanese: '千早 愛音',
    reading: 'ちはや あのん',
    userMentionAliases: ['anon'],
  ),
  CharacterNamePronunciation(
    chinese: '长崎 爽世',
    japanese: '長崎 そよ',
    reading: 'ながさき そよ',
    userMentionAliases: ['soyo', 'soyorin', '长崎素世', '素世', '爽世世', '素世世'],
  ),
  CharacterNamePronunciation(
    chinese: '椎名 立希',
    japanese: '椎名 立希',
    reading: 'しいな たき',
    userMentionAliases: ['taki'],
  ),
  CharacterNamePronunciation(
    chinese: '要 乐奈',
    japanese: '要 楽奈',
    reading: 'かなめ らーな',
    userMentionAliases: ['rana'],
  ),
  CharacterNamePronunciation(
    chinese: '纯田 真奈',
    japanese: '純田 まな',
    reading: 'すみた まな',
    userMentionAliases: ['mana', '甜甜圈女士'],
  ),
  CharacterNamePronunciation(
    chinese: '户山 香澄',
    japanese: '戸山 香澄',
    reading: 'とやま かすみ',
  ),
  CharacterNamePronunciation(
    chinese: '花园 多惠',
    japanese: '花園 たえ',
    reading: 'はなぞの たえ',
  ),
  CharacterNamePronunciation(
    chinese: '牛込 里美',
    japanese: '牛込 りみ',
    reading: 'うしごめ りみ',
  ),
  CharacterNamePronunciation(
    chinese: '山吹沙绫',
    japanese: '山吹 沙綾',
    reading: 'やまぶき さや',
  ),
  CharacterNamePronunciation(
    chinese: '市谷 有咲',
    japanese: '市ヶ谷 有咲',
    reading: 'いちがや ありさ',
  ),
  CharacterNamePronunciation(
    chinese: '凑 友希那',
    japanese: '湊 友希那',
    reading: 'みなと ゆきな',
  ),
  CharacterNamePronunciation(
    chinese: '冰川 纱夜',
    japanese: '氷川 紗夜',
    reading: 'ひかわ さよ',
  ),
  CharacterNamePronunciation(
    chinese: '今井 莉莎',
    japanese: '今井 リサ',
    reading: 'いまい りさ',
  ),
  CharacterNamePronunciation(
    chinese: '宇田川 亚子',
    japanese: '宇田川 あこ',
    reading: 'うだがわ あこ',
  ),
  CharacterNamePronunciation(
    chinese: '白金 燐子',
    japanese: '白金 燐子',
    reading: 'しろかね りんこ',
  ),
  CharacterNamePronunciation(
    chinese: '美竹 兰',
    japanese: '美竹 蘭',
    reading: 'みたけ らん',
  ),
  CharacterNamePronunciation(
    chinese: '青叶 摩卡',
    japanese: '青葉 モカ',
    reading: 'あおば もか',
  ),
  CharacterNamePronunciation(
    chinese: '宇田川 巴',
    japanese: '宇田川 巴',
    reading: 'うだがわ ともえ',
  ),
  CharacterNamePronunciation(
    chinese: '上原 绯玛丽',
    japanese: '上原 ひまり',
    reading: 'うえはら ひまり',
  ),
  CharacterNamePronunciation(
    chinese: '羽泽 鸫',
    japanese: '羽沢 つぐみ',
    reading: 'はざわ つぐみ',
  ),
  CharacterNamePronunciation(
    chinese: '丸山 彩',
    japanese: '丸山 彩',
    reading: 'まるやま あや',
  ),
  CharacterNamePronunciation(
    chinese: '白鹭 千圣',
    japanese: '白鷺 千聖',
    reading: 'しらさぎ ちさと',
  ),
  CharacterNamePronunciation(
    chinese: '冰川 日菜',
    japanese: '氷川 日菜',
    reading: 'ひかわ ひな',
  ),
  CharacterNamePronunciation(
    chinese: '大和 麻弥',
    japanese: '大和 麻弥',
    reading: 'やまと まや',
  ),
  CharacterNamePronunciation(
    chinese: '若宫 伊芙',
    japanese: '若宮 イヴ',
    reading: 'わかみや いぶ',
  ),
  CharacterNamePronunciation(
    chinese: '弦卷 心',
    japanese: '弦巻 こころ',
    reading: 'つるまき こころ',
  ),
  CharacterNamePronunciation(
    chinese: '濑田 薰',
    japanese: '瀬田 薫',
    reading: 'せた かおる',
  ),
  CharacterNamePronunciation(
    chinese: '北泽 育美',
    japanese: '北沢 はぐみ',
    reading: 'きたざわ はぐみ',
  ),
  CharacterNamePronunciation(
    chinese: '松原 花音',
    japanese: '松原 花音',
    reading: 'まつばら かのん',
  ),
  CharacterNamePronunciation(
    chinese: '奥泽 美咲',
    japanese: '奥沢 美咲',
    reading: 'おくさわ みさき',
  ),
  CharacterNamePronunciation(
    chinese: '米歇尔',
    japanese: 'ミッシェル',
    reading: 'ミッシェル',
  ),
  CharacterNamePronunciation(
    chinese: '和奏 瑞依',
    japanese: '和奏 レイ',
    reading: 'わかな れい',
    aliases: {'LAYER': 'れいや'},
  ),
  CharacterNamePronunciation(
    chinese: '鳰原 令王那',
    japanese: '鳰原 令王那',
    reading: 'にゅうばら れおな',
    aliases: {'PAREO': 'ぱれお'},
  ),
  CharacterNamePronunciation(
    chinese: '朝日 六花',
    japanese: '朝日 六花',
    reading: 'あさひ ろっか',
    aliases: {'LOCK': 'ろっく'},
  ),
  CharacterNamePronunciation(
    chinese: '佐藤 益木',
    japanese: '佐藤 益木',
    reading: 'さとう ますき',
    aliases: {'MASKING': 'ますきんぐ'},
  ),
  CharacterNamePronunciation(
    chinese: '珠手 知由',
    japanese: '珠手 知由',
    reading: 'たまで ちゆ',
    aliases: {'CHU²': 'ちゅちゅ'},
  ),
  CharacterNamePronunciation(
    chinese: '仓田 真白',
    japanese: '倉田 ましろ',
    reading: 'くらた ましろ',
  ),
  CharacterNamePronunciation(
    chinese: '二叶 筑紫',
    japanese: '二葉 つくし',
    reading: 'ふたば つくし',
  ),
  CharacterNamePronunciation(
    chinese: '桐谷 透子',
    japanese: '桐ヶ谷 透子',
    reading: 'きりがや とうこ',
  ),
  CharacterNamePronunciation(
    chinese: '广町 七深',
    japanese: '広町 七深',
    reading: 'ひろまち ななみ',
  ),
  CharacterNamePronunciation(
    chinese: '八潮 瑠唯',
    japanese: '八潮 瑠唯',
    reading: 'やしお るい',
  ),
  CharacterNamePronunciation(
    chinese: '月岛 麻里奈',
    japanese: '月島 まりな',
    reading: 'つきしま まりな',
  ),
];

const List<TermNamePronunciation> termNamePronunciations = [
  TermNamePronunciation(
    chinese: '主公大人',
    japanese: 'お館様',
    reading: 'おやかたさま',
  ),
  TermNamePronunciation(
    chinese: '蝶屋',
    japanese: '蝶屋敷',
    reading: 'ちょうやしき',
  ),
  TermNamePronunciation(
    chinese: '锻刀村',
    japanese: '刀鍛冶の里',
    reading: 'かたなかじのさと',
  ),
  TermNamePronunciation(
    chinese: '鬼杀队',
    japanese: '鬼殺隊',
    reading: 'きさつたい',
  ),
  TermNamePronunciation(
    chinese: '无限城',
    japanese: '無限城',
    reading: 'むげんじょう',
  ),
  TermNamePronunciation(
    chinese: '蜘蛛山',
    japanese: '蜘蛛山',
    reading: 'なだくもやま',
  ),
  TermNamePronunciation(
    chinese: '游郭',
    japanese: '遊郭',
    reading: 'ゆうかく',
  ),
  TermNamePronunciation(
    chinese: '十二鬼月',
    japanese: '十二鬼月',
    reading: 'じゅうにきづき',
  ),
  TermNamePronunciation(
    chinese: '上弦之鬼',
    japanese: '上弦の鬼',
    reading: 'じょうげんのおに',
    aliases: {'上弦的鬼': 'じょうげんのおに'},
  ),
  TermNamePronunciation(
    chinese: '下弦之鬼',
    japanese: '下弦の鬼',
    reading: 'かげんのおに',
    aliases: {'下弦的鬼': 'かげんのおに'},
  ),
  TermNamePronunciation(
    chinese: '藤花',
    japanese: '藤の花',
    reading: 'ふじのはな',
    aliases: {'藤之花': 'ふじのはな'},
  ),
  TermNamePronunciation(
    chinese: '虫柱',
    japanese: '蟲柱',
    reading: 'むしばしら',
  ),
  TermNamePronunciation(
    chinese: '花柱',
    japanese: '花柱',
    reading: 'はなばしら',
  ),
  TermNamePronunciation(
    chinese: '水柱',
    japanese: '水柱',
    reading: 'みずばしら',
  ),
  TermNamePronunciation(
    chinese: '音柱',
    japanese: '音柱',
    reading: 'おとばしら',
  ),
  TermNamePronunciation(
    chinese: '霞柱',
    japanese: '霞柱',
    reading: 'かすみばしら',
  ),
  TermNamePronunciation(
    chinese: '岩柱',
    japanese: '岩柱',
    reading: 'いわばしら',
  ),
  TermNamePronunciation(
    chinese: '恋柱',
    japanese: '恋柱',
    reading: 'こいばしら',
  ),
  TermNamePronunciation(
    chinese: '蛇柱',
    japanese: '蛇柱',
    reading: 'へびばしら',
  ),
  TermNamePronunciation(
    chinese: '风柱',
    japanese: '風柱',
    reading: 'かぜばしら',
  ),
  TermNamePronunciation(
    chinese: '炎柱',
    japanese: '炎柱',
    reading: 'ほのおばしら',
  ),
  TermNamePronunciation(
    chinese: '日轮刀',
    japanese: '日輪刀',
    reading: 'にちりんとう',
  ),
  TermNamePronunciation(
    chinese: 'CRYCHIC',
    japanese: 'CRYCHIC',
    reading: 'クライシック',
  ),
  TermNamePronunciation(
    chinese: 'BanG Dream',
    japanese: 'BanG Dream',
    reading: 'ばんどり',
  ),
  TermNamePronunciation(
    chinese: 'Poppin Party',
    japanese: 'Poppin Party',
    reading: 'ぽっぴんぱーてぃー',
  ),
  TermNamePronunciation(
    chinese: 'Popipa',
    japanese: 'Popipa',
    reading: 'ぽぴぱ',
  ),
  TermNamePronunciation(
    chinese: 'Roselia',
    japanese: 'Roselia',
    reading: 'ろぜりあ',
  ),
  TermNamePronunciation(
    chinese: 'Afterglow',
    japanese: 'Afterglow',
    reading: 'あふたーぐろう',
  ),
  TermNamePronunciation(
    chinese: 'Pastel*Palettes',
    japanese: 'Pastel*Palettes',
    reading: 'ぱすてるぱれっと',
  ),
  TermNamePronunciation(
    chinese: 'PasPale',
    japanese: 'PasPale',
    reading: 'ぱすぱれ',
  ),
  TermNamePronunciation(
    chinese: 'Hello, Happy World!',
    japanese: 'Hello, Happy World!',
    reading: 'はろーはっぴーわーるど',
  ),
  TermNamePronunciation(
    chinese: 'RAISE A SUILEN',
    japanese: 'RAISE A SUILEN',
    reading: 'れいずあすいれん',
  ),
  TermNamePronunciation(
    chinese: 'RAS',
    japanese: 'RAS',
    reading: 'らす',
  ),
  TermNamePronunciation(
    chinese: 'Morfonica',
    japanese: 'Morfonica',
    reading: 'もるふぉにか',
  ),
  TermNamePronunciation(
    chinese: 'Monica',
    japanese: 'Monica',
    reading: 'もにか',
  ),
  TermNamePronunciation(
    chinese: '羽丘',
    japanese: '羽丘',
    reading: 'はねおか',
  ),
  TermNamePronunciation(
    chinese: '花咲川',
    japanese: '花咲川',
    reading: 'はなさきがわ',
  ),
  TermNamePronunciation(
    chinese: '月之森',
    japanese: '月ノ森',
    reading: 'つきのもり',
  ),
  TermNamePronunciation(
    chinese: 'CiRCLE',
    japanese: 'CiRCLE',
    reading: 'さーくる',
  ),
  TermNamePronunciation(
    chinese: 'RiNG',
    japanese: 'RiNG',
    reading: 'りんー',
  ),
  TermNamePronunciation(
    chinese: 'Galaxy',
    japanese: 'Galaxy',
    reading: 'ぎゃらくしー',
  ),
  TermNamePronunciation(
    chinese: 'dub',
    japanese: 'dub',
    reading: 'だぶ',
  ),
  TermNamePronunciation(
    chinese: 'SPACE',
    japanese: 'SPACE',
    reading: 'すぺーす',
  ),
  TermNamePronunciation(
    chinese: 'MyGO',
    japanese: 'MyGO',
    reading: 'まいご',
    aliases: {'MyGO!!!!!': 'まいご'},
  ),
  TermNamePronunciation(
    chinese: '春日影',
    japanese: '春日影',
    reading: 'はるひかげ',
  ),
  TermNamePronunciation(
    chinese: '迷星叫',
    japanese: '迷星叫',
    reading: 'まよいうた',
  ),
  TermNamePronunciation(
    chinese: '名无声',
    japanese: '名無声',
    reading: 'なもなき',
  ),
  TermNamePronunciation(
    chinese: '音一会',
    japanese: '音一会',
    reading: 'おといちえ',
  ),
  TermNamePronunciation(
    chinese: '潜在表明',
    japanese: '潜在表明',
    reading: 'せんざいひょうめい',
  ),
  TermNamePronunciation(
    chinese: '影色舞',
    japanese: '影色舞',
    reading: 'しるえっとだんす',
  ),
  TermNamePronunciation(
    chinese: '壱雫空',
    japanese: '壱雫空',
    reading: 'ひとしずく',
  ),
  TermNamePronunciation(
    chinese: '栞',
    japanese: '栞',
    reading: 'しおり',
  ),
  TermNamePronunciation(
    chinese: '焚音打',
    japanese: '焚音打',
    reading: 'たねび',
  ),
  TermNamePronunciation(
    chinese: '碧天伴走',
    japanese: '碧天伴走',
    reading: 'へきてんばんそう',
  ),
  TermNamePronunciation(
    chinese: '一同歌唱一同奏响',
    japanese: '歌いましょう鳴らしましょう',
    reading: 'うたいましょうならしましょう',
  ),
  TermNamePronunciation(
    chinese: '诗超绊',
    japanese: '詩超絆',
    reading: 'うたことば',
  ),
  TermNamePronunciation(
    chinese: '迷路的日子',
    japanese: '迷路日々',
    reading: 'めろでぃ',
  ),
  TermNamePronunciation(
    chinese: '无路矢',
    japanese: '無路矢',
    reading: 'のろし',
  ),
  TermNamePronunciation(
    chinese: '砂寸奏',
    japanese: '砂寸奏',
    reading: 'さすらい',
  ),
  TermNamePronunciation(
    chinese: '回层浮',
    japanese: '回層浮',
    reading: 'かいそう',
  ),
  TermNamePronunciation(
    chinese: '处救生',
    japanese: '処救生',
    reading: 'こきゅう',
  ),
  TermNamePronunciation(
    chinese: '端程山',
    japanese: '端程山',
    reading: 'ぱのらま',
  ),
  TermNamePronunciation(
    chinese: '轮符雨',
    japanese: '輪符雨',
    reading: 'りふれいん',
  ),
  TermNamePronunciation(
    chinese: '孤坏牢',
    japanese: '孤壊牢',
    reading: 'こころ',
  ),
  TermNamePronunciation(
    chinese: '步拾道',
    japanese: '歩拾道',
    reading: 'すぴーど',
  ),
  TermNamePronunciation(
    chinese: '明弦音',
    japanese: '明弦音',
    reading: 'あげいん',
  ),
  TermNamePronunciation(
    chinese: '雾周途',
    japanese: '霧周途',
    reading: 'みすと',
  ),
  TermNamePronunciation(
    chinese: '夜隐染',
    japanese: '夜隠染',
    reading: 'よかぜ',
  ),
  TermNamePronunciation(
    chinese: '过惰幻',
    japanese: '過惰幻',
    reading: 'あだゆめ',
  ),
  TermNamePronunciation(
    chinese: '聿日笺秋',
    japanese: '聿日箋秋',
    reading: 'いちじつせんしゅう',
  ),
  TermNamePronunciation(
    chinese: '掌心正铭',
    japanese: '掌心正銘',
    reading: 'しょうしんしょうめい',
  ),
  TermNamePronunciation(
    chinese: '往栏印',
    japanese: '往欄印',
    reading: 'おうらい',
  ),
  TermNamePronunciation(
    chinese: '残痕字',
    japanese: '残痕字',
    reading: 'ぺーじ',
  ),
  TermNamePronunciation(
    chinese: '静降想',
    japanese: '静降想',
    reading: 'さいれんと',
  ),
  TermNamePronunciation(
    chinese: '描绘未来',
    japanese: 'エガクミライ',
    reading: 'えがくみらい',
  ),
  TermNamePronunciation(
    chinese: '罗永线',
    japanese: '羅永線',
    reading: 'らいん',
  ),
  TermNamePronunciation(
    chinese: '证命赞歌',
    japanese: '証命讃歌',
    reading: 'しょうめいさんか',
    aliases: {'証命讚歌': 'しょうめいさんか'},
  ),
  TermNamePronunciation(
    chinese: '素寄曲',
    japanese: '素寄曲',
    reading: 'すきま',
  ),
  TermNamePronunciation(
    chinese: '骚混出',
    japanese: '騒混出',
    reading: 'さんでい',
  ),
  TermNamePronunciation(
    chinese: '猛独侵袭',
    japanese: '猛独が襲う',
    reading: 'もうどくがおそう',
  ),
  TermNamePronunciation(
    chinese: 'Ave Mujica',
    japanese: 'Ave Mujica',
    reading: 'アヴェムジカ',
    aliases: {'Mujica': 'ムジカ'},
  ),
  TermNamePronunciation(
    chinese: '黑色生日',
    japanese: '黒のバースデイ',
    reading: 'くろのバースデイ',
    aliases: {'Kuro no Birthday': 'くろのバースデイ'},
  ),
  TermNamePronunciation(
    chinese: '双月 ~Deep Into The Forest~',
    japanese: 'ふたつの月 ~Deep Into The Forest~',
    reading: 'ふたつのつき ディープ イントゥ ザ フォレスト',
    aliases: {
      'Futatsu no Tsuki ~Deep Into The Forest~': 'ふたつのつき ディープ イントゥ ザ フォレスト',
    },
  ),
  TermNamePronunciation(
    chinese: "Choir 'S' Choir",
    japanese: "Choir 'S' Choir",
    reading: 'クワイアーズ クワイア',
    aliases: {'Choir ‘S’ Choir': 'クワイアーズ クワイア'},
  ),
  TermNamePronunciation(
    chinese: '神明，笨蛋',
    japanese: '神さま、バカ',
    reading: 'かみさま、バカ',
    aliases: {'Kamisama, Baka': 'かみさま、バカ'},
  ),
  TermNamePronunciation(
    chinese: 'Mas?uerade Rhapsody Re?uest',
    japanese: 'Mas?uerade Rhapsody Re?uest',
    reading: 'マスカレード ラプソディー リクエスト',
    aliases: {
      'Mas?uerade Rhapsody Re?uest': 'マスカレード ラプソディー リクエスト',
      'Masquerade Rhapsody Request': 'マスカレード ラプソディー リクエスト',
    },
  ),
  TermNamePronunciation(
    chinese: '在美好的世界里 也找不到的地方',
    japanese: '素晴らしき世界 でも どこにもない場所',
    reading: 'すばらしきせかい でも どこにもないばしょ',
    aliases: {
      'Subarashiki Sekai demo Dokonimonai Basho': 'すばらしきせかい でも どこにもないばしょ',
    },
  ),
  TermNamePronunciation(
    chinese: 'Angles',
    japanese: 'Angles',
    reading: 'アングルズ',
  ),
  TermNamePronunciation(
    chinese: 'ELEMENTS',
    japanese: 'ELEMENTS',
    reading: 'エレメンツ',
  ),
  TermNamePronunciation(
    chinese: 'Symbol I : 🜂',
    japanese: 'Symbol I : 🜂',
    reading: 'シンボル ワン ファイア',
    aliases: {
      'Symbol I: 🜂': 'シンボル ワン ファイア',
      'Symbol I : △': 'シンボル ワン ファイア',
      'Symbol I: △': 'シンボル ワン ファイア',
    },
  ),
  TermNamePronunciation(
    chinese: 'Symbol II : Air',
    japanese: 'Symbol II : Air',
    reading: 'シンボル ツー エア',
    aliases: {
      'Symbol II: 🜁': 'シンボル ツー エア',
      'Symbol II : 🜁': 'シンボル ツー エア',
      'Symbol II: Air': 'シンボル ツー エア',
    },
  ),
  TermNamePronunciation(
    chinese: 'Symbol III : 🜄',
    japanese: 'Symbol III : 🜄',
    reading: 'シンボル スリー ウォーター',
    aliases: {
      'Symbol III: 🜄': 'シンボル スリー ウォーター',
      'Symbol III : ▽': 'シンボル スリー ウォーター',
      'Symbol III: ▽': 'シンボル スリー ウォーター',
    },
  ),
  TermNamePronunciation(
    chinese: 'Symbol IV : Earth',
    japanese: 'Symbol IV : Earth',
    reading: 'シンボル フォー アース',
    aliases: {
      'Symbol IV: 🜃': 'シンボル フォー アース',
      'Symbol IV : 🜃': 'シンボル フォー アース',
      'Symbol IV: Earth': 'シンボル フォー アース',
    },
  ),
  TermNamePronunciation(
    chinese: 'Ether',
    japanese: 'Ether',
    reading: 'エーテル',
  ),
  TermNamePronunciation(
    chinese: 'KiLLKiSS',
    japanese: 'KiLLKiSS',
    reading: 'キルキス',
    aliases: {'KILLKISS': 'キルキス'},
  ),
  TermNamePronunciation(
    chinese: 'Georgette Me, Georgette You',
    japanese: 'Georgette Me, Georgette You',
    reading: 'ジョーゼット ミー、ジョーゼット ユー',
  ),
  TermNamePronunciation(
    chinese: 'Imprisoned XII',
    japanese: 'Imprisoned XII',
    reading: 'インプリズンド トゥエルブ',
  ),
  TermNamePronunciation(
    chinese: 'Crucifix X',
    japanese: 'Crucifix X',
    reading: 'クルシフィックス キス',
  ),
  TermNamePronunciation(
    chinese: '八芒星之舞',
    japanese: '八芒星ダンス',
    reading: 'はちぼうせいダンス',
    aliases: {'Hachibousei Dance': 'はちぼうせいダンス'},
  ),
  TermNamePronunciation(
    chinese: '颜',
    japanese: '顔',
    reading: 'かお',
  ),
  TermNamePronunciation(
    chinese: '天球的Música',
    japanese: '天球のMúsica',
    reading: 'そらのムジカ',
    aliases: {
      'Sora no Música': 'そらのムジカ',
      'Sora no Musica': 'そらのムジカ',
      '天球のMusica': 'そらのムジカ',
      '天球(そら)のMúsica': 'そらのムジカ',
      '天球(そら)のMusica': 'そらのムジカ',
    },
  ),
  TermNamePronunciation(
    chinese: "'S/' The Way",
    japanese: "'S/' The Way",
    reading: 'スラッシュ ザ ウェイ',
    aliases: {'‘S/’ The Way': 'スラッシュ ザ ウェイ'},
  ),
  TermNamePronunciation(
    chinese: 'Sophie',
    japanese: 'Sophie',
    reading: 'ソフィー',
  ),
  TermNamePronunciation(
    chinese: 'The Whole Blue World',
    japanese: 'The Whole Blue World',
    reading: 'ザ ホール ブルー ワールド',
  ),
  TermNamePronunciation(
    chinese: 'DIVINE',
    japanese: 'DIVINE',
    reading: 'ディヴァイン',
  ),
  TermNamePronunciation(
    chinese: '碧蓝眼瞳之中',
    japanese: '碧い瞳の中に',
    reading: 'あおいひとみのなかに',
    aliases: {'Aoi Hitomi no Naka ni': 'あおいひとみのなかに'},
  ),
];

const List<String> canonTermNamesForSearch = [
  '主公大人',
  '蝶屋',
  '锻刀村',
];

final Map<String, String> termPronunciationDictionary = {
  for (final entry in termNamePronunciations) ...{
    entry.japanese: entry.reading,
    entry.chinese: entry.reading,
    for (final variant in entry.romanizedReadingVariants)
      variant: entry.reading,
    ...entry.aliases,
  },
};

final Map<String, String> characterPronunciationDictionary = {
  for (final entry in characterNamePronunciations) ...{
    entry.japanese: entry.reading,
    entry.chinese: entry.reading,
    ...entry.aliases,
  },
};

final Map<String, String> namePronunciationDictionary = {
  for (final entry in characterNamePronunciations) ...{
    entry.japanese: entry.reading,
    ...entry.aliases,
  },
  ...termPronunciationDictionary,
};

final Map<String, CharacterNamePronunciation> characterNameByJapaneseForm =
    _buildUniqueJapaneseIdentityIndex();

final Map<String, CharacterNamePronunciation> characterNameByChineseForm = {
  for (final entry in characterNamePronunciations) ...{
    entry.chinese: entry,
    entry.chinese.replaceAll(RegExp(r'[\s　]+'), ''): entry,
    for (final alias in entry.chineseAliases) alias: entry,
    for (final alias in entry.chineseAliases)
      alias.replaceAll(RegExp(r'[\s　]+'), ''): entry,
  },
};

Map<String, CharacterNamePronunciation> _buildUniqueJapaneseIdentityIndex() {
  final owners = <String, Set<CharacterNamePronunciation>>{};

  void add(String value, CharacterNamePronunciation entry) {
    final key = value.replaceAll(RegExp(r'[\s　]+'), '').trim();
    if (key.isEmpty) return;
    owners.putIfAbsent(key, () => <CharacterNamePronunciation>{}).add(entry);
  }

  for (final entry in characterNamePronunciations) {
    add(entry.japanese, entry);
    add(entry.reading, entry);
    for (final part in entry.japanese.split(RegExp(r'[\s　]+'))) {
      add(part, entry);
    }
    for (final part in entry.reading.split(RegExp(r'[\s　]+'))) {
      add(part, entry);
    }
    for (final alias in entry.aliases.keys) {
      add(alias, entry);
    }
  }

  return {
    for (final entry in owners.entries)
      if (entry.value.length == 1) entry.key: entry.value.single,
  };
}
