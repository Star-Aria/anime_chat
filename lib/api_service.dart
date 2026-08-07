import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';
import 'api_keys.dart';
import 'grounding_contract.dart';
import 'name_pronunciation.dart';
import 'path_service.dart';

class ApiService {
  static const String deepSeekApiKey = ApiKeys.deepseekApiKey;

  static const String deepSeekModel = 'deepseek-v4-flash';

  static const String deepSeekBaseUrl = 'https://api.deepseek.com/v1';

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
  // _maxTranslationRetries：日语角色化翻译未通过本地门禁时最多尝试几次。
  //   网络抖动、API 偶发返回奇怪格式（如返回中文、返回空、返回带 markdown 的内容）时，
  //   会自动再调用一次翻译 API。为控制延迟和额度，当前最多尝试 2 次。
  // _japaneseFallbackTextForCharacter：所有重试都失败后按角色语体兜底。
  //   存在的意义是：宁可让 AI 随便说一句日语兜底，也绝不能把中文塞给 TTS（GPT-SoVITS）
  //   导致语音乱掉、字幕也是中文。如果想换文案，改这里即可，但必须是纯日语。
  static const int _maxTranslationRetries = 2;

  static const Map<String, List<_CharacterCallName>>
      _fixedCharacterCallNameEntries = {
    'sakiko': [
      _CharacterCallName('高松灯', '灯', '燈'),
      _CharacterCallName('长崎爽世', '爽世', 'そよ'),
      _CharacterCallName('若叶睦', '睦', '睦'),
      _CharacterCallName('三角初音', '初音', '初音'),
      _CharacterCallName('八幡海铃', '海铃', '海鈴'),
      _CharacterCallName('祐天寺若麦', '若麦', 'にゃむ'),
      _CharacterCallName('千早爱音', '爱音同学', '愛音さん'),
      _CharacterCallName('椎名立希', '立希', '立希'),
      _CharacterCallName('要乐奈', '乐奈同学', '楽奈さん'),
      _CharacterCallName('纯田真奈', '真奈同学', 'まなさん'),
    ],
    'tomori': [
      _CharacterCallName('丰川祥子', '小祥', '祥ちゃん'),
      _CharacterCallName('长崎爽世', '爽世酱', 'そよちゃん'),
      _CharacterCallName('千早爱音', '小爱', 'あのちゃん'),
      _CharacterCallName('椎名立希', '立希酱', '立希ちゃん'),
      _CharacterCallName('要乐奈', '乐奈酱', '楽奈ちゃん'),
      _CharacterCallName('若叶睦', '小睦', '睦ちゃん'),
      _CharacterCallName('三角初华', '初华酱', '初華ちゃん'),
      _CharacterCallName('三角初音', '初华酱', '初華ちゃん'),
    ],
    'shinobu': [
      _CharacterCallName('栗花落香奈乎', '香奈乎', 'カナヲ'),
      _CharacterCallName('灶门炭治郎', '炭治郎君', '炭治郎くん'),
      _CharacterCallName('灶门祢豆子', '祢豆子小姐', '禰豆子さん'),
      _CharacterCallName('我妻善逸', '善逸君', '善逸くん'),
      _CharacterCallName('嘴平伊之助', '伊之助君', '伊之助くん'),
      _CharacterCallName('富冈义勇', '富冈先生', '冨岡さん'),
      _CharacterCallName('悲鸣屿行冥', '悲鸣屿先生', '悲鳴嶼さん'),
      _CharacterCallName('不死川实弥', '不死川先生', '不死川さん'),
      _CharacterCallName('伊黑小芭内', '伊黑先生', '伊黒さん'),
      _CharacterCallName('甘露寺蜜璃', '甘露寺小姐', '甘露寺さん'),
      _CharacterCallName('宇髄天元', '宇髄先生', '宇髄さん'),
      _CharacterCallName('炼狱杏寿郎', '炼狱先生', '煉獄さん'),
      _CharacterCallName('时透无一郎', '时透君', '時透くん'),
      _CharacterCallName('产屋敷耀哉', '主公大人', 'お館様'),
    ],
    'muichirou': [
      _CharacterCallName('灶门炭治郎', '炭治郎', '炭治郎'),
      _CharacterCallName('灶门祢豆子', '祢豆子', '禰豆子'),
      _CharacterCallName('我妻善逸', '善逸', '善逸'),
      _CharacterCallName('嘴平伊之助', '伊之助', '伊之助'),
      _CharacterCallName('富冈义勇', '富冈先生', '冨岡さん'),
      _CharacterCallName('蝴蝶忍', '蝴蝶小姐', '胡蝶さん'),
      _CharacterCallName('悲鸣屿行冥', '悲鸣屿先生', '悲鳴嶼さん'),
      _CharacterCallName('不死川实弥', '不死川先生', '不死川さん'),
      _CharacterCallName('伊黑小芭内', '伊黑先生', '伊黒さん'),
      _CharacterCallName('甘露寺蜜璃', '甘露寺小姐', '甘露寺さん'),
      _CharacterCallName('宇髄天元', '宇髄先生', '宇髄さん'),
      _CharacterCallName('炼狱杏寿郎', '炼狱先生', '煉獄さん'),
      _CharacterCallName('产屋敷耀哉', '主公大人', 'お館様'),
    ],
    'giyu': [
      _CharacterCallName('灶门炭治郎', '炭治郎', '炭治郎'),
      _CharacterCallName('灶门祢豆子', '祢豆子', '禰豆子'),
      _CharacterCallName('我妻善逸', '善逸', '善逸'),
      _CharacterCallName('嘴平伊之助', '伊之助', '伊之助'),
      _CharacterCallName('蝴蝶忍', '蝴蝶', '胡蝶'),
      _CharacterCallName('悲鸣屿行冥', '悲鸣屿', '悲鳴嶼'),
      _CharacterCallName('不死川实弥', '不死川', '不死川'),
      _CharacterCallName('伊黑小芭内', '伊黑', '伊黒'),
      _CharacterCallName('甘露寺蜜璃', '甘露寺', '甘露寺'),
      _CharacterCallName('宇髄天元', '宇髄', '宇髄'),
      _CharacterCallName('炼狱杏寿郎', '炼狱', '煉獄'),
      _CharacterCallName('时透无一郎', '时透', '時透'),
      _CharacterCallName('产屋敷耀哉', '主公大人', 'お館様'),
    ],
  };

  static Map<String, Map<String, String>> get _fixedCharacterCallNameMap => {
        for (final entry in _fixedCharacterCallNameEntries.entries)
          entry.key: {
            for (final callName in entry.value)
              callName.fullName: callName.japaneseCallName,
          },
      };

  static Map<String, Map<String, String>>
      get _fixedCharacterChineseCallNameMap => {
            for (final entry in _fixedCharacterCallNameEntries.entries)
              entry.key: {
                for (final callName in entry.value)
                  callName.fullName: callName.chineseCallName,
              },
          };

  static const Map<String, _CharacterSpeechNameProfile>
      _characterSpeechNameProfiles = {
    'shinobu': _CharacterSpeechNameProfile(
      chineseSelfPronoun: '我',
      japaneseSelfPronoun: '私',
      forbiddenJapaneseSelfPronouns: ['俺', 'オレ', 'おれ', '僕', 'ぼく'],
    ),
    'muichirou': _CharacterSpeechNameProfile(
      chineseSelfPronoun: '我',
      japaneseSelfPronoun: '僕',
      forbiddenJapaneseSelfPronouns: ['俺', 'オレ', 'おれ', '私', 'わたし'],
    ),
    'giyu': _CharacterSpeechNameProfile(
      chineseSelfPronoun: '我',
      japaneseSelfPronoun: '俺',
      forbiddenJapaneseSelfPronouns: ['僕', 'ぼく', '私', 'わたし'],
    ),
    'sakiko': _CharacterSpeechNameProfile(
      chineseSelfPronoun: '我',
      japaneseSelfPronoun: '私',
      forbiddenJapaneseSelfPronouns: ['俺', 'オレ', 'おれ', '僕', 'ぼく'],
    ),
    'tomori': _CharacterSpeechNameProfile(
      chineseSelfPronoun: '我',
      japaneseSelfPronoun: '私',
      forbiddenJapaneseSelfPronouns: ['俺', 'オレ', 'おれ', '僕', 'ぼく'],
    ),
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
    for (final entry in characterNamePronunciations) {
      add(entry.chinese);
      for (final alias in entry.chineseAliases) {
        add(alias);
      }
    }
    for (final name in canonTermNamesForSearch) {
      add(name);
    }

    return names;
  }

