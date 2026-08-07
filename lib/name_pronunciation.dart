class CharacterNamePronunciation {
  final String chinese;
  final String japanese;
  final String reading;
  final List<String> chineseAliases;
  final Map<String, String> aliases;

  const CharacterNamePronunciation({
    required this.chinese,
    required this.japanese,
    required this.reading,
    this.chineseAliases = const [],
    this.aliases = const {},
  });

  String get compactJapanese => japanese.replaceAll(RegExp(r'[\s　]+'), '');
}

const List<CharacterNamePronunciation> characterNamePronunciations = [
  CharacterNamePronunciation(
    chinese: '灶门炭治郎',
    japanese: '竈門 炭治郎',
    reading: 'かまど たんじろう',
  ),
  CharacterNamePronunciation(
    chinese: '灶门祢豆子',
    japanese: '竈門 禰豆子',
    reading: 'かまど ねずこ',
  ),
  CharacterNamePronunciation(
    chinese: '我妻善逸',
    japanese: '我妻 善逸',
    reading: 'あがつま ぜんいつ',
  ),
  CharacterNamePronunciation(
    chinese: '嘴平伊之助',
    japanese: '嘴平 伊之助',
    reading: 'はしびら いのすけ',
  ),
  CharacterNamePronunciation(
    chinese: '栗花落香奈乎',
    japanese: '栗花落 カナヲ',
    reading: 'つゆり カナヲ',
  ),
  CharacterNamePronunciation(
    chinese: '富冈义勇',
    japanese: '冨岡 義勇',
    reading: 'とみおか ぎゆう',
  ),
  CharacterNamePronunciation(
    chinese: '蝴蝶忍',
    japanese: '胡蝶 しのぶ',
    reading: 'こちょう しのぶ',
  ),
  CharacterNamePronunciation(
    chinese: '悲鸣屿行冥',
    japanese: '悲鳴嶼 行冥',
    reading: 'ひめじま ぎょうめい',
  ),
  CharacterNamePronunciation(
    chinese: '不死川实弥',
    japanese: '不死川 実弥',
    reading: 'しなずがわ さねみ',
  ),
  CharacterNamePronunciation(
    chinese: '伊黑小芭内',
    japanese: '伊黒 小芭内',
    reading: 'いぐろ おばない',
  ),
  CharacterNamePronunciation(
    chinese: '甘露寺蜜璃',
    japanese: '甘露寺 蜜璃',
    reading: 'かんろじ みつり',
  ),
  CharacterNamePronunciation(
    chinese: '宇髄天元',
    japanese: '宇髄 天元',
    reading: 'うずい てんげん',
  ),
  CharacterNamePronunciation(
    chinese: '炼狱杏寿郎',
    japanese: '煉獄 杏寿郎',
    reading: 'れんごく きょうじゅろう',
  ),
  CharacterNamePronunciation(
    chinese: '时透无一郎',
    japanese: '時透 無一郎',
    reading: 'ときとう むいちろう',
  ),
  CharacterNamePronunciation(
    chinese: '不死川玄弥',
    japanese: '不死川 玄弥',
    reading: 'しなずがわ げんや',
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷耀哉',
    japanese: '産屋敷 耀哉',
    reading: 'うぶやしき かがや',
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷天音',
    japanese: '産屋敷 あまね',
    reading: 'うぶやしき あまね',
  ),
  CharacterNamePronunciation(
    chinese: '产屋敷辉利哉',
    japanese: '産屋敷 輝利哉',
    reading: 'うぶやしき きりや',
  ),
  CharacterNamePronunciation(
    chinese: '鬼舞辻无惨',
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
    chinese: '蝴蝶香奈惠',
    japanese: '胡蝶 カナエ',
    reading: 'こちょう かなえ',
  ),
  CharacterNamePronunciation(
    chinese: '神崎葵',
    japanese: '神崎 アオイ',
    reading: 'かんざき あおい',
  ),
  CharacterNamePronunciation(
    chinese: '寺内清',
    japanese: '寺内 きよ',
    reading: 'てらうち きよ',
  ),
  CharacterNamePronunciation(
    chinese: '中原澄',
    japanese: '中原 すみ',
    reading: 'なかはら すみ',
  ),
  CharacterNamePronunciation(
    chinese: '高田奈穗',
    japanese: '高田 なほ',
    reading: 'たかだ なほ',
    chineseAliases: ['高田奈穂'],
  ),
  CharacterNamePronunciation(
    chinese: '锖兔',
    japanese: '錆兎',
    reading: 'さびと',
  ),
  CharacterNamePronunciation(
    chinese: '鳞泷左近次',
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
    chinese: '丰川祥子',
    japanese: '豊川 祥子',
    reading: 'とがわ さきこ',
    aliases: {'Oblivionis': 'オブリビオニス'},
  ),
  CharacterNamePronunciation(
    chinese: '若叶睦',
    japanese: '若葉 睦',
    reading: 'わかば むつみ',
    aliases: {'Mortis': 'モーティス'},
  ),
  CharacterNamePronunciation(
    chinese: '三角初音',
    japanese: '三角 初音',
    reading: 'みすみ はつね',
  ),
  CharacterNamePronunciation(
    chinese: '三角初华',
    japanese: '三角 初華',
    reading: 'みすみ ういか',
    aliases: {'Doloris': 'ドロリス'},
  ),
  CharacterNamePronunciation(
    chinese: '八幡海铃',
    japanese: '八幡 海鈴',
    reading: 'やはた うみり',
    aliases: {'Timoris': 'ティモリス'},
  ),
  CharacterNamePronunciation(
    chinese: '祐天寺若麦',
    japanese: '祐天寺 にゃむ',
    reading: 'ゆうてんじ にゃむ',
    aliases: {'Amoris': 'アモーリス'},
  ),
  CharacterNamePronunciation(
    chinese: '高松灯',
    japanese: '高松 燈',
    reading: 'たかまつ ともり',
  ),
  CharacterNamePronunciation(
    chinese: '千早爱音',
    japanese: '千早 愛音',
    reading: 'ちはや あのん',
  ),
  CharacterNamePronunciation(
    chinese: '长崎爽世',
    japanese: '長崎 そよ',
    reading: 'ながさき そよ',
  ),
  CharacterNamePronunciation(
    chinese: '椎名立希',
    japanese: '椎名 立希',
    reading: 'しいな たき',
  ),
  CharacterNamePronunciation(
    chinese: '要乐奈',
    japanese: '要 楽奈',
    reading: 'かなめ らーな',
  ),
  CharacterNamePronunciation(
    chinese: '纯田真奈',
    japanese: '純田 まな',
    reading: 'すみた まな',
  ),
  CharacterNamePronunciation(
    chinese: '户山香澄',
    japanese: '戸山 香澄',
    reading: 'とやま かすみ',
  ),
  CharacterNamePronunciation(
    chinese: '花园多惠',
    japanese: '花園 たえ',
    reading: 'はなぞの たえ',
  ),
  CharacterNamePronunciation(
    chinese: '牛込里美',
    japanese: '牛込 りみ',
    reading: 'うしごめ りみ',
  ),
  CharacterNamePronunciation(
    chinese: '山吹沙绫',
    japanese: '山吹 沙綾',
    reading: 'やまぶき さや',
  ),
  CharacterNamePronunciation(
    chinese: '市谷有咲',
    japanese: '市ヶ谷 有咲',
    reading: 'いちがや ありさ',
  ),
  CharacterNamePronunciation(
    chinese: '凑友希那',
    japanese: '湊 友希那',
    reading: 'みなと ゆきな',
  ),
  CharacterNamePronunciation(
    chinese: '冰川纱夜',
    japanese: '氷川 紗夜',
    reading: 'ひかわ さよ',
  ),
  CharacterNamePronunciation(
    chinese: '今井莉莎',
    japanese: '今井 リサ',
    reading: 'いまい りさ',
  ),
  CharacterNamePronunciation(
    chinese: '宇田川亚子',
    japanese: '宇田川 あこ',
    reading: 'うだがわ あこ',
  ),
  CharacterNamePronunciation(
    chinese: '白金燐子',
    japanese: '白金 燐子',
    reading: 'しろかね りんこ',
  ),
  CharacterNamePronunciation(
    chinese: '美竹兰',
    japanese: '美竹 蘭',
    reading: 'みたけ らん',
  ),
  CharacterNamePronunciation(
    chinese: '青叶摩卡',
    japanese: '青葉 モカ',
    reading: 'あおば もか',
  ),
  CharacterNamePronunciation(
    chinese: '宇田川巴',
    japanese: '宇田川 巴',
    reading: 'うだがわ ともえ',
  ),
  CharacterNamePronunciation(
    chinese: '上原绯玛丽',
    japanese: '上原 ひまり',
    reading: 'うえはら ひまり',
  ),
  CharacterNamePronunciation(
    chinese: '羽泽鸫',
    japanese: '羽沢 つぐみ',
    reading: 'はざわ つぐみ',
  ),
  CharacterNamePronunciation(
    chinese: '丸山彩',
    japanese: '丸山 彩',
    reading: 'まるやま あや',
  ),
  CharacterNamePronunciation(
    chinese: '白鹭千圣',
    japanese: '白鷺 千聖',
    reading: 'しらさぎ ちさと',
  ),
  CharacterNamePronunciation(
    chinese: '冰川日菜',
    japanese: '氷川 日菜',
    reading: 'ひかわ ひな',
  ),
  CharacterNamePronunciation(
    chinese: '大和麻弥',
    japanese: '大和 麻弥',
    reading: 'やまと まや',
  ),
  CharacterNamePronunciation(
    chinese: '若宫伊芙',
    japanese: '若宮 イヴ',
    reading: 'わかみや いぶ',
  ),
  CharacterNamePronunciation(
    chinese: '弦卷心',
    japanese: '弦巻 こころ',
    reading: 'つるまき こころ',
  ),
  CharacterNamePronunciation(
    chinese: '濑田薰',
    japanese: '瀬田 薫',
    reading: 'せた かおる',
  ),
  CharacterNamePronunciation(
    chinese: '北泽育美',
    japanese: '北沢 はぐみ',
    reading: 'きたざわ はぐみ',
  ),
  CharacterNamePronunciation(
    chinese: '松原花音',
    japanese: '松原 花音',
    reading: 'まつばら かのん',
  ),
  CharacterNamePronunciation(
    chinese: '奥泽美咲',
    japanese: '奥沢 美咲',
    reading: 'おくさわ みさき',
  ),
  CharacterNamePronunciation(
    chinese: '和奏瑞依',
    japanese: '和奏 レイ',
    reading: 'わかな れい',
    aliases: {'LAYER': 'れいや'},
  ),
  CharacterNamePronunciation(
    chinese: '鳰原令王那',
    japanese: '鳰原 令王那',
    reading: 'にゅうばら れおな',
    aliases: {'PAREO': 'ぱれお'},
  ),
  CharacterNamePronunciation(
    chinese: '朝日六花',
    japanese: '朝日 六花',
    reading: 'あさひ ろっか',
    aliases: {'LOCK': 'ろっく'},
  ),
  CharacterNamePronunciation(
    chinese: '佐藤益木',
    japanese: '佐藤 益木',
    reading: 'さとう ますき',
    aliases: {'MASKING': 'ますきんぐ'},
  ),
  CharacterNamePronunciation(
    chinese: '珠手知由',
    japanese: '珠手 知由',
    reading: 'たまで ちゆ',
    aliases: {'CHU²': 'ちゅちゅ'},
  ),
  CharacterNamePronunciation(
    chinese: '仓田真白',
    japanese: '倉田 ましろ',
    reading: 'くらた ましろ',
  ),
  CharacterNamePronunciation(
    chinese: '二叶筑紫',
    japanese: '二葉 つくし',
    reading: 'ふたば つくし',
  ),
  CharacterNamePronunciation(
    chinese: '桐谷透子',
    japanese: '桐ヶ谷 透子',
    reading: 'きりがや とうこ',
  ),
  CharacterNamePronunciation(
    chinese: '广町七深',
    japanese: '広町 七深',
    reading: 'ひろまち ななみ',
  ),
  CharacterNamePronunciation(
    chinese: '八潮瑠唯',
    japanese: '八潮 瑠唯',
    reading: 'やしお るい',
  ),
  CharacterNamePronunciation(
    chinese: '月岛麻里奈',
    japanese: '月島 まりな',
    reading: 'つきしま まりな',
  ),
];

