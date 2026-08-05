import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';
import 'api_keys.dart';
import 'path_service.dart';

class ApiService {
  static const String doubaoApiKey = ApiKeys.deepseekApiKey;

  static const String doubaoModel = 'deepseek-v4-flash';

  static const String doubaoBaseUrl = 'https://api.deepseek.com/v1';

  // ========================================
  // 豆包视觉模型配置
  // ========================================
  static const String doubaoVisionBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  static const String doubaoVisionEndpoint = 'ep-20260213104644-59ljp';
  static const String doubaoVisionApiKey = ApiKeys.doubaoVisionKey;

  static const String gptSovitsBaseUrl = 'http://127.0.0.1:9880';

  // ========================================
  // 中译日校验与重试参数（可调）
  // ========================================
  // _maxTranslationRetries：翻译失败时最多重试几次。
  //   网络抖动、API 偶发返回奇怪格式（如返回中文、返回空、返回带 markdown 的内容）时，
  //   会自动再调用一次翻译 API。次数过多会拖慢响应速度，建议 2~4 之间。
  // _japaneseFallbackText：所有重试都失败后兜底用的日语句子。
  //   存在的意义是：宁可让 AI 随便说一句日语兜底，也绝不能把中文塞给 TTS（GPT-SoVITS）
  //   导致语音乱掉、字幕也是中文。如果想换文案，改这里即可，但必须是纯日语。
  static const int _maxTranslationRetries = 3;
  static const String _japaneseFallbackText = 'ごめん、ちょっと言葉が出てこなかった…もう一度話してくれる？';

  static const List<_NameEntry> _nameEntries = [
    _NameEntry(japanese: 'カナヲ', chinese: '香奈乎'),
    _NameEntry(japanese: 'しのぶ', chinese: '忍'),
    _NameEntry(japanese: 'かなえ', chinese: '香奈惠'),
    _NameEntry(japanese: 'お館様', chinese: '主公大人'),
    _NameEntry(japanese: '産屋敷あまね', chinese: '产屋敷天音'),
    _NameEntry(japanese: 'はんてんぐ', chinese: '半天狗'),
    _NameEntry(japanese: 'ぎょっこ', chinese: '玉壶', japaneseAliases: ['玉壺']),
    _NameEntry(japanese: '神崎アオイ', chinese: '神崎葵'),
    _NameEntry(japanese: '寺内きよ', chinese: '寺内清'),
    _NameEntry(japanese: '中原すみ', chinese: '中原澄'),
    _NameEntry(japanese: '高田なほ', chinese: '高田奈穗', chineseAliases: ['高田奈穂']),
    _NameEntry(japanese: 'きよ', chinese: '清'),
    _NameEntry(japanese: 'すみ', chinese: '澄'),
    _NameEntry(japanese: 'なほ', chinese: '奈穗', chineseAliases: ['奈穂']),
    _NameEntry(japanese: '蝶屋敷', chinese: '蝶屋'),
    _NameEntry(japanese: '刀鍛冶の里', chinese: '锻刀村'),
    _NameEntry(japanese: 'チュン太郎', chinese: '啾太郎'),
    _NameEntry(japanese: '長崎そよ', chinese: '长崎爽世'),
    _NameEntry(japanese: '祐天寺にゃむ', chinese: '祐天寺若麦'),
    _NameEntry(japanese: '要楽奈', chinese: '要乐奈'),
    _NameEntry(japanese: '純田まな', chinese: '纯田真奈'),
    _NameEntry(japanese: 'あのちゃん', chinese: '爱音酱'),
    _NameEntry(japanese: '祥ちゃん', chinese: '小祥'),
    _NameEntry(japanese: '睦ちゃん', chinese: '小睦'),
    _NameEntry(japanese: 'そよりん', chinese: '爽世世'),
    _NameEntry(japanese: 'ともりん', chinese: '灯灯'),
    _NameEntry(japanese: 'にゃむち', chinese: '喵梦亲'),
    _NameEntry(japanese: '花園たえ', chinese: '花园多惠'),
    _NameEntry(japanese: '牛込りみ', chinese: '牛込里美'),
    _NameEntry(japanese: '市ヶ谷有咲', chinese: '市谷有咲'),
    _NameEntry(japanese: '今井リサ', chinese: '今井莉莎'),
    _NameEntry(japanese: '宇田川あこ', chinese: '宇田川亚子'),
    _NameEntry(japanese: '青葉モカ', chinese: '青叶摩卡'),
    _NameEntry(japanese: '上原ひまり', chinese: '上原绯玛丽'),
    _NameEntry(japanese: '若宮イヴ', chinese: '若宫伊芙'),
    _NameEntry(japanese: '弦巻こころ', chinese: '弦卷心'),
    _NameEntry(japanese: '北沢はぐみ', chinese: '北泽育美'),
    _NameEntry(japanese: 'ミッシェル', chinese: '米歇尔'),
    _NameEntry(japanese: '和奏レイ', chinese: '和奏瑞依'),
    _NameEntry(japanese: '倉田ましろ', chinese: '仓田真白'),
    _NameEntry(japanese: '二葉つくし', chinese: '二叶筑紫'),
    _NameEntry(japanese: '桐ヶ谷透子', chinese: '桐谷透子'),
    _NameEntry(japanese: '月島まりな', chinese: '月岛麻里奈'),
  ];

  static const Map<String, Map<String, String>> _fixedCharacterCallNameMap = {
    'sakiko': {
      '高松灯': '燈',
      '长崎爽世': 'そよ',
      '若叶睦': '睦',
      '三角初音': '初音',
      '八幡海铃': '海鈴',
      '祐天寺若麦': 'にゃむ',
      '千早爱音': '愛音さん',
      '椎名立希': '立希',
      '要乐奈': '楽奈さん',
      '纯田真奈': 'まなさん',
    },
    'tomori': {
      '丰川祥子': '祥ちゃん',
      '长崎爽世': 'そよちゃん',
      '千早爱音': 'あのちゃん',
      '椎名立希': '立希ちゃん',
      '要乐奈': '楽奈ちゃん',
      '若叶睦': '睦ちゃん',
      '三角初华': '初華ちゃん',
      '三角初音': '初華ちゃん',
    },
    'shinobu': {
      '栗花落香奈乎': 'カナヲ',
      '灶门炭治郎': '炭治郎くん',
      '灶门祢豆子': '禰豆子さん',
      '我妻善逸': '善逸くん',
      '嘴平伊之助': '伊之助くん',
      '富冈义勇': '冨岡さん',
      '悲鸣屿行冥': '悲鳴嶼さん',
      '不死川实弥': '不死川さん',
      '伊黑小芭内': '伊黒さん',
      '甘露寺蜜璃': '甘露寺さん',
      '宇髄天元': '宇髄さん',
      '炼狱杏寿郎': '煉獄さん',
      '时透无一郎': '時透さん',
    },
    'muichirou': {
      '灶门炭治郎': '炭治郎',
      '灶门祢豆子': '禰豆子',
      '我妻善逸': '善逸',
      '嘴平伊之助': '伊之助',
      '富冈义勇': '冨岡さん',
      '蝴蝶忍': '胡蝶さん',
      '悲鸣屿行冥': '悲鳴嶼さん',
      '不死川实弥': '不死川さん',
      '伊黑小芭内': '伊黒さん',
      '甘露寺蜜璃': '甘露寺さん',
      '宇髄天元': '宇髄さん',
      '炼狱杏寿郎': '煉獄さん',
    },
    'giyu': {
      '灶门炭治郎': '炭治郎',
      '灶门祢豆子': '禰豆子',
      '我妻善逸': '善逸',
      '嘴平伊之助': '伊之助',
      '蝴蝶忍': '胡蝶',
      '悲鸣屿行冥': '悲鳴嶼',
      '不死川实弥': '不死川',
      '伊黑小芭内': '伊黒',
      '甘露寺蜜璃': '甘露寺',
      '宇髄天元': '宇髄',
      '炼狱杏寿郎': '煉獄',
      '时透无一郎': '時透',
    },
  };

  static List<String> canonicalChineseNamesForSearch({String? characterId}) {
    final names = <String>[];
    void add(String value) {
      final name = value.trim();
      if (name.length < 2 || names.contains(name)) return;
      names.add(name);
    }

    final currentCallNames =
        characterId == null ? null : _fixedCharacterCallNameMap[characterId];
    currentCallNames?.keys.forEach(add);
    for (final map in _fixedCharacterCallNameMap.values) {
      map.keys.forEach(add);
    }
    for (final entry in _nameEntries) {
      add(entry.chinese);
      for (final alias in entry.chineseAliases) {
        add(alias);
      }
    }

    return names;
  }

  static Map<String, String> fixedCharacterCallNamesForCharacter(
    String? characterId,
  ) {
    final configured =
        characterId == null ? null : _fixedCharacterCallNameMap[characterId];
    if (configured == null) return const {};
    return Map.unmodifiable(configured);
  }

  static Map<String, String> fixedCharacterCallNameChineseTargets(
    String? characterId,
  ) {
    final configured =
        characterId == null ? null : _fixedCharacterCallNameMap[characterId];
    if (configured == null) return const {};
    return Map.unmodifiable({
      for (final entry in configured.entries)
        entry.key: _callNameChineseTarget(entry.key, entry.value),
    });
  }

  static List<String> nameTranslationGlossaryForPrompt() {
    final lines = <String>[];
    for (final entry in _nameEntries) {
      void add(String source) {
        final trimmed = source.trim();
        if (trimmed.isEmpty) return;
        final line = '$trimmed=${entry.chinese}';
        if (!lines.contains(line)) lines.add(line);
      }

      add(entry.japanese);
      for (final alias in entry.japaneseAliases) {
        add(alias);
      }
      for (final alias in entry.chineseAliases) {
        add(alias);
      }
    }
    return lines;
  }

  static String normalizeKnownNamesForChineseText(String text) {
    var result = text;
    for (final entry in _nameEntries) {
      for (final source in [
        entry.japanese,
        ...entry.japaneseAliases,
        ...entry.chineseAliases,
      ]) {
        if (source.isEmpty || source == entry.chinese) continue;
        result = result.replaceAll(source, entry.chinese);
      }
    }
    return result;
  }

  static String _genderHintsForTranslationPrompt(String? webContext) {
    if (webContext == null || webContext.trim().isEmpty) return '';
    final hints = <String, String>{};
    final pattern = RegExp(
      r'([一-龥ぁ-ゖァ-ヺA-Za-z0-9・·ー々ヶヵ]{1,30})[（(](男|女)[）)]',
    );

    for (final match in pattern.allMatches(webContext)) {
      var name = (match.group(1) ?? '').trim();
      final gender = match.group(2);
      if (name.isEmpty || gender == null) continue;

      final pieces = name
          .split(RegExp(r'(?:分别为|包括|以及|还有|其中|名为|叫做|是|为|和|与|及|、|，|,|：|:|\s)+'))
          .where((piece) => piece.trim().isNotEmpty)
          .toList();
      if (pieces.isNotEmpty) name = pieces.last.trim();
      if (name.isEmpty || name.length > 12) continue;
      hints.putIfAbsent(name, () => gender == '女' ? '女性' : '男性');
      if (hints.length >= 30) break;
    }

    if (hints.isEmpty) return '';
    final lines = hints.entries.map((entry) => '- ${entry.key}：${entry.value}');
    return '【人物性别参考】以下信息来自联网事实中的性别标注，只用于翻译第三人称代词和“たち/みんな/三人”等指代；不要把性别括号翻译进正文。\n'
        '${lines.join('\n')}\n';
  }