  static Map<String, String> characterSearchAliasesForSearch({
    String? characterId,
  }) {
    final aliases = <String, String>{};
    void add(String alias, String target) {
      final source = alias.trim();
      final compactTarget = target.replaceAll(RegExp(r'[\s　]+'), '').trim();
      if (source.length < 2 || compactTarget.length < 2) return;
      aliases.putIfAbsent(source, () => compactTarget);
    }

    for (final entry in characterNamePronunciations) {
      for (final alias in entry.searchAliases) {
        add(alias, entry.chinese);
      }
    }
    return Map.unmodifiable(aliases);
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
    final configuredChinese = _fixedCharacterChineseCallNameMap[characterId];
    return Map.unmodifiable({
      for (final entry in configured.entries)
        entry.key: configuredChinese?[entry.key] ??
            _callNameChineseTarget(entry.key, entry.value),
    });
  }

  @visibleForTesting
  static String applyJapaneseNameMappingsForTest(
    String chineseText, {
    String? characterId,
  }) {
    final fixedCallNames = fixedCharacterCallNamesForCharacter(characterId);
    final fixedChineseCallNames = _fixedCharacterChineseCallNames(
      fixedCallNames,
      characterId: characterId,
    );
    final protectedText = _protectMappedNamesForJapaneseTranslation(
      chineseText,
      fixedCharacterCallNames: fixedCallNames,
      fixedChineseCallNames: fixedChineseCallNames,
    );
    final restored = _restoreProtectedMappedNames(
      protectedText.text,
      protectedText.placeholders,
    );
    return _applyFixedCharacterCallNames(
      _applyStandardJapaneseNameSpellings(restored),
      fixedCallNames,
      fixedChineseCallNames,
    );
  }