const Map<String, String> termPronunciationDictionary = {
  'お館様': 'おやかたさま',
  '鬼殺隊': 'きさつたい',
  '無限城': 'むげんじょう',
  '蜘蛛山': 'なだくもやま',
  '刀鍛冶の里': 'かたなかじのさと',
  '遊郭': 'ゆうかく',
  '十二鬼月': 'じゅうにきづき',
  '上弦の鬼': 'じょうげんのおに',
  '下弦の鬼': 'かげんのおに',
  '藤の花': 'ふじのはな',
  '蟲柱': 'むしばしら',
  '花柱': 'はなばしら',
  '水柱': 'みずばしら',
  '音柱': 'おとばしら',
  '霞柱': 'かすみばしら',
  '岩柱': 'いわばしら',
  '恋柱': 'こいばしら',
  '蛇柱': 'へびばしら',
  '風柱': 'かぜばしら',
  '炎柱': 'ほのおばしら',
  '日輪刀': 'にちりんとう',
  'MyGO': 'まいご',
  'MyGO!!!!!': 'まいご',
  'Ave Mujica': 'あべむじか',
  'CRYCHIC': 'クライシック',
  'BanG Dream': 'ばんどり',
  'Poppin Party': 'ぽっぴんぱーてぃー',
  'Popipa': 'ぽぴぱ',
  'Roselia': 'ろぜりあ',
  'Afterglow': 'あふたーぐろう',
  'Pastel*Palettes': 'ぱすてるぱれっと',
  'PasPale': 'ぱすぱれ',
  'Hello, Happy World!': 'はろーはっぴーわーるど',
  'RAISE A SUILEN': 'れいずあすいれん',
  'RAS': 'らす',
  'Morfonica': 'もるふぉにか',
  'Monica': 'もにか',
  '羽丘': 'はねおか',
  '花咲川': 'はなさきがわ',
  '月ノ森': 'つきのもり',
  'CiRCLE': 'さーくる',
  'RiNG': 'りんー',
  'Galaxy': 'ぎゃらくしー',
  'dub': 'だぶ',
  'SPACE': 'すぺーす',
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
    for (final alias in entry.chineseAliases) alias: entry,
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