  // 生成对话回复
  // characterLanguage: 'ja' = 日语角色（默认），'zh' = 中文角色
  // 中文角色：AI 直接以中文回复，跳过日语校验与翻译步骤，
  //           返回 {'japanese': '', 'chinese': <中文回复>}
  // 日语角色：保持原有流程，返回 {'japanese': <日文>, 'chinese': <中文翻译>}
  static Future<Map<String, String>> generateResponse({
    required String characterPersonality,
    required List<Message> conversationHistory,
    required String userMessage,
    String? timeContext,
    String? webContext,
    String? proactiveInstruction,
    List<String>? imagePaths,
    String? characterId,
    String characterLanguage = 'ja',
  }) async {
    try {
      String imageContext = '';
      if (imagePaths != null && imagePaths.isNotEmpty) {
        final descriptions = <String>[];
        for (int i = 0; i < imagePaths.length; i++) {
          debugPrint('调用视觉模型：图片 ${i + 1}/${imagePaths.length}');
          final desc = await _describeImage(imagePaths[i]);
          if (desc.isNotEmpty) {
            descriptions.add(imagePaths.length > 1 ? '图片${i + 1}：$desc' : desc);
          }
        }
        if (descriptions.isNotEmpty) {
          imageContext = '\n\n【图片内容】${descriptions.join('\n')}';
          debugPrint('视觉模型描述: $imageContext');
        }
      }

      final isEmotionSupportTurn = _isEmotionSupportUserMessage(userMessage);
      final isRelationshipArcTurn = _isRelationshipArcQuestion(userMessage);
      final isEventProcessTurn = _isEventProcessQuestion(userMessage);

      final StringBuffer systemBuffer = StringBuffer();
      systemBuffer.write(characterPersonality);
      final exactUserName = _extractExactUserName(characterPersonality);
      final translatedUserName =
          _extractTranslatedUserName(characterPersonality);
      final fixedCharacterCallNames = _fixedCharacterCallNames(
        characterPersonality,
        characterId: characterId,
      );
      final standardJapaneseNames = _standardJapaneseNameRulesForPrompt();

      if (timeContext != null && timeContext.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(timeContext);
      }

      if (webContext != null && webContext.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(webContext);
        systemBuffer.writeln();
        systemBuffer.write('''
【联网事实使用硬规则】
如果本轮提供了联网事实，你可以用角色口吻自然转述，但必须保持事实里的动作主体、对象、因果和时间顺序不变。
- 不要把“某人的动物、部下、同伴、相关物”改成“某人本人”。
- 不要把“某事被完成、某人被打倒、某事发生”推断成没有在事实里明确出现的角色完成。
- 如果事实只说结果，没有说明是谁做的，就只能说结果，不要补出执行者。
- 如果资料中出现【事实时间线】，最终回答必须优先服从时间线的先后顺序和【回答约束】；不要把时间线标明不连续的事件用“然后、于是、だから”等词直接连成连续因果。
- 严格区分时间顺序和因果关系。事实里只写“之后、随后、当时、期间”的内容，不能改成“因为、导致、用得太多所以”等因果说法。
- 严格区分亲历、听说和资料确认。除非角色设定或实时资料明确说当前角色亲眼见过/在场，不要把“听说、资料显示、有人提到”的事实说成“我亲眼看到、近くで見ていた”。
- 地点、篇章、事件名、人物名、敌人名属于事实锚点，必须从联网事实中照搬或忠实翻译，不要替换、合并或省略成同作品里的其他地点、篇章或角色；如果事实写的是“从A追到B”“在B说出某句台词”，回复也必须保留B这个具体地点。
- 如果同一条事实里一个转折连续出现多个地点，后续地点通常承载真正结果，回复不能只保留前一个地点；必须把后续地点和对应行动/台词一起写出。
- 如果事实只支持“不太确定/听说/大概”，回复也要保留这种不确定性。
- 优先回答用户真正问的点，不要主动加入联网事实里的旁支趣闻；如果要加入细节，必须逐字核对人物名字和动作主体。
- 用户询问名称、喜好、常去地点、歌曲、招式等单点事实时，只能回答资料中明确写出的具体名词；资料没写出的动物名、地点名、歌曲名、人物名、招式名一律不能凭印象补充。资料没有明确答案时，要自然说明“这点没有明确听说/资料里只确认……”，再回答已确认的部分。
- 用户问“叫什么/名字/是谁/有哪些人”时，优先只回答被问对象的名字和必要身份；不要顺手展开同一网页里的相邻人物、管理者、亲属、后续经历或旁支设定。
- 用户提到“我喜欢/我们家有/我最近在看”等自己的喜好或经历时，不等于当前角色也有同样喜好或经历；除非资料明确支持当前角色喜欢同一对象，否则只能回应用户的喜好，不要说“我也喜欢”。
- 如果资料没有明确写出当前角色对用户所提对象的喜恶，不要替角色评价“也不错/很可爱/挺喜欢/不讨厌/讨厌”；只能说“你喜欢的话也很好”“听起来很有意思”这类不声明角色偏好的回应。
- 如果用户一条消息同时问多个事实点，比如“喜欢什么动物”和“闲暇常去哪里”，必须逐一回答每个事实点；要合并使用【网页搜索摘要】和【角色设定资料】，不要只回答第一项。
- 歌曲相关回答必须区分作品内事实和三次元使用信息：如果角色设定里当前角色负责作曲/创作，可以用第一人称谈创作；但不得让作品角色提到“这首歌被用作动画片头/片尾、现实发售、厂牌、特典、演唱会、榜单”等三次元信息，除非用户明确在问现实发行或动画制作信息。
- 歌曲名、乐队名、专有标题如果资料中以英文/罗马字出现，最终回复应保留原文表记，不要擅自音译成片假名或中文。
- 如果用户询问某个事件“如何/怎么/经过”，回复要围绕用户问的动作目标筛选事实。只挑 2 到 4 个最相关的核心动作自然回答；不要因为资料或时间线里有后续事件，就把审判、冲突、结局等无关后续全部讲出来。
- 如果用户问“如何支援/救援/协助/处理”，不要主动复述和支援目标相反的后续冲突、审判或结局补充；除非用户明确追问这些后续。
- 联网事实中人物姓名后的“（男）/（女）”只是性别指代参考，角色日语回答里不要把这个括号标注读出来或写出来。
- 如果用户询问人物关系、相互影响、救赎、关系变化或一段经历，不要只做抽象评价；从资料中挑能体现关系变化的核心转折自然回答，再给出角色自己的感受。
- 对人物关系、相互影响、救赎、关系变化类问题，优先选择能串起变化的核心转折：相识/邀请、冲突/逃避、鼓励/追回、回归/和解、结果。资料里有明确地点、行动、台词或作品名时，优先使用这些事实锚点，不要只用“互相支持、互相救赎”之类的概括，也不要用无关旁支替代核心转折。
- “去过某地点/某集出现某地点/去看某物”不等于“闲暇常去某地点”；只有资料明确写出兴趣、闲暇、常去、经常、休息日等习惯语义时，才能说成常去地点。
''');
      }

      if (proactiveInstruction != null && proactiveInstruction.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(proactiveInstruction);
      }

      // 明确回复语言。角色人设大多用中文书写，如果不硬性指定，
      // 模型容易先用中文回答，再触发后续翻译流程。
      if (characterLanguage == 'zh') {
        systemBuffer.writeln();
        systemBuffer.write('【语言要求】请全程用自然地道的中文回复，不要使用日语或其他语言。');
      } else {
        systemBuffer.writeln();
        systemBuffer.write(
            '【语言要求】あなたは必ず自然な日本語だけで返答してください。中国語、翻訳文、説明文、前置きは出力しないでください。漢字は日本語の標準的な表記を使い、中国語の字形や中国語の語句を混ぜないでください。');
        systemBuffer.writeln();
        systemBuffer.write(
            '【中文資料の扱い】参考資料が中国語で書かれている場合、必ず意味で日本語に訳してください。字形が似ているだけの日本語漢字語へ置き換えないでください。');
        systemBuffer.writeln();
        systemBuffer.write(
            '【日本語表現ルール】複数の人物名を列挙するときは「A、B、C」または「AとBとC」の形にしてください。列挙の区切りとして「Aに、B、C」のような書き方はしないでください。');
        systemBuffer.writeln();
        systemBuffer.write(
            '【好みの扱い】ユーザーが「私はXが好き」と言っても、あなた自身もXが好きだとは限りません。資料にあなたのXへの好悪がない場合、「私も好き」「Xも素敵」「Xも可愛い」「嫌いではない」など、あなた自身の評価として書かないでください。「あなたが好きなら、それは素敵ですね」のように、ユーザーの好みとして受け止めてください。');
        if (fixedCharacterCallNames.isNotEmpty) {
          systemBuffer.writeln();
          systemBuffer.write('【人物の呼び方】次の相手に触れるときは、必ず指定された呼び方をそのまま使ってください。'
              '勝手にさん・ちゃん・くん等を足さないでください。\n');
          for (final entry in fixedCharacterCallNames.entries) {
            systemBuffer.writeln('- ${entry.key}：${entry.value}');
          }
        }
        if (standardJapaneseNames.isNotEmpty) {
          systemBuffer.writeln();
          systemBuffer.write('【固有名詞の標準表記】以下の中国語名・別表記に触れる場合、'
              '日本語の返答では必ず指定された標準表記を使ってください。漢字の後ろに読み仮名を括弧で足さないでください。\n');
          for (final entry in standardJapaneseNames.entries) {
            systemBuffer.writeln('- ${entry.key}：${entry.value}');
          }
        }
      }

      systemBuffer.writeln();
      systemBuffer.write('''
【情绪感知回复规则】

当用户的消息中明显出现以下任意一种情况时，进入更深度的「情绪支持模式」：
- 表达情绪低落、难过、哭泣、心情不好
- 表达焦虑、压力大、喘不过气、睡不着
- 表达迷茫、不知道该怎么办、感到无力
- 主动倾诉烦恼、困境或内心困扰
- 希望被安慰、被理解、被倾听
- 寻求建议或解决办法

进入「情绪支持模式」后，必须遵守以下规则：
1. 回复长度要比平时聊天明显更长，充分回应对方的情绪，不要三言两语带过
2. 先共情、后引导：先让对方感到被理解和接纳，再给出温和的建议或鼓励
3. 不要说教，不要急着给解决方案，重点是陪伴和倾听的感觉
4. 如果对方说的烦恼比较具体，可以追问细节，表现出真正在意的样子
5. 全程保持你自己角色的说话方式和性格，不要变成机械助手的语气
6. 可以联系你和对方的关系、你自己的经历来表达共鸣，让安慰更真实有温度

未进入「情绪支持模式」时（即普通日常聊天），完全忽略以上规则，按平时正常方式回复。
''');

      systemBuffer.writeln();
      systemBuffer.write(isEmotionSupportTurn
          ? '【本轮回复篇幅】用户本轮明显在表达情绪困扰，可以适度写长。'
          : isRelationshipArcTurn
              ? '【本轮回复篇幅】用户本轮在问关系变化。可以比普通日常聊天稍长，但不要灌水；优先讲清关键转折，再控制语气自然。'
              : isEventProcessTurn
                  ? '【本轮回复篇幅】用户本轮在问事件经过或处理方式。用聊天口吻挑最相关的核心动作回答，不要从头到尾念资料。'
                  : '【本轮回复篇幅】用户本轮不是情绪倾诉。请用日常聊天篇幅回复，控制在4到8句左右。');

      systemBuffer.writeln();
      systemBuffer.write('''
【日常聊天硬性禁句】
以下表达会让角色显得像客服或助手，严禁在普通聊天、开场寒暄、主动消息和连续补充消息中使用：
- 中文："有什么事吗"、"有什么需要帮助的吗"、"我能帮你什么"、"需要我做什么"
- 日语："何か用"、"何の用"、"ご用件"、"用事ですか"、"どうしましたか"

如果用户只是打招呼，例如"早上好"、"晚上好"、"こんにちは"、"こんばんは"，不要追问对方有什么事。
正确做法：自然回应问候，再顺着时间、天气、当前心情、角色自己的日常或与对方的关系说一句有内容的话。
''');

      systemBuffer.writeln();
      systemBuffer.write(characterLanguage == 'zh'
          ? '【最终输出语言】只输出中文回复正文。'
          : '【最終出力言語】参考資料やユーザー発言が中国語でも、最終返答は必ず日本語だけで書いてください。中国語の文、翻訳文、説明文、括弧書きの動作描写は出力禁止です。');

      final List<Map<String, String>> japaneseMessages = [
        {
          'role': 'system',
          'content': systemBuffer.toString(),
        },
      ];

      japaneseMessages.addAll(conversationHistory.map((msg) {
        String content = msg.content;
        if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
          content = content.split('\n\n中文：')[0];
        }
        if (msg.role == 'user' &&
            msg.imageDescription != null &&
            msg.imageDescription!.isNotEmpty) {
          final displayText = content.startsWith('[图片')
              ? content.replaceFirst(RegExp(r'^\[图片[^\]]*\] ?'), '')
              : content;
          final textPart = displayText.isNotEmpty ? '$displayText\n\n' : '';
          content = '$textPart【图片内容】${msg.imageDescription}';
        }
        return {
          'role': msg.role,
          'content': content,
        };
      }));

      final currentUserContent = proactiveInstruction != null
          ? ''
          : _buildCurrentUserContent(
              userMessage: userMessage,
              imageContext: imageContext,
              webContext: webContext,
            );

      japaneseMessages.add(
        proactiveInstruction != null
            ? {'role': 'user', 'content': ''}
            : {'role': 'user', 'content': currentUserContent},
      );
      final hasGroundingContext = webContext != null && webContext.isNotEmpty;

      final japaneseResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': japaneseMessages,
          'max_tokens': 1000,
          'temperature': hasGroundingContext ? 0.55 : 0.8,
          'stream': false,
          'top_p': hasGroundingContext ? 0.8 : 0.9,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.0,
        }),
      );

      if (japaneseResponse.statusCode != 200) {
        debugPrint('DeepSeek API 错误: ${japaneseResponse.statusCode}');
        debugPrint('错误内容: ${japaneseResponse.body}');
        return {'japanese': '申し訳ございません...', 'chinese': '抱歉，我现在无法回答...'};
      }

      final japaneseData = jsonDecode(utf8.decode(japaneseResponse.bodyBytes));
      String rawResponseText =
          japaneseData['choices'][0]['message']['content'] as String;
      rawResponseText =
          _sanitizeUserNameHonorifics(rawResponseText, exactUserName);

      if (_weatherContextForbidsRain(webContext) &&
          _containsProhibitedRainClaim(rawResponseText)) {
        debugPrint(
          '检测到回复违背实时天气上下文，自动重试生成天气回复: '
          '${_logPreview(rawResponseText)}',
        );
        rawResponseText = await _retryWeatherGroundedResponse(
          messages: japaneseMessages,
          badResponse: rawResponseText,
          characterLanguage: characterLanguage,
          exactUserName: exactUserName,
        );
      }

      if (_containsAssistantLikeGreetingQuestion(rawResponseText)) {
        debugPrint(
          '检测到助手式客套问句，自动重试生成回复: '
          '${_logPreview(rawResponseText)}',
        );
        japaneseMessages.add({
          'role': 'assistant',
          'content': rawResponseText,
        });
        japaneseMessages.add({
          'role': 'user',
          'content': characterLanguage == 'zh'
              ? '刚才的回复像客服或助手，并且包含"有什么事吗"这类禁句。请重新回答：自然回应我的上一句话，不要问我有什么事，不要说有什么需要帮助。'
              : '先ほどの返答は事務的で、「何か用」「ご用件」のような禁止表現を含んでいます。必ず自然な日本語で返答し直してください。相手に用件を尋ねず、挨拶を返して、今の時間・気分・日常の小さな話題を一言添えてください。',
        });

        final retryResponse = await http.post(
          Uri.parse('$doubaoBaseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $doubaoApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': doubaoModel,
            'thinking': {'type': 'disabled'},
            'messages': japaneseMessages,
            'max_tokens': 1000,
            'temperature': 0.75,
            'stream': false,
            'top_p': 0.9,
            'presence_penalty': 0.0,
            'frequency_penalty': 0.2,
          }),
        );

        if (retryResponse.statusCode == 200) {
          final retryData = jsonDecode(utf8.decode(retryResponse.bodyBytes));
          final retryText =
              retryData['choices'][0]['message']['content'] as String;
          final sanitizedRetryText =
              _sanitizeUserNameHonorifics(retryText, exactUserName);
          if (!_containsAssistantLikeGreetingQuestion(sanitizedRetryText)) {
            rawResponseText = sanitizedRetryText;
          } else {
            debugPrint(
              '重试结果仍包含助手式客套问句，使用日常寒暄兜底: '
              '${_logPreview(retryText)}',
            );
            rawResponseText = _casualGreetingFallback(characterLanguage);
          }
        } else {
          debugPrint('助手式问句重试 API 错误: ${retryResponse.statusCode}');
          debugPrint('错误内容: ${retryResponse.body}');
          rawResponseText = _casualGreetingFallback(characterLanguage);
        }
      }

      if (_weatherContextForbidsSpecificLocation(webContext) &&
          _containsForbiddenWeatherLocation(rawResponseText)) {
        debugPrint(
          '检测到鬼灭天气回复提及具体地点，自动重试: '
          '${_logPreview(rawResponseText)}',
        );
        rawResponseText = await _retryWeatherLocationlessResponse(
          messages: japaneseMessages,
          badResponse: rawResponseText,
          characterLanguage: characterLanguage,
          exactUserName: exactUserName,
        );
      }

      // ========================================
      // 中文角色：直接返回中文回复，跳过日语相关流程
      // ========================================
      if (characterLanguage == 'zh') {
        debugPrint('中文角色，直接使用中文回复，跳过日语校验与翻译');
        return {
          'japanese': '',
          'chinese': rawResponseText.trim(),
          'imageDescription': imageContext.isNotEmpty
              ? imageContext.replaceFirst('\n\n【图片内容】', '')
              : '',
        };
      }

      // ========================================
      // 日语角色：中译日的核心校验逻辑
      // ========================================
      // 新版本采用「是否含日语假名（平假名/片假名）」作为「翻译成功」的判定依据：
      //   - 任何一句正常日语都至少会有一个假名
      //   - 纯中文不可能含假名，因此假名是中日文最可靠的区分点
      if (_isLikelyJapanese(rawResponseText)) {
        rawResponseText = await _normalizeJapaneseOrthographyIfUseful(
          rawResponseText,
          exactUserName,
        );
      }

      if (!_isCleanJapaneseForTts(rawResponseText)) {
        debugPrint(
          '回复未通过日语纯净度检测，先重试生成日文: '
          '${_logPreview(rawResponseText)}',
        );

        final regenerated = await _retryJapaneseOnlyResponse(
          messages: japaneseMessages,
          badResponse: rawResponseText,
          exactUserName: exactUserName,
        );
        if (_isCleanJapaneseForTts(regenerated)) {
          rawResponseText = regenerated;
        } else {
          debugPrint('重试生成仍未通过日语纯净度检测，开始翻译为日文...');
          debugPrint('  重试返回: $regenerated');

          String translated = rawResponseText;
          bool success = false;

          for (int attempt = 1; attempt <= _maxTranslationRetries; attempt++) {
            debugPrint('  翻译尝试 $attempt / $_maxTranslationRetries ...');
            translated = await _translateToJapanese(rawResponseText);
            translated = _sanitizeUserNameHonorifics(translated, exactUserName);

            if (_isCleanJapaneseForTts(translated)) {
              debugPrint('  翻译成功（第 $attempt 次）: $translated');
              success = true;
              break;
            } else {
              debugPrint('  翻译结果仍未通过日语纯净度检测，准备重试');
              debugPrint('  本次返回: $translated');
            }
          }

          if (success) {
            rawResponseText = translated;
          } else {
            debugPrint('  翻译多次失败，使用兜底日语文本: $_japaneseFallbackText');
            rawResponseText = _japaneseFallbackText;
          }
        }
      }

      String japaneseText = _removeChinese(rawResponseText);
      japaneseText = _sanitizeUserNameHonorifics(japaneseText, exactUserName);
      japaneseText = _removeRubyReadings(japaneseText);
      japaneseText = _applyStandardJapaneseNameSpellings(japaneseText);
      japaneseText =
          _applyFixedCharacterCallNames(japaneseText, fixedCharacterCallNames);
      japaneseText = await _normalizeJapaneseOrthographyIfUseful(
        japaneseText,
        exactUserName,
      );
      japaneseText = _applyStandardJapaneseNameSpellings(japaneseText);
      japaneseText =
          _applyFixedCharacterCallNames(japaneseText, fixedCharacterCallNames);
      if (!_isCleanJapaneseForTts(japaneseText)) {
        debugPrint('最终日语回复仍混入中文片段，重新翻译后再进入显示/TTS: $japaneseText');
        final retranslated = await _translateToJapanese(japaneseText);
        if (_isCleanJapaneseForTts(retranslated)) {
          japaneseText = _applyStandardJapaneseNameSpellings(
            _removeRubyReadings(
              _sanitizeUserNameHonorifics(retranslated, exactUserName),
            ),
          );
          japaneseText = _applyFixedCharacterCallNames(
            japaneseText,
            fixedCharacterCallNames,
          );
        } else {
          debugPrint('中文残留重译失败，使用日语兜底: $retranslated');
          japaneseText = _japaneseFallbackText;
        }
      }
      if (_containsAssistantLikeGreetingQuestion(japaneseText)) {
        debugPrint('最终日语回复仍包含助手式客套问句，使用日常寒暄兜底: $japaneseText');
        japaneseText = _casualGreetingFallback(characterLanguage);
      }

      final textForTranslation = japaneseText.trim();

      String chineseText;
      if (textForTranslation.isEmpty) {
        chineseText = '';
      } else {
        final protectedTranslationText = _protectMappedNamesForTranslation(
          textForTranslation,
          exactUserName: exactUserName,
          translatedUserName: translatedUserName,
          fixedCharacterCallNames: fixedCharacterCallNames,
        );
        final genderHints = _genderHintsForTranslationPrompt(webContext);
        final translationMessages = [
          {
            'role': 'system',
            'content': '你是一个专业的日语翻译。请将用户提供的日语文本翻译成中文。只输出翻译结果，不要有任何额外的解释或说明。\n'
                '译文要像朋友之间自然聊天的中文，不要过度书面、客套或正式。\n'
                '禁止使用"您"、"您的"、"阁下"、"是否"、"不必"这类疏远或正式的说法，默认使用"你"、"你的"、"是不是"、"不用"。\n'
                '专有名词不要猜测性别或改写。\n'
                '如果原文中出现形如 __USER_NAME__、__NAME_0__ 或 __NAMESEQ_0__ 的占位符，必须原样保留，不要翻译、删除或改写。\n'
                '这些占位符中有一部分代表“当前说话角色对对方的固定称呼”，必须按占位符还原后的称呼翻译，不要自行扩写成全名，也不要改成对用户说话的“你”。\n'
                '如果日语原文是在列举多个人名，译文也必须写成中文姓名并列，不要把姓名后的「に」误译成“对……来说/对于……”。\n'
                '如果原文明确说的是女孩子或女性群体，中文代词优先使用“她们”或“这些孩子”；否则日语的“たち”不要默认译成“她们”，可以译成“他们”“这些人”“这些孩子”。\n'
                '如果原文没有明确的性别代词，尽量重复姓名、称呼或使用“那孩子/对方”，不要自行猜成“他”或“她”。\n'
                '$genderHints'
                '除用户称呼占位符外，其他人名后的さん、ちゃん、くん、君、様、先生等称呼后缀要根据人物关系和上下文自然翻译，可以译成同学、学姐、学长、先生、小姐、老师、大人、酱、君等；不要机械保留日语后缀。',
          },
          {
            'role': 'user',
            'content': '请将以下日语翻译成中文：\n${protectedTranslationText.text}',
          },
        ];

        final translationResponse = await http.post(
          Uri.parse('$doubaoBaseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $doubaoApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': doubaoModel,
            'thinking': {'type': 'disabled'},
            'messages': translationMessages,
            'max_tokens': 1000,
            'temperature': 0.3,
            'stream': false,
            'top_p': 0.9,
            'presence_penalty': 0.0,
            'frequency_penalty': 0.0,
          }),
        );

        if (translationResponse.statusCode == 200) {
          final translationData =
              jsonDecode(utf8.decode(translationResponse.bodyBytes));
          chineseText =
              translationData['choices'][0]['message']['content'] as String;
          chineseText = _restoreProtectedMappedNames(
            chineseText,
            protectedTranslationText.placeholders,
          );
          chineseText = _localizeUserNameForChineseTranslation(
            chineseText,
            exactUserName,
            translatedUserName,
          );
          chineseText = _casualizeChineseTranslation(chineseText);
          chineseText = _fixThirdPersonFixedCallTranslation(
            chineseText,
            textForTranslation,
            fixedCharacterCallNames,
          );
        } else {
          debugPrint('翻译 API 错误: ${translationResponse.statusCode}');
          chineseText = '[翻译失败]';
        }
      }

      return {
        'japanese': japaneseText,
        'chinese': chineseText,
        'imageDescription': imageContext.isNotEmpty
            ? imageContext.replaceFirst('\n\n【图片内容】', '')
            : '',
      };
    } catch (e) {
      debugPrint('请求失败: $e');
      return {'japanese': '申し訳ございません...', 'chinese': '抱歉，连接失败了...'};
    }
  }

  // 把“本轮实时资料”贴到最后一条用户消息前面。
  //
  // 原本 webContext 只放在 system prompt 里；system prompt 很长时，
  // 模型容易被角色人设、旧聊天记录或自己的常识带偏。
  // 这里再把同一份资料贴近用户最后一句，让模型在回答本轮问题时更容易看见。
  static String _buildCurrentUserContent({
    required String userMessage,
    required String imageContext,
    String? webContext,
  }) {
    final baseUserMessage = '$userMessage$imageContext';
    if (webContext == null || webContext.trim().isEmpty) {
      return baseUserMessage;
    }

    final processReminder = _isRelationshipArcQuestion(userMessage)
        ? '\n【本轮写作提醒】用户问的是人物关系、相互影响、救赎或关系变化。不要只取资料开头的一条事实，也不要只做抽象评价；请按时间线挑选能体现关系变化的核心转折回答。资料里有明确地点、行动、台词或作品名时优先使用，但不需要把所有资料逐条复述。\n'
        : _isEventProcessQuestion(userMessage)
            ? '\n【本轮写作提醒】用户问的是事件经过、处理方式或支援方式。请只选和用户问点直接相关的核心动作回答；资料里的后续审判、旁支冲突、结局补充，如果不是用户问点所需，不要主动展开。用户问“如何支援/救援/协助/处理”时，不要主动复述和支援目标相反的后续冲突。\n'
            : '';

    return '''
【系统提供的本轮实时资料，不是用户发言】
$webContext
【使用要求】
回答本轮用户问题时，必须优先服从上面的实时资料。可以自然融入角色语气，但不要和实时资料相反；不要逐字念出资料来源。
如果实时资料中有【事实时间线】，先按时间线理解事件顺序，再组织角色回复；不要把时间线约束中标明不连续的事件直接写成连续发生。
地点、篇章、事件名、人物名、敌人名必须以实时资料为准，不要替换成同作品里另一个相似设定。
如果用户问某个具体事实，而实时资料没有写出对应答案，不要用模型记忆或联想补具体名词；请说明没有明确听说，再说资料中能确认的内容。
如果用户问“叫什么/名字/是谁/有哪些人”，只回答被问对象的名字和必要身份，不要展开同一网页里的相邻人物或旁支设定。
如果用户只是说自己喜欢某个东西，不要把它改写成当前角色也喜欢；只有实时资料明确写出当前角色喜欢，才能说“我也喜欢”。资料没有写出当前角色对这个东西的喜恶时，不要评价“也不错/很可爱/挺喜欢/不讨厌/讨厌”，只能接住用户的喜好。
如果用户问人物关系、相互影响、救赎或关系变化，请优先按实时资料中的时间线回答，选用能体现关系变化的核心转折；资料里有明确地点、行动、台词或作品名时要优先使用，不要只给抽象评价。
如果用户问事件经过、处理方式或支援方式，请围绕用户问点筛选事实，不要把时间线里的无关后续都讲出来。

【用户原话】
$baseUserMessage
$processReminder
''';
  }

  static bool _isRelationshipArcQuestion(String userMessage) {
    final normalized = userMessage.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return false;
    return RegExp(
      r'关系|相互|救赎|影响|变化|经历|原委|原因|为什么|为何|'
      r'怎么回事|'
      r'组成|组建|和解|冲突|矛盾|在意|感情',
    ).hasMatch(normalized);
  }

  static bool _isEventProcessQuestion(String userMessage) {
    final normalized = userMessage.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return false;
    return RegExp(r'经过|过程|如何|怎么|怎样|怎么做|怎么处理|支援|救援|恢复|解决|出任务')
        .hasMatch(normalized);
  }

  // 判断本轮天气上下文是否明确禁止说“正在下雨/要下雨”。
  //
  // WebContextService 在当前降水量为 0、天气代码不是雨雪雷时，
  // 会写入“当前不允许说正在下雨...”这句硬限制。
  static bool _weatherContextForbidsRain(String? webContext) {
    if (webContext == null || webContext.isEmpty) return false;
    return webContext.contains('【实时天气】') && webContext.contains('当前不允许说正在下雨');
  }

  static bool _weatherContextForbidsSpecificLocation(String? webContext) {
    if (webContext == null || webContext.isEmpty) return false;
    return webContext.contains('【实时天气】') && webContext.contains('禁止说“东京”');
  }

  // 判断回复里是否出现了和“当前无降水”冲突的说法。
  //
  // 注意：不能简单检测“雨”这个字。
  // “没有下雨”“雷雨ではありません”是正确表达，不能误杀。
  static bool _containsProhibitedRainClaim(String text) {
    var normalized = text;
    normalized = normalized.replaceAll(
      RegExp(
        r'没有下雨|不会下雨|不下雨|不是雨天|没有降雨|不会降雨|没有雷雨|不是雷雨|'
        r'雨は降っていない|雨は降っていません|降っていない|降っていません|'
        r'雨ではありません|雨じゃありません|雷雨ではありません|雷雨じゃありません',
      ),
      '',
    );

    return RegExp(
      r'雷雨|雨模様|下雨|要下雨|会下雨|雨天|降雨|打雷|雷声|雷鳴|'
      r'带伞|雨伞|傘|本降り|雨が降|降り出|雷が',
    ).hasMatch(normalized);
  }

  static bool _containsForbiddenWeatherLocation(String text) {
    return RegExp(r'东京|東京|东京都|東京都').hasMatch(text);
  }

  // 如果模型第一次无视实时天气，给它一次“带着错误原因”的重试机会。
  //
  // 这比直接改掉文本更自然：角色语气仍然由模型生成，
  // 但必须承认当前实时天气不是雨。
  static Future<String> _retryWeatherGroundedResponse({
    required List<Map<String, String>> messages,
    required String badResponse,
    required String characterLanguage,
    required String? exactUserName,
  }) async {
    final retryMessages = List<Map<String, String>>.from(messages)
      ..add({
        'role': 'assistant',
        'content': badResponse,
      })
      ..add({
        'role': 'user',
        'content': characterLanguage == 'zh'
            ? '刚才的回复违背了实时天气资料。当前实时天气不是雨天，不是雷雨，当前降水量为 0。请重新回答我的天气问题：可以提湿度高或体感闷热，但禁止说正在下雨、要下雨、雷雨、打雷或建议带伞。'
            : '直前の返答はリアルタイム天気情報に反しています。現在の天気は雨でも雷雨でもなく、降水量は0です。湿度が高い、蒸し暑いとは言って構いませんが、雨、雷雨、雷、傘を持つべきという内容は禁止です。自然な日本語で返答し直してください。',
      });

    try {
      final retryResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': retryMessages,
          'max_tokens': 1000,
          'temperature': 0.55,
          'stream': false,
          'top_p': 0.8,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.3,
        }),
      );

      if (retryResponse.statusCode == 200) {
        final retryData = jsonDecode(utf8.decode(retryResponse.bodyBytes));
        final retryText =
            retryData['choices'][0]['message']['content'] as String;
        final sanitizedRetryText =
            _sanitizeUserNameHonorifics(retryText, exactUserName);
        if (!_containsProhibitedRainClaim(sanitizedRetryText)) {
          return sanitizedRetryText;
        }
        debugPrint('天气重试仍违背实时天气，使用天气兜底: $sanitizedRetryText');
      } else {
        debugPrint('天气重试 API 错误: ${retryResponse.statusCode}');
        debugPrint('错误内容: ${retryResponse.body}');
      }
    } catch (e) {
      debugPrint('天气重试失败: $e');
    }

    return characterLanguage == 'zh'
        ? '现在不是雨天，也没有雷雨。只是湿度偏高，体感会有些闷热，外出不用特意因为下雨带伞。'
        : '今は雨でも雷雨でもありませんわ。ただ湿度が高くて、少し蒸し暑く感じるかもしれません。';
  }

  static Future<String> _retryWeatherLocationlessResponse({
    required List<Map<String, String>> messages,
    required String badResponse,
    required String characterLanguage,
    required String? exactUserName,
  }) async {
    final retryMessages = List<Map<String, String>>.from(messages)
      ..add({
        'role': 'assistant',
        'content': badResponse,
      })
      ..add({
        'role': 'user',
        'content': characterLanguage == 'zh'
            ? '刚才的回复把天气地点说成了东京。对《鬼灭之刃》角色来说，东京只是查询现实天气用的参考点，不是原作地点。请重新回答：禁止提到东京、东京都或任何具体城市，只能说“这边”“附近”“蝶屋这边”等模糊地点。'
            : '直前の返答では天気の場所を東京として言ってしまいました。東京は現実の天気を調べるための参考地点であって、『鬼滅の刃』の作中所在地ではありません。東京、東京都、具体的な都市名は一切出さず、「こちら」「この辺り」「蝶屋のあたり」などの曖昧な場所表現で、自然な日本語で返答し直してください。',
      });

    try {
      final retryResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': retryMessages,
          'max_tokens': 700,
          'temperature': 0.7,
          'top_p': 0.9,
          'presence_penalty': 0.2,
          'frequency_penalty': 0.3,
        }),
      );

      if (retryResponse.statusCode == 200) {
        final retryData = jsonDecode(utf8.decode(retryResponse.bodyBytes));
        final retryText =
            retryData['choices'][0]['message']['content'] as String;
        final sanitizedRetryText =
            _sanitizeUserNameHonorifics(retryText, exactUserName);
        if (!_containsForbiddenWeatherLocation(sanitizedRetryText)) {
          return sanitizedRetryText;
        }
        debugPrint('天气地点重试仍提及具体地点，执行保守替换: $sanitizedRetryText');
        return _removeForbiddenWeatherLocationMentions(sanitizedRetryText);
      }

      debugPrint('天气地点重试 API 错误: ${retryResponse.statusCode}');
      debugPrint('错误内容: ${retryResponse.body}');
    } catch (e) {
      debugPrint('天气地点重试失败: $e');
    }

    return _removeForbiddenWeatherLocationMentions(badResponse);
  }

  static String _removeForbiddenWeatherLocationMentions(String text) {
    return text
        .replaceAll('東京都', 'この辺り')
        .replaceAll('東京', 'この辺り')
        .replaceAll('东京都', '这边')
        .replaceAll('东京', '这边');
  }

  static Future<String> _retryJapaneseOnlyResponse({
    required List<Map<String, String>> messages,
    required String badResponse,
    required String? exactUserName,
  }) async {
    final retryMessages = List<Map<String, String>>.from(messages)
      ..add({
        'role': 'assistant',
        'content': badResponse,
      })
      ..add({
        'role': 'user',
        'content': '直前の返答は日本語キャラクターの返答として不適切です。'
            '必ず同じキャラクター本人として、自然な日本語だけで返答し直してください。'
            '中国語を混ぜないでください。翻訳文ではなく、最初から日本語で話してください。'
            '一人称、語尾、相手への呼び方はキャラクター設定に従ってください。'
            '本輪にリアルタイム資料や検索事実がある場合は、それを必ず使ってください。'
            '人物関係・相互影響・救済・経緯について聞かれている場合は、抽象的な感想だけにせず、'
            '資料にある具体的な行動、場所、台詞、転機を前半・中盤・後半から自然に入れてください。'
            '資料に関係修復、帰還、和解、再接続を示す後半の事実がある場合は、途中の励ましだけで終わらせず、'
            'その後半の結果も必ず含めてください。',
      });

    try {
      final retryResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': retryMessages,
          'max_tokens': 1000,
          'temperature': 0.55,
          'stream': false,
          'top_p': 0.85,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.25,
        }),
      );

      if (retryResponse.statusCode == 200) {
        final retryData = jsonDecode(utf8.decode(retryResponse.bodyBytes));
        final retryText =
            retryData['choices'][0]['message']['content'] as String;
        return _sanitizeUserNameHonorifics(retryText, exactUserName);
      }

      debugPrint('日语重生成 API 错误: ${retryResponse.statusCode}');
      debugPrint('错误内容: ${retryResponse.body}');
    } catch (e) {
      debugPrint('日语重生成失败: $e');
    }

    return badResponse;
  }

  // 生成语音（GPT-SoVITS api_v2 TTS）
  // 上层已经按完整句子逐句调用这里。这里默认保持一句话不再拆分，
  // 只在极长文本时兜底切开，避免一句话中间出现生硬停顿。
  // textLanguage: 合成文本的语言，'ja'=日语（默认），'zh'=中文
  static Future<List<String>> generateSpeechSegments({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
    // TTS 播放速度倍率，由角色设置页面配置，默认 1.0（正常速度）
    // 范围 0.5（慢速）~ 2.0（快速），传递给 GPT-SoVITS 的 speed_factor 参数
    double speedFactor = 1.0,
    String textLanguage = 'ja',
  }) async {
    final cleanedText = _stripActionDescriptions(text);
    List<String> segments = _splitTextIntoSegments(cleanedText);
    List<String> audioPaths = [];
    final resolvedReferWavPath = AppPaths.resolve(referWavPath);

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      try {
        final response = await http.post(
          Uri.parse('$gptSovitsBaseUrl/tts'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'ref_audio_path': resolvedReferWavPath,
            'prompt_text': promptText,
            'prompt_lang': promptLanguage,
            'text': segment,
            'text_lang': textLanguage,
            'top_k': 5,
            'top_p': 0.8,
            'temperature': 0.8,
            'text_split_method': 'cut0',
            'batch_size': 1,
            'batch_threshold': 0.75,
            'split_bucket': true,
            // 使用传入的语速参数，不再硬编码 1.0
            'speed_factor': speedFactor,
            'fragment_interval': 0.3,
            'seed': -1,
            'media_type': 'wav',
            'streaming_mode': false,
            'parallel_infer': false,
            'repetition_penalty': 1.35,
          }),
        );

        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filePath = '${tempDir.path}/audio_${timestamp}_$i.wav';

          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          audioPaths.add(filePath);
          debugPrint(
              '成功生成音频段 $i: $filePath (${response.bodyBytes.length} bytes)');
        } else {
          debugPrint('GPT-SoVITS 错误 (段落$i): ${response.statusCode}');
          debugPrint('错误内容: ${response.body}');
        }
      } catch (e) {
        debugPrint('GPT-SoVITS 请求失败 (段落$i): $e');
      }
    }

    return audioPaths;
  }

  // 切换角色模型（api_v2 新功能）
  static Future<bool> switchCharacterModel({
    required String gptModelPath,
    required String sovitsModelPath,
  }) async {
    try {
      final resolvedGptModelPath = AppPaths.resolve(gptModelPath);
      final resolvedSovitsModelPath = AppPaths.resolve(sovitsModelPath);
      debugPrint('正在切换模型...');
      debugPrint('GPT 模型: $resolvedGptModelPath');
      debugPrint('SoVITS 模型: $resolvedSovitsModelPath');

      final gptResponse = await http.get(
        Uri.parse('$gptSovitsBaseUrl/set_gpt_weights').replace(
          queryParameters: {'weights_path': resolvedGptModelPath},
        ),
      );

      if (gptResponse.statusCode != 200) {
        debugPrint('切换 GPT 模型失败: ${gptResponse.statusCode}');
        debugPrint('响应: ${gptResponse.body}');
        return false;
      }

      final sovitsResponse = await http.get(
        Uri.parse('$gptSovitsBaseUrl/set_sovits_weights').replace(
          queryParameters: {'weights_path': resolvedSovitsModelPath},
        ),
      );

      if (sovitsResponse.statusCode != 200) {
        debugPrint('切换 SoVITS 模型失败: ${sovitsResponse.statusCode}');
        debugPrint('响应: ${sovitsResponse.body}');
        return false;
      }

      debugPrint('模型切换成功');
      return true;
    } catch (e) {
      debugPrint('切换模型失败: $e');
      return false;
    }
  }

  // ========================================
  // 语音文本预处理
  // ========================================

  static String _stripActionDescriptions(String text) {
    String cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]+\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'  +'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\n+'), '\n');
    cleaned = cleaned.trim();

    if (cleaned != text) {
      debugPrint('括号内容已删除');
      debugPrint('  原文: $text');
      debugPrint('  清理后: $cleaned');
    }

    return cleaned;
  }

  static List<String> _splitTextIntoSegments(String text) {
    const int maxCharsPerSegment = 180;
    final String cleaned = text.trim();

    if (cleaned.isEmpty) {
      return [];
    }

    if (cleaned.length <= maxCharsPerSegment) {
      return [cleaned];
    }

    final List<String> segments = [];
    final List<String> parts = cleaned
        .split(RegExp(r'(?<=[。！？!?、，；;：:\n])'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    String currentSegment = '';

    for (final part in parts) {
      if (part.length > maxCharsPerSegment) {
        if (currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = '';
        }

        for (int i = 0; i < part.length; i += maxCharsPerSegment) {
          final int end = (i + maxCharsPerSegment < part.length)
              ? i + maxCharsPerSegment
              : part.length;
          segments.add(part.substring(i, end));
        }
        continue;
      }

      final String nextSegment = currentSegment + part;
      if (nextSegment.length > maxCharsPerSegment &&
          currentSegment.isNotEmpty) {
        segments.add(currentSegment);
        currentSegment = part;
      } else {
        currentSegment = nextSegment;
      }
    }

    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment);
    }

    return segments;
  }

  static bool _containsAssistantLikeGreetingQuestion(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('？', '?')
        .replaceAll('！', '!')
        .toLowerCase();

    final forbiddenPatterns = [
      RegExp(r'有什么事'),
      RegExp(r'什么事[吗嘛呀啊]?'),
      RegExp(r'需要.*帮助'),
      RegExp(r'帮你.*什么'),
      RegExp(r'我能.*帮'),
      RegExp(r'何か用'),
      RegExp(r'何の用'),
      RegExp(r'何用'),
      RegExp(r'ご用件'),
      RegExp(r'用件'),
      RegExp(r'用事'),
      RegExp(r'どうしました'),
      RegExp(r'どうしたの'),
      RegExp(r'どうかしました'),
      RegExp(r'何かありました'),
    ];

    return forbiddenPatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  static String? _extractExactUserName(String characterPersonality) {
    final patterns = [
      RegExp(r'用户设置的唯一称呼是"([^"]+)"'),
      RegExp(r'请在对话中用"([^"]+)"称呼用户'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(characterPersonality);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _extractTranslatedUserName(String characterPersonality) {
    final match =
        RegExp(r'中文翻译中显示用户称呼时，必须使用"([^"]+)"').firstMatch(characterPersonality);
    final value = match?.group(1)?.trim();
    return value != null && value.isNotEmpty ? value : null;
  }

  static Map<String, String> _fixedCharacterCallNames(
    String characterPersonality, {
    String? characterId,
  }) {
    final callNames = <String, String>{};

    final configuredCallNames =
        characterId == null ? null : _fixedCharacterCallNameMap[characterId];
    if (configuredCallNames != null) {
      callNames.addAll(configuredCallNames);
    }

    final pattern = RegExp(r'（([^（）]*?，你称呼[^（）]*?为“([^”]+)”[^（）]*?)）');

    for (final match in pattern.allMatches(characterPersonality)) {
      final inside = match.group(1)?.trim() ?? '';
      final preferredCallName = match.group(2)?.trim() ?? '';
      if (inside.isEmpty || preferredCallName.isEmpty) continue;

      final displayName = _nameBeforeParenthesis(
        characterPersonality.substring(0, match.start),
      );
      if (displayName.isNotEmpty) {
        callNames.putIfAbsent(displayName, () => preferredCallName);
      }
    }

    return callNames;
  }

  static String _nameBeforeParenthesis(String prefix) {
    final match =
        RegExp(r'([\u4e00-\u9fffぁ-んァ-ヶーA-Za-z・\s]+)$').firstMatch(prefix);
    return (match?.group(1) ?? '')
        .replaceFirst(RegExp(r'^[\s·•\-*]+'), '')
        .trim();
  }

  static String _removeRubyReadings(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'([\u3400-\u9fff々〆ヶ]+)（[ぁ-ゖァ-ヺー・\s]+）'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'([\u3400-\u9fff々〆ヶ]+)\([ぁ-ゖァ-ヺー・\s]+\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _applyStandardJapaneseNameSpellings(String text) {
    var result = text;
    final entries = _chineseToJapaneseNameMap().entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      result = _replaceNameTerm(result, entry.key, entry.value);
    }
    return result;
  }

  static String _applyFixedCharacterCallNames(
    String text,
    Map<String, String> fixedCharacterCallNames,
  ) {
    if (text.isEmpty || fixedCharacterCallNames.isEmpty) return text;

    var result = text;
    final entries = fixedCharacterCallNames.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in entries) {
      final displayName = entry.key.trim();
      final callName = entry.value.trim();
      if (displayName.isEmpty || callName.isEmpty) continue;

      final variants = <String>{
        displayName,
        _applyStandardJapaneseNameSpellings(displayName),
      }.where((value) => value.isNotEmpty && value != callName).toList()
        ..sort((a, b) => b.length.compareTo(a.length));

      for (final variant in variants) {
        result = _replaceNameTerm(result, variant, callName);
      }

      if (!_endsWithKnownHonorific(callName)) {
        for (final suffix in _knownJapaneseHonorifics) {
          result = result.replaceAll('$callName$suffix', callName);
        }
      }
    }

    return result;
  }

  static const List<String> _knownJapaneseHonorifics = [
    'さん',
    'ちゃん',
    'くん',
    '君',
    '様',
    'さま',
    '先生',
    '先輩',
    '後輩',
  ];

  static bool _endsWithKnownHonorific(String text) {
    return _knownJapaneseHonorifics.any(text.endsWith);
  }

  static String _sanitizeUserNameHonorifics(
      String text, String? exactUserName) {
    if (exactUserName == null || exactUserName.isEmpty) return text;

    final allowedSuffixes = [
      'さん',
      'ちゃん',
      'くん',
      '君',
      '様',
      'さま',
      '先生',
      '小姐',
      '女士',
      '同学',
    ];

    // 用户已经在设置页写了完整后缀时，尊重原样称呼，不再剥离。
    if (allowedSuffixes.any((suffix) => exactUserName.endsWith(suffix))) {
      return text;
    }

    var result = text;
    for (final suffix in allowedSuffixes) {
      result = result.replaceAll('$exactUserName$suffix', exactUserName);
    }
    return result;
  }

  static String _localizeUserNameForChineseTranslation(
    String text,
    String? exactUserName,
    String? translatedUserName,
  ) {
    if (exactUserName == null || exactUserName.isEmpty) return text;

    if (translatedUserName != null && translatedUserName.isNotEmpty) {
      final baseName = _stripKnownHonorific(exactUserName);
      return text
          .replaceAll(exactUserName, translatedUserName)
          .replaceAll('$baseName先生', translatedUserName)
          .replaceAll('$baseName小姐', translatedUserName)
          .replaceAll('$baseName同学', translatedUserName)
          .replaceAll('$baseName酱', translatedUserName);
    }

    final honorificMap = <String, String>{
      'さん': '同学',
      'ちゃん': '酱',
      'くん': '君',
      '君': '君',
      '様': '大人',
      'さま': '大人',
      '先生': '老师',
    };

    for (final entry in honorificMap.entries) {
      final suffix = entry.key;
      if (!exactUserName.endsWith(suffix)) continue;

      final baseName =
          exactUserName.substring(0, exactUserName.length - suffix.length);
      if (baseName.isEmpty) return text;

      final localizedName = '$baseName${entry.value}';
      return text
          .replaceAll(exactUserName, localizedName)
          .replaceAll('$baseName先生', localizedName)
          .replaceAll('$baseName小姐', localizedName)
          .replaceAll('$baseName同学', localizedName);
    }

    return text;
  }

  static String _fixThirdPersonFixedCallTranslation(
    String chineseText,
    String japaneseSourceText,
    Map<String, String> fixedCharacterCallNames,
  ) {
    if (chineseText.isEmpty ||
        japaneseSourceText.isEmpty ||
        fixedCharacterCallNames.isEmpty) {
      return chineseText;
    }

    var result = chineseText;
    for (final entry in fixedCharacterCallNames.entries) {
      final callName = entry.value.trim();
      if (callName.isEmpty) continue;
      final target = _callNameChineseTarget(entry.key, callName);
      if (target.isEmpty) continue;

      final thirdPersonInSource = RegExp(
        '${RegExp.escape(callName)}(?:は|が|も|の|に|を|と|では|には)',
      ).hasMatch(japaneseSourceText);
      if (!thirdPersonInSource) continue;

      result = _fixSecondPersonPronounsInTargetSentences(result, target);
    }
    return result;
  }

  static String _fixSecondPersonPronounsInTargetSentences(
    String text,
    String target,
  ) {
    final buffer = StringBuffer();
    final sentencePattern = RegExp(r'[^。！？!?]+[。！？!?]?');
    var lastEnd = 0;
    for (final match in sentencePattern.allMatches(text)) {
      if (match.start > lastEnd) {
        buffer.write(text.substring(lastEnd, match.start));
      }
      var sentence = match.group(0) ?? '';
      if (sentence.contains(target)) {
        sentence = sentence
            .replaceAll('$target你', target)
            .replaceAll('$target您', target)
            .replaceAll('$target你的', '$target的')
            .replaceAll('$target您的', '$target的')
            .replaceAll('你喜欢', '$target喜欢')
            .replaceAll('您喜欢', '$target喜欢')
            .replaceAll('你常', '$target常')
            .replaceAll('您常', '$target常')
            .replaceAll('你经常', '$target经常')
            .replaceAll('您经常', '$target经常')
            .replaceAll('你会', '$target会')
            .replaceAll('您会', '$target会')
            .replaceAll('你去', '$target去')
            .replaceAll('您去', '$target去')
            .replaceAll('你拿', '$target拿')
            .replaceAll('您拿', '$target拿')
            .replaceAll('你的', '$target的')
            .replaceAll('您的', '$target的');
      }
      buffer.write(sentence);
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      buffer.write(text.substring(lastEnd));
    }
    return buffer.toString();
  }

  static _ProtectedTranslationText _protectMappedNamesForTranslation(
    String text, {
    String? exactUserName,
    String? translatedUserName,
    Map<String, String> fixedCharacterCallNames = const {},
  }) {
    var protectedText = text;
    final placeholders = <String, String>{};

    final userNameTarget = _userNameChineseTranslationTarget(
      exactUserName,
      translatedUserName,
    );
    if (exactUserName != null &&
        exactUserName.isNotEmpty &&
        userNameTarget != null &&
        protectedText.contains(exactUserName)) {
      const placeholder = '__USER_NAME__';
      protectedText = protectedText.replaceAll(exactUserName, placeholder);
      placeholders[placeholder] = userNameTarget;
    }

    final entries = {
      ..._fixedCallNameTranslationMap(fixedCharacterCallNames),
      ..._expandedJapaneseNameTranslationMap(),
    }.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    final sequenceProtected = _protectMappedNameSequences(
      protectedText,
      entries,
      placeholders,
    );
    protectedText = sequenceProtected;

    for (final entry in entries) {
      if (!protectedText.contains(entry.key)) continue;

      final placeholder = '__NAME_${placeholders.length}__';
      protectedText = protectedText.replaceAll(entry.key, placeholder);
      placeholders[placeholder] = entry.value;
    }

    return _ProtectedTranslationText(
      text: protectedText,
      placeholders: placeholders,
    );
  }

  static String _protectMappedNameSequences(
    String text,
    List<MapEntry<String, String>> entries,
    Map<String, String> placeholders,
  ) {
    if (entries.isEmpty || text.isEmpty) return text;

    final byJapanese = <String, String>{
      for (final entry in entries)
        if (entry.key.trim().isNotEmpty) entry.key: entry.value,
    };
    final names = byJapanese.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    String? matchNameAt(String source, int index) {
      for (final name in names) {
        if (index + name.length <= source.length &&
            source.substring(index, index + name.length) == name) {
          return name;
        }
      }
      return null;
    }

    var result = '';
    var index = 0;
    while (index < text.length) {
      final firstName = matchNameAt(text, index);
      if (firstName == null) {
        result += text[index];
        index++;
        continue;
      }

      final matchedNames = <String>[firstName];
      var cursor = index + firstName.length;
      var sequenceEnd = cursor;

      while (cursor < text.length) {
        final separatorStart = cursor;
        cursor = _consumeNameSequenceSeparator(text, cursor);
        if (cursor == separatorStart) break;

        final nextName = matchNameAt(text, cursor);
        if (nextName == null) break;

        matchedNames.add(nextName);
        cursor += nextName.length;
        sequenceEnd = cursor;
      }

      if (matchedNames.length < 2) {
        result += firstName;
        index += firstName.length;
        continue;
      }

      final placeholder = '__NAMESEQ_${placeholders.length}__';
      placeholders[placeholder] =
          matchedNames.map((name) => byJapanese[name] ?? name).join('、');
      result += placeholder;
      index = sequenceEnd;
    }

    return result;
  }

  static int _consumeNameSequenceSeparator(String text, int start) {
    var index = start;
    var consumed = false;
    while (index < text.length) {
      final char = text[index];
      if (RegExp(r'[\s　、,，・･·]').hasMatch(char)) {
        consumed = true;
        index++;
        continue;
      }
      break;
    }

    if (index < text.length && text.startsWith('に', index)) {
      final afterNi = index + 'に'.length;
      if (afterNi < text.length &&
          RegExp(r'[\s　、,，・･·]').hasMatch(text[afterNi])) {
        consumed = true;
        index = afterNi;
        while (index < text.length) {
          final char = text[index];
          if (RegExp(r'[\s　、,，・･·]').hasMatch(char)) {
            index++;
            continue;
          }
          break;
        }
      }
    }

    if (index < text.length &&
        (text.startsWith('と', index) || text.startsWith('や', index))) {
      consumed = true;
      index++;
      while (index < text.length) {
        final char = text[index];
        if (RegExp(r'[\s　、,，・･·]').hasMatch(char)) {
          index++;
          continue;
        }
        break;
      }
    }

    return consumed ? index : start;
  }

  static _ProtectedTranslationText _protectMappedNamesForJapaneseTranslation(
    String text,
  ) {
    var protectedText = text;
    final placeholders = <String, String>{};
    final entries = _chineseToJapaneseNameMap().entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in entries) {
      if (!protectedText.contains(entry.key)) continue;

      final placeholder = '__JP_NAME_${placeholders.length}__';
      final replaced = _replaceNameTerm(protectedText, entry.key, placeholder);
      if (replaced == protectedText) continue;

      protectedText = replaced;
      placeholders[placeholder] = entry.value;
    }

    return _ProtectedTranslationText(
      text: protectedText,
      placeholders: placeholders,
    );
  }

  static String _restoreProtectedMappedNames(
    String text,
    Map<String, String> placeholders,
  ) {
    var result = text;
    placeholders.forEach((placeholder, target) {
      result = result.replaceAll(placeholder, target);
    });
    return result;
  }

  static String _replaceNameTerm(String text, String source, String target) {
    if (source.isEmpty || source == target) return text;
    if (source.runes.length > 1) {
      final buffer = StringBuffer();
      var changed = false;
      var index = 0;
      while (index < text.length) {
        if (!text.startsWith(source, index)) {
          buffer.write(text[index]);
          index += 1;
          continue;
        }

        if (target.startsWith(source) && text.startsWith(target, index)) {
          buffer.write(source);
          index += source.length;
          continue;
        }

        buffer.write(target);
        changed = true;
        index += source.length;
      }
      return changed ? buffer.toString() : text;
    }

    final buffer = StringBuffer();
    var changed = false;
    final runes = text.runes.toList();
    final sourceRune = source.runes.single;
    for (var i = 0; i < runes.length; i++) {
      final current = runes[i];
      if (current != sourceRune ||
          !_isStandaloneSingleCharacterName(runes, i)) {
        buffer.writeCharCode(current);
        continue;
      }

      buffer.write(target);
      changed = true;
    }

    return changed ? buffer.toString() : text;
  }

  static bool _isStandaloneSingleCharacterName(List<int> runes, int index) {
    final previous = index > 0 ? String.fromCharCode(runes[index - 1]) : '';
    final next =
        index + 1 < runes.length ? String.fromCharCode(runes[index + 1]) : '';

    final previousAllows = previous.isEmpty ||
        !_isCjkLetter(previous) ||
        _isNameConnector(previous);
    final nextAllows =
        next.isEmpty || !_isCjkLetter(next) || _isNameConnector(next);
    return previousAllows && nextAllows;
  }

  static bool _isCjkLetter(String char) {
    return RegExp(r'[\u3400-\u9fff々〆ヶ]').hasMatch(char);
  }

  static bool _isNameConnector(String char) {
    return RegExp(r'[、，,・･と和与及跟还有\s]').hasMatch(char);
  }

  static String? _userNameChineseTranslationTarget(
    String? exactUserName,
    String? translatedUserName,
  ) {
    if (exactUserName == null || exactUserName.isEmpty) return null;
    if (translatedUserName != null && translatedUserName.isNotEmpty) {
      return translatedUserName;
    }

    final honorificMap = <String, String>{
      'さん': '同学',
      'ちゃん': '酱',
      'くん': '君',
      '君': '君',
      '様': '大人',
      'さま': '大人',
      '先生': '老师',
    };

    for (final entry in honorificMap.entries) {
      final suffix = entry.key;
      if (!exactUserName.endsWith(suffix)) continue;

      final baseName =
          exactUserName.substring(0, exactUserName.length - suffix.length);
      if (baseName.isEmpty) return exactUserName;
      return '$baseName${entry.value}';
    }

    return exactUserName;
  }

  static Map<String, String> _expandedJapaneseNameTranslationMap() {
    final expanded = <String, String>{};
    for (final entry in _japaneseToChineseNameMap().entries) {
      expanded[entry.key] = entry.value;

      final compactKey = entry.key.replaceAll(RegExp(r'[\s　]+'), '');
      if (compactKey != entry.key) {
        expanded[compactKey] = entry.value.replaceAll(RegExp(r'[\s　]+'), '');
      }

      final sourceParts = _splitNameLikeText(entry.key);
      final targetParts = _splitTranslationTarget(entry.value, sourceParts);
      if (sourceParts.length == targetParts.length && sourceParts.length > 1) {
        for (int i = 0; i < sourceParts.length; i++) {
          expanded.putIfAbsent(sourceParts[i], () => targetParts[i]);
        }
      }
    }

    return expanded;
  }

  static Map<String, String> _japaneseToChineseNameMap() {
    final result = <String, String>{};
    for (final entry in _nameEntries) {
      result[entry.japanese] = entry.chinese;
      for (final alias in entry.japaneseAliases) {
        result[alias] = entry.chinese;
      }
    }
    return result;
  }

  static Map<String, String> _chineseToJapaneseNameMap() {
    final result = <String, String>{};
    for (final entry in _nameEntries) {
      result[entry.chinese] = entry.japanese;
      for (final alias in entry.japaneseAliases) {
        result[alias] = entry.japanese;
      }
      for (final alias in entry.chineseAliases) {
        result[alias] = entry.japanese;
      }
    }
    return result;
  }

  static Map<String, String> _standardJapaneseNameRulesForPrompt() {
    final result = <String, String>{};
    for (final entry in _nameEntries) {
      result[entry.chinese] = entry.japanese;
      for (final alias in entry.japaneseAliases) {
        result[alias] = entry.japanese;
      }
      for (final alias in entry.chineseAliases) {
        result[alias] = entry.japanese;
      }
    }
    return result;
  }

  static Map<String, String> _fixedCallNameTranslationMap(
    Map<String, String> fixedCharacterCallNames,
  ) {
    final result = <String, String>{};
    for (final entry in fixedCharacterCallNames.entries) {
      final displayName = entry.key.trim();
      final callName = entry.value.trim();
      if (displayName.isEmpty || callName.isEmpty) continue;

      final translatedCallName = _callNameChineseTarget(displayName, callName);
      if (translatedCallName.isNotEmpty) {
        result[callName] = translatedCallName;
      }
    }
    return result;
  }

  static String _callNameChineseTarget(String displayName, String callName) {
    final suffixTranslations = {
      'さん': '同学',
      'ちゃん': '酱',
      'くん': '君',
      '君': '君',
      '様': '大人',
      'さま': '大人',
      '先生': '老师',
    };

    var bareCallName = callName;
    var suffixTranslation = '';
    for (final entry in suffixTranslations.entries) {
      if (!bareCallName.endsWith(entry.key)) continue;
      bareCallName =
          bareCallName.substring(0, bareCallName.length - entry.key.length);
      suffixTranslation = entry.value;
      break;
    }

    final targetLength = bareCallName.runes.length;
    if (targetLength <= 0) return displayName;

    final displayKey = _cjkLooseMatchKey(displayName);
    final callKey = _cjkLooseMatchKey(bareCallName);
    String baseTarget;

    if (callKey.isNotEmpty && displayKey.startsWith(callKey)) {
      baseTarget = _takeRunes(displayName, targetLength, fromEnd: false);
    } else if (callKey.isNotEmpty && displayKey.endsWith(callKey)) {
      baseTarget = _takeRunes(displayName, targetLength, fromEnd: true);
    } else if (_containsKana(bareCallName)) {
      baseTarget = _takeRunes(displayName, targetLength, fromEnd: true);
    } else {
      baseTarget = displayName;
    }

    return '$baseTarget$suffixTranslation';
  }

  static String _takeRunes(
    String text,
    int count, {
    required bool fromEnd,
  }) {
    final runes = text.runes.toList();
    if (count >= runes.length) return text;
    return fromEnd
        ? String.fromCharCodes(runes.sublist(runes.length - count))
        : String.fromCharCodes(runes.sublist(0, count));
  }

  static String _logPreview(String text, {int maxRunes = 120}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.runes.length <= maxRunes) return normalized;
    return '${_takeRunes(normalized, maxRunes, fromEnd: false)}...';
  }

  static bool _containsKana(String text) {
    return RegExp(r'[ぁ-ゖァ-ヺー]').hasMatch(text);
  }

  static String _cjkLooseMatchKey(String text) {
    const variants = {
      '時': '时',
      '冨': '富',
      '岡': '冈',
      '鳴': '鸣',
      '嶼': '屿',
      '黒': '黑',
      '煉': '炼',
      '獄': '狱',
      '禰': '祢',
      '燈': '灯',
      '愛': '爱',
      '樂': '乐',
      '楽': '乐',
      '華': '华',
    };
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(variants[char] ?? char);
    }
    return buffer.toString();
  }

  static List<String> _splitTranslationTarget(
    String target,
    List<String> sourceParts,
  ) {
    final separated = _splitByNameSeparators(target);
    if (separated.length == sourceParts.length) return separated;

    if (sourceParts.length <= 1) return [target];

    if (target.startsWith(sourceParts.first) &&
        target.length > sourceParts.first.length) {
      return [
        sourceParts.first,
        target.substring(sourceParts.first.length),
      ];
    }

    final totalSourceLength =
        sourceParts.fold<int>(0, (sum, part) => sum + part.length);
    if (target.length == totalSourceLength) {
      final parts = <String>[];
      int start = 0;
      for (final sourcePart in sourceParts) {
        final end = start + sourcePart.length;
        parts.add(target.substring(start, end));
        start = end;
      }
      return parts;
    }

    return [target];
  }

  static List<String> _splitNameLikeText(String text) {
    final separated = _splitByNameSeparators(text);
    if (separated.length > 1) return separated;

    final parts = <String>[];
    final buffer = StringBuffer();
    _NameCharKind? currentKind;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final kind = _nameCharKind(rune);
      if (currentKind != null && kind != currentKind) {
        parts.add(buffer.toString());
        buffer.clear();
      }
      buffer.write(char);
      currentKind = kind;
    }

    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }

    return parts.where((part) => part.trim().isNotEmpty).toList();
  }

  static List<String> _splitByNameSeparators(String text) {
    return text
        .split(RegExp(r'[\s　・･·]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static _NameCharKind _nameCharKind(int rune) {
    if ((rune >= 0x3040 && rune <= 0x309F) ||
        (rune >= 0x30A0 && rune <= 0x30FF)) {
      return _NameCharKind.kana;
    }
    if (rune >= 0x4E00 && rune <= 0x9FFF) {
      return _NameCharKind.cjk;
    }
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x0030 && rune <= 0x0039)) {
      return _NameCharKind.latin;
    }
    return _NameCharKind.other;
  }

  static String _casualizeChineseTranslation(String text) {
    return text
        .replaceAll('您的', '你的')
        .replaceAll('您', '你')
        .replaceAll('阁下', '你')
        .replaceAll('无需', '不用')
        .replaceAll('一同', '一起')
        .replaceAll('若是', '如果')
        .replaceAll('君她们', '君他们');
  }

  static String _stripKnownHonorific(String exactUserName) {
    const suffixes = ['さん', 'ちゃん', 'くん', '君', '様', 'さま', '先生'];
    for (final suffix in suffixes) {
      if (exactUserName.endsWith(suffix)) {
        return exactUserName.substring(0, exactUserName.length - suffix.length);
      }
    }
    return exactUserName;
  }

  static String _casualGreetingFallback(String characterLanguage) {
    if (characterLanguage == 'zh') {
      return '晚上好。这个时间收到你的消息，还挺让人安心的。';
    }
    return 'こんばんは。こんな時間に声をかけてくれるの、少し不思議ですけれど……悪くありませんわ。';
  }

  static bool _isEmotionSupportUserMessage(String userMessage) {
    final text = userMessage.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return false;
    return RegExp(
      r'难过|傷心|想哭|哭了|崩溃|撑不住|焦虑|压力|痛苦|失眠|睡不着|'
      r'怎么办|不知道该怎么办|好累|受不了了|害怕|不安|孤独|寂寞|'
      r'安慰|陪陪|抱抱|心情不好|喘不过气|没有力气',
    ).hasMatch(text);
  }

  // ========================================
  // 日语判定（新增）
  // ========================================
  // 判断文本是否「像日语」：只要含至少一个平假名（ぁ-ゖ）或片假名（ァ-ヺ），就视为日语。
  // 原因：
  //   - 中文里没有假名，只要出现假名一定不是纯中文
  //   - 任意一句自然日语几乎一定会出现假名（助词、词尾变化、外来语等）
  //   - 偶尔会出现一整句全是汉字的日语（例如「日本語」三个字本身），
  //     但 AI 生成的对话回复几乎不可能全句不含假名，所以这种边缘情况可以接受
  // 这是当前用来判断"翻译是否成功"的最可靠依据。
  static bool _isLikelyJapanese(String text) {
    // 平假名范围：U+3040 ~ U+309F
    // 片假名范围：U+30A0 ~ U+30FF
    return RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text);
  }

  static bool _isCleanJapaneseForTts(String text) {
    if (!_isLikelyJapanese(text)) return false;
    return !_containsChineseResidueInJapanese(text);
  }

  static bool _containsChineseResidueInJapanese(String text) {
    return _japaneseValidationClauses(text).any(_isStructurallyChineseClause);
  }

  static List<String> _japaneseValidationClauses(String text) {
    return text
        .split(RegExp(r'[。！？!?、，；;：:\n\r]+|…+|\.{2,}'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static bool _isStructurallyChineseClause(String clause) {
    final kanaCount = _countPattern(clause, RegExp(r'[\u3040-\u30ffー]'));
    final hanCount = _countPattern(clause, RegExp(r'[\u4e00-\u9fff]'));
    if (hanCount == 0) return false;

    if (kanaCount == 0 && hanCount >= 4) return true;

    final meaningfulCount = kanaCount + hanCount;
    if (meaningfulCount >= 12 && kanaCount / meaningfulCount < 0.18) {
      return true;
    }

    final firstKana = RegExp(r'[\u3040-\u30ffー]').firstMatch(clause);
    if (firstKana == null) return false;

    final leadingText = clause.substring(0, firstKana.start);
    final leadingHanCount =
        _countPattern(leadingText, RegExp(r'[\u4e00-\u9fff]'));
    return leadingHanCount >= 7;
  }

  static int _countPattern(String text, RegExp pattern) {
    return pattern.allMatches(text).length;
  }

  static Future<String> _normalizeJapaneseOrthographyIfUseful(
    String text,
    String? exactUserName,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_isLikelyJapanese(trimmed)) return text;

    final protectedText = _protectCanonicalJapaneseNames(trimmed);
    final normalized = await _normalizeJapaneseOrthography(protectedText.text);
    if (normalized.isEmpty || !_isLikelyJapanese(normalized)) {
      return text;
    }

    final restored = _restoreProtectedMappedNames(
      normalized,
      protectedText.placeholders,
    );
    return _applyStandardJapaneseNameSpellings(
      _sanitizeUserNameHonorifics(restored, exactUserName),
    );
  }

  static _ProtectedTranslationText _protectCanonicalJapaneseNames(String text) {
    var protectedText = text;
    final placeholders = <String, String>{};
    final names = _nameEntries
        .map((entry) => entry.japanese)
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final name in names) {
      if (!protectedText.contains(name)) continue;

      final placeholder = '__CANON_JP_NAME_${placeholders.length}__';
      final replaced = _replaceNameTerm(protectedText, name, placeholder);
      if (replaced == protectedText) continue;

      protectedText = replaced;
      placeholders[placeholder] = name;
    }

    return _ProtectedTranslationText(
      text: protectedText,
      placeholders: placeholders,
    );
  }

  static Future<String> _normalizeJapaneseOrthography(
      String japaneseText) async {
    try {
      final response = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': [
            {
              'role': 'system',
              'content': 'あなたは日本語表記の校正者です。\n'
                  '入力文の意味、話し方、敬語、語尾、改行、記号を保ったまま、日本語として自然な表記に整えてください。\n'
                  '日本語文の中に中国語の字形や中国語の語句が混じっている場合は、日本語の標準的な漢字表記と自然な日本語表現に直してください。\n'
                  'すでに自然な日本語なら、できるだけそのまま返してください。\n'
                  '出力は修正後の日本語本文のみ。説明、注釈、引用符、翻訳文は出力しないでください。',
            },
            {
              'role': 'user',
              'content': japaneseText,
            },
          ],
          'max_tokens': 1000,
          'temperature': 0.0,
          'stream': false,
          'top_p': 0.9,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.0,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('日语表记规范化 API 错误: ${response.statusCode}');
        debugPrint('错误内容: ${response.body}');
        return '';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return (data['choices'][0]['message']['content'] as String)
          .replaceAll('```', '')
          .trim();
    } catch (e) {
      debugPrint('日语表记规范化异常: $e');
      return '';
    }
  }

  // ========================================
  // 调用 DeepSeek 把中文翻译成日语
  // ========================================
  // 调用方：generateResponse 内部，在判定回复非日语时使用。
  // 改动点：
  //   - 增加了对返回内容的清洗（去掉可能残留的代码块、前缀说明等）
  //   - 把 system prompt 改为更明确的指令，要求只返回日语本体
  //   - 不再在异常时静默返回原中文，而是返回空字符串，
  //     由外层 generateResponse 的 _isLikelyJapanese 校验决定是否重试或兜底，
  //     彻底杜绝把中文继续传给 TTS 的可能
  static Future<String> _translateToJapanese(String chineseText) async {
    try {
      final protectedText =
          _protectMappedNamesForJapaneseTranslation(chineseText);
      final response = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'thinking': {'type': 'disabled'},
          'messages': [
            {
              'role': 'system',
              'content': 'あなたはプロの中日翻訳者です。\n'
                  'ユーザーが入力した中国語のテキストを、自然で口語的な日本語に翻訳してください。\n'
                  '\n'
                  '厳守事項:\n'
                  '1. 出力は日本語のみ。中国語の文字、説明、注釈、コードブロック、引用符を一切含めないこと。\n'
                  '2. 「翻訳:」「日本語:」のような前置きを付けない。翻訳本文のみを出力する。\n'
                  '3. 元のテキストに括弧書きの動作描写（例:（笑顔で））がある場合は日本語の括弧で残してよい。\n'
                  '4. 必ず平仮名または片仮名を含む自然な日本語で出力すること。\n'
                  '5. __JP_NAME_0__ のような占位符が含まれる場合は、翻訳せず、そのまま残すこと。',
            },
            {
              'role': 'user',
              'content': protectedText.text,
            },
          ],
          'max_tokens': 1000,
          'temperature': 0.3,
          'stream': false,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String result = data['choices'][0]['message']['content'] as String;
        // 清理模型有时会返回的 markdown 代码块标记和常见前缀
        // 即使 system prompt 已经禁止，仍偶发出现，这里再兜一层
        result = result
            .replaceAll('```japanese', '')
            .replaceAll('```ja', '')
            .replaceAll('```', '')
            .trim();
        // 去掉一些可能的中文前缀（如「翻译：」「日文：」）
        // 只在开头匹配，避免误删正文里的内容
        result = result.replaceFirst(RegExp(r'^(翻訳|翻译|日本語|日文|译文)[:：]\s*'), '');
        result = _restoreProtectedMappedNames(
          result,
          protectedText.placeholders,
        );
        result =
            _applyStandardJapaneseNameSpellings(_removeRubyReadings(result));
        return result.trim();
      } else {
        debugPrint('日文转换 API 错误: ${response.statusCode}');
        debugPrint('错误内容: ${response.body}');
      }
    } catch (e) {
      debugPrint('日文转换失败: $e');
    }
    // 失败时返回空字符串而不是原中文。
    // 外层 generateResponse 会用 _isLikelyJapanese 判断这个空串"不是日语"，
    // 进入下一次重试或兜底文案，从而保证最终一定是日语进 TTS。
    return '';
  }

  static String _removeChinese(String text) {
    final chineseBracketPattern = RegExp(r'（[^）]*[\u4e00-\u9fff][^）]*）');
    String result = text.replaceAll(chineseBracketPattern, '').trim();
    if (result.isEmpty) return text;
    return result;
  }

  // ========================================
  // 图片理解：调用豆包视觉模型
  // ========================================
  static Future<String> _describeImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('图片文件不存在: $imagePath');
        return '';
      }

      final bytes = await file.readAsBytes();
      final String b64 = base64Encode(bytes);

      final ext = imagePath.toLowerCase().split('.').last;
      final String mime = const {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
          }[ext] ??
          'image/jpeg';

      const String visionPrompt = '请用简洁的中文描述这张图片的内容，包括主要对象、场景、活动、氛围等，'
          '100字以内，只描述看到的内容，不分析不评价。';

      final response = await http.post(
        Uri.parse('$doubaoVisionBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoVisionApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoVisionEndpoint,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$b64'},
                },
                {
                  'type': 'text',
                  'text': visionPrompt,
                },
              ],
            },
          ],
          'max_tokens': 200,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final String desc =
            (data['choices'][0]['message']['content'] as String?) ?? '';
        return desc.trim();
      } else {
        debugPrint('豆包视觉模型错误 ${response.statusCode}: ${response.body}');
        return '';
      }
    } catch (e) {
      debugPrint('图片理解失败: $e');
      return '';
    }
  }
}

class _ProtectedTranslationText {
  final String text;
  final Map<String, String> placeholders;

  const _ProtectedTranslationText({
    required this.text,
    required this.placeholders,
  });
}

class _NameEntry {
  final String japanese;
  final String chinese;
  final List<String> japaneseAliases;
  final List<String> chineseAliases;

  const _NameEntry({
    required this.japanese,
    required this.chinese,
    this.japaneseAliases = const [],
    this.chineseAliases = const [],
  });
}

enum _NameCharKind { cjk, kana, latin, other }