  static List<String> nameTranslationGlossaryForPrompt() {
    final lines = <String>[];
    void addLine(String source, String chinese) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) return;
      final line = '$trimmed=$chinese';
      if (!lines.contains(line)) lines.add(line);
    }

    for (final entry in characterNamePronunciations) {
      addLine(entry.japanese, entry.chinese);
      addLine(entry.compactJapanese, entry.chinese);
      addLine(entry.reading, entry.chinese);
      for (final alias in entry.aliases.entries) {
        addLine(
          alias.key,
          _preservesCharacterAliasDisplay(alias.key)
              ? alias.key
              : entry.chinese,
        );
      }
      for (final alias in entry.chineseAliases) {
        addLine(alias, entry.chinese);
      }
    }
    for (final entry in termNamePronunciations) {
      addLine(entry.japanese, entry.chinese);
      addLine(entry.compactJapanese, entry.chinese);
      addLine(entry.reading, entry.chinese);
      for (final variant in entry.romanizedReadingVariants) {
        addLine(variant, entry.chinese);
      }
      for (final alias in entry.aliases.keys) {
        addLine(alias, entry.chinese);
      }
    }
    return lines;
  }

  static String normalizeKnownNamesForChineseText(String text) {
    var result = text;
    for (final entry in characterNamePronunciations) {
      for (final source in {
        entry.japanese,
        entry.compactJapanese,
        entry.reading,
        for (final alias in entry.aliases.keys)
          if (!_preservesCharacterAliasDisplay(alias)) alias,
        ...entry.chineseAliases,
      }) {
        if (source.isEmpty || source == entry.chinese) continue;
        result = result.replaceAll(source, entry.chinese);
      }
    }
    for (final entry in termNamePronunciations) {
      for (final source in {
        entry.japanese,
        entry.compactJapanese,
        entry.reading,
        ...entry.romanizedReadingVariants,
        for (final alias in entry.aliases.keys)
          if (!entry.japanese.contains(alias)) alias,
      }) {
        if (source.isEmpty || source == entry.chinese) continue;
        result = result.replaceAll(source, entry.chinese);
      }
    }
    return result;
  }

  static String nameSearchMatchKey(String text) {
    return _cjkLooseMatchKey(text).replaceAll(RegExp(r'[\s　]+'), '');
  }

  static bool _preservesCharacterAliasDisplay(String alias) {
    return RegExp(r'[A-Za-z]').hasMatch(alias);
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
  // 日语角色：先生成中文角色回答，再进行受约束的日语角色化翻译，
  //           返回 {'japanese': <日文>, 'chinese': <中文原稿>}
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
      final timelineAnswerContract =
          _TimelineAnswerContract.fromWebContext(webContext);
      final allowsBoundedRoleplay =
          (webContext?.contains('【有限角色发挥】') ?? false) ||
              (webContext?.contains('【明确设定与有限发挥并存】') ?? false);

      final StringBuffer systemBuffer = StringBuffer();
      systemBuffer.write(characterPersonality);
      final exactUserName = _extractExactUserName(characterPersonality);
      final translatedUserName =
          _extractTranslatedUserName(characterPersonality);
      final fixedCharacterCallNames = _fixedCharacterCallNames(
        characterPersonality,
        characterId: characterId,
      );
      final fixedChineseCallNames = _fixedCharacterChineseCallNames(
        fixedCharacterCallNames,
        characterId: characterId,
      );

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
- 如果本轮资料明确包含【有限角色发挥】，上一条只限制真实候选和事实边界：可以从摘要明确给出的候选中，以角色第一人称自然表达自己的选择、习惯、偏好、感受或评价，不需要网页直接写出这句主观回答。不得创造摘要中没有的专名、能力、经历或因果，也不要向用户提及“资料没有写/搜索结果没有说明”。
- 如果本轮资料明确包含【明确原作设定优先】，必须直接采用资料中已经明确给出的喜好、习惯、频率或评价依据；角色化发挥只能补充自然语气，不能另选答案或弱化该设定。
- 如果本轮资料包含【明确设定与有限发挥并存】，明确 facts 必须直接采用；标为候选范围的 facts 可以用于自然表达倾向，但不得反过来覆盖、否定或改写明确 facts。
- 联网证据中的动画/游戏集数、章节、资料页、设定集等只用于核对事实。角色回答只能自然讲作品世界内发生的事，不得说“动画第几集、游戏剧情、资料记载、页面提到”等三次元出处。
- 用户问“叫什么/名字/是谁/有哪些人”时，优先只回答被问对象的名字和必要身份；不要顺手展开同一网页里的相邻人物、管理者、亲属、后续经历或旁支设定。
- 用户提到“我喜欢/我们家有/我最近在看”等自己的喜好或经历时，不等于当前角色也有同样喜好或经历；除非资料明确支持当前角色喜欢同一对象，否则只能回应用户的喜好，不要说“我也喜欢”。
- 如果资料没有明确写出当前角色对用户所提对象的喜恶，不要替角色评价“也不错/很可爱/挺喜欢/不讨厌/讨厌”；只能说“你喜欢的话也很好”“听起来很有意思”这类不声明角色偏好的回应。
- 如果用户一条消息同时问多个事实点，比如“喜欢什么动物”和“闲暇常去哪里”，必须逐一回答每个事实点；要合并使用【网页搜索摘要】和【角色设定资料】，不要只回答第一项。
- 歌曲相关回答必须区分作品内事实和三次元使用信息：如果角色设定里当前角色负责作曲/创作，可以用第一人称谈创作；但不得让作品角色提到“这首歌被用作动画片头/片尾、现实发售、厂牌、特典、演唱会、榜单”等三次元信息，除非用户明确在问现实发行或动画制作信息。
- 歌曲名、乐队名、专有标题如果资料中以英文/罗马字出现，最终回复应保留原文表记，不要擅自音译成片假名或中文。
- 如果用户询问某个事件“如何/怎么/经过”，回复要围绕用户问的动作目标筛选事实。只挑 2 到 4 个最相关的核心动作自然回答；不要因为资料或时间线里有后续事件，就把审判、冲突、结局等无关后续全部讲出来。
- 如果用户问“如何支援/救援/协助/处理”，不要主动复述和支援目标相反的后续冲突、审判或结局补充；除非用户明确追问这些后续。
- 联网事实中人物姓名后的“（男）/（女）”只是性别指代参考，任何最终角色回答都不得把这个括号标注读出来或写出来。
- 如果用户询问人物关系、相互影响、救赎、关系变化或一段经历，不要只做抽象评价；从资料中挑能体现关系变化的核心转折自然回答，再给出角色自己的感受。
- 对人物关系、相互影响、救赎、关系变化类问题，优先选择真正改变双方处境或关系的核心转折。问题明确询问双向作用时，必须分别用至少一个具体事实说明双方各自带来的影响；背景铺垫不得挤掉其中任何一方。资料里有明确地点、行动、台词或作品名时，优先使用这些事实锚点，不要只用抽象概括，也不要用无关旁支替代核心转折。
- “去过某地点/某集出现某地点/去看某物”不等于“闲暇常去某地点”；只有资料明确写出兴趣、闲暇、常去、经常、休息日等习惯语义时，才能说成常去地点。
''');
      }

      if (proactiveInstruction != null && proactiveInstruction.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(proactiveInstruction);
      }

      // 第一阶段始终生成中文角色回答。事实、时间线和人设保持同一语言，
      // 先确定“说什么”，日语角色再在第二阶段独立处理表达。
      systemBuffer.writeln();
      systemBuffer.write('【语言要求】请全程用自然地道的中文回复，不要使用日语或其他语言。'
          '称呼用户时使用自然亲近的“你”，不要使用“您”。'
          '整体使用现代口语聊天表达，不要使用偏文言或过度书面化的连接词。');
      final chineseSpeechNameInstruction =
          _chineseSpeechNameInstruction(characterId);
      if (chineseSpeechNameInstruction.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(chineseSpeechNameInstruction);
      }
      if (fixedChineseCallNames.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write('【人物的称呼】提到以下人物时，必须使用指定的中文称呼，'
            '不要擅自换成其他昵称或敬称。\n');
        for (final entry in fixedChineseCallNames.entries) {
          systemBuffer.writeln('- ${entry.key}：${entry.value}');
        }
      }

      systemBuffer.writeln();
      systemBuffer.write('''
【情绪感知回复规则】

当用户的消息中明显出现以下任意一种情况时，进入更深度的「情绪支持模式」：
- 表达情绪低落、难过、哭泣、心情不好
- 表达焦虑、压力大、喘不过气、睡不着
- 表达迷茫、不知道该怎么办、感到无力、忙到撑不住、累到没力气
- 主动倾诉烦恼、困境或内心困扰
- 希望被安慰、被理解、被倾听
- 寻求建议或解决办法

进入「情绪支持模式」后，必须遵守以下规则：
1. 回复长度要比平时聊天明显更长，充分回应对方的情绪，不要三言两语带过
2. 先共情、后引导：先让对方感到被理解和接纳，再给出温和的建议或鼓励
3. 不要说教，不要急着给解决方案，重点是陪伴和倾听的感觉；可以保留角色的理性判断，但先接住情绪，再轻轻点一句
4. 语气要比普通分析更软一点，可以自然使用少量缓冲词和语气词，比如“嗯”“好了”“先别急”“好不好”“知道了”，但不要变成撒娇或客服话术
5. 如果对方说的烦恼比较具体，可以追问细节，表现出真正在意的样子
6. 全程保持你自己角色的说话方式和性格，不要变成机械助手的语气
7. 可以联系你和对方的关系、你自己的经历来表达共鸣，让安慰更真实有温度

未进入「情绪支持模式」时（即普通日常聊天），完全忽略以上规则，按平时正常方式回复。
''');

      systemBuffer.writeln();
      systemBuffer.write(isEmotionSupportTurn
          ? '【本轮回复篇幅】用户本轮明显在表达情绪困扰，可以适度写长，但不要为了显得体贴而重复同一层意思。'
          : isRelationshipArcTurn
              ? '【本轮回复篇幅】用户本轮在问关系变化。用4到7句讲清主要变化和感受，不要为了覆盖资料而继续展开。'
              : isEventProcessTurn
                  ? '【本轮回复篇幅】用户本轮在问事件经过或处理方式。用4到6句挑最相关的核心动作回答，不要从头到尾念资料。'
                  : '【本轮回复篇幅】用户本轮不是情绪倾诉。请用日常聊天篇幅回复，控制在3到6句左右。');
      systemBuffer.writeln();
      systemBuffer.write('''
【中文原稿表达方式】
- 这是会话气泡里的角色回答，不是资料总结、小说旁白或舞台剧脚本。
- 先回应用户真正问的内容，再选少量最相关的细节和感受自然聊开；不要因为 facts 很多就逐条使用。
- 按适合翻成自然日语口语的短句节奏组织中文，不要写成过度铺陈、排比或抒情的中文网文腔。
- 动作或神态描写默认不必添加。如果它确实能表现当下情绪，整段最多保留一处简短的括号描写，不要连续穿插舞台指示。
''');
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
      if (timelineAnswerContract == null) {
        systemBuffer.write('【最终输出语言】只输出中文回复正文。');
      } else {
        systemBuffer.write(timelineAnswerContract.outputInstruction);
      }

      final List<Map<String, String>> responseMessages = [
        {
          'role': 'system',
          'content': systemBuffer.toString(),
        },
      ];

      responseMessages.addAll(conversationHistory.map((msg) {
        String content = msg.content;
        if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
          content = content.split('\n\n中文：').last;
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
              characterId: characterId,
              allowsBoundedRoleplay: allowsBoundedRoleplay,
            );

      responseMessages.add(
        proactiveInstruction != null
            ? {'role': 'user', 'content': ''}
            : {'role': 'user', 'content': currentUserContent},
      );
      final hasGroundingContext = webContext != null && webContext.isNotEmpty;

      final response = await http.post(
        Uri.parse('$deepSeekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepSeekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepSeekModel,
          'thinking': {'type': 'disabled'},
          'messages': responseMessages,
          'max_tokens': 1000,
          'temperature': hasGroundingContext ? 0.55 : 0.8,
          'stream': false,
          'top_p': hasGroundingContext ? 0.8 : 0.9,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.0,
          if (timelineAnswerContract != null)
            'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('DeepSeek API 错误: ${response.statusCode}');
        debugPrint('错误内容: ${response.body}');
        return {'japanese': '申し訳ございません...', 'chinese': '抱歉，我现在无法回答...'};
      }

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));
      String rawResponseText =
          responseData['choices'][0]['message']['content'] as String;
      rawResponseText =
          _sanitizeUserNameHonorifics(rawResponseText, exactUserName);

      if (timelineAnswerContract != null) {
        rawResponseText = await _resolveTimelineConstrainedAnswer(
          messages: responseMessages,
          rawResponse: rawResponseText,
          contract: timelineAnswerContract,
          exactUserName: exactUserName,
        );
      }

      if (_weatherContextForbidsRain(webContext) &&
          _containsProhibitedRainClaim(rawResponseText)) {
        debugPrint(
          '检测到回复违背实时天气上下文，自动重试生成天气回复: '
          '${_logPreview(rawResponseText)}',
        );
        rawResponseText = await _retryWeatherGroundedResponse(
          messages: responseMessages,
          badResponse: rawResponseText,
          characterLanguage: 'zh',
          exactUserName: exactUserName,
        );
      }

      if (_containsAssistantLikeGreetingQuestion(rawResponseText)) {
        debugPrint(
          '检测到助手式客套问句，自动重试生成回复: '
          '${_logPreview(rawResponseText)}',
        );
        responseMessages.add({
          'role': 'assistant',
          'content': rawResponseText,
        });
        responseMessages.add({
          'role': 'user',
          'content': '刚才的回复像客服或助手，并且包含"有什么事吗"这类禁句。'
              '请用中文重新回答：自然回应我的上一句话，不要问我有什么事，不要说有什么需要帮助。',
        });

        final retryResponse = await http.post(
          Uri.parse('$deepSeekBaseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $deepSeekApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': deepSeekModel,
            'thinking': {'type': 'disabled'},
            'messages': responseMessages,
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
            rawResponseText = _casualGreetingFallback('zh');
          }
        } else {
          debugPrint('助手式问句重试 API 错误: ${retryResponse.statusCode}');
          debugPrint('错误内容: ${retryResponse.body}');
          rawResponseText = _casualGreetingFallback('zh');
        }
      }

      if (_weatherContextForbidsSpecificLocation(webContext) &&
          _containsForbiddenWeatherLocation(rawResponseText)) {
        debugPrint(
          '检测到鬼灭天气回复提及具体地点，自动重试: '
          '${_logPreview(rawResponseText)}',
        );
        rawResponseText = await _retryWeatherLocationlessResponse(
          messages: responseMessages,
          badResponse: rawResponseText,
          characterLanguage: 'zh',
          exactUserName: exactUserName,
        );
      }

      rawResponseText = _applyFixedChineseCallNames(
        rawResponseText,
        fixedChineseCallNames,
      );
      rawResponseText = normalizeKnownNamesForChineseText(rawResponseText);
      rawResponseText = _normalizeChineseConversationWording(rawResponseText);

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

      final chineseText = rawResponseText.trim();
      String japaneseText = '';
      for (var attempt = 1; attempt <= _maxTranslationRetries; attempt++) {
        japaneseText = await _translateChineseRoleResponseToJapanese(
          chineseText,
          characterId: characterId,
          exactUserName: exactUserName,
          translatedUserName: translatedUserName,
          fixedCharacterCallNames: fixedCharacterCallNames,
          fixedChineseCallNames: fixedChineseCallNames,
          webContext: webContext,
          isRetry: attempt > 1,
        );
        if (_isAcceptableJapaneseForCharacter(japaneseText, characterId)) {
          break;
        }
        debugPrint(
          '日语角色化翻译未通过本地校验: '
          'attempt=$attempt, '
          'cleanJapanese=${_isCleanJapaneseForTts(japaneseText)}, '
          'baseStyle=${isJapaneseStyleCompatible(japaneseText, characterId)}, '
          'translationStyle=${isJapaneseTranslationStyleCompatible(japaneseText, characterId)}, '
          'text=${_logPreview(japaneseText)}',
        );
      }
      if (!_isAcceptableJapaneseForCharacter(japaneseText, characterId)) {
        debugPrint('日语角色化翻译失败，使用日语兜底文本');
        japaneseText = _japaneseFallbackTextForCharacter(characterId);
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
    String? characterId,
    bool allowsBoundedRoleplay = false,
  }) {
    final baseUserMessage = '$userMessage$imageContext';
    if (webContext == null || webContext.trim().isEmpty) {
      return baseUserMessage;
    }

    final processReminder = _isRelationshipArcQuestion(userMessage)
        ? '\n【本轮写作提醒】用户问的是人物关系、相互影响、救赎或关系变化。不要只取资料开头的一条事实，也不要只做抽象评价；请按时间线优先选择真正改变双方处境或关系的核心转折。问题明确询问双向作用时，必须分别用至少一个具体事实说明双方各自带来的影响，背景铺垫不得挤掉其中任何一方。资料里有明确地点、行动、台词或作品名时优先使用，但不需要把所有资料逐条复述。\n'
        : _isEventProcessQuestion(userMessage)
            ? '\n【本轮写作提醒】用户问的是事件经过、处理方式或支援方式。时间线只用于理解顺序，不是回答清单；请只选2到4个和用户问点直接相关的核心事实，用4到6句日常聊天回答。资料里的后续审判、旁支冲突、结局补充，如果不是用户问点所需，不要主动展开。用户问“如何支援/救援/协助/处理”时，不要主动复述和支援目标相反的后续冲突。\n'
            : '';
    final boundedRoleplayReminder = allowsBoundedRoleplay
        ? '\n【本轮角色发挥提醒】网页摘要负责限定真实候选和事实边界。你可以从摘要明确列出的候选中自然表达角色自己的选择、习惯、偏好、感受或评价；不要创造新专名、新能力、新经历或新因果，也不要说“资料没有写”或“搜索结果没有说明”。\n'
        : '';
    final responseShapeReminder = _isEmotionSupportUserMessage(userMessage)
        ? '\n【本轮表达节奏】可以根据情绪需要适度写长，但不要重复同一层意思。动作或神态括号描写最多一处，也可以不写。\n'
        : _isRelationshipArcQuestion(userMessage)
            ? '\n【本轮表达节奏】最终只写4到7句日常聊天式回答。动作或神态括号描写最多一处，也可以不写；不要为了覆盖所有 facts 继续增加段落。\n'
            : _isEventProcessQuestion(userMessage)
                ? '\n【本轮表达节奏】最终只写4到6句日常聊天式回答。动作或神态括号描写最多一处，也可以不写。\n'
                : '\n【本轮表达节奏】最终只写3到6句日常聊天式回答。动作或神态括号描写最多一处，也可以不写。\n';
    final mediaQuestionReminder = RegExp(
      r'番剧|动画|漫画|电影|电视剧|书影音|歌曲|乐队|作品感想|追番',
      caseSensitive: false,
    ).hasMatch(userMessage)
        ? characterId == 'andy'
            ? '\n【本轮媒体回答提醒】用户在问番剧、动画、漫画、电影、电视剧、歌曲或乐队。Andy 对这类年轻娱乐/二次元话题不算熟，必须允许自己说“不太清楚”“我刚查了一下”“我看了下资料”“只知道个大概”，不要说得像原本就了解。避免“有印象”“刚好看到过”“倒是知道一点”这类像本来熟悉的说法。只讲作品识别、角色/成员、题材、用户感受和自然接话；不要主动提首播、播出、制作人员、厂牌、PV、发售、榜单或演出这类三次元宣传信息。\n'
            : '\n【本轮媒体回答提醒】如果用户在问番剧、动画、漫画、电影、电视剧、歌曲或乐队，先按角色人设判断她是否本来熟悉这个圈子；人设没有明确熟悉时，优先说“不太清楚/刚看了一下/只知道个大概”，不要装作原本就懂。只讲作品识别、角色/成员、题材、感受和自然接话；不要主动提首播、播出、制作人员、厂牌、PV、发售、榜单或演出这类三次元宣传信息。\n'
        : '';

    return '''
【系统提供的本轮实时资料，不是用户发言】
$webContext
【使用要求】
回答本轮用户问题时，必须优先服从上面的实时资料。可以自然融入角色语气，但不要和实时资料相反；不要逐字念出资料来源。
如果实时资料中有【事实时间线】，先按时间线理解事件顺序，再组织角色回复；不要把时间线约束中标明不连续的事件直接写成连续发生。
时间线中相邻节点如果共同构成同一过程，前一节点仅负责转场、追赶或带离现场时，必须结合后一节点记载的实际谈话、行动与结果来表达，否则省略这个过渡节点。后一节点明确写出的归队、和解或关系变化必须保留，不能被前一节点的动作替代。
改写 facts 时必须保持动作的施事意图、移动方向和完成程度。单独一个过渡动作不能被概括成问题已经解决；只有后续事实明确给出结果时，才能写出相应结果。不能从结果反推当事人有意促成，也不能把阶段性接触写成关系状态已经改变。写完后逐句核对所属阶段，不要输出核对过程。
地点、篇章、事件名、人物名、敌人名必须以实时资料为准，不要替换成同作品里另一个相似设定。
如果用户问某个具体事实，而实时资料没有写出对应答案，不要用模型记忆或联想补具体名词；请说明没有明确听说，再说资料中能确认的内容。
如果用户问“叫什么/名字/是谁/有哪些人”，只回答被问对象的名字和必要身份，不要展开同一网页里的相邻人物或旁支设定。
如果用户只是说自己喜欢某个东西，不要把它改写成当前角色也喜欢；只有实时资料明确写出当前角色喜欢，才能说“我也喜欢”。资料没有写出当前角色对这个东西的喜恶时，不要评价“也不错/很可爱/挺喜欢/不讨厌/讨厌”，只能接住用户的喜好。
如果用户问人物关系、相互影响、救赎或关系变化，请优先按实时资料中的时间线回答，选用真正改变双方处境或关系的核心转折。问题明确询问双向作用时，必须分别用至少一个具体事实说明双方各自带来的影响，背景铺垫不得挤掉其中任何一方；不要只给抽象评价。
如果用户问事件经过、处理方式或支援方式，请围绕用户问点筛选事实，不要把时间线里的无关后续都讲出来。

【用户原话】
$baseUserMessage
$processReminder
$boundedRoleplayReminder
$mediaQuestionReminder
$responseShapeReminder
''';
  }

  static Future<String> _resolveTimelineConstrainedAnswer({
    required List<Map<String, String>> messages,
    required String rawResponse,
    required _TimelineAnswerContract contract,
    required String? exactUserName,
  }) async {
    var parsed = contract.parse(rawResponse);
    if (parsed.isValid) {
      debugPrint(
        '中文回答时间线契约通过: '
        'sentences=${parsed.sentenceCount}, refs=${parsed.references.join('>')}',
      );
      return parsed.text;
    }

    debugPrint('中文回答时间线契约未通过，使用同一上下文修正一次: ${parsed.issue}');
    try {
      final retryMessages = <Map<String, String>>[
        ...messages,
        {'role': 'assistant', 'content': rawResponse},
        {
          'role': 'user',
          'content': '刚才的输出没有通过时间线结构校验：${parsed.issue}。'
              '请重新输出同一回答，不要增加新事实。每个事实句都要引用其实际依据的时间线编号，'
              '句子和编号必须共同保持时间先后顺序。只输出规定的 JSON 对象。',
        },
      ];
      final response = await http.post(
        Uri.parse('$deepSeekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepSeekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepSeekModel,
          'thinking': {'type': 'disabled'},
          'messages': retryMessages,
          'max_tokens': 1000,
          'temperature': 0.2,
          'stream': false,
          'response_format': {'type': 'json_object'},
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final retryRaw = '${data['choices']?[0]?['message']?['content'] ?? ''}';
        parsed = contract.parse(
          _sanitizeUserNameHonorifics(retryRaw, exactUserName),
        );
        if (parsed.isValid) {
          debugPrint(
            '中文回答时间线契约修正通过: '
            'sentences=${parsed.sentenceCount}, refs=${parsed.references.join('>')}',
          );
          return parsed.text;
        }
        debugPrint('中文回答时间线契约修正仍未通过: ${parsed.issue}');
      } else {
        debugPrint('中文回答时间线契约修正 API 错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('中文回答时间线契约修正失败: $e');
    }

    return _timelineContractFallback();
  }

  static String _timelineContractFallback() =>
      '嗯，这件事的前后经过有些复杂。我确实有所耳闻，不过不想把其中的顺序说错，还是不随意拼凑细节了。';

  @visibleForTesting
  static String? parseTimelineAnswerForTest({
    required String webContext,
    required String response,
  }) {
    final contract = _TimelineAnswerContract.fromWebContext(webContext);
    if (contract == null) return null;
    final parsed = contract.parse(response);
    return parsed.isValid ? parsed.text : null;
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
        Uri.parse('$deepSeekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepSeekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepSeekModel,
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
        Uri.parse('$deepSeekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepSeekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepSeekModel,
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

  @visibleForTesting
  static String stripActionDescriptionsForTest(String text) {
    return _stripActionDescriptions(text);
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
    Map<String, String> fixedChineseCallNames,
  ) {
    if (text.isEmpty || fixedCharacterCallNames.isEmpty) return text;

    var result = text;
    final entries = fixedChineseCallNames.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in entries) {
      final chineseCallName = entry.value.trim();
      final callName = fixedCharacterCallNames[entry.key]?.trim() ?? '';
      if (chineseCallName.isEmpty || callName.isEmpty) continue;
      final protectedFullNames = <String>{
        entry.key.trim(),
        _applyStandardJapaneseNameSpellings(entry.key.trim()),
      }.where((value) => value.isNotEmpty).toSet();

      final variants = <String>{
        chineseCallName,
        _applyStandardJapaneseNameSpellings(chineseCallName),
      }.where((value) => value.isNotEmpty && value != callName).toList()
        ..sort((a, b) => b.length.compareTo(a.length));

      for (final variant in variants) {
        for (final suffix in _knownJapaneseHonorifics) {
          result = _replaceCallNameVariant(
            result,
            '$variant$suffix',
            callName,
            protectedFullNames,
          );
        }
        result = _replaceCallNameVariant(
          result,
          variant,
          callName,
          protectedFullNames,
        );
      }

      if (_endsWithKnownHonorific(callName)) {
        for (final suffix in _knownJapaneseHonorifics) {
          if (callName.endsWith(suffix)) {
            result = _replaceCallNameVariant(
              result,
              '$callName$suffix',
              callName,
              protectedFullNames,
            );
          }
        }
      } else {
        for (final suffix in _knownJapaneseHonorifics) {
          result = _replaceCallNameVariant(
            result,
            '$callName$suffix',
            callName,
            protectedFullNames,
          );
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

  static String _normalizeChineseConversationWording(String text) {
    return text.replaceAll('您', '你').replaceAll('若是', '要是');
  }

  @visibleForTesting
  static String normalizeChineseConversationWordingForTest(String text) {
    return _normalizeChineseConversationWording(text);
  }

  static String _chineseSpeechNameInstruction(String? characterId) {
    final profile = _characterSpeechNameProfiles[characterId];
    if (profile == null) return '';
    return '【角色自称与用户称呼】角色提到自己时使用“${profile.chineseSelfPronoun}”。'
        '称呼用户时使用“你”，不要使用“您”。';
  }

  static String _japaneseSelfPronounInstruction(String? characterId) {
    final profile = _characterSpeechNameProfiles[characterId];
    if (profile == null) return '';
    return '中国語原文の「${profile.chineseSelfPronoun}」が話者自身を指す場合、'
        '日本語では必ず「${profile.japaneseSelfPronoun}」として訳してください。'
        '「${profile.forbiddenJapaneseSelfPronouns.join('」「')}」は使わないでください。';
  }

  static _ProtectedTranslationText _protectMappedNamesForJapaneseTranslation(
    String text, {
    String? exactUserName,
    String? translatedUserName,
    Map<String, String> fixedCharacterCallNames = const {},
    Map<String, String> fixedChineseCallNames = const {},
  }) {
    var protectedText = text;
    final placeholders = <String, String>{};
    final nameMap = <String, String>{};

    if (exactUserName != null && exactUserName.trim().isNotEmpty) {
      nameMap[exactUserName.trim()] = exactUserName.trim();
      if (translatedUserName != null && translatedUserName.trim().isNotEmpty) {
        nameMap[translatedUserName.trim()] = exactUserName.trim();
      }
    }

    for (final entry in fixedChineseCallNames.entries) {
      final displayName = entry.key.trim();
      final chineseCallName = entry.value.trim();
      final japaneseCallName = fixedCharacterCallNames[displayName]?.trim();
      if (chineseCallName.isEmpty ||
          japaneseCallName == null ||
          japaneseCallName.isEmpty) {
        continue;
      }
      nameMap[chineseCallName] = japaneseCallName;
    }

    for (final entry in _chineseToJapaneseNameMap().entries) {
      nameMap.putIfAbsent(entry.key, () => entry.value);
    }

    final entries = nameMap.entries.toList()
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

  static String _replaceCallNameVariant(
    String text,
    String source,
    String target,
    Set<String> protectedFullNames,
  ) {
    if (source.isEmpty || source == target) return text;
    if (source.runes.length == 1) {
      return _replaceNameTerm(text, source, target);
    }
    final buffer = StringBuffer();
    var changed = false;
    var index = 0;
    while (index < text.length) {
      if (!text.startsWith(source, index) ||
          _isProtectedFullNameSuffix(
            text,
            index,
            source,
            protectedFullNames,
          )) {
        buffer.write(text[index]);
        index += 1;
        continue;
      }

      buffer.write(target);
      changed = true;
      index += source.length;
    }
    return changed ? buffer.toString() : text;
  }

  static bool _isProtectedFullNameSuffix(
    String text,
    int start,
    String source,
    Set<String> protectedFullNames,
  ) {
    for (final fullName in protectedFullNames) {
      if (!fullName.endsWith(source) || fullName.length <= source.length) {
        continue;
      }
      final fullStart = start - (fullName.length - source.length);
      if (fullStart >= 0 && text.startsWith(fullName, fullStart)) {
        return true;
      }
    }
    return false;
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

  static Map<String, String> _chineseToJapaneseNameMap() {
    final result = <String, String>{};
    for (final entry in characterNamePronunciations) {
      result[entry.chinese] = entry.compactJapanese;
      result[entry.chinese.replaceAll(RegExp(r'[\s　]+'), '')] =
          entry.compactJapanese;
      for (final alias in entry.chineseAliases) {
        result[alias] = entry.compactJapanese;
        result[alias.replaceAll(RegExp(r'[\s　]+'), '')] = entry.compactJapanese;
      }
      for (final alias in entry.aliases.entries) {
        result[alias.key] = _characterAliasJapaneseDisplay(
          alias.key,
          alias.value,
          entry,
        );
      }
    }
    for (final entry in termNamePronunciations) {
      result[entry.chinese] = entry.japanese;
      result[entry.chinese.replaceAll(RegExp(r'[\s　]+'), '')] = entry.japanese;
      for (final alias in entry.aliases.keys) {
        if (entry.japanese.contains(alias)) continue;
        result[alias] = entry.japanese;
      }
    }
    return result;
  }

  static String _characterAliasJapaneseDisplay(
    String alias,
    String aliasReading,
    CharacterNamePronunciation entry,
  ) {
    final trimmedAlias = alias.trim();
    if (_preservesCharacterAliasDisplay(trimmedAlias)) return trimmedAlias;
    final trimmedReading = aliasReading.trim();
    if (trimmedReading.isNotEmpty) return trimmedReading;
    return entry.compactJapanese;
  }

  static Map<String, String> _fixedCharacterChineseCallNames(
    Map<String, String> fixedCharacterCallNames, {
    String? characterId,
  }) {
    final result = <String, String>{};
    final configuredChinese = characterId == null
        ? null
        : _fixedCharacterChineseCallNameMap[characterId];
    for (final entry in fixedCharacterCallNames.entries) {
      final displayName = entry.key.trim();
      final callName = entry.value.trim();
      if (displayName.isEmpty || callName.isEmpty) continue;
      final chineseCallName = configuredChinese?[displayName] ??
          _callNameChineseTarget(displayName, callName);
      if (chineseCallName.isNotEmpty) {
        result[displayName] = chineseCallName;
      }
    }
    return result;
  }

  static String _applyFixedChineseCallNames(
    String text,
    Map<String, String> fixedChineseCallNames,
  ) {
    var result = text;
    for (final entry in fixedChineseCallNames.entries) {
      result = _replaceNameTerm(result, entry.key, entry.value);
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

    if (_containsKana(bareCallName)) {
      baseTarget = _knownChineseGivenName(displayName) ?? displayName;
    } else if (callKey.isNotEmpty && displayKey.startsWith(callKey)) {
      baseTarget = _takeRunes(displayName, targetLength, fromEnd: false);
    } else if (callKey.isNotEmpty && displayKey.endsWith(callKey)) {
      baseTarget = _takeRunes(displayName, targetLength, fromEnd: true);
    } else {
      baseTarget = displayName;
    }

    return '$baseTarget$suffixTranslation';
  }

  static String? _knownChineseGivenName(String displayName) {
    final displayKey = displayName.replaceAll(RegExp(r'[\s　]+'), '');
    for (final entry in characterNamePronunciations) {
      final chinese = entry.chinese.trim();
      if (chinese.isEmpty) continue;
      final compactChinese = chinese.replaceAll(RegExp(r'[\s　]+'), '');
      if (displayKey != compactChinese &&
          !entry.chineseAliases
              .map((alias) => alias.replaceAll(RegExp(r'[\s　]+'), ''))
              .contains(displayKey)) {
        continue;
      }

      final explicitParts = chinese.split(RegExp(r'[\s　]+'));
      if (explicitParts.length >= 2 && explicitParts.last.trim().isNotEmpty) {
        return explicitParts.last.trim();
      }

      final japaneseParts = entry.japanese.trim().split(RegExp(r'[\s　]+'));
      if (japaneseParts.length < 2) return null;
      final surnameLength = japaneseParts.first.runes.length;
      if (compactChinese.runes.length <= surnameLength) return null;
      return String.fromCharCodes(
        compactChinese.runes.skip(surnameLength),
      );
    }
    return null;
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

  static String _japaneseTranslationStyle(String? characterId) {
    final selfPronounRule = _japaneseSelfPronounInstruction(characterId);
    final baseStyle = switch (characterId) {
      'shinobu' =>
        '胡蝶しのぶらしい、柔らかく上品で落ち着いた丁寧語を使ってください。基本は「です・ます」調とし、乱暴または過度にくだけた語尾にしないでください。',
      'sakiko' =>
        '豊川祥子らしい、上品で抑制の利いた丁寧語を使ってください。地の文を含む各文の結びは一貫して「です・ます」調にし、4文以上の返答では「ですわ・ますわ・ですの」のいずれかを全体に少なくとも1回、文脈に合わせて自然に使ってください。引用した台詞以外を常体で結ばないでください。',
      'muichirou' => '時透無一郎らしい、静かで簡潔な少年の常体を使ってください。無理に丁寧語や華やかな表現を足さないでください。',
      'giyu' => '冨岡義勇らしい、短く抑制された常体を使ってください。感情や語尾を過度に飾らないでください。',
      'tomori' => '高松燈らしい、素朴で柔らかく、少しためらいのある自然な話し方にしてください。強気で流暢すぎる表現にしないでください。',
      _ => '原文の人物らしい一人称、丁寧さ、語尾と感情の強さを保ってください。',
    };
    return selfPronounRule.isEmpty ? baseStyle : '$baseStyle$selfPronounRule';
  }

  static String _japaneseFallbackTextForCharacter(String? characterId) {
    return switch (characterId) {
      'shinobu' => 'すみません、うまく言葉にできませんでした。もう一度お話ししていただけますか？',
      'sakiko' => '申し訳ありませんわ。うまく言葉にできませんでしたの。もう一度お話しいただけますか？',
      'muichirou' => 'ごめん、うまく言葉にできなかった。もう一度話してくれる？',
      'giyu' => 'すまない。うまく言えなかった。もう一度話してくれ。',
      'tomori' => 'ごめんなさい。うまく言葉にできなくて……もう一度、話してくれる？',
      _ => 'ごめん、ちょっと言葉が出てこなかった…もう一度話してくれる？',
    };
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
      r'安慰|陪陪|抱抱|心情不好|喘不过气|没有力气|'
      r'好忙|太忙|忙死|忙不过来|忙到|力竭|累死|累到|疲惫|疲憊',
    ).hasMatch(text);
  }

  // ========================================
  // 日语判定
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

  static bool _isAcceptableJapaneseForCharacter(
    String text,
    String? characterId,
  ) {
    return _isCleanJapaneseForTts(text) &&
        isJapaneseTranslationStyleCompatible(text, characterId);
  }

  @visibleForTesting
  static bool isJapaneseTranslationStyleCompatible(
    String text,
    String? characterId,
  ) {
    if (!isJapaneseStyleCompatible(text, characterId)) return false;
    return true;
  }

  static bool isJapaneseStyleCompatible(String text, String? characterId) {
    if (text.trim().isEmpty) return false;
    if (!_hasAllowedJapaneseSelfPronoun(text, characterId)) return false;
    if (characterId != 'sakiko' && characterId != 'shinobu') return true;

    final clauses = _japaneseValidationClauses(text);
    if (clauses.isEmpty) return false;
    final stronglyCasualClauses = clauses.where((clause) {
      return RegExp(r'(?:だよ|だね|なんだ|なんだよ|だろ|じゃん)$').hasMatch(clause);
    }).length;
    return stronglyCasualClauses <= 1;
  }

  static bool _hasAllowedJapaneseSelfPronoun(
    String text,
    String? characterId,
  ) {
    final profile = _characterSpeechNameProfiles[characterId];
    if (profile == null) return true;
    return !profile.forbiddenJapaneseSelfPronouns.any(
      (pronoun) => _containsJapaneseSelfPronoun(text, pronoun),
    );
  }

  static bool _containsJapaneseSelfPronoun(String text, String pronoun) {
    if (pronoun == '私') {
      return RegExp(r'私(?=$|[はもがのにをへでと、。！？\s]|自身|たち|達)').hasMatch(text);
    }
    return text.contains(pronoun);
  }

  static bool _containsChineseResidueInJapanese(String text) {
    if (_containsChineseOnlyParenthetical(text)) return true;
    return _japaneseValidationClauses(text).any(_isStructurallyChineseClause);
  }

  static bool _containsChineseOnlyParenthetical(String text) {
    final parentheticalPattern = RegExp(r'[（(]([^（）()]{1,40})[）)]');
    for (final match in parentheticalPattern.allMatches(text)) {
      final content = (match.group(1) ?? '').trim();
      if (content.isEmpty) continue;
      final kanaCount = _countPattern(content, RegExp(r'[\u3040-\u30ffー]'));
      final hanCount = _countPattern(content, RegExp(r'[\u4e00-\u9fff]'));
      if (kanaCount == 0 && hanCount >= 4) return true;
    }
    return false;
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

  static Future<String> _translateChineseRoleResponseToJapanese(
    String chineseText, {
    required String? characterId,
    required String? exactUserName,
    required String? translatedUserName,
    required Map<String, String> fixedCharacterCallNames,
    required Map<String, String> fixedChineseCallNames,
    required String? webContext,
    required bool isRetry,
  }) async {
    try {
      final protectedText = _protectMappedNamesForJapaneseTranslation(
        chineseText,
        exactUserName: exactUserName,
        translatedUserName: translatedUserName,
        fixedCharacterCallNames: fixedCharacterCallNames,
        fixedChineseCallNames: fixedChineseCallNames,
      );
      final sourceUnits = _splitChineseTranslationUnits(protectedText.text);
      if (sourceUnits.isEmpty) return '';
      final genderHints = _genderHintsForTranslationPrompt(webContext);
      final retryInstruction = isRetry
          ? '前回の出力は、文対応・主語と目的語・能動と受動・日本語の純粋さ・キャラクターの話し方のいずれかの検査に通りませんでした。今回は原文の各文を一文ずつ照合し、関係を変えずに修正してください。\n'
          : '';
      final sourcePayload = jsonEncode({
        'source_sentences': [
          for (var i = 0; i < sourceUnits.length; i++)
            {'source_index': i + 1, 'text': sourceUnits[i]},
        ],
      });
      final systemPrompt = isRetry
          ? '你是负责角色台词的中译日翻译器。\n'
              '输入是已经确定内容和角色性的中文回答。你的任务不是复述、润色中文或解释，而是把每个 source_index 的 text 翻译成自然日语。\n'
              '\n'
              '硬性规则：\n'
              '1. 只输出这个 JSON 对象：{"translations":[{"source_index":1,"text":"日本語訳"}]}。不要代码块，不要说明。\n'
              '2. 每个输入 source_index 必须对应一个译文，数量、顺序、source_index 必须完全一致；不要跨句移动、合并或拆分。\n'
              '3. text 里只能写日语。严禁保留中文原句、中文动作描写、中文标点说明或“翻译如下”等前置语。\n'
              '4. 如果原文包含中文括号动作，例如“（轻轻点头）”，必须翻成日语括号动作，例如“（そっと頷いて）”。\n'
              '5. 原文里的 __JP_NAME_0__ 这类占位符必须在同一个 source_index 的译文里原样保留，一个字符也不能改，不能移动到别的句子。\n'
              '6. 事实范围、动作主体、对象、主动/被动、因果关系和完成程度必须保持一致。\n'
              '7. 必须包含平假名或片假名，写成日本语母语者日常会话里自然会说的句子。\n'
              '8. $genderHints'
              '9. 角色语体要求：${_japaneseTranslationStyle(characterId)}\n'
              '10. 输出前逐项检查：是否仍有中文残留；是否每个 source_index 都完成了真正的日语翻译。\n'
          : 'あなたはキャラクター会話の中日翻訳者です。\n'
              '入力は内容とキャラクター性を確定済みの中国語返答です。'
              '日本語話者が日常会話で自然に話す文章として翻訳してください。\n'
              '\n'
              '厳守事項:\n'
              '1. 次の形の JSON オブジェクトだけを出力すること: '
              '{"translations":[{"source_index":1,"text":"日本語訳"}]}。コードブロックや説明を付けない。\n'
              '2. 入力の各 source_index に対して翻訳を一つだけ出し、件数と順序を完全に一致させる。文を別の index に移動、結合、分割しない。\n'
              '3. text は日本語だけにし、中国語の語句、説明、注釈、前置きを残さない。\n'
              '4. 各文の事実範囲、動作主、対象、能動・受動、因果関係、完了の程度を変えない。自然な日本語にするための語順変更はよいが、誰が誰に何をしたかを変えない。\n'
              '5. 元の文にある __JP_NAME_0__ のような占位符は、その同じ index の訳文に一文字も変えず残す。別の文へ移さない。\n'
              '6. 元のテキストに括弧書きの動作や表情がある場合は、削除せず自然な日本語にして括弧内に残す。\n'
              '7. 必ず平仮名または片仮名を含む自然な日本語にし、中国語の漢字語を字形だけで残さない。\n'
              '8. $genderHints'
              '9. ${_japaneseTranslationStyle(characterId)}\n'
              '10. 出力前に各 source_index の原文と訳文を一対一で照合し、主語と能動・受動が一致しているか確認する。\n'
              '$retryInstruction';
      final response = await http.post(
        Uri.parse('$deepSeekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepSeekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepSeekModel,
          'thinking': {'type': 'disabled'},
          'messages': [
            {
              'role': 'system',
              'content': systemPrompt,
            },
            {
              'role': 'user',
              'content': sourcePayload,
            },
          ],
          'max_tokens': 1000,
          'temperature': isRetry ? 0.2 : 0.3,
          'stream': false,
          'response_format': {'type': 'json_object'},
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawResult = data['choices'][0]['message']['content'] as String;
        final parsed = _parseAlignedJapaneseTranslations(
          sourceUnits: sourceUnits,
          rawResponse: rawResult,
          placeholders: protectedText.placeholders,
        );
        if (!parsed.isValid) {
          debugPrint('日语逐句翻译契约未通过: ${parsed.issue}');
          return '';
        }
        debugPrint('日语逐句翻译契约通过: sentences=${sourceUnits.length}');
        var result = _restoreProtectedMappedNames(
          parsed.text,
          protectedText.placeholders,
        );
        result = _sanitizeUserNameHonorifics(result, exactUserName);
        result =
            _applyStandardJapaneseNameSpellings(_removeRubyReadings(result));
        result = _applyFixedCharacterCallNames(
          result,
          fixedCharacterCallNames,
          fixedChineseCallNames,
        );
        return result.trim();
      } else {
        debugPrint('日文转换 API 错误: ${response.statusCode}');
        debugPrint('错误内容: ${response.body}');
      }
    } catch (e) {
      debugPrint('日文转换失败: $e');
    }
    return '';
  }

  static List<String> _splitChineseTranslationUnits(String text) {
    const protectedMyGo = '__MYGO_FIVE_EXCLAMATIONS__';
    final protectedText = text.replaceAll('MyGO!!!!!', protectedMyGo);
    final units = <String>[];
    final buffer = StringBuffer();
    const sentenceEndings = {'。', '！', '？', '!', '?'};
    for (final rune in protectedText.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(character);
      if (sentenceEndings.contains(character)) {
        final unit = buffer.toString().trim();
        if (unit.isNotEmpty) units.add(unit);
        buffer.clear();
      }
    }
    final remainder = buffer.toString().trim();
    if (remainder.isNotEmpty) units.add(remainder);
    return units
        .map((unit) => unit.replaceAll(protectedMyGo, 'MyGO!!!!!'))
        .toList(growable: false);
  }

  static _AlignedTranslationParseResult _parseAlignedJapaneseTranslations({
    required List<String> sourceUnits,
    required String rawResponse,
    required Map<String, String> placeholders,
  }) {
    final cleaned = rawResponse
        .replaceAll(RegExp(r'^\s*```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```\s*$'), '')
        .trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      return const _AlignedTranslationParseResult.invalid('输出不是有效 JSON');
    }
    if (decoded is! Map || decoded['translations'] is! List) {
      return const _AlignedTranslationParseResult.invalid(
        '缺少 translations 数组',
      );
    }
    final translations = decoded['translations'] as List;
    if (translations.length != sourceUnits.length) {
      return _AlignedTranslationParseResult.invalid(
        '翻译句数 ${translations.length} 与原文 ${sourceUnits.length} 不一致',
      );
    }

    final translatedUnits = <String>[];
    final placeholderPattern = RegExp(r'__JP_NAME_\d+__');
    for (var i = 0; i < sourceUnits.length; i++) {
      final rawTranslation = translations[i];
      if (rawTranslation is! Map || rawTranslation['source_index'] != i + 1) {
        return _AlignedTranslationParseResult.invalid(
          '第 ${i + 1} 项的 source_index 不匹配',
        );
      }
      final translatedText = '${rawTranslation['text'] ?? ''}'.trim();
      if (translatedText.isEmpty) {
        return _AlignedTranslationParseResult.invalid('第 ${i + 1} 项译文为空');
      }

      final expectedPlaceholders = placeholders.keys
          .where((placeholder) => sourceUnits[i].contains(placeholder))
          .toSet();
      final actualPlaceholders = placeholderPattern
          .allMatches(translatedText)
          .map((match) => match.group(0)!)
          .toSet();
      if (!_sameStringSet(expectedPlaceholders, actualPlaceholders)) {
        return _AlignedTranslationParseResult.invalid(
          '第 ${i + 1} 项的人名占位符发生丢失或跨句移动',
        );
      }
      if (_hasPotentialPassiveVoiceShift(
        sourceUnits[i],
        translatedText,
        expectedPlaceholders,
      )) {
        return _AlignedTranslationParseResult.invalid(
          '第 ${i + 1} 项疑似把主动关系翻成了被动关系',
        );
      }
      translatedUnits.add(translatedText);
    }
    return _AlignedTranslationParseResult.valid(translatedUnits.join());
  }

  static bool _sameStringSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  static bool _hasPotentialPassiveVoiceShift(
    String source,
    String translation,
    Set<String> placeholders,
  ) {
    if (RegExp(r'被|遭|受到').hasMatch(source)) return false;
    for (final placeholder in placeholders) {
      final namedPassive = RegExp(
        '${RegExp.escape(placeholder)}(?:は|が)[^。！？!?]{0,48}'
        r'され(?:る|た|て|ない|ます|ました|ません|ている|ています)',
      );
      if (namedPassive.hasMatch(translation)) return true;
    }
    return false;
  }

  @visibleForTesting
  static List<String> splitChineseTranslationUnitsForTest(String text) =>
      _splitChineseTranslationUnits(text);

  @visibleForTesting
  static String? parseAlignedJapaneseTranslationsForTest({
    required List<String> sourceUnits,
    required String response,
    Map<String, String> placeholders = const {},
  }) {
    final parsed = _parseAlignedJapaneseTranslations(
      sourceUnits: sourceUnits,
      rawResponse: response,
      placeholders: placeholders,
    );
    return parsed.isValid ? parsed.text : null;
  }

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

class _TimelineAnswerContract {
  final List<GroundingTimelineSnapshot> timeline;

  const _TimelineAnswerContract(this.timeline);

  static _TimelineAnswerContract? fromWebContext(String? webContext) {
    if (webContext == null ||
        webContext.trim().isEmpty ||
        !webContext.contains('【事实时间线】')) {
      return null;
    }
    final snapshot = GroundingSnapshot.fromAudit(
      logs: const [],
      webContext: webContext,
    );
    if (snapshot.timeline.isEmpty) return null;
    return _TimelineAnswerContract(snapshot.timeline);
  }

  String get outputInstruction => '''
【最终输出语言与时间线结构契约】
只输出一个 JSON 对象，不要输出代码块或说明：
{"sentences":[{"text":"一条自然的中文角色台词","timeline_refs":[1]}]}

- sentences 按最终说话顺序排列，text 拼接后就是完整回复。
- 陈述剧情事实的句子必须在 timeline_refs 中填写它实际依据的【时间线】编号；纯粹的问候、感受或评价填写空数组。
- timeline_refs 只能使用 1 到 ${timeline.length}，同一句引用多个阶段时必须连续递增；整段回复引用的编号也必须随句子递增，不能倒序。
- 可以省略不重要的时间线阶段，不必使用全部编号；但不得为了缩短篇幅交换事件顺序。
- 编号只用于程序校验，不要把编号写进 text。
''';

  _TimelineAnswerParseResult parse(String rawResponse) {
    final cleaned = rawResponse
        .replaceAll(RegExp(r'^\s*```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```\s*$'), '')
        .trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      return const _TimelineAnswerParseResult.invalid('输出不是有效 JSON');
    }
    if (decoded is! Map || decoded['sentences'] is! List) {
      return const _TimelineAnswerParseResult.invalid('缺少 sentences 数组');
    }

    final sentenceTexts = <String>[];
    final allReferences = <int>[];
    var previousReference = 0;
    final rawSentences = decoded['sentences'] as List;
    if (rawSentences.isEmpty) {
      return const _TimelineAnswerParseResult.invalid('sentences 为空');
    }

    for (var sentenceIndex = 0;
        sentenceIndex < rawSentences.length;
        sentenceIndex++) {
      final rawSentence = rawSentences[sentenceIndex];
      if (rawSentence is! Map) {
        return _TimelineAnswerParseResult.invalid(
          '第 ${sentenceIndex + 1} 句不是对象',
        );
      }
      final text = '${rawSentence['text'] ?? ''}'.trim();
      if (text.isEmpty) {
        return _TimelineAnswerParseResult.invalid(
          '第 ${sentenceIndex + 1} 句正文为空',
        );
      }
      final rawReferences = rawSentence['timeline_refs'];
      if (rawReferences is! List) {
        return _TimelineAnswerParseResult.invalid(
          '第 ${sentenceIndex + 1} 句缺少 timeline_refs 数组',
        );
      }

      final references = <int>[];
      for (final rawReference in rawReferences) {
        final reference =
            rawReference is int ? rawReference : int.tryParse('$rawReference');
        if (reference == null || reference < 1 || reference > timeline.length) {
          return _TimelineAnswerParseResult.invalid(
            '第 ${sentenceIndex + 1} 句引用了无效时间线编号',
          );
        }
        if (references.isNotEmpty && reference <= references.last) {
          return _TimelineAnswerParseResult.invalid(
            '第 ${sentenceIndex + 1} 句的时间线编号没有严格递增',
          );
        }
        if (references.isNotEmpty && reference != references.last + 1) {
          return _TimelineAnswerParseResult.invalid(
            '第 ${sentenceIndex + 1} 句合并了不相邻的时间线阶段',
          );
        }
        references.add(reference);
      }

      if (references.isNotEmpty) {
        if (references.first < previousReference) {
          return _TimelineAnswerParseResult.invalid(
            '第 ${sentenceIndex + 1} 句的事件顺序发生倒退',
          );
        }
        previousReference = references.last;
        allReferences.addAll(references);
      }
      sentenceTexts.add(text);
    }

    if (allReferences.isEmpty) {
      return const _TimelineAnswerParseResult.invalid('回答没有引用任何时间线阶段');
    }
    return _TimelineAnswerParseResult.valid(
      _joinTimelineAnswerSentences(sentenceTexts),
      sentenceTexts.length,
      allReferences,
    );
  }

  static String _joinTimelineAnswerSentences(List<String> sentences) {
    final buffer = StringBuffer();
    final terminalPunctuation = RegExp(r'[。！？!?…）」】”]$');
    for (final sentence in sentences) {
      buffer.write(sentence);
      if (!terminalPunctuation.hasMatch(sentence)) buffer.write('。');
    }
    return buffer.toString();
  }
}

class _TimelineAnswerParseResult {
  final bool isValid;
  final String text;
  final int sentenceCount;
  final List<int> references;
  final String issue;

  const _TimelineAnswerParseResult.valid(
    this.text,
    this.sentenceCount,
    this.references,
  )   : isValid = true,
        issue = '';

  const _TimelineAnswerParseResult.invalid(this.issue)
      : isValid = false,
        text = '',
        sentenceCount = 0,
        references = const [];
}

class _AlignedTranslationParseResult {
  final bool isValid;
  final String text;
  final String issue;

  const _AlignedTranslationParseResult.valid(this.text)
      : isValid = true,
        issue = '';

  const _AlignedTranslationParseResult.invalid(this.issue)
      : isValid = false,
        text = '';
}

class _ProtectedTranslationText {
  final String text;
  final Map<String, String> placeholders;

  const _ProtectedTranslationText({
    required this.text,
    required this.placeholders,
  });
}

class _CharacterCallName {
  final String fullName;
  final String chineseCallName;
  final String japaneseCallName;

  const _CharacterCallName(
    this.fullName,
    this.chineseCallName,
    this.japaneseCallName,
  );
}

class _CharacterSpeechNameProfile {
  final String chineseSelfPronoun;
  final String japaneseSelfPronoun;
  final List<String> forbiddenJapaneseSelfPronouns;

  const _CharacterSpeechNameProfile({
    required this.chineseSelfPronoun,
    required this.japaneseSelfPronoun,
    required this.forbiddenJapaneseSelfPronouns,
  });
}
