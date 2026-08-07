import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_keys.dart';
import 'api_service.dart';
import 'character_config.dart';
import 'grounding_contract.dart';
import 'name_pronunciation.dart';
import 'storage_service.dart';

// ========================================
// 现实/联网信息上下文服务
// ========================================
// 这个类不直接生成角色回复。
// 它的工作是：
// 1. 看用户这句话需不需要现实信息，比如天气、节日、物候、网络梗、原作剧情。
// 2. 按“当前角色”的规则决定允许查什么。
// 3. 真的去调用天气接口或网页搜索。
// 4. 把查到的信息整理成一段 prompt 上下文，交给 DeepSeek。
//
// 最终回答仍然由 ApiService.generateResponse() 调 DeepSeek 生成。
// 也就是说：这里负责“查资料”，DeepSeek 负责“扮演角色说出来”。
class WebContextService {
  // 普通联网请求最多等 8 秒。
  // 如果天气或 planner 太慢，就放弃这部分信息，避免聊天一直卡住。
  static const Duration _timeout = Duration(seconds: 8);
  // 搜索 API 偶尔会超过 8 秒，尤其是联网搜索和页面正文补全。
  // 搜索比天气更能容忍稍慢一点，所以单独给更宽松的超时。
  static const Duration _searchTimeout = Duration(seconds: 18);
  static const Duration _factExtractionTimeout = Duration(seconds: 90);

  // 用豆包做“是否需要联网”的智能判断。
  // 注意：这里不是正式聊天回复，只是让模型输出一小段 JSON 搜索计划。
  static const String _deepSeekApiKey = ApiKeys.deepseekApiKey;
  static const String _deepSeekModel = 'deepseek-v4-flash';
  static const String _deepSeekBaseUrl = 'https://api.deepseek.com/v1';
  static const String _baiduMapAk = ApiKeys.baiduMapAk;
  static const String _answerModeStrictFact = 'strict_fact';
  static const String _answerModeBoundedRoleplay = 'bounded_roleplay';
  static const String _answerModeAdaptive = 'adaptive';
  static const String _answerBasisExplicitFact = 'explicit_fact';
  static const String _answerBasisBoundedCandidates = 'bounded_candidates';
  static const String _answerBasisInsufficient = 'insufficient';
  static const String _answerBasisMixed = 'mixed';
  static const String _doubaoCustomSearchEndpoint =
      'https://open.feedcoopapi.com/search_api/web_search';
  static const String _doubaoGlobalSearchEndpoint =
      'https://open.feedcoopapi.com/search_api/global_search';
  static const String _moegirlSites =
      'zh.moegirl.org.cn|moegirl.org.cn|moegirl.org|moegirl.uk';
  static const String _authoritativeNewsSites =
      'gov.cn|xinhuanet.com|people.com.cn|cctv.com|chinanews.com.cn|thepaper.cn|caixin.com|yicai.com|reuters.com|apnews.com';
  static const String _authoritativeFinanceSites =
      'pbc.gov.cn|stats.gov.cn|mof.gov.cn|csrc.gov.cn|sse.com.cn|szse.cn|eastmoney.com|caixin.com|yicai.com|reuters.com';
  static const int _authoritativeAuthInfoLevel = 2;
  static const int _doubaoFactMaxResults = 8;
  static const int _doubaoFactPerResultMaxChars = 20000;
  static const bool _verboseSearchDiagnostics = false;
  static const String _doubaoTimelineResultPrefix = '__DOUBAO_TIMELINE__';
  static const String _doubaoAnswerBasisResultPrefix =
      '__DOUBAO_ANSWER_BASIS__';
  static const String _arkChatBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  static const Map<String, String> _browserSearchHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7',
    'Referer': 'https://www.baidu.com/',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
    'Connection': 'keep-alive',
  };
  static const Map<String, String> _mobileBrowserSearchHeaders = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7',
    'Referer': 'https://m.baidu.com/',
    'Connection': 'keep-alive',
  };

  static void _logSearch(String message) {
    debugPrint(message);
  }

  static void _logSearchVerbose(String message) {
    if (_verboseSearchDiagnostics) debugPrint(message);
  }

  static const int _maxDoubaoSearchApiCallsPerTurn = 6;

  // ========================================
  // 入口方法：聊天页每次用户发消息时会调用这里
  // ========================================
  // 参数说明：
  // - userMessage：用户刚发的文字
  // - characterId：角色 id，例如 shinobu / sakiko / andy
  // - characterName：角色中文名，用来拼搜索关键词
  //
  // 返回：
  // - 如果这句话需要现实信息，返回一段“【现实与联网信息】...”
  // - 如果不需要联网，返回空字符串 ''
  static Future<String> buildContext({
    required String userMessage,
    required String characterId,
    required String characterName,
    List<Message> conversationHistory = const [],
  }) async {
    final result = await buildContextDetailed(
      userMessage: userMessage,
      characterId: characterId,
      characterName: characterName,
      conversationHistory: conversationHistory,
    );
    return result.context;
  }

  static Future<WebContextBuildResult> buildContextDetailed({
    required String userMessage,
    required String characterId,
    required String characterName,
    List<Message> conversationHistory = const [],
  }) async {
    final trace = GroundingRunTrace(
      userMessage: userMessage,
      characterId: characterId,
    );
    final runState = _WebContextRunState();
    final context = await runZoned(
      () => _buildContextInternal(
        userMessage: userMessage,
        characterId: characterId,
        characterName: characterName,
        conversationHistory: conversationHistory,
      ),
      zoneValues: {
        #groundingRunTrace: trace,
        #webContextRunState: runState,
      },
    );
    trace.finish();
    debugPrint('联网调用统计: ${trace.compactSummary}');
    return WebContextBuildResult(context: context, trace: trace);
  }

  static GroundingRunTrace? get _activeTrace =>
      Zone.current[#groundingRunTrace] as GroundingRunTrace?;

  static _WebContextRunState? get _activeRunState =>
      Zone.current[#webContextRunState] as _WebContextRunState?;

  static Future<String> _buildContextInternal({
    required String userMessage,
    required String characterId,
    required String characterName,
    List<Message> conversationHistory = const [],
  }) async {
    final text = userMessage.trim();
    if (text.isEmpty) return '';

    // 根据角色 id 生成“联网权限配置”。
    // 这是本文件最核心的分流逻辑：
    // 鬼灭角色、祥子、安迪会拿到不同的天气城市、节日范围、搜索权限。
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );

    // 先让搜索计划模型判断这句话需不需要现实/原作资料。
    // 这样可以覆盖很多关键词法抓不到的情况：
    // - “她后来怎么样了？” -> 可能需要原作剧情
    // - “你那边外面怎么样？” -> 可能需要天气
    // - “这个说法最近很火吗？” -> 可能需要网页搜索
    // - “外面是不是已经有秋天的感觉了？” -> 可能需要物候搜索
    //
    // 如果这个小判定失败，会自动回退到关键词规则，保证功能不会直接断掉。
    final plan = await _buildSearchPlan(text, profile, conversationHistory);
    final planObjectLog =
        plan.primarySearchObjects.isEmpty && plan.secondarySearchObjects.isEmpty
            ? ''
            : ', primary=${plan.primarySearchObjects.join('|')}, '
                'secondary=${plan.secondarySearchObjects.join('|')}';
    final answerRequirements = plan.answerRequirements.isNotEmpty
        ? plan.answerRequirements
        : [_AnswerRequirement(text: text)];
    final requirementLog = answerRequirements.map((requirement) {
      final cueText = requirement.directEvidenceCues.isEmpty
          ? ''
          : '{直接关系=${requirement.directEvidenceCues.join('/')}}';
      return '${requirement.text}$cueText';
    }).join('|');
    debugPrint(
      '联网计划: character=${profile.characterId}, '
      'category=${plan.category}, '
      'answer_requirements=$requirementLog, '
      'weather=${plan.includeWeather}, festival=${plan.includeFestivals}, '
      'phenology=${plan.includePhenology}$planObjectLog',
    );
    _logSearchVerbose('联网计划原始查询: ${plan.searchQuery}');

    if (!plan.hasAnyTask) return '';

    // sections 用来收集本次查到的所有现实信息。
    // 比如用户问“上海今天天气怎么样，快到什么节日了？”
    // sections 里可能会有：
    // - 近期节日
    // - 实时天气
    // 最后再合并成一整段上下文。
    final sections = <String>[];
    var resolvedAnswerBasis = _answerBasisInsufficient;

    // 节日信息：
    // 使用受角色地区约束的本地节日表；旧网页搜索兜底已移除。
    if (profile.includeFestivals && plan.includeFestivals) {
      final festivalContext = _buildFestivalContext(DateTime.now(), profile);
      if (festivalContext.isNotEmpty) {
        sections.add(festivalContext);
      }
    }

    // 天气信息：
    // 只有搜索计划认为这句话需要天气背景时才查。
    // 比如“你那边外面怎么样？”没有“天气”二字，也可以触发。
    // 具体查询城市由 profile 控制：
    // - 鬼灭角色：用东京作为日本现实天气参考，但不会把东京暴露给角色回复
    // - 祥子：固定东京
    // - 安迪：默认上海，但允许用户问其他城市
    if (profile.includeWeather && plan.includeWeather) {
      final city = plan.weatherCity ?? profile.weatherCity;
      final weather = await _fetchWeather(
        city,
        displayName: profile.weatherContextName,
        extraRule: profile.weatherSpeechRule,
      );
      if (weather.isNotEmpty) {
        sections.add(weather);
      } else {
        sections.add('''
【实时天气查询失败】
本轮没有成功取得${profile.weatherContextName}的实时天气数据。
天气表述限制：不要编造晴天、阴天、下雨、雷雨、打雷、降温、升温、带伞等具体天气情况；如果必须回应天气问题，只能自然表示“暂时不太确定/刚才没查到实时天气”。${profile.weatherSpeechRule}
''');
      }
    }

    // 物候信息旧版依赖普通网页搜索兜底；旧链路移除后暂不生成物候上下文。

    // 网页搜索：
    // 天气有专门接口，普通天气问题不走网页搜索。
    // 原剧剧情、网络流行语、经济新闻等才可能走网页搜索。
    // 是否允许搜索某类内容，也由 profile 决定。
    if (plan.searchQuery != null && plan.searchQuery!.isNotEmpty) {
      final webSearchQuery = plan.category == 'canon'
          ? _buildDoubaoSearchQuery(
              plan.searchQuery!,
              userText: text,
              category: plan.category,
              profile: profile,
            )
          : plan.searchQuery!;
      final canonSearchTargets = plan.category == 'canon'
          ? _canonSearchTargetsForPlan(plan, text, webSearchQuery, profile)
          : const <String>[];
      if (canonSearchTargets.isNotEmpty) {
        debugPrint('原作搜索对象: ${canonSearchTargets.join(' -> ')}');
      }
      final executionSearchQuery = canonSearchTargets.isNotEmpty
          ? canonSearchTargets.join(' / ')
          : webSearchQuery;
      final localProfileQuery = canonSearchTargets.isNotEmpty
          ? canonSearchTargets.first
          : webSearchQuery;
      final localProfileResults = plan.category == 'canon'
          ? _searchLocalCharacterProfile(
              localProfileQuery,
              profile,
              userIntent: text,
            )
          : const <String>[];

      var results = await _searchDoubaoGroundedFacts(
        executionSearchQuery,
        userText: text,
        category: plan.category,
        answerMode: _answerModeAdaptive,
        answerRequirements: answerRequirements,
        profile: profile,
        searchTargets: canonSearchTargets,
      );

      final doubaoSearchConfigured = _shouldUseDoubaoSearch(plan.category) &&
          _doubaoSearchApiKey.isNotEmpty;

      if (results.isEmpty &&
          _requiresAuthoritativeDoubaoSearch(
            plan.category,
            profile,
          )) {
        debugPrint(
          '豆包权威搜索事实不足，不使用旧搜索兜底: '
          'category=${plan.category}, query=$executionSearchQuery',
        );
      }

      if (results.isEmpty &&
          doubaoSearchConfigured &&
          plan.category == 'canon') {
        debugPrint(
          '豆包原作搜索事实不足，不进入旧搜索兜底: query=$executionSearchQuery',
        );
      } else if (results.isEmpty) {
        debugPrint(
          '豆包搜索事实不足，旧网页搜索兜底已移除: '
          'category=${plan.category}, query=$executionSearchQuery',
        );
      }

      if (results.isNotEmpty) {
        final answerBasisResults = results
            .where(
                (result) => result.startsWith(_doubaoAnswerBasisResultPrefix))
            .map((result) =>
                result.substring(_doubaoAnswerBasisResultPrefix.length).trim())
            .where((result) => result.isNotEmpty)
            .toList();
        if (answerBasisResults.isNotEmpty) {
          resolvedAnswerBasis = answerBasisResults.last;
        }
        final timelineResults = results
            .where((result) => result.startsWith(_doubaoTimelineResultPrefix))
            .map((result) =>
                result.substring(_doubaoTimelineResultPrefix.length).trim())
            .where((result) => result.isNotEmpty)
            .toList();
        final searchResults = results
            .where((result) =>
                !result.startsWith(_doubaoTimelineResultPrefix) &&
                !result.startsWith(_doubaoAnswerBasisResultPrefix))
            .toList();
        final includeLocalProfileInWebSummary =
            localProfileResults.isNotEmpty &&
                plan.category == 'canon' &&
                _queryAsksProfileTraits(text) &&
                !_queryAsksMusicInfo(text);
        final mergedSummaryResults = <String>[
          if (includeLocalProfileInWebSummary)
            ..._localProfileResultsAsSearchFacts(localProfileResults),
          ...searchResults,
        ];
        if (includeLocalProfileInWebSummary) {
          sections.add('【角色设定资料】\n${localProfileResults.join('\n')}');
        }
        if (mergedSummaryResults.isNotEmpty) {
          sections.add(
            '【网页搜索摘要】\n搜索词：$executionSearchQuery\n${mergedSummaryResults.join('\n')}',
          );
        }
        if (timelineResults.isNotEmpty) {
          sections.add('【事实时间线】\n${timelineResults.join('\n\n')}');
        }
        if (localProfileResults.isNotEmpty &&
            !(plan.category == 'canon' && _queryAsksProfileTraits(text))) {
          sections.add('【角色设定资料】\n${localProfileResults.join('\n')}');
        }
      } else if (localProfileResults.isNotEmpty) {
        debugPrint(
          '网页搜索无结果，使用本地角色设定资料: '
          'character=${profile.characterId}, query=$executionSearchQuery',
        );
        sections.add('【角色设定资料】\n${localProfileResults.join('\n')}');
      } else {
        sections.add('''
【网页搜索失败】
本轮尝试搜索：$executionSearchQuery
搜索类别：${plan.category}
使用限制：不要把没有查到的信息说成确定事实；如果必须回应，只能结合已有对话和角色常识，用“不太确定”“我印象里”这类自然说法轻轻带过。
''');
      }
    }

    if (sections.isEmpty) return '';

    // 这里返回的是一段“额外资料”，不是直接显示给用户的文字。
    // ApiService 会把它拼进 system prompt。
    // 下面的“使用规则”是给 DeepSeek 看的，告诉它：
    // - 可以自然使用这些信息
    // - 不要机械地说“根据搜索结果”
    // - 不确定时别瞎编
    return '''
【现实与联网信息】
${profile.contextRule}

${sections.join('\n\n')}

${resolvedAnswerBasis == _answerBasisExplicitFact ? '''
【明确原作设定优先】
本轮网页资料已经直接给出了用户所问内容的明确作品内设定。回答必须优先采用这项明确设定，不得用角色临场发挥的偏好、习惯或评价替换、弱化或否定它；可以在不改变事实的前提下自然接话。
''' : resolvedAnswerBasis == _answerBasisMixed ? '''
【明确设定与有限发挥并存】
本轮部分问项已有明确作品内设定，必须原样优先采用；其余问项只有真实候选或行为依据，可以在这些事实边界内自然表达倾向。不得用候选推测覆盖明确设定，也不得创造摘要外的专名、能力、经历或因果。
''' : resolvedAnswerBasis == _answerBasisBoundedCandidates ? '''
【有限角色发挥】
本轮网页资料用于限定真实候选、名称、能力、事件和关系边界，不需要替角色直接写出主观选择。角色可以在不违背资料的前提下，从摘要明确提供的候选中自然表达自己的偏好、习惯、感受或评价；不得创造摘要中不存在的专名、能力、经历或因果，也不要对用户说“资料没有写”或“搜索结果没有说明”。
''' : ''}

【使用这些信息的规则】
- 这些信息是给你理解现实世界用的，不要机械地说“根据搜索结果”。
- 只挑和用户问题最相关的 1-2 个事实自然带入，不要像天气预报、财经新闻或百科词条一样铺开讲。
- 角色说话要像日常聊天：可以像你刚看到、刚查到、或本来就知道一样自然提起，但不要背资料。
- 如果搜索摘要不够确定，就用“不太确定”“我印象里”“好像”这类自然表达，不要编造细节。
- 回答原作/剧情事实时，只能使用搜索摘要里明确支持的信息；摘要没说清楚就表达不确定，不要用模型记忆补成确定事实。
- 如果上下文包含【事实时间线】，它是回答的剧情顺序骨架；必须按时间线顺序组织叙述，不要把时间线里的事件前后移动，也不要把后续事实提前解释。
- 时间线后的“依据事实：#编号”只用于核对每个节点的来源，不得在角色回复中念出编号或提到“依据事实”。
- 使用搜索事实时必须保留动作主体和因果关系：不要把“某人的动物/部下/相关物”改成“某人本人”，不要把“某事被完成/某人被打倒”推断成搜索摘要未说明的角色完成。
- 当用户问“经过、如何、怎么发生、怎么恢复、怎么解决、怎么支援、战斗过程”等事件经过时，必须覆盖时间线里明确出现的关键手段和结果；如果资料写到招式/手段、击败/救助结果、后续反应，不要只讲原因或性格变化。
- 当用户问人物关系、相互影响、救赎、关系变化或一段经历时，必须覆盖搜索摘要支持的开端、冲突/逃避、追回/鼓励、回归/和解结果；不要只讲前半段，也不要把不同阶段用“然后”硬接成连续同一事件。
- 如果时间线里后面的阶段才出现“回归、回到乐队、归队、和解、重新连接”等结果，前面的鼓励、谈心或相遇阶段不能写成已经达成这些结果。
- 不要把不同地点、不同触发原因的阶段合并；地点、台词和结果必须绑定在时间线对应阶段上。
- 严格事实模式下，频率、偏好和强弱判断必须由摘要明确支持。有限角色发挥模式下，可以从摘要明确给出的真实候选中自然选择和评价，但候选名称、能力、经历和因果仍必须以摘要为准。
- 如果上下文包含【明确原作设定优先】，必须先回答该明确设定；角色化表达只能补充语气和感受，不能另选一个与设定冲突的答案。
- 原文证据中的动画/游戏集数、章节、资料页、设定集等出处只用于核对事实；角色回答时只能自然讲作品世界内的事实，不得说“动画第几集、游戏剧情、资料记载、页面提到”等三次元来源表述。
- 不要在回复里列链接。
''';
  }

  // ========================================
  // 智能搜索计划：先让豆包判断“要不要查”
  // ========================================
  // 这是比关键词触发更自然的一层。
  //
  // 为什么需要它？
  // 用户常常不会直接说“查原作剧情”，而是会说：
  // - “她后来和灯怎么样了？”
  // - “那件事之后她还会在意爽世吗？”
  // - “你那边外面怎么样？”
  // 这些句子没有明显关键词，但确实需要原作资料或现实天气。
  //
  // 所以这里先调用一次搜索计划模型，让它输出一个 JSON 搜索计划。
  // 然后本程序再按角色权限执行搜索。
  static Future<_SearchPlan> _buildSearchPlan(
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
    final llmPlan =
        await _buildSearchPlanWithDoubao(text, profile, conversationHistory);
    if (llmPlan != null) {
      return await _applySemanticCanonGuard(
        _applyProfileRules(
          llmPlan,
          text,
          profile,
          allowImplicitCurrentAffairsSearch: false,
        ),
        text,
        profile,
        conversationHistory,
        allowLocalCanonRecovery: false,
      );
    }

    // 如果豆包计划失败，比如网络错误、JSON 解析失败，就回退到本地关键词规则。
    // 这样最差也只是“没那么聪明”，不会让聊天直接坏掉。
    return await _applySemanticCanonGuard(
      _applyProfileRules(_keywordSearchPlan(text, profile), text, profile),
      text,
      profile,
      conversationHistory,
      allowLocalCanonRecovery: true,
    );
  }

  // 调豆包生成搜索计划。
  // 返回 null 表示这一步失败，让上层回退关键词规则。
  static Future<_SearchPlan?> _buildSearchPlanWithDoubao(
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
    try {
      final apiKey = _doubaoTextApiKey;
      final endpoint = _doubaoTextEndpoint;
      if (apiKey.isEmpty || endpoint.isEmpty) {
        debugPrint('豆包搜索计划模型未配置，使用关键词计划兜底');
        return null;
      }

      final messages = [
        {
          'role': 'system',
          'content': _searchPlannerPrompt(profile),
        },
        {
          'role': 'user',
          'content': '''
最近对话：
${_recentHistoryForPlanner(conversationHistory)}

用户刚发来的消息：$text
''',
        },
      ];

      final chatResult = await _postChatCompletions(
        baseUrl: _arkChatBaseUrl,
        apiKey: apiKey,
        model: endpoint,
        messages: messages,
        providerName: '豆包/火山方舟搜索计划',
        includeThinkingField: false,
        maxTokens: 350,
      );
      if (chatResult == null) {
        return null;
      }

      final data = jsonDecode(utf8.decode(chatResult.response.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      if (content is! String || content.trim().isEmpty) return null;

      final jsonText = _extractJsonObject(content);
      if (jsonText == null) return null;

      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;

      return _SearchPlan(
        includeWeather: _jsonBool(decoded['weather']),
        weatherCity: _jsonString(decoded['city']),
        includeFestivals: _jsonBool(decoded['festival']),
        includePhenology: _jsonBool(decoded['phenology']),
        searchQuery: _jsonBool(decoded['web_search'])
            ? _jsonString(decoded['query'])
            : null,
        category: _jsonString(decoded['category']) ?? 'none',
        answerMode: _answerModeAdaptive,
        answerRequirements: _jsonAnswerRequirements(
          decoded['answer_requirements'],
        ),
        primarySearchObjects: _jsonStringList(decoded['primary_objects']),
        secondarySearchObjects: _jsonStringList(decoded['secondary_objects']),
      );
    } catch (e) {
      debugPrint('豆包搜索计划异常: $e');
      return null;
    }
  }

  // 给“搜索计划模型”的提示词。
  // 重点：它只负责判断，不负责扮演角色回复。
  static String _searchPlannerPrompt(_WebProfile profile) {
    final now = DateTime.now();
    final today = _formatDate(now);
    return '''
你是聊天应用的“联网搜索计划器”，不是聊天角色本人。
你的任务是判断用户这句话是否需要补充现实信息、天气、节日、物候或作品原作资料。

当前日期：$today
当前年份：${now.year}
如果用户说“最近、近期、现在、当前、今年、这两年”，必须按当前日期理解；除非用户明确写出某个年份，否则 query 里不要使用过去的年份。

当前角色：${profile.characterName}
角色联网范围：${profile.contextRule}

请只输出一个 JSON 对象，不要输出 markdown，不要解释。

JSON 格式：
{
  "weather": true/false,
  "city": "城市名或空字符串",
  "festival": true/false,
  "phenology": true/false,
  "web_search": true/false,
  "category": "none/weather/festival/canon/slang/economy/current/general",
  "answer_requirements": [
    {
      "need": "用户问题中需要资料回答的独立问项",
      "direct_evidence_cues": ["原文若要直接回答该问项，必须明确表达的关系或限定语；不填写答案"]
    }
  ],
  "query": "需要网页搜索时使用的搜索词；不需要则空字符串",
  "primary_objects": ["原作搜索的主要对象；每项只写一个角色、地点、事件、歌曲或作品内专名"],
  "secondary_objects": ["需要补充搜索的次要对象；每项也只能写一个对象"]
}

判断原则：
0. 判定优先级：角色不应知道的现实世界信息优先于搜索需求。若问题需要现实运营、商业日程或现实活动资料才能回答，则不要搜索；这类信息不能因为包含作品内人物、乐队或组织名而改判成 canon。
1. 如果用户问“你那边外面怎么样、冷不冷、下雨了吗、热吗”等，即使没说天气，也应该 weather=true。
2. 如果用户问今天、最近、假期、节日、生日氛围等，festival=true。
3. 如果用户问外面景色、季节感、花、树、发芽、落叶、红叶、樱花、紫藤、桂花、银杏等，phenology=true。单纯问“今天天气如何/冷不冷/热不热/下雨吗”时，weather=true 但 phenology=false。
4. 如果用户提到角色经历、关系、过去事件、后来发展、某个角色“她/他/你”与其他人的关系，可能需要作品原作资料，web_search=true，category="canon"。
5. 如果用户问网络流行语、梗、最近流行说法，web_search=true，category="slang"。
6. 如果用户问经济、金融、股市、投资、房价、汇率，category="economy"。
7. 如果当前角色范围不允许某类搜索，也仍然按“用户意图”填写 category；程序之后会二次过滤。
8. query 要写成适合搜索引擎的中文关键词，不要太长；原作搜索时 query 只是兜底描述，真正搜索对象必须写进 primary_objects / secondary_objects。
9. 经济、新闻、政策类问题如果用户没有指定年份，query 必须包含当前年份 ${now.year} 和“最新/近期”等词。
10. 如果用户只是以当前角色视角问近况、心情、日常趣事、身边有没有好玩的事、想闲聊或撒娇，没有要求核实具体剧情、现实日期、新闻或政策，web_search=false，category="none"。
11. 对二次元角色，现实中的三次元企划、商业运营或现实活动安排属于角色不应知道的信息，web_search=false，category="none"。如果用户明确问作品剧情中的事件经过，再按原作资料处理。不要把这类现实时间变动问题改写为“当前年份 + 近期 + 作品名”的搜索问项。
12. 只要当前消息或最近对话涉及需要核实的作品内事实，宁可 web_search=true、category="canon"，不要让聊天模型凭记忆回答。作品内事实包括人物、人物关系、乐队/组织/学校/店铺/地点、事件、台词、口头禅、喜好、食物、身份、职位、集数、剧情和设定。
13. 如果用户是在问番剧、动画、漫画、电影、电视剧、书影音、角色、剧情、设定、歌曲、乐队、作品感想或“我最近在看什么”，不要判成 slang；这类优先 general 或 canon。
14. 如果用户是在辨认一句短的、口语化的、像网络热词/流行说法的表达，即使没有明确写“什么意思”，也可以判 slang。
15. 如果当前消息出现新对象，query 必须围绕新对象，不要沿用最近对话里的旧对象。
16. 原作 query 必须包含用户真正询问的对象；不要因为当前聊天角色是 ${profile.characterName} 就把 ${profile.characterName} 放进 query，除非用户确实在问 ${profile.characterName} 本人。
17. 如果问题围绕当前角色与另一个人物、地点或事件的作品内联系，query 优先写“被问到的具体对象 + 关系/事件 + 作品名”；当前角色名只能作为辅助词，不能重复出现。
18. 原作搜索对象拆分规则：先解析用户真正询问的主要对象，再解析需要补充的次要对象；每个数组元素只能是一个干净对象名，不要把问题整句、作品名、感想、关系词或多个对象拼成一项。例如问“KiLLKiSS这首歌怎么样”时，主要对象是“KiLLKiSS”；问“灯喜欢什么动物”时，主要对象是“高松灯”；问“你当初在那田蜘蛛山如何支援”且当前角色就是被问者时，主要对象是当前角色。
19. answer_requirements 只拆分用户实际需要回答的独立信息需求，不得在搜索前判断它是明确设定还是主观表达，也不要把寒暄、称呼或感想单独列成问项。
20. direct_evidence_cues 只描述原文直接回答该问项时必须明确表达的关系或限定语，不得填写人物、招式、地点等答案，不得判断网页中是否存在答案。它用于读取网页后的命题核验；没有特殊限定时可以为空数组。
''';
  }

  // 搜索计划模型有时会用 ```json 包起来。
  // 这里从返回文本中抠出第一个 JSON 对象。
  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  static bool _jsonBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static String? _jsonString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _jsonStringList(dynamic value) {
    if (value is! List) return const [];
    final result = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }

  static List<_AnswerRequirement> _jsonAnswerRequirements(dynamic value) {
    if (value is! List) return const [];
    final result = <_AnswerRequirement>[];
    final seen = <String>{};
    for (final item in value) {
      String text;
      List<String> directEvidenceCues;
      if (item is String) {
        text = item.trim();
        directEvidenceCues = const [];
      } else if (item is Map) {
        text = _dynamicMapString(item, 'need').trim();
        directEvidenceCues = _jsonStringList(item['direct_evidence_cues']);
      } else {
        continue;
      }
      if (text.isEmpty || !seen.add(text)) continue;
      result.add(_AnswerRequirement(
        text: text,
        directEvidenceCues: directEvidenceCues,
      ));
    }
    return result;
  }

  static List<int> _jsonIntList(
    dynamic value, {
    required int maxExclusive,
  }) {
    if (value is! List || maxExclusive <= 0) return const [];
    final result = <int>[];
    for (final item in value) {
      final index = item is int ? item : int.tryParse(item.toString());
      if (index == null || index < 0 || index >= maxExclusive) continue;
      if (!result.contains(index)) result.add(index);
    }
    return result;
  }

  static String _recentHistoryForPlanner(List<Message> conversationHistory) {
    if (conversationHistory.isEmpty) return '（无）';

    return conversationHistory.reversed
        .take(6)
        .toList()
        .reversed
        .map((message) {
      final role = message.role == 'assistant' ? '角色' : '用户';
      final content = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final shortened =
          content.length > 180 ? '${content.substring(0, 180)}...' : content;
      return '$role：$shortened';
    }).join('\n');
  }

  // 本地关键词方案：作为豆包搜索计划失败时的兜底。
  static _SearchPlan _keywordSearchPlan(String text, _WebProfile profile) {
    return _SearchPlan(
      includeWeather: _asksWeather(text),
      weatherCity: _extractWeatherCity(text, profile),
      includeFestivals: _shouldMentionDateOrFestival(text),
      includePhenology: _asksPhenology(text),
      searchQuery: _shouldSearchWeb(text, profile)
          ? _buildSearchQuery(text, profile)
          : null,
      category: _asksCanon(text)
          ? 'canon'
          : _asksEconomy(text)
              ? 'economy'
              : 'general',
    );
  }

  // 二次过滤：无论搜索计划模型怎么判断，最终都必须服从角色权限。
  // 这能避免“祥子去查股市”或“鬼灭角色去查现代热点”。
  static _SearchPlan _applyProfileRules(
      _SearchPlan plan, String text, _WebProfile profile,
      {bool allowImplicitCurrentAffairsSearch = true}) {
    // 天气问题用“大模型判断 + 本地关键词”双保险。
    //
    // 原因：
    // 搜索计划模型偶尔会把“今天天气如何”这种很短的日常问句
    // 当成普通寒暄，返回 weather=false。那样后面就完全不会查天气，
    // 角色只能按人设和想象发挥，很容易说出“雷雨/下雨”。
    //
    // 所以：只要本地关键词明确命中天气，就强制 includeWeather=true。
    final keywordWeather = _asksWeather(text);
    final includeWeather =
        profile.includeWeather && (plan.includeWeather || keywordWeather);
    final weatherCity = includeWeather
        ? profile.allowUserWeatherCity
            ? (plan.weatherCity ??
                _extractWeatherCity(text, profile) ??
                profile.weatherCity)
            : profile.weatherCity
        : null;

    final includeFestivals = profile.includeFestivals && plan.includeFestivals;
    final includePhenology = profile.includePhenology && plan.includePhenology;

    String? searchQuery = plan.searchQuery;
    var category = plan.category;
    final isPlainWeatherQuestion =
        keywordWeather && !RegExp(r'新闻|台风|暴雨|预警|灾害|最近|近期').hasMatch(text);
    final entertainmentTopicPattern = RegExp(
      r'番剧|动画|漫画|电影|电视剧|书影音|乐队|歌曲|曲子|音乐|作品|角色|剧情|设定|台词|人设|追番',
      caseSensitive: false,
    );
    final slangIntentPattern = RegExp(
      r'流行语|梗|热梗|网络热词|网络流行说法|什么意思|指什么|怎么理解|最近.*流行|最近.*很火|这词|这句话',
      caseSensitive: false,
    );

    if (category == 'slang' && !slangIntentPattern.hasMatch(text)) {
      category = entertainmentTopicPattern.hasMatch(text) ? 'general' : 'none';
      searchQuery = null;
    } else if ((category == 'none' || category == 'general') &&
        !entertainmentTopicPattern.hasMatch(text) &&
        slangIntentPattern.hasMatch(text)) {
      category = 'slang';
    }
    if ((category == 'none' || category == 'general') &&
        searchQuery == null &&
        allowImplicitCurrentAffairsSearch &&
        _textLooksLikeCurrentAffairsQuestion(text) &&
        _requiresAuthoritativeDoubaoSearch('general', profile)) {
      category = 'general';
      searchQuery = _buildSearchQuery(text, profile);
    }
    if (searchQuery == null && category == 'slang') {
      searchQuery = _buildSearchQuery(text, profile);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      if (category == 'canon' &&
          profile.seriesName == '欢乐颂' &&
          !_canonTextContainsTerm(text, profile.seriesName) &&
          !_canonTextContainsTerm(text, profile.characterName)) {
        category = 'general';
      }

      // 天气和节日都有专门的数据来源：
      // - 天气走天气 API，拿“当前状态/降水量”
      // - 节日走受角色作品限制的节日搜索和本地兜底列表
      //
      // 所以这里故意关掉普通网页搜索。
      // 否则搜索摘要里只要出现“雷雨/阵雨/梅雨”等词，
      // DeepSeek 就可能把它和天气 API 混在一起，误说正在下雨。
      if (isPlainWeatherQuestion ||
          category == 'weather' ||
          category == 'festival') {
        searchQuery = null;
      } else if (category == 'economy' && !profile.allowEconomySearch) {
        searchQuery = null;
      } else if (profile.onlyCanonSearch && category != 'canon') {
        searchQuery = null;
      } else {
        searchQuery =
            _normalizeSearchQuery(searchQuery, category, text, profile);
      }
    }

    final primarySearchObjects = category == 'canon'
        ? _removeUnmentionedPlannerCharacterObjects(
            plan.primarySearchObjects,
            text,
            profile,
          )
        : plan.primarySearchObjects;
    final secondarySearchObjects = category == 'canon'
        ? _removeUnmentionedPlannerCharacterObjects(
            plan.secondarySearchObjects,
            text,
            profile,
          )
        : plan.secondarySearchObjects;

    return _SearchPlan(
      includeWeather: includeWeather,
      weatherCity: weatherCity,
      includeFestivals: includeFestivals,
      includePhenology: includePhenology,
      searchQuery: searchQuery,
      category: category,
      answerMode: _answerModeAdaptive,
      answerRequirements: plan.answerRequirements,
      primarySearchObjects: primarySearchObjects,
      secondarySearchObjects: secondarySearchObjects,
    );
  }

  static List<String> _removeUnmentionedPlannerCharacterObjects(
    List<String> objects,
    String userText,
    _WebProfile profile,
  ) {
    if (objects.isEmpty) return objects;
    final mentionedCharacters = _matchedCanonNamesForSearch(
      userText,
      '',
      profile,
    ).map((name) => name.replaceAll(RegExp(r'\s+'), '')).toSet();
    if (_asksAboutCurrentCharacterInCanon(userText)) {
      mentionedCharacters.add(
        profile.characterName.replaceAll(RegExp(r'\s+'), ''),
      );
    }

    final filtered = <String>[];
    for (final object in objects) {
      final normalized = _normalizeCanonSearchObject(
        object,
        userText,
        profile,
      ).replaceAll(RegExp(r'\s+'), '');
      if (normalized.isEmpty) continue;
      if (_isKnownCanonCharacterSearchObject(normalized, profile) &&
          !mentionedCharacters.contains(normalized)) {
        continue;
      }
      if (!filtered.contains(normalized)) filtered.add(normalized);
    }
    return filtered;
  }

  // 把搜索计划模型给出的搜索词再整理一下：
  // - 原作搜索一定加作品前缀，但不强塞当前聊天角色名
  // - 经济/新闻类加地区提示
  // - 如果模型没给 query，就用旧规则生成一个
  static String _normalizeSearchQuery(
    String query,
    String category,
    String text,
    _WebProfile profile,
  ) {
    final now = DateTime.now();
    var trimmed =
        query.trim().isEmpty ? _buildSearchQuery(text, profile) : query.trim();

    if (category == 'canon') {
      if (_canonQueryLooksPollutedByPlanner(trimmed, text)) {
        trimmed = _fallbackCanonQueryFromUserText(text, profile);
      }
      final matchedNames = _matchedCanonNamesForSearch(text, '', profile)
          .where((name) => name.trim() != profile.characterName.trim())
          .toList();
      if (!_asksAboutCurrentCharacterInCanon(text) && matchedNames.isNotEmpty) {
        trimmed = _dedupeSearchQueryTerms([
          profile.canonSearchPrefix,
          ...matchedNames.take(2),
          _compactUserQuestionForSearch(text),
        ].join(' '));
      }
      final shouldAddSeriesPrefix = profile.seriesName == '欢乐颂'
          ? (_canonTextContainsTerm(text, profile.seriesName) ||
              _canonTextContainsTerm(text, profile.characterName))
          : true;
      if (shouldAddSeriesPrefix &&
          !trimmed.contains(profile.canonSearchPrefix)) {
        trimmed = '${profile.canonSearchPrefix} $trimmed';
      }
      trimmed =
          _deemphasizeCurrentCharacterInCanonQuery(trimmed, text, profile);
      return _dedupeSearchQueryTerms(trimmed);
    }

    if (category == 'economy' || category == 'current') {
      // “最近/现在/今年”这类问题必须按运行时当前年份理解。
      // 搜索计划模型有时会受训练语料影响，把最近经济形势写成 2025。
      // 如果用户原话没有明确指定年份，就把搜索词里的旧年份替换成当前年份。
      if (!_userExplicitlyMentionedYear(text)) {
        trimmed = trimmed.replaceAll(RegExp(r'20\d{2}年?'), '').trim();
        if (!trimmed.contains('${now.year}')) {
          trimmed = '${now.year}年 $trimmed';
        }
      }

      if (profile.searchRegionHint.isNotEmpty &&
          !trimmed.contains(profile.searchRegionHint)) {
        trimmed = '$trimmed ${profile.searchRegionHint}';
      }
      if (!RegExp(r'最新|近期|当前|现在|形势|趋势|展望').hasMatch(trimmed)) {
        trimmed = '$trimmed 最新';
      }
    }

    return trimmed;
  }

  static bool _canonQueryLooksPollutedByPlanner(String query, String text) {
    final queryTerms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty);
    for (final term in queryTerms) {
      if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(term) &&
          !text.contains(term)) {
        return true;
      }
    }
    return false;
  }

  static String _fallbackCanonQueryFromUserText(
    String text,
    _WebProfile profile,
  ) {
    final compact = _compactUserQuestionForSearch(text);
    final subject = compact.isEmpty ? profile.characterName : compact;
    return '${profile.canonSearchPrefix} ${profile.characterName} $subject';
  }

  static String _compactUserQuestionForSearch(String text) {
    final candidates = <String>[];
    final normalized = _stripAddressForSearch(text)
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final match
        in RegExp(r'[A-Za-z][A-Za-z0-9!★☆*._-]{1,30}').allMatches(normalized)) {
      candidates.add(match.group(0)!);
    }
    for (final match
        in RegExp(r'[\u4e00-\u9fa5ぁ-んァ-ンー]{2,16}').allMatches(normalized)) {
      final term = match.group(0) ?? '';
      if (_isQuestionIntentTerm(term)) continue;
      if (_canonQueryNoiseTerms.contains(term.toLowerCase())) continue;
      candidates.add(term);
    }

    return _dedupeSearchQueryTerms(candidates.take(5).join(' '));
  }

  static String _stripAddressForSearch(String text) {
    return text
        .replaceAll(
          RegExp(
            r'(^|[\s，。！？、,.!?；;：:])[\u4e00-\u9fa5ぁ-んァ-ンー]{1,8}(?:小姐|先生|老师|前辈|学姐|学长|同学|姐姐|哥哥|ちゃん|さん|くん|君|様)(?=$|[\s，。！？、,.!?；;：:])',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _searchLocalCharacterProfile(
    String query,
    _WebProfile profile, {
    String userIntent = '',
  }) {
    try {
      final character = CharacterConfig.getCharacterById(profile.characterId);
      final rawPersonality = character.personality;
      final personality = rawPersonality.replaceAll(RegExp(r'\s+'), ' ');
      final intentText = userIntent.trim().isEmpty ? query : userIntent;
      final relatedNames = _matchedCanonNamesForSearch(
        query,
        userIntent,
        profile,
      ).where((name) => name.trim() != character.name.trim()).toList();
      final relatedSnippets = <String>[];
      for (final name in relatedNames.take(3)) {
        var relatedSnippet = _localProfileTraitSnippet(
          rawPersonality,
          name,
          intentText,
        );
        relatedSnippet = relatedSnippet.isNotEmpty
            ? relatedSnippet
            : _relevantRawSnippet(
                personality,
                '$name $query',
                character.name,
                maxLength: 900,
                maxFragments: 4,
                minLength: 180,
                anchorTerms: [name],
              );
        relatedSnippet = relatedSnippet.isNotEmpty
            ? relatedSnippet
            : _relevantRawSnippet(
                personality,
                name,
                character.name,
                maxLength: 900,
                maxFragments: 4,
                minLength: 180,
                anchorTerms: [name],
              );
        if (relatedSnippet.isEmpty) continue;
        relatedSnippets.add(
          '${relatedSnippets.length + 1}. ${character.name}设定中关于$name：$relatedSnippet',
        );
      }
      if (relatedSnippets.isNotEmpty) return relatedSnippets;

      final snippet = _relevantRawSnippet(
        personality,
        query,
        character.name,
        maxLength: 1200,
        maxFragments: 8,
        minLength: 180,
      );
      if (snippet.isNotEmpty) {
        return ['1. ${character.name}：相关设定：$snippet'];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static String _localProfileTraitSnippet(
    String rawPersonality,
    String name,
    String query,
  ) {
    if (!_queryAsksProfileTraits(query)) return '';
    final fragments = rawPersonality
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n+|(?=·\s*)'))
        .map((fragment) => fragment.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((fragment) => fragment.isNotEmpty);

    for (final fragment in fragments) {
      if (!_canonTextContainsTerm(fragment, name)) continue;
      if (!RegExp(r'兴趣|愛好|爱好|喜欢|喜好|讨厌|常去|地方|地点|场所').hasMatch(fragment)) {
        continue;
      }
      return _truncateSearchSnippet(fragment, maxLength: 900);
    }

    return '';
  }

  static bool _queryAsksProfileTraits(String query) {
    return RegExp(r'兴趣|愛好|爱好|喜欢|喜好|讨厌|动物|食物|闲暇|空闲|常去|地方|地点|场所').hasMatch(query);
  }

  static List<String> _localProfileResultsAsSearchFacts(List<String> results) {
    return results.map((result) {
      final item = _stripSearchIndex(result).trim();
      return '本地角色设定：相关事实：$item';
    }).toList(growable: false);
  }

  static List<String> _canonDirectTitleHints(
    String query,
    String userText,
    _WebProfile profile,
    String relatedCanonTerm,
  ) {
    final hints = <String>[];
    void add(String value) {
      final title = value.replaceAll(RegExp(r'\s+'), '').trim();
      if (title.length < 2 || hints.contains(title)) return;
      if (_canonQueryNoiseTerms.contains(title.toLowerCase())) return;
      if (_isQuestionIntentTerm(title)) return;
      hints.add(title);
    }

    final corpus = '$query $userText';
    void addConfiguredCharacterNames() {
      for (final character in CharacterConfig.characters) {
        if (_WebProfile._seriesNameForCharacterId(character.id) !=
            profile.seriesName) {
          continue;
        }
        final name = character.name.trim();
        if (name.isEmpty) continue;
        if (_canonTextContainsTerm(corpus, name)) {
          add(name);
          continue;
        }

        final runes = name.runes.toList();
        if (runes.length >= 4) {
          final lastTwo = String.fromCharCodes(runes.sublist(runes.length - 2));
          if (_canonTextContainsTerm(corpus, lastTwo)) add(name);
        } else if (runes.length == 3) {
          final lastTwo = String.fromCharCodes(runes.sublist(1));
          if (_canonTextContainsTerm(corpus, lastTwo)) add(name);
        }
      }
    }

    void addNamesFromTranslationList() {
      for (final name in ApiService.canonicalChineseNamesForSearch(
        characterId: profile.characterId,
      )) {
        if (_canonTextContainsTerm(corpus, name)) {
          add(name);
          continue;
        }
        final runes = name.runes.toList();
        if (runes.length >= 4) {
          final lastTwo = String.fromCharCodes(runes.sublist(runes.length - 2));
          if (_canonTextContainsTerm(corpus, lastTwo)) add(name);
        } else if (runes.length == 3) {
          final lastTwo = String.fromCharCodes(runes.sublist(1));
          if (_canonTextContainsTerm(corpus, lastTwo)) add(name);
        }
      }
    }

    for (final term in _explicitCanonTitleTerms(userText, query)) {
      add(term);
    }
    add(relatedCanonTerm);
    addConfiguredCharacterNames();
    addNamesFromTranslationList();

    return hints.take(8).toList();
  }

  static String _deemphasizeCurrentCharacterInCanonQuery(
    String query,
    String text,
    _WebProfile profile,
  ) {
    final characterName = profile.characterName.trim();
    if (characterName.isEmpty) return query;

    final terms = query.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
    final otherTerms = terms.where((term) {
      final cleaned = term.trim();
      if (cleaned.isEmpty) return false;
      if (cleaned == profile.canonSearchPrefix) return false;
      if (cleaned == characterName) return false;
      if (_canonQueryNoiseTerms.contains(cleaned.toLowerCase())) return false;
      return true;
    }).toList();

    // 如果 query 里已经有更具体的对象，
    // 当前聊天角色名就不再作为主搜索词，避免搜索结果被当前角色百科带偏。
    if (otherTerms.length >= 2) {
      return terms.where((term) => term.trim() != characterName).join(' ');
    }

    return query;
  }

  static const Set<String> _canonQueryNoiseTerms = {
    '鬼灭之刃',
    'bang',
    'dream',
    '欢乐颂',
    'ave',
    'mujica',
    'mygo',
    'crychic',
    'poppin',
    '角色',
    '角色设定',
    '人物',
    '名字',
    '名称',
    '叫法',
    '介绍',
    '资料',
    '百科',
    '剧情',
    '设定',
    '性格',
    '关系',
    '救赎',
    '相互救赎',
    '影响',
    '变化',
    '经过',
    '时期',
    '阶段',
    '组成时期',
    '那段时间',
    '学生',
    '学校',
    '学园',
    '女子',
    '高中',
    '年级',
  };

  static const Set<String> _canonQueryContextTerms = {
    '鬼灭之刃',
    'bang',
    'dream',
    'ave',
    'mujica',
    'mygo',
    'crychic',
    'poppin',
    '欢乐颂',
  };

  static String _dedupeSearchQueryTerms(String query) {
    final terms = query.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
    final seen = <String>{};
    final deduped = <String>[];

    for (final term in terms) {
      final cleaned = term.trim();
      if (cleaned.isEmpty) continue;
      final key = cleaned.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      deduped.add(cleaned);
    }

    return deduped.join(' ');
  }

  // 原作事实搜索守门：
  //
  // 先用少量本地结构规则兜住明显的原作对象，再让 DeepSeek 做一次语义判断。
  // 这样第二轮追问或新提到的角色/地点/设定不必依赖手写角色名单。
  static Future<_SearchPlan> _applySemanticCanonGuard(_SearchPlan plan,
      String text, _WebProfile profile, List<Message> conversationHistory,
      {required bool allowLocalCanonRecovery}) async {
    final localPlan = allowLocalCanonRecovery
        ? _applyFollowUpRules(plan, text, profile, conversationHistory)
        : plan;
    if (localPlan.hasAnyTask) return localPlan;
    if (!allowLocalCanonRecovery) return localPlan;

    final guardPlan = await _buildCanonGuardPlanWithDeepSeek(
      text,
      profile,
      conversationHistory,
    );
    if (guardPlan == null) return localPlan;

    final filteredPlan = _applyProfileRules(guardPlan, text, profile);
    if (filteredPlan.searchQuery != null &&
        filteredPlan.searchQuery!.isNotEmpty) {
      debugPrint('原作事实守门员触发 canon 搜索: ${filteredPlan.searchQuery}');
    }
    return filteredPlan;
  }

  static Future<_SearchPlan?> _buildCanonGuardPlanWithDeepSeek(
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
    if (profile.canonSearchPrefix.trim().isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_deepSeekBaseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_deepSeekApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _deepSeekModel,
              'thinking': {'type': 'disabled'},
              'messages': [
                {
                  'role': 'system',
                  'content': _canonGuardPrompt(profile),
                },
                {
                  'role': 'user',
                  'content': '''
最近对话：
${_recentHistoryForPlanner(conversationHistory)}

用户刚发来的消息：$text
''',
                },
              ],
              'max_tokens': 220,
              'temperature': 0,
              'stream': false,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('原作事实守门员判定失败: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      if (content is! String || content.trim().isEmpty) return null;

      final jsonText = _extractJsonObject(content);
      if (jsonText == null) return null;

      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;

      final shouldSearch = _jsonBool(decoded['canon_search']);
      final query = _jsonString(decoded['query']);
      if (!shouldSearch || query == null || query.isEmpty) return null;

      return _SearchPlan(
        includeWeather: false,
        weatherCity: null,
        includeFestivals: false,
        includePhenology: false,
        searchQuery: _normalizeSearchQuery(query, 'canon', text, profile),
        category: 'canon',
        answerMode: _answerModeAdaptive,
        answerRequirements: _jsonAnswerRequirements(
          decoded['answer_requirements'],
        ),
        primarySearchObjects: _jsonStringList(decoded['primary_objects']),
        secondarySearchObjects: _jsonStringList(decoded['secondary_objects']),
      );
    } catch (e) {
      debugPrint('原作事实守门员异常: $e');
      return null;
    }
  }

  static String _canonGuardPrompt(_WebProfile profile) {
    return '''
你是“原作事实搜索守门员”，不是聊天角色。
你的任务：判断用户当前消息是否需要搜索作品原作/设定资料，避免聊天模型凭记忆编错。

当前角色：${profile.characterName}
所属作品：${profile.seriesName}
允许的原作搜索前缀：${profile.canonSearchPrefix}

只输出 JSON，不要解释：
{
  "canon_search": true/false,
  "answer_requirements": [
    {
      "need": "需要原作资料回答的独立问项；不预判事实等级",
      "direct_evidence_cues": ["原文若要直接回答该问项，必须明确表达的关系或限定语；不填写答案"]
    }
  ],
  "query": "需要搜索时给出简短搜索词；不需要则空字符串",
  "primary_objects": ["主要搜索对象；每项只写一个角色、地点、事件、歌曲或作品内专名"],
  "secondary_objects": ["次要搜索对象；每项也只写一个对象"]
}

必须 canon_search=true 的情况：
- 用户提到或追问作品内已经发生的剧情、稳定设定或角色可合理知道的作品内事实，例如人物、人物关系、乐队/组织/学校/店铺/地点、事件、台词、口头禅、喜好、食物、道具、身份、职位、集数、剧情和设定。
- 用户没有明确说作品名，但最近对话正在聊作品设定，而当前消息用“她/他/这个/那个/同学/那家店/那句话”等继续追问。
- 当前问题只要回答错会造成角色、关系、归属、喜好、地点或剧情事实错误，就应该搜索。

必须 canon_search=false 的情况：
- 纯问候、闲聊感受、情绪陪伴、现实天气/节日/经济等非原作内容。
- 用户询问现实运营、商业日程或现实活动安排时，即使问题里出现作品内角色、乐队或组织名，也不是原作事实；二次元角色不应通过联网知道这些三次元信息。

query 规则：
- 用当前作品名 + 当前消息里最核心的人物/地点/物品/事件 + 设定类型。
- query 要短，不要整句复制用户消息，不要把最近历史里的旧话题强行带入新话题。
- 如果当前消息出现新对象，优先搜索新对象，不要沿用历史旧对象。
- primary_objects / secondary_objects 必须拆成干净对象名；不要把作品名、问题整句、感想或关系词拼进去。
- answer_requirements 只负责拆分需要查证的独立问项。是否存在明确设定、是否只能得到候选范围，必须留给读取网页后的事实抽取判断。
- direct_evidence_cues 只写直接证据必须表达的关系或限定语，不写答案，也不判断资料是否存在。例如问项包含频率或偏好限定时，保留该限定关系；普通身份或名称问项可以为空。
''';
  }

  static _SearchPlan _applyFollowUpRules(
    _SearchPlan plan,
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) {
    final currentTopic = _currentCanonTopic(text);
    final canInheritRecentTopic =
        currentTopic == null && _containsCanonFollowUpSignal(text);
    final recentTopic = canInheritRecentTopic
        ? _recentCanonTopic(conversationHistory, profile)
        : null;

    if (!plan.hasAnyTask && _shouldForceCanonSearch(text, recentTopic)) {
      final topic = currentTopic ?? recentTopic ?? text;
      final query = _buildCanonFollowUpSearchQuery(text, topic, profile);
      debugPrint('检测到原作相关内容，强制 canon 搜索: $query');
      return _SearchPlan(
        includeWeather: false,
        weatherCity: null,
        includeFestivals: false,
        includePhenology: false,
        searchQuery: query,
        category: 'canon',
      );
    }

    if (plan.hasAnyTask) return plan;
    if (!_looksLikeFollowUpQuestion(text)) return plan;

    final topic = currentTopic ?? recentTopic;
    if (topic == null || topic.isEmpty) return plan;

    final query = _buildCanonFollowUpSearchQuery(text, topic, profile);
    debugPrint('检测到原作资料追问，补充 canon 搜索: $query');

    return _SearchPlan(
      includeWeather: false,
      weatherCity: null,
      includeFestivals: false,
      includePhenology: false,
      searchQuery: query,
      category: 'canon',
    );
  }

  // 原作搜索词要短：作品名 + 被追问对象 + 本轮问题焦点。
  // 搜索词越接近日常检索习惯，豆包搜索越不容易跑偏或超时。
  static String _buildCanonFollowUpSearchQuery(
    String text,
    String topic,
    _WebProfile profile,
  ) {
    final seriesPrefix = _canonSeriesSearchPrefix(profile);
    final subject = _compactCanonSearchTerms(topic);
    final currentTerms = _compactCanonSearchTerms(text);
    final focus = currentTerms == text ? '原作 设定 剧情' : '$currentTerms 原作 设定 剧情';
    return '$seriesPrefix $subject $focus'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _canonSeriesSearchPrefix(_WebProfile profile) {
    if (profile.seriesName == 'BanG Dream') return 'BanG Dream';
    if (profile.seriesName == '鬼灭之刃') return '鬼灭之刃';
    if (profile.seriesName == '欢乐颂') return '欢乐颂';
    return profile.seriesName == '未分类'
        ? profile.characterName
        : profile.seriesName;
  }

  static bool _looksLikeFollowUpQuestion(String text) {
    // “这个我知道……”通常是在补充新信息，不是追问。
    // 这种情况下如果句子里出现新角色，应优先让 planner 或当前实体识别处理。
    if (RegExp(r'^这个我知道|^这个我懂').hasMatch(text.trim())) {
      return _currentCanonTopic(text) != null;
    }
    return RegExp(
      r'这个|这件事|这段|这些|这种|那个|那件事|那段|那些|那种|这是什么意思|什么意思|指什么|怎么理解|她|他|它|TA|刚才|上面|前面|后来|之后|当时|那时候',
    ).hasMatch(text);
  }

  // 当前用户消息里明确提到的新原作对象，优先级高于历史话题。
  // 这里不维护角色名单，而是抓“称呼、地点、事件、台词、设定词”等结构。
  static String? _currentCanonTopic(String text) {
    if (!_containsCanonEntitySignal(text)) return null;
    final terms = _extractCanonSearchTerms(text);
    if (terms.isEmpty) return null;
    return terms.join(' ');
  }

  static bool _shouldForceCanonSearch(
    String text,
    String? recentTopic,
  ) {
    if (_currentCanonTopic(text) != null) return true;
    if (_asksCanon(text)) return true;
    if (recentTopic != null && _containsCanonFollowUpSignal(text)) return true;
    return false;
  }

  static String? _recentCanonTopic(
    List<Message> conversationHistory,
    _WebProfile profile,
  ) {
    final recent = conversationHistory.reversed.take(6).toList().reversed;
    final joined = recent.map((m) => m.content).join('\n');
    if (joined.trim().isEmpty) return null;

    final hasCanonContext = _asksCanon(joined) ||
        joined.contains(profile.canonSearchPrefix) ||
        joined.contains(profile.seriesName) ||
        _containsCanonEntitySignal(joined);
    if (!hasCanonContext) return null;

    final terms = _extractCanonSearchTerms(joined);
    if (terms.isEmpty) return profile.canonSearchPrefix;
    return terms.take(6).join(' ');
  }

  static List<String> _extractCanonSearchTerms(String text) {
    final terms = <String>[];

    void addTerm(String value) {
      final cleaned = value
          .replaceAll(RegExp(r'[，。！？、,.!?；;：:\n\r\t]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length < 2) return;
      if (cleaned.length > 30) {
        terms.add(cleaned.substring(0, 30));
      } else {
        terms.add(cleaned);
      }
    }

    for (final match
        in RegExp(r'[“"「『《]([^”"」』》]{2,24})[”"」』》]').allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match
        in RegExp(r"([A-Za-z][A-Za-z0-9!'’ ._-]{2,30})").allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r'([\u4e00-\u9fa5ぁ-んァ-ンー]{1,8})(?:同学|同窗|さん|桑|ちゃん|君|前辈|老师|先生|小姐)',
    ).allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r"([\u4e00-\u9fa5ぁ-んァ-ンーA-Za-z0-9!'’ ._-]{2,18}(?:乐队|学校|学园|学院|面包房|烘焙坊|商店街|店|家|社团|livehouse|ライブハウス))",
      caseSensitive: false,
    ).allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r"([\u4e00-\u9fa5ぁ-んァ-ンーA-Za-z0-9!'’ ._-]{2,18}(?:台词|口头禅|口癖|名言|称呼|关系|事件|设定|剧情|食物|面包|料理|鼓手|吉他手|主唱|键盘手|贝斯手))",
      caseSensitive: false,
    ).allMatches(text)) {
      addTerm(match.group(1)!);
    }

    return terms.toSet().take(8).toList();
  }

  static String _compactCanonSearchTerms(String topic) {
    final terms = _extractCanonSearchTerms(topic);
    if (terms.isNotEmpty) return terms.take(5).join(' ');
    return topic.length > 36 ? topic.substring(0, 36) : topic;
  }

  static bool _containsCanonEntitySignal(String text) {
    return RegExp(
      r'BanG|Poppin|Ave Mujica|MyGO|CRYCHIC|鬼灭|欢乐颂|'
      r'同学|さん|ちゃん|前辈|乐队|学校|学园|'
      r'面包房|烘焙坊|商店街|livehouse|ライブハウス|'
      r'鼓手|吉他手|主唱|键盘手|贝斯手|台词|设定|剧情|人物关系|'
      r'食物|面包|喜欢吃|爱吃|口头禅|口癖|名言|事件',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _containsCanonFollowUpSignal(String text) {
    return RegExp(
      r'这个|这件事|这段|这些|这种|那个|那件事|那段|那些|那种|她|他|它|TA|刚才|上面|前面|后来|之后|当时|那时候',
    ).hasMatch(text);
  }

  // ========================================
  // 下面这些 _asksXXX 方法：判断用户这句话想问什么
  // ========================================
  // 这里是模型判定失败时的本地兜底。
  // 主路径仍然由搜索计划模型 / 原作事实守门员做语义判断。

  // 判断是否和日期/节日有关。
  static bool _shouldMentionDateOrFestival(String text) {
    return RegExp(
      r'日期|星期|周几|节日|假期|节气|纪念日|生日|什么日子|几月几|'
      r'明天|后天|今天.*(?:节|假|星期|周几|日期|什么日子)|(?:节|假).*今天',
    ).hasMatch(text);
  }

  // 判断是否和天气有关。
  static bool _asksWeather(String text) {
    return RegExp(r'天气|气温|下雨|降雨|冷不冷|热不热|温度|台风|空气质量').hasMatch(text);
  }

  // 判断是否和物候有关。
  // 物候就是季节变化在自然界里的表现，比如开花、发芽、蝉鸣、红叶、落叶。
  static bool _asksPhenology(String text) {
    return RegExp(
            r'物候|花|开花|花期|花开|花谢|樱花|紫藤|梅花|桂花|银杏|红叶|枫叶|落叶|发芽|新绿|蝉|蝉鸣|梅雨|季节|景色|外面')
        .hasMatch(text);
  }

  // 判断是否和原作/原剧/角色设定有关。
  // 鬼灭角色的网页搜索只允许这一类问题。
  static bool _asksCanon(String text) {
    return RegExp(
      r'原作|原剧|剧情|设定|人物关系|台词|出处|动画|漫画|电视剧|'
      r'欢乐颂|鬼灭|BanG|MyGO|Ave Mujica|CRYCHIC|Poppin|'
      r'角色|同学|さん|ちゃん|前辈|乐队|学校|学园|'
      r'面包房|烘焙坊|商店街|livehouse|ライブハウス|'
      r'鼓手|吉他手|主唱|键盘手|贝斯手|'
      r'喜欢吃|爱吃|口头禅|口癖|名言|第\d+集|第[一二三四五六七八九十]+集',
      caseSensitive: false,
    ).hasMatch(text);
  }

  // 判断是否和经济金融有关。
  // 目前只有安迪允许查这类内容。
  static bool _asksEconomy(String text) {
    return RegExp(r'经济|金融|股市|股票|基金|汇率|利率|通胀|财政|货币政策|房地产|房价|公司财报|投资|市场行情')
        .hasMatch(text);
  }

  // 用户如果明确写了年份，例如“2025 年经济形势”，程序就尊重这个年份。
  // 如果没写年份，只说“最近/现在/今年”，搜索词会被归到当前年份。
  static bool _userExplicitlyMentionedYear(String text) {
    return RegExp(r'20\d{2}\s*年?').hasMatch(text);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  // 综合判断：这句话到底要不要网页搜索。
  //
  // 注意：
  // - 普通天气不走网页搜索，因为天气接口更准确。
  // - 如果角色不允许经济搜索，经济类问题不会触发搜索。
  // - 如果是鬼灭角色，只允许原作/剧情类搜索。
  static bool _shouldSearchWeb(String text, _WebProfile profile) {
    if (_asksWeather(text) && !RegExp(r'新闻|台风|暴雨|预警|灾害|最近|近期').hasMatch(text)) {
      return false;
    }
    if (_asksEconomy(text) && !profile.allowEconomySearch) return false;
    if (profile.onlyCanonSearch) return _asksCanon(text);
    return RegExp(
      r'最近|近期|现在|今天|新闻|热搜|流行语|梗|什么意思|经济|股市|汇率|政策|书|电影|电视剧|动画|漫画|原作|原剧|剧情|设定|人物关系|台词|出处|真实|资料|百科',
    ).hasMatch(text);
  }

  // ========================================
  // 构造搜索关键词
  // ========================================
  // 用户原话不一定适合直接搜索，所以这里会加一些前缀/后缀：
  // - 原作问题：加作品名和角色名，避免搜到无关内容
  // - 流行语：加“网络流行语 含义”
  // - 最近新闻：加地区提示和“最新”
  static String _buildSearchQuery(String text, _WebProfile profile) {
    final trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (RegExp(r'原作|原剧|剧情|设定|人物关系|台词|出处').hasMatch(trimmed)) {
      return '${profile.canonSearchPrefix} $trimmed';
    }
    if (RegExp(r'流行语|梗|什么意思').hasMatch(trimmed)) {
      return '$trimmed 网络流行语 含义';
    }
    if (RegExp(r'最近|近期|现在|今天|新闻|经济|股市|政策').hasMatch(trimmed)) {
      final regionHint = profile.searchRegionHint.isEmpty
          ? ''
          : ' ${profile.searchRegionHint}';
      return '$trimmed$regionHint 最新';
    }
    return trimmed;
  }

  // ========================================
  // 从用户句子里提取天气城市
  // ========================================
  // 这里有一个角色限制：
  // - 安迪 allowUserWeatherCity = true，可以问“北京天气”“东京天气”
  // - 祥子/鬼灭 allowUserWeatherCity = false，即使用户提上海，也仍查东京
  //   这样角色不会突然生活到不属于她的地方。
  static String? _extractWeatherCity(String text, _WebProfile profile) {
    const knownCities = [
      '上海',
      '北京',
      '南通',
      '广州',
      '深圳',
      '杭州',
      '南京',
      '苏州',
      '成都',
      '重庆',
      '武汉',
      '西安',
      '东京',
      '大阪',
      '纽约',
      '洛杉矶',
      '伦敦',
      '巴黎',
    ];
    for (final city in knownCities) {
      if (text.contains(city)) {
        return profile.allowUserWeatherCity ? city : profile.weatherCity;
      }
    }
    final match = RegExp(r'([\u4e00-\u9fa5]{2,8})(?:的)?天气').firstMatch(text);
    final matchedCity = match?.group(1);
    if (matchedCity == null) return null;
    if (!profile.allowUserWeatherCity) return profile.weatherCity;
    return matchedCity;
  }

  // ========================================
  // 生成本地节日上下文
  // ========================================
  // 注意：现在节日主路径已经改成联网搜索。
  // 这个本地表只是兜底：当搜索失败时，至少还能给角色一点基本节日信息。
  // profile 会按“番剧/作品名”决定节日范围：
  // - 鬼灭之刃：大正时期已经存在的日本民俗/季节行事
  // - BanG Dream：现代日本非政治节日/行事 + 国际节日
  // - 欢乐颂：现代中国节日 + 国际节日
  //
  // 这里只返回“今天以后最近的 3 个节日”，避免 prompt 太长。
  static String _buildFestivalContext(DateTime now, _WebProfile profile) {
    final festivals = _festivalDatesForScope(now.year, profile.festivalScope);

    final today = DateTime(now.year, now.month, now.day);
    festivals.sort((a, b) => a.date.compareTo(b.date));
    final upcoming = festivals.where((f) => !f.date.isBefore(today)).take(3);

    final lines = upcoming.map((f) {
      final days = f.date.difference(today).inDays;
      if (days == 0) return '- 今天是${f.name}。';
      if (days == 1) return '- 明天是${f.name}。';
      return '- 距离${f.name}还有$days天。';
    }).toList();

    return lines.isEmpty ? '' : '【近期日期与节日】\n${lines.join('\n')}';
  }

  static List<_Festival> _festivalDatesForScope(
    int year,
    _FestivalScope scope,
  ) {
    switch (scope) {
      case _FestivalScope.kimetsuTaishoJapan:
        return _kimetsuTaishoFestivalDates(year);
      case _FestivalScope.modernJapanNonPolitical:
        return [
          ..._modernJapanNonPoliticalFestivalDates(year),
          ..._internationalFestivalDates(year),
        ];
      case _FestivalScope.chinaInternational:
        return [
          ..._chinaFestivalDates(year),
          ..._internationalFestivalDates(year),
        ];
      case _FestivalScope.internationalOnly:
        return _internationalFestivalDates(year);
    }
  }

  // 国际节日：不强绑定某个国家，祥子和安迪都会知道。
  static List<_Festival> _internationalFestivalDates(int year) {
    return [
      _Festival('元旦', DateTime(year, 1, 1)),
      _Festival('情人节', DateTime(year, 2, 14)),
      _Festival('妇女节', DateTime(year, 3, 8)),
      _Festival('愚人节', DateTime(year, 4, 1)),
      _Festival('万圣节', DateTime(year, 10, 31)),
      _Festival('圣诞节', DateTime(year, 12, 25)),
    ];
  }

  // 中国节日：主要给安迪使用。
  // 农历节日每年公历日期不同，所以这里手写了 2026-2030。
  // 如果以后还继续用，可以在 datesByYear 里继续补 2031、2032...
  static List<_Festival> _chinaFestivalDates(int year) {
    final fixedDates = [
      _Festival('劳动节', DateTime(year, 5, 1)),
      _Festival('儿童节', DateTime(year, 6, 1)),
      _Festival('国庆节', DateTime(year, 10, 1)),
    ];

    final datesByYear = <int, List<_Festival>>{
      2026: [
        _Festival('除夕', DateTime(2026, 2, 16)),
        _Festival('春节', DateTime(2026, 2, 17)),
        _Festival('元宵节', DateTime(2026, 3, 3)),
        _Festival('清明节', DateTime(2026, 4, 5)),
        _Festival('端午节', DateTime(2026, 6, 19)),
        _Festival('七夕', DateTime(2026, 8, 19)),
        _Festival('中秋节', DateTime(2026, 9, 25)),
        _Festival('重阳节', DateTime(2026, 10, 18)),
      ],
      2027: [
        _Festival('除夕', DateTime(2027, 2, 5)),
        _Festival('春节', DateTime(2027, 2, 6)),
        _Festival('元宵节', DateTime(2027, 2, 20)),
        _Festival('清明节', DateTime(2027, 4, 5)),
        _Festival('端午节', DateTime(2027, 6, 9)),
        _Festival('七夕', DateTime(2027, 8, 8)),
        _Festival('中秋节', DateTime(2027, 9, 15)),
        _Festival('重阳节', DateTime(2027, 10, 8)),
      ],
      2028: [
        _Festival('除夕', DateTime(2028, 1, 25)),
        _Festival('春节', DateTime(2028, 1, 26)),
        _Festival('元宵节', DateTime(2028, 2, 9)),
        _Festival('清明节', DateTime(2028, 4, 4)),
        _Festival('端午节', DateTime(2028, 5, 28)),
        _Festival('七夕', DateTime(2028, 8, 26)),
        _Festival('中秋节', DateTime(2028, 10, 3)),
        _Festival('重阳节', DateTime(2028, 10, 26)),
      ],
      2029: [
        _Festival('除夕', DateTime(2029, 2, 12)),
        _Festival('春节', DateTime(2029, 2, 13)),
        _Festival('元宵节', DateTime(2029, 2, 27)),
        _Festival('清明节', DateTime(2029, 4, 4)),
        _Festival('端午节', DateTime(2029, 6, 16)),
        _Festival('七夕', DateTime(2029, 8, 16)),
        _Festival('中秋节', DateTime(2029, 9, 22)),
        _Festival('重阳节', DateTime(2029, 10, 16)),
      ],
      2030: [
        _Festival('除夕', DateTime(2030, 2, 2)),
        _Festival('春节', DateTime(2030, 2, 3)),
        _Festival('元宵节', DateTime(2030, 2, 17)),
        _Festival('清明节', DateTime(2030, 4, 5)),
        _Festival('端午节', DateTime(2030, 6, 5)),
        _Festival('七夕', DateTime(2030, 8, 5)),
        _Festival('中秋节', DateTime(2030, 9, 12)),
        _Festival('重阳节', DateTime(2030, 10, 5)),
      ],
    };

    return [
      ...fixedDates,
      ...(datesByYear[year] ?? [_Festival('清明节', DateTime(year, 4, 4))]),
    ];
  }

  // 鬼灭之刃：大正时期已经存在的日本民俗/季节行事。
  // 这不是现代日本国民祝日列表，所以不会出现天皇、建国、宪法、昭和等政治色彩节日。
  static List<_Festival> _kimetsuTaishoFestivalDates(int year) {
    return [
      _Festival('元日', DateTime(year, 1, 1)),
      _Festival('节分', DateTime(year, 2, 3)),
      _Festival('桃之节句', DateTime(year, 3, 3)),
      _Festival('春彼岸', DateTime(year, 3, 20)),
      _Festival('端午之节句', DateTime(year, 5, 5)),
      _Festival('七夕', DateTime(year, 7, 7)),
      _Festival('盂兰盆节', DateTime(year, 8, 13)),
      _Festival('十五夜', DateTime(year, 9, 15)),
      _Festival('秋彼岸', DateTime(year, 9, 23)),
      _Festival('七五三', DateTime(year, 11, 15)),
      _Festival('大晦日', DateTime(year, 12, 31)),
    ];
  }

  // BanG Dream：现代日本非政治节日/行事。
  // 刻意排除天皇诞生日、建国纪念日、昭和之日、宪法纪念日等政治色彩较强的节日。
  static List<_Festival> _modernJapanNonPoliticalFestivalDates(int year) {
    final datesByYear = <int, List<_Festival>>{
      2026: [
        _Festival('元日', DateTime(2026, 1, 1)),
        _Festival('成人之日', DateTime(2026, 1, 12)),
        _Festival('节分', DateTime(2026, 2, 3)),
        _Festival('桃之节句', DateTime(2026, 3, 3)),
        _Festival('春分日', DateTime(2026, 3, 20)),
        _Festival('樱花季', DateTime(2026, 3, 25)),
        _Festival('儿童之日', DateTime(2026, 5, 5)),
        _Festival('七夕', DateTime(2026, 7, 7)),
        _Festival('夏日祭', DateTime(2026, 7, 15)),
        _Festival('海之日', DateTime(2026, 7, 20)),
        _Festival('花火大会季', DateTime(2026, 7, 25)),
        _Festival('山之日', DateTime(2026, 8, 11)),
        _Festival('盂兰盆节', DateTime(2026, 8, 13)),
        _Festival('十五夜', DateTime(2026, 9, 15)),
        _Festival('敬老之日', DateTime(2026, 9, 21)),
        _Festival('秋分日', DateTime(2026, 9, 23)),
        _Festival('体育之日', DateTime(2026, 10, 12)),
      ],
      2027: [
        _Festival('元日', DateTime(2027, 1, 1)),
        _Festival('成人之日', DateTime(2027, 1, 11)),
        _Festival('节分', DateTime(2027, 2, 3)),
        _Festival('桃之节句', DateTime(2027, 3, 3)),
        _Festival('春分日', DateTime(2027, 3, 21)),
        _Festival('樱花季', DateTime(2027, 3, 25)),
        _Festival('儿童之日', DateTime(2027, 5, 5)),
        _Festival('七夕', DateTime(2027, 7, 7)),
        _Festival('夏日祭', DateTime(2027, 7, 15)),
        _Festival('海之日', DateTime(2027, 7, 19)),
        _Festival('花火大会季', DateTime(2027, 7, 25)),
        _Festival('山之日', DateTime(2027, 8, 11)),
        _Festival('盂兰盆节', DateTime(2027, 8, 13)),
        _Festival('十五夜', DateTime(2027, 9, 15)),
        _Festival('敬老之日', DateTime(2027, 9, 20)),
        _Festival('秋分日', DateTime(2027, 9, 23)),
        _Festival('体育之日', DateTime(2027, 10, 11)),
      ],
      2028: [
        _Festival('元日', DateTime(2028, 1, 1)),
        _Festival('成人之日', DateTime(2028, 1, 10)),
        _Festival('节分', DateTime(2028, 2, 3)),
        _Festival('桃之节句', DateTime(2028, 3, 3)),
        _Festival('春分日', DateTime(2028, 3, 20)),
        _Festival('樱花季', DateTime(2028, 3, 25)),
        _Festival('儿童之日', DateTime(2028, 5, 5)),
        _Festival('七夕', DateTime(2028, 7, 7)),
        _Festival('夏日祭', DateTime(2028, 7, 15)),
        _Festival('海之日', DateTime(2028, 7, 17)),
        _Festival('花火大会季', DateTime(2028, 7, 25)),
        _Festival('山之日', DateTime(2028, 8, 11)),
        _Festival('盂兰盆节', DateTime(2028, 8, 13)),
        _Festival('十五夜', DateTime(2028, 9, 15)),
        _Festival('敬老之日', DateTime(2028, 9, 18)),
        _Festival('秋分日', DateTime(2028, 9, 22)),
        _Festival('体育之日', DateTime(2028, 10, 9)),
      ],
    };

    final fallback = [
      _Festival('元日', DateTime(year, 1, 1)),
      _Festival('节分', DateTime(year, 2, 3)),
      _Festival('桃之节句', DateTime(year, 3, 3)),
      _Festival('樱花季', DateTime(year, 3, 25)),
      _Festival('儿童之日', DateTime(year, 5, 5)),
      _Festival('七夕', DateTime(year, 7, 7)),
      _Festival('夏日祭', DateTime(year, 7, 15)),
      _Festival('花火大会季', DateTime(year, 7, 25)),
      _Festival('山之日', DateTime(year, 8, 11)),
      _Festival('盂兰盆节', DateTime(year, 8, 13)),
      _Festival('十五夜', DateTime(year, 9, 15)),
    ];

    return datesByYear[year] ?? fallback;
  }

  // ========================================
  // 查询实时天气
  // ========================================
  // 优先使用百度地图天气 API：
  // - 和你在百度里看到的天气来源更接近
  // - 支持国内/海外经纬度天气查询
  //
  // 如果 ApiKeys.baiduMapAk 没填，或者百度接口失败，再退回 Open-Meteo：
  // 1. 先用 geocoding-api 把城市名转成经纬度
  // 2. 再用 forecast API 查实时天气
  static Future<String> _fetchWeather(
    String city, {
    String? displayName,
    String extraRule = '',
  }) async {
    try {
      final location = _knownWeatherLocation(city) ?? await _geocodeCity(city);
      if (location == null) return '';

      final baiduWeather = await _fetchBaiduWeather(location);
      if (baiduWeather.isNotEmpty) {
        return _rewriteWeatherContext(
          baiduWeather,
          displayName ?? location.name,
          extraRule,
        );
      }

      final openMeteoWeather = await _fetchOpenMeteoWeather(location);
      return _rewriteWeatherContext(
        openMeteoWeather,
        displayName ?? location.name,
        extraRule,
      );
    } catch (e) {
      debugPrint('获取天气失败: $e');
      return '';
    }
  }

  // 常用角色固定城市的本地经纬度兜底。
  //
  // 这样即使 Open-Meteo 的地理编码接口临时失败，
  // 也还能直接拿经纬度去查天气，不会让角色凭空编天气。
  static _WeatherLocation? _knownWeatherLocation(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.contains('东京') ||
        normalized.contains('東京') ||
        normalized.contains('tokyo')) {
      return const _WeatherLocation(
        name: '东京',
        latitude: 35.6762,
        longitude: 139.6503,
        isBaiduAbroad: true,
      );
    }
    if (normalized.contains('上海') || normalized.contains('shanghai')) {
      return const _WeatherLocation(
        name: '上海',
        latitude: 31.2304,
        longitude: 121.4737,
        isBaiduAbroad: false,
      );
    }
    return null;
  }

  static Future<_WeatherLocation?> _geocodeCity(String city) async {
    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': city,
      'count': '1',
      'language': 'zh',
      'format': 'json',
    });
    final geoResponse = await http.get(geoUri).timeout(_timeout);
    if (geoResponse.statusCode != 200) return null;

    final geo = jsonDecode(utf8.decode(geoResponse.bodyBytes));
    final results = geo['results'];
    if (results is! List || results.isEmpty) return null;

    final place = results.first as Map<String, dynamic>;
    final latitude = place['latitude'];
    final longitude = place['longitude'];
    final displayName = place['name'] ?? city;
    final countryCode = '${place['country_code'] ?? ''}'.toUpperCase();
    if (latitude is! num || longitude is! num) return null;

    return _WeatherLocation(
      name: '$displayName',
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      isBaiduAbroad: countryCode.isNotEmpty && countryCode != 'CN',
    );
  }

  static Future<String> _fetchBaiduWeather(_WeatherLocation location) async {
    if (_baiduMapAk.trim().isEmpty) return '';

    try {
      // 百度天气把国内和海外分成两个接口：
      // - 中国大陆城市用 /weather/v1/
      // - 东京这类海外城市用 /weather_abroad/v1/
      //
      // 如果把东京经纬度发给国内接口，百度会返回 41：
      // “查询的经纬度值范围无效”。
      final path =
          location.isBaiduAbroad ? '/weather_abroad/v1/' : '/weather/v1/';
      final responseSource = location.isBaiduAbroad ? '百度地图海外天气' : '百度地图天气';
      final weatherUri = Uri.https('api.map.baidu.com', path, {
        'location': '${location.longitude},${location.latitude}',
        'coordtype': 'wgs84',
        'data_type': 'now',
        'output': 'json',
        'ak': _baiduMapAk,
      });
      final response = await http.get(weatherUri).timeout(_timeout);
      if (response.statusCode != 200) return '';

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return '';
      if ('${data['status']}' != '0' && '${data['status']}' != '200') {
        debugPrint('百度天气 API 返回异常: ${data['status']} ${data['message'] ?? ''}');
        return '';
      }

      final result = data['result'];
      if (result is! Map<String, dynamic>) return '';
      final now = result['now'];
      if (now is! Map<String, dynamic>) return '';

      final address = result['address'];
      final cityName = address is Map<String, dynamic>
          ? (address['city'] ?? address['name'] ?? location.name)
          : location.name;
      final text = now['text'] ?? '未知';
      final precipitation = now['prec_1h'];
      final isPrecipitating = _weatherTextMentionsPrecipitation('$text') ||
          _isPositiveNumberString(precipitation);
      final precipitationRule = isPrecipitating
          ? '当前允许提及降水，但仍要以数据为准，不要夸大雨势。'
          : '当前不允许说正在下雨、快要下雨、雨要来了或建议因为下雨带伞。';

      return '''
【实时天气】
$cityName：数据源 $responseSource；数据时间 ${now['uptime'] ?? '未知时间'}；当前状态 $text；气温 ${now['temp'] ?? '?'}℃，体感 ${now['feels_like'] ?? '?'}℃，湿度 ${now['rh'] ?? '?'}%，${now['wind_dir'] ?? '风向未知'} ${now['wind_class'] ?? ''}，当前1小时降水量 ${precipitation ?? '?'} mm。
天气表述限制：必须按“当前状态”和“当前1小时降水量”描述天气；不要凭湿度高、多云或季节信息推测下雨。$precipitationRule
''';
    } catch (e) {
      debugPrint('百度天气请求失败，退回 Open-Meteo: $e');
      return '';
    }
  }

  static Future<String> _fetchOpenMeteoWeather(
      _WeatherLocation location) async {
    final weatherUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${location.latitude}',
      'longitude': '${location.longitude}',
      'current':
          'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
      'timezone': 'auto',
    });
    final weatherResponse = await http.get(weatherUri).timeout(_timeout);
    if (weatherResponse.statusCode != 200) return '';

    final weather = jsonDecode(utf8.decode(weatherResponse.bodyBytes));
    final current = weather['current'];
    if (current is! Map<String, dynamic>) return '';

    final code = current['weather_code'];
    final precipitation = current['precipitation'];
    final currentTime = current['time'] ?? '未知时间';
    final weatherText = _weatherCodeText(code);
    final isPrecipitating =
        _isPrecipitatingCode(code) || _isPositiveNumber(precipitation);
    final precipitationRule = isPrecipitating
        ? '当前允许提及降水，但仍要以数据为准，不要夸大雨势。'
        : '当前不允许说正在下雨、快要下雨、雨要来了或建议因为下雨带伞。';
    return '''
【实时天气】
${location.name}：数据源 Open-Meteo；天气数据时间 $currentTime；当前状态 $weatherText；气温 ${_formatNumber(current['temperature_2m'])}℃，体感 ${_formatNumber(current['apparent_temperature'])}℃，湿度 ${_formatNumber(current['relative_humidity_2m'])}%，风速 ${_formatNumber(current['wind_speed_10m'])} km/h，当前降水量 ${_formatNumber(precipitation)} mm。
天气表述限制：必须按“当前状态”和“当前降水量”描述天气；不要凭湿度高、多云或季节信息推测下雨。$precipitationRule
''';
  }

  static String _rewriteWeatherContext(
    String weather,
    String displayName,
    String extraRule,
  ) {
    if (weather.isEmpty) return '';

    final lines = weather.trim().split('\n');
    if (lines.length >= 2 && lines[0].trim() == '【实时天气】') {
      final separatorIndex = lines[1].indexOf('：');
      if (separatorIndex >= 0) {
        lines[1] = '$displayName${lines[1].substring(separatorIndex)}';
      }
    }

    if (extraRule.trim().isNotEmpty) {
      lines.add('地点表述限制：${extraRule.trim()}');
    }

    return '${lines.join('\n')}\n';
  }

  static String get _doubaoSearchApiKey {
    final configured = ApiKeys.doubaoSearchApiKey.trim();
    if (configured.isNotEmpty) return configured;
    try {
      return (Platform.environment['ASK_ECHO_SEARCH_INFINITY_API_KEY'] ?? '')
          .trim();
    } catch (_) {
      return '';
    }
  }

  static String get _doubaoTextApiKey {
    final configured = ApiKeys.doubaoTextApiKey.trim();
    if (configured.isNotEmpty) return configured;
    try {
      final envKey = (Platform.environment['ARK_API_KEY'] ?? '').trim();
      if (envKey.isNotEmpty) return envKey;
    } catch (_) {
      // Ignore and try the existing Ark key below.
    }
    return ApiKeys.doubaoVisionKey.trim();
  }

  static String get _doubaoTextEndpoint {
    final configured = ApiKeys.doubaoTextEndpoint.trim();
    if (configured.isNotEmpty) return configured;
    try {
      final envEndpoint =
          (Platform.environment['ARK_TEXT_ENDPOINT'] ?? '').trim();
      if (envEndpoint.isNotEmpty) return envEndpoint;
    } catch (_) {
      // Ignore and try the existing Ark endpoint below.
    }
    return ApiService.doubaoVisionEndpoint.trim();
  }

  // ========================================
  // 豆包/火山联网搜索 API
  // ========================================
  // 主路径只做两步：
  // 1. 按火山引擎联网搜索 API 的官方字段请求网页结果。
  // 2. 让模型从搜索结果里抽取“能直接回答用户问题”的事实。
  //
  // facts 只允许由豆包/火山方舟抽取；服务不可用时立即停止本轮事实链，
  // 不切换其他模型，也不继续搜索更多页面浪费额度。
  static bool get _factExtractorUnavailableThisTurn =>
      _activeRunState?.factExtractorUnavailable == true;

  static bool _stopSearchAfterFactExtractorFailure() {
    final runState = _activeRunState;
    if (runState?.factExtractorUnavailable != true) return false;
    if (!runState!.factExtractorStopLogged) {
      _logSearch('事实抽取服务不可用，停止本轮后续搜索与事实调用');
      runState.factExtractorStopLogged = true;
    }
    return true;
  }

  static Future<List<String>> _searchDoubaoGroundedFacts(
    String query, {
    required String userText,
    required String category,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
    required _WebProfile profile,
    List<String> searchTargets = const [],
  }) async {
    if (!_shouldUseDoubaoSearch(category)) return const [];

    final apiKey = _doubaoSearchApiKey;
    if (apiKey.isEmpty) {
      debugPrint('豆包搜索 API 未配置 key，停止豆包搜索');
      return const [];
    }

    final builtBaseQuery = _buildDoubaoSearchQuery(
      query,
      userText: userText,
      category: category,
      profile: profile,
    );
    final baseQuery =
        searchTargets.isNotEmpty ? searchTargets.first : builtBaseQuery;
    if (baseQuery.isEmpty) return const [];

    final attempts = _doubaoSearchAttempts(
      baseQuery,
      originalQuery: query,
      userText: userText,
      category: category,
      profile: profile,
      searchTargets: searchTargets,
    );
    final seenAttempts = <String>{};
    final priorities = attempts.map((attempt) => attempt.priority).toSet()
      ..removeWhere((priority) => priority < 0);
    final orderedPriorities = priorities.toList()..sort();
    final collectedFacts = <_DoubaoGroundedFact>[];
    final extractedSourceKeys = <String>{};
    final factLimit = _doubaoFactLimitForUserText(userText);
    final needsBroadFactCoverage =
        category == 'canon' && _needsBroadCanonFactCoverage(userText);
    final eventProcessSearch =
        category == 'canon' && _isEventProcessCanonQuestion(userText);
    final includeTimeline = needsBroadFactCoverage || eventProcessSearch;
    final extractionFactLimit = factLimit;
    final minimumFactTarget = _minimumDoubaoFactTarget(
      category: category,
      profile: profile,
      userText: userText,
      needsBroadFactCoverage: needsBroadFactCoverage,
      eventProcessSearch: eventProcessSearch,
    );
    final minimumSourceTarget = _minimumDoubaoSourceTarget(
      category: category,
      profile: profile,
      userText: userText,
    );
    final collectFactLimit = minimumSourceTarget > 1
        ? 40
        : (needsBroadFactCoverage ? 40 : factLimit);
    final separateFactOutput = needsBroadFactCoverage;
    var collectedAnswerBasis = _answerBasisInsufficient;
    final displayQuery =
        searchTargets.isNotEmpty ? searchTargets.join(' / ') : baseQuery;
    var searchBudgetLogWritten = false;

    for (final priority in orderedPriorities) {
      final phaseAttempts =
          attempts.where((attempt) => attempt.priority == priority).toList();
      final phaseLayerName = _searchLayerName(
        priority,
        phaseAttempts.isNotEmpty ? phaseAttempts.first.label : '',
      );
      var phaseAdoptLayerName = phaseLayerName;
      var phaseHasCompleteAnswer = false;
      var phaseResultCount = 0;
      var phaseReached = false;

      if (category == 'canon' &&
          priority == 0 &&
          profile.preferMoegirlCanonSearch) {
        final directItems = await _searchPrimaryMoegirlDirectItems(
          searchTargets.isNotEmpty ? searchTargets : [baseQuery],
        );
        if (directItems.isNotEmpty) {
          phaseReached = true;
          var extraction = const _DoubaoFactExtraction.empty();
          if (minimumFactTarget > 2 && directItems.length > 1) {
            final perPageFacts = <_DoubaoGroundedFact>[];
            var perPageBasis = _answerBasisInsufficient;
            var perPageProvider = 'none';
            for (final item in directItems) {
              final pageExtraction = await _extractDoubaoFactsWithModel(
                searchQuery: displayQuery,
                userText: userText,
                category: category,
                profile: profile,
                items: [item],
                factLimit: extractionFactLimit,
                minimumFactTarget: minimumFactTarget - perPageFacts.length > 0
                    ? minimumFactTarget - perPageFacts.length
                    : 1,
                minimumSourceTarget: minimumSourceTarget,
                preferEvidenceText: needsBroadFactCoverage,
                answerMode: answerMode,
                answerRequirements: answerRequirements,
              );
              _addUniqueDoubaoFacts(
                perPageFacts,
                pageExtraction.facts,
                maxFacts: needsBroadFactCoverage ? 40 : extractionFactLimit,
              );
              perPageBasis = _mergeAnswerBasis(
                perPageBasis,
                pageExtraction.answerBasis,
              );
              if (pageExtraction.provider != 'none') {
                perPageProvider = pageExtraction.provider;
              }
              if (_factExtractorUnavailableThisTurn) break;
            }
            extraction = _DoubaoFactExtraction(
              status:
                  perPageFacts.length >= minimumFactTarget ? 'ok' : 'partial',
              facts: perPageFacts,
              discardReason: '',
              provider: perPageProvider,
              answerBasis: perPageBasis,
            );
          } else {
            extraction = await _extractDoubaoFactsWithModel(
              searchQuery: displayQuery,
              userText: userText,
              category: category,
              profile: profile,
              items: directItems,
              factLimit: extractionFactLimit,
              minimumFactTarget: minimumFactTarget,
              minimumSourceTarget: minimumSourceTarget,
              preferEvidenceText: needsBroadFactCoverage,
              answerMode: answerMode,
              answerRequirements: answerRequirements,
            );
          }
          if (extraction.facts.isEmpty && !_factExtractorUnavailableThisTurn) {
            _logSearch('萌娘百科直达事实首次抽取为空，执行一次同页候选事实复核');
            extraction = await _extractDoubaoFactsWithModel(
              searchQuery: displayQuery,
              userText: userText,
              category: category,
              profile: profile,
              items: directItems,
              factLimit: extractionFactLimit,
              minimumFactTarget: minimumFactTarget,
              minimumSourceTarget: minimumSourceTarget,
              preferEvidenceText: needsBroadFactCoverage,
              answerMode: answerMode,
              answerRequirements: answerRequirements,
              candidateRecoveryPass: true,
            );
          }
          if (minimumFactTarget > 2 &&
              !_factExtractorUnavailableThisTurn &&
              extraction.facts.length >= minimumFactTarget - 1 &&
              extraction.facts.length < minimumFactTarget &&
              _factsCoverAnswerRequirements(
                extraction.facts,
                answerRequirements,
              )) {
            _logSearch(
              '萌娘百科直达事实已覆盖问项但尚差'
              '${minimumFactTarget - extraction.facts.length}条，'
              '先从同批全文补充不重复事实',
            );
            final representedSourceUrls = extraction.facts
                .map((fact) => fact.sourceUrl.trim().toLowerCase())
                .where((url) => url.isNotEmpty)
                .toSet();
            final representedSourceTitles = extraction.facts
                .map((fact) => fact.sourceTitle.trim())
                .where((title) => title.isNotEmpty)
                .toSet();
            final uncoveredDirectItems = directItems.where((item) {
              final normalizedUrl = item.url.trim().toLowerCase();
              final normalizedTitle = item.title.trim();
              final urlCovered = normalizedUrl.isNotEmpty &&
                  representedSourceUrls.contains(normalizedUrl);
              final titleCovered = normalizedTitle.isNotEmpty &&
                  representedSourceTitles.contains(normalizedTitle);
              return !urlCovered && !titleCovered;
            }).toList(growable: false);
            final supplemental = await _extractDoubaoFactsWithModel(
              searchQuery: displayQuery,
              userText: userText,
              category: category,
              profile: profile,
              items: uncoveredDirectItems.isNotEmpty
                  ? uncoveredDirectItems
                  : directItems,
              factLimit: extractionFactLimit,
              minimumFactTarget: minimumFactTarget - extraction.facts.length,
              minimumSourceTarget: minimumSourceTarget,
              preferEvidenceText: needsBroadFactCoverage,
              answerMode: answerMode,
              answerRequirements: answerRequirements,
              excludedFacts: extraction.facts,
            );
            if (supplemental.facts.isNotEmpty) {
              final mergedFacts = [...extraction.facts];
              _addUniqueDoubaoFacts(
                mergedFacts,
                supplemental.facts,
                maxFacts: extractionFactLimit,
              );
              extraction = _DoubaoFactExtraction(
                status: mergedFacts.length >= minimumFactTarget
                    ? 'ok'
                    : extraction.status,
                facts: mergedFacts,
                discardReason: extraction.discardReason,
                provider: extraction.provider,
                answerBasis: _mergeAnswerBasis(
                  extraction.answerBasis,
                  supplemental.answerBasis,
                ),
              );
            }
          }
          _logSearch(
            '萌娘百科词条直达优先: '
            '命中${directItems.length}条，抽取事实=${extraction.facts.length}'
            '(${extraction.status}, ${extraction.answerBasis})，'
            '${_formatRequirementCoverageForLog(extraction.facts, answerRequirements)}',
          );
          if (extraction.facts.isNotEmpty) {
            collectedAnswerBasis = _mergeAnswerBasis(
              collectedAnswerBasis,
              extraction.answerBasis,
            );
            _addUniqueDoubaoFacts(
              collectedFacts,
              extraction.facts,
              maxFacts: collectFactLimit,
            );
            phaseHasCompleteAnswer = _hasEnoughDoubaoFactsForSearchStop(
              collectedFacts,
              factLimit: factLimit,
              minimumFactTarget: minimumFactTarget,
              minimumSourceTarget: minimumSourceTarget,
              extractionStatus: extraction.status,
              answerRequirements: answerRequirements,
            );
          }
          phaseResultCount += directItems.length;
        }
      }

      if (_stopSearchAfterFactExtractorFailure()) break;

      if (category == 'canon' && priority == 1) {
        final browserItems = await _searchSecondaryCanonBrowserItems(
          baseQuery,
          userText: userText,
          profile: profile,
        );
        if (browserItems.isNotEmpty) {
          phaseReached = true;
          final extraction = await _extractDoubaoFactsWithModel(
            searchQuery: baseQuery,
            userText: userText,
            category: category,
            profile: profile,
            items: browserItems,
            factLimit: extractionFactLimit,
            minimumFactTarget: minimumFactTarget,
            minimumSourceTarget: minimumSourceTarget,
            preferEvidenceText: needsBroadFactCoverage,
            answerMode: answerMode,
            answerRequirements: answerRequirements,
          );
          _logSearch(
            '本地百度/维基直达优先: '
            '命中${browserItems.length}条${_formatSourceHostsForLog(browserItems)}，'
            '抽取事实=${extraction.facts.length}'
            '(${extraction.status}, ${extraction.answerBasis})，'
            '${_formatRequirementCoverageForLog(extraction.facts, answerRequirements)}',
          );
          if (extraction.facts.isNotEmpty) {
            collectedAnswerBasis = _mergeAnswerBasis(
              collectedAnswerBasis,
              extraction.answerBasis,
            );
            _logSearchVerbose(
              '本地百度/维基事实提取摘要: '
              '${_formatDoubaoFactsCompactForLog(extraction.facts)}',
            );
            _addUniqueDoubaoFacts(
              collectedFacts,
              extraction.facts,
              maxFacts: collectFactLimit,
            );
            phaseHasCompleteAnswer = _hasEnoughDoubaoFactsForSearchStop(
              collectedFacts,
              factLimit: factLimit,
              minimumFactTarget: minimumFactTarget,
              minimumSourceTarget: minimumSourceTarget,
              extractionStatus: extraction.status,
              answerRequirements: answerRequirements,
            );
            phaseAdoptLayerName = _searchLayerName(priority, '本地百度/维基补充');
          }
          phaseResultCount += browserItems.length;
        }
      }

      if (_stopSearchAfterFactExtractorFailure()) break;

      final directFactsEnough = phaseHasCompleteAnswer;

      if (!directFactsEnough) {
        for (final attempt in phaseAttempts) {
          if ((_activeTrace?.searchApiCalls ?? 0) >=
              _maxDoubaoSearchApiCallsPerTurn) {
            if (!searchBudgetLogWritten) {
              _logSearch(
                '搜索 API 预算已用完: '
                '本轮上限=$_maxDoubaoSearchApiCallsPerTurn，'
                '停止后续豆包搜索并保留已有事实',
              );
              searchBudgetLogWritten = true;
            }
            break;
          }
          final searchQuery = _truncateDoubaoQuery(attempt.query);
          final attemptKey =
              '$priority::${attempt.useGlobal}::${attempt.sites ?? ''}::${attempt.authInfoLevel}::$searchQuery';
          if (searchQuery.isEmpty || !seenAttempts.add(attemptKey)) continue;

          final siteLog =
              attempt.sites == null ? '' : ', sites=${attempt.sites}';
          final authLog = attempt.authInfoLevel > 0
              ? ', authInfoLevel=${attempt.authInfoLevel}'
              : '';
          final engineLog = attempt.useGlobal ? ', engine=Global' : '';
          final layerName = _searchLayerName(priority, attempt.label);
          phaseReached = true;
          _logSearch(
            '搜索步骤开始[$layerName]: '
            '${attempt.useGlobal ? 'Global' : 'Custom'} | '
            '$searchQuery${_formatSitesBriefForLog(attempt.sites)}$authLog',
          );
          final items = await _callDoubaoSearchApi(
            searchQuery,
            apiKey: apiKey,
            count: _doubaoSearchCountForAttempt(
              category: category,
              useGlobal: attempt.useGlobal,
            ),
            authLevel: attempt.authInfoLevel,
            sites: attempt.sites,
            useGlobal: attempt.useGlobal,
            category: category,
            profile: profile,
          );
          if (items.isEmpty) {
            _logSearch(
              '搜索步骤结果[$layerName]: 无可用结果',
            );
            continue;
          }
          phaseResultCount += items.length;

          _logSearchVerbose(
            '豆包搜索 API 成功[${attempt.label}]: '
            'query=$searchQuery$siteLog$authLog$engineLog, results=${items.length}',
          );
          _logSearchVerbose(
            '豆包搜索 API 候选摘要:\n${_formatDoubaoItemsForLog(items)}',
          );
          final enrichedItems = await _enrichDoubaoItemsWithFetchedContent(
            items,
            query: searchQuery,
            category: category,
            needsSourceDiversity: minimumSourceTarget > 1,
          );
          if (!_sameDoubaoContentLengths(items, enrichedItems)) {
            _logSearchVerbose(
              '豆包搜索 Top URL 正文补全摘要:\n'
              '${_formatDoubaoItemsForLog(enrichedItems)}',
            );
          }
          final extractionSourceKey = _doubaoExtractionSourceKey(
            searchQuery,
            enrichedItems,
          );
          if (!extractedSourceKeys.add(extractionSourceKey)) {
            _logSearchVerbose(
              '豆包事实抽取跳过重复候选: query=$searchQuery, '
              'results=${enrichedItems.length}',
            );
            continue;
          }
          final extraction = await _extractDoubaoFactsWithModel(
            searchQuery: searchQuery,
            userText: userText,
            category: category,
            profile: profile,
            items: enrichedItems,
            factLimit: extractionFactLimit,
            minimumFactTarget: minimumFactTarget,
            minimumSourceTarget: minimumSourceTarget,
            preferEvidenceText: needsBroadFactCoverage,
            answerMode: answerMode,
            answerRequirements: answerRequirements,
          );
          if (_factExtractorUnavailableThisTurn) {
            _stopSearchAfterFactExtractorFailure();
            break;
          }
          final enrichedContentCount =
              enrichedItems.where((item) => item.content.isNotEmpty).length;
          _logSearch(
            '搜索步骤结果[$layerName]: '
            '命中${items.length}条，正文$enrichedContentCount/${enrichedItems.length}，'
            '抽取事实=${extraction.facts.length}'
            '(${extraction.status}, ${extraction.answerBasis})，'
            '${_formatRequirementCoverageForLog(extraction.facts, answerRequirements)}',
          );
          if (extraction.facts.isNotEmpty) {
            collectedAnswerBasis = _mergeAnswerBasis(
              collectedAnswerBasis,
              extraction.answerBasis,
            );
            _logSearchVerbose(
              '豆包事实提取摘要: '
              '${_formatDoubaoFactsCompactForLog(extraction.facts)}',
            );
            _addUniqueDoubaoFacts(
              collectedFacts,
              extraction.facts,
              maxFacts: collectFactLimit,
            );
            phaseHasCompleteAnswer = _hasEnoughDoubaoFactsForSearchStop(
              collectedFacts,
              factLimit: factLimit,
              minimumFactTarget: minimumFactTarget,
              minimumSourceTarget: minimumSourceTarget,
              extractionStatus: extraction.status,
              answerRequirements: answerRequirements,
            );
            if (phaseHasCompleteAnswer) {
              _logSearch(
                '网页事实已足够，停止搜索: '
                '${_formatDoubaoFactsUsageForLog(collectedFacts, factLimit)}，'
                '停在$layerName',
              );
              phaseAdoptLayerName = layerName;
              break;
            }
          }
        }
      }

      if (_stopSearchAfterFactExtractorFailure()) break;

      final phaseHasEnoughFacts = phaseHasCompleteAnswer;

      if (phaseHasEnoughFacts) {
        _logSearch(
          '采用网页事实[$phaseAdoptLayerName]: '
          '${_formatDoubaoFactsUsageForLog(collectedFacts, factLimit)}',
        );
        final formatted = await _formatDoubaoFactsWithTimeline(
          collectedFacts,
          originalQuery: displayQuery,
          maxFacts: factLimit,
          separateFacts: separateFactOutput,
          includeTimeline: includeTimeline,
          userText: userText,
          profile: profile,
        );
        if (formatted.isNotEmpty) {
          final resolvedCollectedBasis = _answerBasisForFacts(
            collectedFacts,
            fallback: collectedAnswerBasis,
          );
          final resultsWithBasis = [
            ...formatted,
            '$_doubaoAnswerBasisResultPrefix$resolvedCollectedBasis',
          ];
          return resultsWithBasis;
        }
      }

      if (collectedFacts.isNotEmpty && phaseReached) {
        _logSearch(
          '当前搜索层未满足，进入下一层: '
          '$phaseLayerName，命中结果=$phaseResultCount，'
          '${_formatDoubaoFactsUsageForLog(collectedFacts, factLimit)}',
        );
      }
    }

    if (collectedFacts.isNotEmpty) {
      _logSearch(
        collectedFacts.length >= factLimit
            ? '网页事实已达上限，使用已收集事实: '
            : '网页事实不足但可用，使用已收集事实: '
                '${_formatDoubaoFactsUsageForLog(collectedFacts, factLimit)}',
      );
      final formatted = await _formatDoubaoFactsWithTimeline(
        collectedFacts,
        originalQuery: displayQuery,
        maxFacts: factLimit,
        separateFacts: separateFactOutput,
        includeTimeline: includeTimeline,
        userText: userText,
        profile: profile,
      );
      if (formatted.isNotEmpty) {
        final resolvedCollectedBasis = _answerBasisForFacts(
          collectedFacts,
          fallback: collectedAnswerBasis,
        );
        final resultsWithBasis = [
          ...formatted,
          '$_doubaoAnswerBasisResultPrefix$resolvedCollectedBasis',
        ];
        return resultsWithBasis;
      }
    }

    debugPrint('豆包搜索事实不足: category=$category, query=$query');
    return const [];
  }

  static Future<List<_DoubaoSearchItem>> _enrichDoubaoItemsWithFetchedContent(
    List<_DoubaoSearchItem> items, {
    required String query,
    required String category,
    bool needsSourceDiversity = false,
  }) async {
    if (items.isEmpty || (category != 'canon' && !needsSourceDiversity)) {
      return items;
    }

    final enriched = <_DoubaoSearchItem>[];
    for (final item in items.take(_doubaoFactMaxResults)) {
      final fetched = await _fetchReadableContentForDoubaoItem(
        item,
        query: query,
      );
      enriched.add(fetched);
    }

    if (items.length > enriched.length) {
      enriched.addAll(items.skip(enriched.length));
    }
    return enriched;
  }

  static int _doubaoSearchCountForAttempt({
    required String category,
    required bool useGlobal,
  }) {
    if (category == 'canon') return useGlobal ? 20 : 12;
    return useGlobal ? 10 : 6;
  }

  static Future<List<_DoubaoSearchItem>> _searchSecondaryCanonBrowserItems(
    String query, {
    required String userText,
    required _WebProfile profile,
  }) async {
    final hints = _canonDirectTitleHints(query, userText, profile, '');
    final baiduResults = await _searchBaiduBaikeSequence(
      query,
      directTitleHints: hints,
    );
    final wikipediaResults = await _searchWikipediaSequence(
      query,
      directTitleHints: hints,
    );
    final items = <_DoubaoSearchItem>[];
    for (final result in [...baiduResults, ...wikipediaResults.results]) {
      final item = _doubaoItemFromFormattedSearchResult(result);
      if (item == null) continue;
      if (items.any((existing) => existing.url == item.url)) continue;
      items.add(item);
    }
    return _sortDoubaoCanonItemsBySourcePriority(items, profile)
        .take(_doubaoFactMaxResults)
        .toList(growable: false);
  }

  static Future<List<_DoubaoSearchItem>> _searchPrimaryMoegirlDirectItems(
    List<String> searchTargets,
  ) async {
    final items = <_DoubaoSearchItem>[];
    final seenUrls = <String>{};
    for (final target in searchTargets
        .map(_truncateDoubaoQuery)
        .where(_isCleanCanonObjectQuery)
        .take(4)) {
      final directItem = await _fetchMoegirlTitleAsDoubaoItem(target);
      if (directItem != null) {
        final key = directItem.url.isNotEmpty
            ? directItem.url
            : '${directItem.title}::$target';
        if (seenUrls.add(key)) {
          items.add(directItem);
          _logSearch(
            '萌娘百科词条全文直达成功: '
            '${directItem.title.replaceFirst(' - 萌娘百科', '')}，'
            '正文${directItem.content.runes.length}字',
          );
          continue;
        }
        _logSearchVerbose('萌娘百科词条直达重复，已合并: $target -> ${directItem.url}');
        continue;
      }

      final direct = await _searchDirectMoegirl(
        target,
        directTitleHints: [target],
      );
      for (final result in direct.results) {
        final item = _doubaoItemFromFormattedSearchResult(result);
        if (item == null) continue;
        final key = item.url.isNotEmpty ? item.url : '${item.title}::$target';
        if (!seenUrls.add(key)) continue;
        items.add(item);
      }
    }
    return items.take(_doubaoFactMaxResults).toList(growable: false);
  }

  static Future<_DoubaoSearchItem?> _fetchMoegirlTitleAsDoubaoItem(
    String title,
  ) async {
    try {
      final cleanTitle = title.trim();
      if (cleanTitle.isEmpty) return null;
      final requestUri = Uri.https(
        'zh.moegirl.org.cn',
        '/$cleanTitle',
        const {'variant': 'zh-cn'},
      );
      final extract = await _fetchMoegirlPlainTextExtract(cleanTitle);
      var readable = extract?.text ?? '';
      var canonicalTitle = extract?.canonicalTitle.trim() ?? '';
      if (canonicalTitle.isEmpty) canonicalTitle = cleanTitle;
      if (readable.isEmpty) {
        final response = await http
            .get(requestUri, headers: _browserSearchHeaders)
            .timeout(_searchTimeout);
        if (response.statusCode != 200) {
          _logSearchVerbose(
            '萌娘百科词条全文直达失败: status=${response.statusCode}, title=$title',
          );
          return null;
        }

        final html = utf8.decode(response.bodyBytes, allowMalformed: true);
        readable = _preferredMoegirlSectionText(html);
        if (readable.runes.length < 800) {
          readable = _cleanMoegirlContentText(html);
        }
      }
      final cleaned = readable.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.runes.length < 240 || _looksLikeGarbledText(cleaned)) {
        _logSearchVerbose(
          '萌娘百科词条全文直达为空或乱码: title=$title, chars=${cleaned.runes.length}',
        );
        return null;
      }

      final canonicalUri = Uri.https(
        'zh.moegirl.org.cn',
        '/$canonicalTitle',
        const {'variant': 'zh-cn'},
      );
      return _DoubaoSearchItem(
        title: '$canonicalTitle - 萌娘百科',
        snippet: '',
        siteName: 'zh.moegirl.org.cn',
        url: canonicalUri.toString(),
        summary: '',
        content: cleaned,
        publishTime: '',
      );
    } catch (e) {
      _logSearchVerbose('萌娘百科词条全文直达异常: title=$title, error=$e');
      return null;
    }
  }

  static Future<({String text, String canonicalTitle})?>
      _fetchMoegirlPlainTextExtract(String title) async {
    try {
      final uri = Uri.https('zh.moegirl.org.cn', '/api.php', {
        'action': 'query',
        'prop': 'extracts',
        'explaintext': '1',
        'redirects': '1',
        'titles': title,
        'format': 'json',
        'variant': 'zh-cn',
      });
      final response = await http
          .get(uri, headers: _browserSearchHeaders)
          .timeout(_searchTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final query = decoded['query'];
      if (query is! Map) return null;
      final pages = query['pages'];
      if (pages is! Map) return null;
      for (final page in pages.values) {
        if (page is! Map) continue;
        final extract = page['extract'];
        if (extract is! String || extract.trim().isEmpty) continue;
        final cleaned = _cleanMoegirlContentText(extract);
        if (cleaned.runes.length >= 240 && !_looksLikeGarbledText(cleaned)) {
          _logSearchVerbose(
            '萌娘百科官方 API 纯文本成功: $title，正文${cleaned.runes.length}字',
          );
          final canonicalTitle = page['title'] is String
              ? (page['title'] as String).trim()
              : title.trim();
          return (text: cleaned, canonicalTitle: canonicalTitle);
        }
      }
    } catch (e) {
      _logSearchVerbose('萌娘百科官方 API 纯文本失败: $title, $e');
    }
    return null;
  }

  static _DoubaoSearchItem? _doubaoItemFromFormattedSearchResult(
    String result,
  ) {
    final trimmed = result.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(
      r'^\d+\.\s*([^：:]+)[：:]\s*(.*?)(?:（来源：([^）]+)）)?$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (match == null) {
      return _DoubaoSearchItem(
        title: '本地网页解析结果',
        snippet: trimmed,
        siteName: '',
        url: '',
        summary: '',
        content: trimmed,
        publishTime: '',
      );
    }
    final title = (match.group(1) ?? '').trim();
    final body = (match.group(2) ?? '').trim();
    final url = (match.group(3) ?? '').trim();
    return _DoubaoSearchItem(
      title: title.isEmpty ? '本地网页解析结果' : title,
      snippet: '',
      siteName: Uri.tryParse(url)?.host ?? '',
      url: url,
      summary: '',
      content: body,
      publishTime: '',
    );
  }

  static Future<_DoubaoSearchItem> _fetchReadableContentForDoubaoItem(
    _DoubaoSearchItem item, {
    required String query,
  }) async {
    try {
      final uri = Uri.tryParse(item.url);
      if (uri == null ||
          !uri.hasScheme ||
          uri.host.isEmpty ||
          _isUnwantedSearchResultUrl(item.url)) {
        return item;
      }

      final requestUri = _isMoegirlUrl(item.url)
          ? _moegirlSimplifiedUri(uri)
          : _isBaiduBaikeUrl(item.url)
              ? _baiduBaikeReadableUri(uri)
              : uri;
      final response = await http
          .get(requestUri, headers: _browserSearchHeaders)
          .timeout(_searchTimeout);
      if (response.statusCode != 200) {
        _logSearchVerbose(
          '豆包候选正文补全失败: status=${response.statusCode}, url=${item.url}',
        );
        return item;
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final readable = _isMoegirlUrl(requestUri.toString())
          ? _preferredMoegirlSectionText(html)
          : _cleanExternalCanonRawText(html, requestUri.toString());
      final cleaned = readable.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.length < 120 || _looksLikeGarbledText(cleaned)) {
        _logSearchVerbose(
          '豆包候选正文补全为空或乱码: url=${item.url}, chars=${cleaned.length}',
        );
        return item;
      }

      _logSearchVerbose(
        '豆包候选正文补全成功: title=${item.title}, '
        'url=${requestUri.toString()}, chars=${cleaned.runes.length}, '
        'query=$query',
      );
      return item.copyWith(
        url: requestUri.toString(),
        content: cleaned,
      );
    } catch (e) {
      _logSearchVerbose('豆包候选正文补全异常: url=${item.url}, error=$e');
      return item;
    }
  }

  static bool _sameDoubaoContentLengths(
    List<_DoubaoSearchItem> before,
    List<_DoubaoSearchItem> after,
  ) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (before[i].content.runes.length != after[i].content.runes.length ||
          before[i].url != after[i].url) {
        return false;
      }
    }
    return true;
  }

  static List<_DoubaoSearchAttempt> _doubaoSearchAttempts(
    String baseQuery, {
    required String originalQuery,
    required String userText,
    required String category,
    required _WebProfile profile,
    List<String> searchTargets = const [],
  }) {
    if (category == 'canon' && profile.preferMoegirlCanonSearch) {
      final objectQueries = searchTargets
          .map(_truncateDoubaoQuery)
          .where(_isCleanCanonObjectQuery)
          .where((query) => query.trim().isNotEmpty)
          .toList(growable: false);
      final fallbackQueries = _mainCanonDoubaoQueries(
        baseQuery,
        originalQuery: originalQuery,
        userText: userText,
        profile: profile,
        searchTargets: objectQueries,
      );
      final cleanQueries =
          objectQueries.isNotEmpty ? objectQueries : fallbackQueries;
      if (cleanQueries.isNotEmpty) {
        final primaryQueries = cleanQueries
            .take(3)
            .map((query) => _primaryCanonObjectSearchQuery(query, profile))
            .where((query) => query.isNotEmpty)
            .toList(growable: false);
        final secondarySites = _secondaryCanonSitesForProfile(profile);
        final secondaryQueries = <String>[];
        void addSecondaryQuery(String query) {
          final clean = _truncateDoubaoQuery(query);
          if (clean.isEmpty || secondaryQueries.contains(clean)) return;
          secondaryQueries.add(clean);
        }

        final orderedSecondaryObjects = [
          ...primaryQueries.where(
            (query) => !_canonTextContainsTerm(query, profile.characterName),
          ),
          ...primaryQueries.where(
            (query) => _canonTextContainsTerm(query, profile.characterName),
          ),
        ];
        for (final query in orderedSecondaryObjects) {
          addSecondaryQuery(query);
        }
        final fallbackGlobalQuery = secondaryQueries.isNotEmpty
            ? secondaryQueries.first
            : primaryQueries.first;
        return [
          for (final query in primaryQueries)
            _DoubaoSearchAttempt(
              query: _globalSiteScopedQuery(query, 'zh.moegirl.org.cn'),
              useGlobal: true,
              label: 'Global主站点',
              priority: 0,
            ),
          for (final query in secondaryQueries.take(2))
            _DoubaoSearchAttempt(
              query: query,
              sites: secondarySites,
              label: 'Custom次级站点补充',
              priority: 1,
            ),
          _DoubaoSearchAttempt(
            query: fallbackGlobalQuery,
            useGlobal: true,
            label: 'Global全网兜底',
            priority: 2,
          ),
        ];
      }
      final layeredQueries = _customCanonSingleSearchQueries(
        cleanQueries,
        userText: userText,
        profile: profile,
      );
      final layeredSites = _joinSites([
        _primaryCanonSitesForProfile(profile),
        _secondaryCanonSitesForProfile(profile),
      ]);
      return [
        for (final query in layeredQueries)
          _DoubaoSearchAttempt(
            query: query,
            sites: layeredSites,
            label: 'Custom站点白名单',
            priority: layeredQueries.indexOf(query),
          ),
      ];
    }

    if (_requiresAuthoritativeDoubaoSearch(category, profile)) {
      final sites = _authoritativeSitesForCategory(category);
      return [
        if (sites.isNotEmpty)
          _DoubaoSearchAttempt(
            query: baseQuery,
            sites: sites,
            authInfoLevel: _authoritativeAuthInfoLevel,
            label: '权威白名单',
            priority: 0,
          ),
        _DoubaoSearchAttempt(
          query: baseQuery,
          authInfoLevel: _authoritativeAuthInfoLevel,
          label: '权威全网',
          priority: 1,
        ),
        if (category == 'general' || category == 'slang')
          _DoubaoSearchAttempt(
            query: baseQuery,
            label: '开放全网',
            priority: 2,
          ),
        if (category == 'general' || category == 'slang')
          _DoubaoSearchAttempt(
            query: baseQuery,
            useGlobal: true,
            label: 'Global全网兜底',
            priority: 3,
          ),
      ];
    }

    return [_DoubaoSearchAttempt(query: baseQuery, label: '全网', priority: 0)];
  }

  static String _primaryCanonObjectSearchQuery(
    String query,
    _WebProfile profile,
  ) {
    final clean = _truncateDoubaoQuery(query);
    if (clean.isEmpty) return '';
    final prefix = profile.canonSearchPrefix.trim();
    if (prefix.isEmpty || clean.contains(prefix)) return clean;
    if (_isExplicitCanonTitleTerm(clean) &&
        RegExp(r'^[A-Za-z0-9!☆_:\-\s]+$').hasMatch(clean)) {
      return clean;
    }
    return _truncateDoubaoQuery('$prefix $clean');
  }

  static bool _isCleanCanonObjectQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    if (_isExplicitCanonTitleTerm(trimmed)) return true;
    if (_isQuestionIntentTerm(trimmed)) return false;
    if (_canonQueryContextTerms.contains(trimmed.toLowerCase())) return false;
    if (RegExp(r'[？?。！!；;]').hasMatch(trimmed)) return false;
    if (trimmed.runes.length > 24 &&
        !RegExp(r'^[A-Za-z0-9!☆_:\-\s]+$').hasMatch(trimmed)) {
      return false;
    }
    return true;
  }

  static String _globalSiteScopedQuery(String query, String site) {
    final cleanQuery = _truncateDoubaoQuery(query);
    final cleanSite = site.trim().replaceFirst(RegExp(r'^www\.'), '');
    if (cleanSite.isEmpty) return cleanQuery;
    return _truncateDoubaoQuery('$cleanQuery site:$cleanSite');
  }

  static List<String> _customCanonSingleSearchQueries(
    List<String> queries, {
    required String userText,
    required _WebProfile profile,
  }) {
    final results = <String>[];
    void add(String value) {
      final query = _truncateDoubaoQuery(value);
      if (query.isEmpty) return;
      if (results.contains(query)) return;
      results.add(query);
    }

    final objects = queries
        .map(_truncateDoubaoQuery)
        .where((query) => query.isNotEmpty)
        .toList(growable: false);
    if (objects.isEmpty) return const [];

    final primary = objects.first;
    final contextObjects = objects
        .skip(1)
        .where((query) => query != profile.characterName)
        .take(2)
        .toList(growable: false);
    final context = contextObjects.join(' ');
    add(primary);

    if (_queryAsksMusicInfo(userText) && _isExplicitCanonTitleTerm(primary)) {
      final normalizedPrimary = _latinSearchIndexTitle(primary);
      add('$normalizedPrimary 歌曲');
    } else if (contextObjects.isNotEmpty) {
      add(contextObjects.first);
    } else if (_isExplicitCanonTitleTerm(primary)) {
      final normalizedPrimary = primary
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .map((part) => _isExplicitCanonTitleTerm(part)
              ? _latinSearchIndexTitle(part)
              : part)
          .join(' ');
      add([normalizedPrimary, if (context.isNotEmpty) context].join(' '));
    } else if (profile.canonSearchPrefix.isNotEmpty) {
      add('$primary ${profile.canonSearchPrefix}');
    }

    return results.take(2).toList(growable: false);
  }

  static String _latinSearchIndexTitle(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9!☆_:\-]*$').hasMatch(trimmed)) {
      return trimmed;
    }
    final lower = trimmed.toLowerCase();
    if (lower.isEmpty) return trimmed;
    return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
  }

  static String _officialCanonSitesForProfile(_WebProfile profile) {
    switch (profile.seriesName) {
      case 'BanG Dream':
        return 'bang-dream.com|anime.bang-dream.com|bushiroad-music.com|bang-dream.bushimo.jp';
      case '鬼灭之刃':
        return 'kimetsu.com';
      default:
        return '';
    }
  }

  static String _primaryCanonSitesForProfile(_WebProfile profile) {
    if (profile.preferMoegirlCanonSearch) return _moegirlSites;
    return _officialCanonSitesForProfile(profile);
  }

  static String _secondaryCanonSitesForProfile(_WebProfile profile) {
    final common = 'baike.baidu.com|zh.wikipedia.org|wikipedia.org';
    return _joinSites([
      common,
      _officialCanonSitesForProfile(profile),
      _supplementalCanonSitesForProfile(profile),
    ]);
  }

  static String _joinSites(List<String> values) {
    final sites = <String>[];
    for (final value in values) {
      for (final site in value.split('|')) {
        final normalized = site.trim().replaceFirst(RegExp(r'^www\.'), '');
        if (normalized.isEmpty || sites.contains(normalized)) continue;
        sites.add(normalized);
      }
    }
    return sites.join('|');
  }

  static String _supplementalCanonSitesForProfile(_WebProfile profile) {
    switch (profile.seriesName) {
      case 'BanG Dream':
        return 'bandori.miraheze.org|bandori.fandom.com|bandori.party';
      default:
        return '';
    }
  }

  static bool _requiresAuthoritativeDoubaoSearch(
    String category,
    _WebProfile profile,
  ) {
    if (profile.seriesName != '欢乐颂') return false;
    return category == 'economy' ||
        category == 'current' ||
        category == 'general' ||
        category == 'slang';
  }

  static String _authoritativeSitesForCategory(String category) {
    if (category == 'economy') return _authoritativeFinanceSites;
    if (category == 'current' || category == 'general' || category == 'slang') {
      return _authoritativeNewsSites;
    }
    return '';
  }

  static bool _shouldUseDoubaoSearch(String category) {
    return category == 'canon' ||
        category == 'current' ||
        category == 'slang' ||
        category == 'economy' ||
        category == 'general';
  }

  static String _buildDoubaoSearchQuery(
    String query, {
    required String userText,
    required String category,
    required _WebProfile profile,
  }) {
    var compactQuestion = _compactUserQuestionForSearch(userText);
    if (compactQuestion.isEmpty) compactQuestion = query.trim();

    if (category == 'canon') {
      final asksCurrentCharacter = _asksAboutCurrentCharacterInCanon(userText);
      final subjectText = asksCurrentCharacter
          ? _removeOtherCharacterNamesForCurrentSubjectQuery(
              query.trim().isEmpty ? compactQuestion : query,
              profile,
            )
          : compactQuestion;
      final terms = <String>[
        profile.canonSearchPrefix,
        if (asksCurrentCharacter) profile.characterName,
        if (!asksCurrentCharacter)
          ..._matchedCanonNamesForSearch(
            userText,
            '',
            profile,
          ).take(2),
        subjectText,
      ];
      return _truncateDoubaoQuery(_dedupeSearchQueryTerms(terms.join(' ')));
    }

    final normalized =
        _normalizeSearchQuery(query, category, userText, profile);
    return _truncateDoubaoQuery(normalized);
  }

  static List<String> _canonSearchTargetsForPlan(
    _SearchPlan plan,
    String userText,
    String query,
    _WebProfile profile,
  ) {
    final targets = <String>[];
    final asksCurrentCharacter = _asksAboutCurrentCharacterInCanon(userText);
    final matchedNames = _matchedCanonNamesForSearch(
      userText,
      query,
      profile,
    );
    final prioritizeKnownCharacters = _queryAsksProfileTraits(userText) &&
        !asksCurrentCharacter &&
        matchedNames.isNotEmpty;

    void addTarget(String value, {bool allowContextQualifier = true}) {
      final target = _normalizeCanonSearchObject(value, userText, profile);
      if (target.isEmpty) return;
      if (!allowContextQualifier &&
          _isContextOnlyCanonQualifierForProfileQuestion(target, profile)) {
        return;
      }
      final key = target.toLowerCase();
      if (targets.any((existing) => existing.toLowerCase() == key)) return;
      targets.add(target);
    }

    if (prioritizeKnownCharacters) {
      for (final name in matchedNames) {
        addTarget(name);
      }
    }
    for (final title in _explicitCanonTitleTerms(userText, query)) {
      addTarget(title, allowContextQualifier: !prioritizeKnownCharacters);
    }
    for (final object in plan.primarySearchObjects) {
      addTarget(object, allowContextQualifier: !prioritizeKnownCharacters);
    }
    if (!prioritizeKnownCharacters) {
      for (final name in matchedNames) {
        if (!asksCurrentCharacter &&
            name.trim() == profile.characterName.trim()) {
          continue;
        }
        addTarget(name);
      }
    }
    if (asksCurrentCharacter) {
      addTarget(profile.characterName);
    }
    for (final object in plan.secondarySearchObjects) {
      if (_queryAsksProfileTraits(userText) &&
          !_isKnownCanonCharacterSearchObject(object, profile) &&
          !_isExplicitCanonTitleTerm(object)) {
        continue;
      }
      addTarget(object, allowContextQualifier: !prioritizeKnownCharacters);
    }

    return targets.take(6).toList(growable: false);
  }

  static bool _isContextOnlyCanonQualifierForProfileQuestion(
    String value,
    _WebProfile profile,
  ) {
    if (_isKnownCanonCharacterSearchObject(value, profile)) return false;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (_canonQueryContextTerms.contains(normalized)) return true;
    if (_isExplicitCanonTitleTerm(value)) return true;
    return RegExp(r'(?:乐队|学校|学园|学院|社团|组织)$').hasMatch(value);
  }

  @visibleForTesting
  static List<String> canonSearchTargetsForTest({
    required String userText,
    required String query,
    required String characterId,
    required String characterName,
    List<String> primaryObjects = const [],
    List<String> secondaryObjects = const [],
  }) {
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );
    return _canonSearchTargetsForPlan(
      _SearchPlan(
        includeWeather: false,
        weatherCity: null,
        includeFestivals: false,
        includePhenology: false,
        searchQuery: query,
        category: 'canon',
        primarySearchObjects: primaryObjects,
        secondarySearchObjects: secondaryObjects,
      ),
      userText,
      query,
      profile,
    );
  }

  @visibleForTesting
  static Map<String, Object?> localSearchPlanSnapshotForTest({
    required String userText,
    required String characterId,
    required String characterName,
    List<Message> conversationHistory = const [],
  }) {
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );
    final keywordPlan = _applyProfileRules(
      _keywordSearchPlan(userText, profile),
      userText,
      profile,
    );
    final plan = _applyFollowUpRules(
      keywordPlan,
      userText,
      profile,
      conversationHistory,
    );

    return {
      'hasAnyTask': plan.hasAnyTask,
      'includeWeather': plan.includeWeather,
      'includeFestivals': plan.includeFestivals,
      'includePhenology': plan.includePhenology,
      'searchQuery': plan.searchQuery ?? '',
      'category': plan.category,
    };
  }

  @visibleForTesting
  static Map<String, Object?> simulatedPlannerNoSearchSnapshotForTest({
    required String userText,
    required String characterId,
    required String characterName,
  }) {
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );
    final plan = _applyProfileRules(
      const _SearchPlan(
        includeWeather: false,
        weatherCity: null,
        includeFestivals: false,
        includePhenology: false,
        searchQuery: null,
        category: 'none',
      ),
      userText,
      profile,
      allowImplicitCurrentAffairsSearch: false,
    );

    return {
      'hasAnyTask': plan.hasAnyTask,
      'includeWeather': plan.includeWeather,
      'includeFestivals': plan.includeFestivals,
      'includePhenology': plan.includePhenology,
      'searchQuery': plan.searchQuery ?? '',
      'category': plan.category,
    };
  }

  static bool _isKnownCanonCharacterSearchObject(
    String value,
    _WebProfile profile,
  ) {
    final target = value.replaceAll(RegExp(r'\s+'), '').trim();
    if (target.isEmpty) return false;
    if (target == profile.characterName.replaceAll(RegExp(r'\s+'), '')) {
      return true;
    }
    return ApiService.canonicalChineseNamesForSearch(
          characterId: profile.characterId,
        ).any((name) => name.replaceAll(RegExp(r'\s+'), '') == target) ||
        ApiService.characterSearchAliasesForSearch(
          characterId: profile.characterId,
        ).entries.any(
              (entry) =>
                  entry.key.replaceAll(RegExp(r'\s+'), '') == target ||
                  entry.value.replaceAll(RegExp(r'\s+'), '') == target,
            );
  }

  static String _normalizeCanonSearchObject(
    String value,
    String userText,
    _WebProfile profile,
  ) {
    final raw = value
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (raw.isEmpty) return '';

    if (RegExp(r'^[A-Za-z][A-Za-z0-9!☆_:\-\s]{2,}$').hasMatch(raw) &&
        raw.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length <=
            4) {
      return raw;
    }

    for (final title in _explicitCanonTitleTerms(raw, '')) {
      return title;
    }

    final matchedNames = _matchedCanonNamesForSearch(raw, '', profile);
    if (matchedNames.isNotEmpty) return matchedNames.first;

    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 2) return '';
    if (_canonQueryNoiseTerms.contains(compact.toLowerCase())) return '';
    if (_isQuestionIntentTerm(compact)) return '';
    if (_canonQueryContextTerms.contains(compact.toLowerCase())) return '';
    if (compact.length > 24) return '';
    return compact;
  }

  static List<String> _matchedCanonNamesForSearch(
    String userText,
    String query,
    _WebProfile profile,
  ) {
    final corpus = '$userText $query';
    final matches = <String>[];
    void add(String value) {
      final name = value.trim();
      if (name.length < 2 || matches.contains(name)) return;
      matches.add(name);
    }

    for (final character in CharacterConfig.characters) {
      if (_WebProfile._seriesNameForCharacterId(character.id) !=
          profile.seriesName) {
        continue;
      }
      final name = character.name.trim();
      if (name.isEmpty) continue;
      if (_canonTextContainsTerm(corpus, name) ||
          _canonTextContainsTerm(corpus, _nameTail(name, 2))) {
        add(name);
      }
    }

    final uniqueShortNames = _uniqueSeriesCharacterShortNames(profile);
    for (final entry in uniqueShortNames.entries) {
      if (_canonTextContainsTerm(corpus, entry.key)) {
        add(entry.value);
      }
    }

    final pronunciationAliases = _uniquePronunciationCharacterAliases();
    final normalizedCorpus = ApiService.nameSearchMatchKey(corpus);
    for (final entry in pronunciationAliases.entries) {
      final aliasKey = ApiService.nameSearchMatchKey(entry.key);
      if (aliasKey.isNotEmpty && normalizedCorpus.contains(aliasKey)) {
        add(entry.value);
      }
    }

    final characterSearchAliases = ApiService.characterSearchAliasesForSearch(
      characterId: profile.characterId,
    );
    for (final entry in characterSearchAliases.entries) {
      final aliasKey = ApiService.nameSearchMatchKey(entry.key);
      if (aliasKey.isNotEmpty && normalizedCorpus.contains(aliasKey)) {
        add(entry.value);
      }
    }

    final configuredCallNames =
        ApiService.fixedCharacterCallNameChineseTargets(profile.characterId);
    for (final entry in configuredCallNames.entries) {
      final callName = entry.value.trim();
      if (callName.isEmpty) continue;
      if (_canonTextContainsTerm(corpus, callName)) {
        add(entry.key);
      }
    }

    for (final name in ApiService.canonicalChineseNamesForSearch(
      characterId: profile.characterId,
    )) {
      if (_canonTextContainsTerm(corpus, name) ||
          _canonTextContainsTerm(corpus, _nameTail(name, 2))) {
        add(name);
      }
    }

    for (final name in _roleTitleMatchesForSearch(corpus, profile)) {
      add(name);
    }

    matches.sort((a, b) {
      final indexA = _firstCanonNameHitIndex(userText, a);
      final indexB = _firstCanonNameHitIndex(userText, b);
      if (indexA != indexB) return indexA.compareTo(indexB);
      return 0;
    });
    return matches;
  }

  static Map<String, String> _uniquePronunciationCharacterAliases() {
    final owners = <String, Set<String>>{};
    final displayAliases = <String, String>{};
    for (final entry in characterNamePronunciations) {
      final writtenParts = entry.japanese
          .split(RegExp(r'[\s　]+'))
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      final readingParts = entry.reading
          .split(RegExp(r'[\s　]+'))
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      if (writtenParts.length < 2 || readingParts.length < 2) continue;
      if (!RegExp(r'[一-龥ぁ-ゖァ-ヺ]').hasMatch(entry.japanese)) continue;

      final writtenFullName = writtenParts.join();
      for (final alias in <String>{
        writtenFullName,
        ...writtenParts,
        ...readingParts,
        ...entry.aliases.keys,
      }) {
        final aliasKey = ApiService.nameSearchMatchKey(alias);
        if (aliasKey.isEmpty) continue;
        owners.putIfAbsent(aliasKey, () => <String>{}).add(entry.chinese);
        displayAliases.putIfAbsent(aliasKey, () => alias);
      }
    }

    final result = <String, String>{};
    for (final entry in owners.entries) {
      if (entry.value.length != 1) continue;
      final alias = displayAliases[entry.key];
      if (alias == null || alias.isEmpty) continue;
      result[alias] = entry.value.single;
    }
    return result;
  }

  static int _firstCanonNameHitIndex(String text, String name) {
    final forms = _nameFormsForSearch(name).toList()
      ..sort((a, b) => b.runes.length.compareTo(a.runes.length));
    for (final form in forms) {
      final index = text.indexOf(form);
      if (index >= 0) return index;
    }
    return 1 << 30;
  }

  static Map<String, String> _uniqueSeriesCharacterShortNames(
    _WebProfile profile,
  ) {
    final owners = <String, Set<String>>{};

    void addForm(String form, String fullName) {
      final normalized = form.trim();
      if (normalized.isEmpty || normalized == fullName) return;
      owners.putIfAbsent(normalized, () => <String>{}).add(fullName);
    }

    for (final character in CharacterConfig.characters) {
      if (_WebProfile._seriesNameForCharacterId(character.id) !=
          profile.seriesName) {
        continue;
      }
      final name = character.name.trim();
      if (name.isEmpty) continue;
      final runes = name.runes.toList();
      if (runes.length >= 3) {
        addForm(String.fromCharCodes(runes.sublist(runes.length - 2)), name);
      }
    }

    final result = <String, String>{};
    for (final entry in owners.entries) {
      if (entry.value.length == 1) {
        result[entry.key] = entry.value.single;
      }
    }
    return result;
  }

  static List<String> _mainCanonDoubaoQueries(
    String baseQuery, {
    required String originalQuery,
    required String userText,
    required _WebProfile profile,
    List<String> searchTargets = const [],
  }) {
    final queries = <String>[];

    void addQuery(String value) {
      final query = _truncateDoubaoQuery(_dedupeSearchQueryTerms(value));
      if (query.isEmpty || queries.contains(query)) return;
      queries.add(query);
    }

    for (final target in searchTargets) {
      addQuery(target);
    }
    if (queries.isNotEmpty) return queries;

    final asksCurrentCharacter = _asksAboutCurrentCharacterInCanon(userText) ||
        _canonTextContainsTerm(originalQuery, profile.characterName) ||
        _canonTextContainsTerm(baseQuery, profile.characterName);
    if (asksCurrentCharacter) {
      addQuery('${profile.canonSearchPrefix} ${profile.characterName}');
    }
    addQuery(baseQuery);
    if (asksCurrentCharacter && originalQuery.trim().isNotEmpty) {
      addQuery(
        '${profile.canonSearchPrefix} ${profile.characterName} $originalQuery',
      );
    }

    return queries;
  }

  static List<String> _explicitCanonTitleTerms(
    String userText,
    String originalQuery,
  ) {
    final corpus = '$userText $originalQuery';
    final terms = <String>[];
    void add(String value) {
      final term = value.trim();
      if (term.length < 3 || terms.contains(term)) return;
      if (_canonQueryNoiseTerms.contains(term.toLowerCase())) return;
      terms.add(term);
    }

    final latinTokenPattern = RegExp(r'[A-Za-z][A-Za-z0-9!☆_:\-]{2,}');
    for (final match in latinTokenPattern.allMatches(corpus)) {
      add(match.group(0) ?? '');
    }
    return terms;
  }

  static bool _asksAboutCurrentCharacterInCanon(String userText) {
    return RegExp(
      r'你当初|你自己|你本人|你们|你的|你比较|你好像|你喜欢|你常|关于你|和你|对你',
    ).hasMatch(userText);
  }

  static String _removeOtherCharacterNamesForCurrentSubjectQuery(
    String text,
    _WebProfile profile,
  ) {
    return _removeCharacterNamesExceptForSearch(
      text,
      keepName: profile.characterName,
      profile: profile,
    );
  }

  static String _removeCharacterNamesExceptForSearch(
    String text, {
    required String keepName,
    required _WebProfile profile,
  }) {
    var result = text;
    final keepForms = _nameFormsForSearch(keepName);
    final names = <String>{};

    void addOtherNameForm(String name) {
      final trimmed = name.trim();
      if (trimmed.length < 2 || keepForms.contains(trimmed)) return;
      names.add(trimmed);

      final runes = trimmed.runes.toList();
      if (runes.length >= 4) {
        final tail3 = String.fromCharCodes(runes.sublist(runes.length - 3));
        if (!keepForms.contains(tail3)) names.add(tail3);
      }
      if (runes.length >= 3) {
        final tail2 = String.fromCharCodes(runes.sublist(runes.length - 2));
        if (!keepForms.contains(tail2)) names.add(tail2);
      }
    }

    for (final character in CharacterConfig.characters) {
      if (_WebProfile._seriesNameForCharacterId(character.id) ==
          profile.seriesName) {
        addOtherNameForm(character.name);
      }
    }
    for (final name in ApiService.canonicalChineseNamesForSearch(
      characterId: profile.characterId,
    )) {
      addOtherNameForm(name);
    }

    final sortedNames = names.toList()
      ..sort((a, b) => b.runes.length.compareTo(a.runes.length));
    for (final name in sortedNames) {
      result = result.replaceAll(name, ' ');
    }

    result = result
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return result.isEmpty ? keepName.trim() : result;
  }

  static Set<String> _nameFormsForSearch(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const {};
    final forms = <String>{trimmed};
    final runes = trimmed.runes.toList();
    if (runes.length >= 4) {
      forms.add(String.fromCharCodes(runes.sublist(runes.length - 3)));
    }
    if (runes.length >= 3) {
      forms.add(String.fromCharCodes(runes.sublist(runes.length - 2)));
    }
    return forms;
  }

  static List<String> _roleTitleMatchesForSearch(
    String corpus,
    _WebProfile profile,
  ) {
    final matches = <String>[];
    void add(String value) {
      final name = value.trim();
      if (name.length < 2 || matches.contains(name)) return;
      matches.add(name);
    }

    for (final character in CharacterConfig.characters) {
      if (_WebProfile._seriesNameForCharacterId(character.id) !=
          profile.seriesName) {
        continue;
      }
      final source = character.personality;
      for (final match in RegExp(
        r'([\u4e00-\u9fa5]{1,3}柱)[·・]\s*([\u4e00-\u9fa5髄]+)',
      ).allMatches(source)) {
        final title = match.group(1) ?? '';
        final name = match.group(2) ?? '';
        if (title.isEmpty || name.isEmpty) continue;
        if (_canonTextContainsTerm(corpus, title) ||
            _canonTextContainsTerm(corpus, name) ||
            _canonTextContainsTerm(corpus, _nameTail(name, 2))) {
          add(name);
        }
      }
    }

    return matches;
  }

  static String _nameTail(String value, int count) {
    final runes = value.runes.toList();
    if (runes.length <= count) return value;
    return String.fromCharCodes(runes.sublist(runes.length - count));
  }

  static String _truncateDoubaoQuery(String query) {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.runes.length <= 100) return normalized;
    return String.fromCharCodes(normalized.runes.take(100)).trim();
  }

  static Future<List<_DoubaoSearchItem>> _callDoubaoSearchApi(
    String query, {
    required String apiKey,
    required int count,
    int authLevel = 0,
    String? timeRange,
    String? sites,
    bool useGlobal = false,
    String category = 'general',
    _WebProfile? profile,
  }) async {
    try {
      if ((_activeTrace?.searchApiCalls ?? 0) >=
          _maxDoubaoSearchApiCallsPerTurn) {
        _logSearchVerbose(
          '豆包搜索请求被本地预算门禁拦截: query=${_truncateDoubaoQuery(query)}',
        );
        return const [];
      }
      final body = <String, dynamic>{
        'Query': _truncateDoubaoQuery(query),
        'SearchType': 'web',
        'Count': count.clamp(1, 50),
        'QueryControl': {'QueryRewrite': true},
        'NeedSummary': true,
        'NeedContent': true,
        if (sites != null && sites.trim().isNotEmpty) 'Sites': sites.trim(),
        if (authLevel > 0) 'Filter': {'AuthInfoLevel': authLevel},
        if (timeRange != null && timeRange.trim().isNotEmpty)
          'TimeRange': timeRange.trim(),
      };

      _activeTrace?.recordRemoteCall(
        kind: 'search_api',
        provider: useGlobal ? 'Doubao Global' : 'Doubao Custom',
        operation: 'web_search',
        requestLabel: _truncateDoubaoQuery(query),
      );

      final response = await http
          .post(
            Uri.parse(useGlobal
                ? _doubaoGlobalSearchEndpoint
                : _doubaoCustomSearchEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
              'X-Traffic-Tag': 'ark_anime_chat_app_web_search',
            },
            body: jsonEncode(body),
          )
          .timeout(_searchTimeout);

      if (response.statusCode != 200) {
        _logSearch(
          '豆包搜索 API 失败: status=${response.statusCode}',
        );
        _logSearchVerbose('豆包搜索 API 失败详情: ${response.body}');
        return const [];
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final apiError = _doubaoSearchApiErrorMessage(decoded);
      if (apiError.isNotEmpty) {
        _logSearch('豆包搜索 API 返回错误: $apiError');
        return const [];
      }
      final rawItems = _extractDoubaoResultItems(decoded);
      final parsedItems = rawItems
          .whereType<Map>()
          .map((item) => _DoubaoSearchItem.fromMap(item))
          .where((item) => item.title.isNotEmpty || item.bestText.isNotEmpty)
          .toList();
      final urlFilteredItems = parsedItems
          .where((item) =>
              item.url.isEmpty || !_isUnwantedSearchResultUrl(item.url))
          .toList();
      final isExplicitCanonTarget =
          category == 'canon' && _shouldApplyExplicitTargetFilter(query);
      final explicitTargetTerms = _explicitTargetTermsForSearch(query);
      final canonFilteredItems = category == 'canon'
          ? urlFilteredItems
              .where(
                (item) => _isAcceptableCanonDoubaoItem(item, profile),
              )
              .toList()
          : urlFilteredItems;
      final siteFilteredItems = canonFilteredItems
          .where((item) =>
              sites == null ||
              sites.trim().isEmpty ||
              _doubaoItemMatchesSites(item, sites))
          .toList();
      final targetFilteredItems = isExplicitCanonTarget
          ? siteFilteredItems.where((item) {
              final combined =
                  '${item.title} ${item.snippet} ${item.summary} ${item.content} ${item.url}';
              return explicitTargetTerms.any(
                (term) => _canonTextContainsTerm(combined, term),
              );
            }).toList()
          : siteFilteredItems;
      final siteLog = sites == null || sites.trim().isEmpty
          ? ''
          : ', sites=${sites.trim()}';
      final authLog = authLevel > 0 ? ', authInfoLevel=$authLevel' : '';
      final engineName = useGlobal ? 'Global' : 'Custom';
      _logSearchVerbose(
        '豆包搜索 API 过滤: raw=${rawItems.length}, parsed=${parsedItems.length}, '
        'engine=$engineName, '
        'afterUrl=${urlFilteredItems.length}, '
        'afterCanon=${canonFilteredItems.length}, '
        'afterSites=${siteFilteredItems.length}, '
        'afterTarget=${targetFilteredItems.length}, '
        'needContent=true'
        '$siteLog$authLog',
      );
      if (category == 'canon' && targetFilteredItems.isEmpty) {
        _logSearchVerbose(
          '豆包搜索候选过滤诊断:\n'
          '${_formatDoubaoFilterDebug(urlFilteredItems, explicitTargetTerms.join('|'), profile, sites)}',
        );
      }
      final sortedItems = category == 'canon'
          ? _sortDoubaoCanonItemsBySourcePriority(targetFilteredItems, profile)
          : targetFilteredItems;
      if (category == 'canon' && sortedItems.isNotEmpty) {
        _logSearchVerbose(
          '豆包搜索本地来源排序:\n${_formatDoubaoItemsForLog(sortedItems)}',
        );
      }
      return sortedItems;
    } catch (e) {
      _logSearch('豆包搜索 API 异常: $e');
      return const [];
    }
  }

  static bool _doubaoItemMatchesSites(_DoubaoSearchItem item, String sites) {
    final allowedHosts = sites
        .split('|')
        .map((site) => site.trim().replaceFirst(RegExp(r'^www\.'), ''))
        .where((site) => site.isNotEmpty)
        .toList(growable: false);
    if (allowedHosts.isEmpty) return true;

    final urlHost = Uri.tryParse(item.url)
        ?.host
        .replaceFirst(RegExp(r'^www\.'), '')
        .toLowerCase();
    final siteName =
        item.siteName.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();

    bool matches(String host) {
      if (host.isEmpty) return false;
      return allowedHosts.any(
        (allowed) => host == allowed || host.endsWith('.$allowed'),
      );
    }

    return matches(urlHost ?? '') || matches(siteName);
  }

  static String _doubaoExtractionSourceKey(
    String query,
    List<_DoubaoSearchItem> items,
  ) {
    final urls = items
        .take(_doubaoFactMaxResults)
        .map((item) => item.url.isNotEmpty
            ? item.url
            : '${item.title}:${item.bestText.runes.length}')
        .join('|');
    return '${_normalizeForDedupe(query)}::$urls';
  }

  static List<String> _explicitTargetTermsForSearch(String query) {
    final terms = <String>[];
    void add(String value) {
      final term = value.trim();
      if (term.isEmpty) return;
      final key = term.toLowerCase();
      if (terms.any((existing) => existing.toLowerCase() == key)) return;
      terms.add(term);
    }

    for (final term in _explicitCanonTitleTerms(query, '')) {
      add(term);
      add(_latinSearchIndexTitle(term));
      add(term.toUpperCase());
    }
    return terms.isEmpty ? [query] : terms;
  }

  static bool _shouldApplyExplicitTargetFilter(String query) {
    final clean = query.trim();
    if (!_isExplicitCanonTitleTerm(clean)) return false;
    if (RegExp(r'[\u3400-\u9fffぁ-ゟァ-ヿ]').hasMatch(clean)) {
      return false;
    }
    return clean
            .split(RegExp(r'\s+'))
            .where((part) => part.trim().isNotEmpty)
            .length <=
        4;
  }

  static String _formatDoubaoFilterDebug(
    List<_DoubaoSearchItem> items,
    String queryTerms,
    _WebProfile? profile,
    String? sites,
  ) {
    if (items.isEmpty) return '无 URL 过滤后的候选';
    final targetTerms = queryTerms
        .split('|')
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final lines = <String>[];
    for (final item in items.take(6)) {
      final host =
          Uri.tryParse(item.url)?.host.replaceFirst(RegExp(r'^www\.'), '') ??
              '';
      final combined =
          '${item.title} ${item.siteName} ${item.url} ${item.snippet} ${item.summary} ${item.content}';
      final trusted = host.isNotEmpty && _isTrustedCanonResultDomain(host);
      final series = profile == null || _doubaoItemMatchesSeries(item, profile);
      final unwanted = _doubaoSourceLabelLooksUnwanted(item);
      final siteMatch = sites == null ||
          sites.trim().isEmpty ||
          _doubaoItemMatchesSites(item, sites);
      final target = targetTerms.isEmpty ||
          targetTerms.any((term) => _canonTextContainsTerm(combined, term));
      lines.add(
        '- ${_shortenRunes(item.title.isEmpty ? item.url : item.title, 80)} '
        'host=$host trusted=$trusted series=$series unwanted=$unwanted '
        'site=$siteMatch target=$target url=${item.url}',
      );
    }
    return lines.join('\n');
  }

  static List<_DoubaoSearchItem> _sortDoubaoCanonItemsBySourcePriority(
    List<_DoubaoSearchItem> items,
    _WebProfile? profile,
  ) {
    final indexed = <({int index, int weight, _DoubaoSearchItem item})>[];
    for (var i = 0; i < items.length; i++) {
      indexed.add((
        index: i,
        weight: _canonSourcePriorityWeight(items[i], profile),
        item: items[i],
      ));
    }
    indexed.sort((a, b) {
      final weightCompare = a.weight.compareTo(b.weight);
      if (weightCompare != 0) return weightCompare;
      final textCompare = b.item.bestText.runes.length.compareTo(
        a.item.bestText.runes.length,
      );
      if (textCompare != 0) return textCompare;
      return a.index.compareTo(b.index);
    });
    return indexed.map((entry) => entry.item).toList(growable: false);
  }

  static int _canonSourcePriorityWeight(
    _DoubaoSearchItem item,
    _WebProfile? profile,
  ) {
    final host =
        Uri.tryParse(item.url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';
    if (host.isEmpty) return 9;
    if (_isMoegirlDomain(host)) return 1;
    if (host == 'baike.baidu.com' || host == 'wapbaike.baidu.com') return 2;
    if (host == 'zh.wikipedia.org' || host.endsWith('.wikipedia.org')) {
      return 2;
    }
    if (profile != null) {
      final official = _officialCanonSitesForProfile(profile).split('|');
      final supplemental =
          _supplementalCanonSitesForProfile(profile).split('|');
      if ([...official, ...supplemental].any((domain) {
        final normalized = domain.trim().replaceFirst(RegExp(r'^www\.'), '');
        return normalized.isNotEmpty &&
            (host == normalized || host.endsWith('.$normalized'));
      })) {
        return 3;
      }
    }
    return 4;
  }

  static bool _isMoegirlDomain(String host) {
    final normalized = host.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
    return normalized == 'zh.moegirl.org.cn' ||
        normalized == 'moegirl.org.cn' ||
        normalized == 'moegirl.org' ||
        normalized == 'moegirl.uk' ||
        normalized.endsWith('.moegirl.org.cn') ||
        normalized.endsWith('.moegirl.org') ||
        normalized.endsWith('.moegirl.uk');
  }

  static bool _isAcceptableCanonDoubaoItem(
    _DoubaoSearchItem item,
    _WebProfile? profile,
  ) {
    final uri = Uri.tryParse(item.url);
    final host =
        uri?.host.replaceFirst(RegExp(r'^www\.'), '').toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (!_isTrustedCanonResultDomain(host)) return false;
    if (profile != null && !_doubaoItemMatchesSeries(item, profile)) {
      return false;
    }

    return !_doubaoSourceLabelLooksUnwanted(item);
  }

  static bool _doubaoSourceLabelLooksUnwanted(_DoubaoSearchItem item) {
    final sourceLabel = '${item.title} ${item.siteName} ${item.url}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return RegExp(
      r'论坛|讨论|专楼|同人|二创|安科|攻略|剪辑|视频|评论|弹幕|商品|周边|下载|安装包|公测|运营|直播|新闻|访谈|演唱会',
      caseSensitive: false,
    ).hasMatch(sourceLabel);
  }

  static bool _doubaoItemMatchesSeries(
    _DoubaoSearchItem item,
    _WebProfile profile,
  ) {
    final combined =
        '${item.title} ${item.siteName} ${item.url} ${item.snippet} ${item.summary} ${item.content}';
    if (combined.trim().isEmpty) return false;

    List<String> markers;
    switch (profile.seriesName) {
      case 'BanG Dream':
        markers = const [
          'BanG Dream',
          'バンドリ',
          'MyGO',
          'Ave Mujica',
          'Mujica',
          'CRYCHIC',
        ];
        break;
      case '鬼灭之刃':
        markers = [
          '鬼灭之刃',
          '鬼滅之刃',
          '鬼滅の刃',
          'Kimetsu',
          'Demon Slayer',
          'kimetsu-no-yaiba',
          profile.characterName,
          profile.canonSearchPrefix,
        ];
        break;
      case '欢乐颂':
        markers = const ['欢乐颂'];
        break;
      default:
        markers = [profile.seriesName, profile.canonSearchPrefix];
    }
    return markers.any((marker) => _canonTextContainsTerm(combined, marker));
  }

  static List<dynamic> _extractDoubaoResultItems(dynamic node) {
    if (node is List &&
        node.any((item) =>
            item is Map &&
            (_dynamicMapString(item, 'Title').isNotEmpty ||
                _dynamicMapString(item, 'title').isNotEmpty ||
                _dynamicMapString(item, 'Snippet').isNotEmpty ||
                _dynamicMapString(item, 'snippet').isNotEmpty))) {
      return node;
    }

    if (node is Map) {
      for (final key in const [
        'Results',
        'results',
        'Result',
        'result',
        'SearchResults',
        'search_results',
        'Data',
        'data',
      ]) {
        if (!node.containsKey(key)) continue;
        final nested = _extractDoubaoResultItems(node[key]);
        if (nested.isNotEmpty) return nested;
      }

      for (final value in node.values) {
        final nested = _extractDoubaoResultItems(value);
        if (nested.isNotEmpty) return nested;
      }
    }

    return const [];
  }

  static String _doubaoSearchApiErrorMessage(dynamic decoded) {
    if (decoded is! Map) return '';
    final metadata = decoded['ResponseMetadata'];
    if (metadata is Map) {
      final error = metadata['Error'];
      if (error is Map) {
        final code = _dynamicMapString(error, 'Code');
        final codeN = _dynamicMapString(error, 'CodeN');
        final message = _dynamicMapString(error, 'Message');
        final parts = [
          if (code.isNotEmpty) 'code=$code',
          if (codeN.isNotEmpty && codeN != code) 'codeN=$codeN',
          if (message.isNotEmpty) message,
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
    }

    final code = _dynamicMapString(decoded, 'Code');
    final message = _dynamicMapString(decoded, 'Message');
    if (code.isEmpty && message.isEmpty) return '';
    return [
      if (code.isNotEmpty) 'code=$code',
      if (message.isNotEmpty) message,
    ].join(', ');
  }

  static String _dynamicMapString(Map item, String key) {
    final value = item[key];
    return value is String ? value.trim() : '';
  }

  static Future<_DoubaoFactExtraction> _extractDoubaoFactsWithModel({
    required String searchQuery,
    required String userText,
    required String category,
    required _WebProfile profile,
    required List<_DoubaoSearchItem> items,
    required int factLimit,
    required int minimumFactTarget,
    int minimumSourceTarget = 1,
    required bool preferEvidenceText,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
    bool candidateRecoveryPass = false,
    List<_DoubaoGroundedFact> excludedFacts = const [],
  }) async {
    try {
      final rawResults = _formatDoubaoRawResultsForModel(items);
      if (rawResults.isEmpty) return const _DoubaoFactExtraction.empty();
      final contentCount =
          items.where((item) => item.content.isNotEmpty).length;
      final summaryCount =
          items.where((item) => item.summary.isNotEmpty).length;
      final snippetCount =
          items.where((item) => item.snippet.isNotEmpty).length;
      _logSearchVerbose(
        '豆包事实抽取输入: results=${items.length}, chars=${rawResults.runes.length}, '
        'withContent=$contentCount, withSummary=$summaryCount, withSnippet=$snippetCount, '
        'perResultMax=$_doubaoFactPerResultMaxChars, '
        'factLimit=$factLimit, '
        'note=优先使用搜索 API 返回的 Content 正文；Content 为空时才退回 Summary/Snippet',
      );

      final messages = [
        {
          'role': 'system',
          'content': _doubaoFactExtractorPrompt(
            profile,
            category,
            factLimit: factLimit,
            minimumFactTarget: minimumFactTarget,
            minimumSourceTarget: minimumSourceTarget,
            answerMode: answerMode,
            answerRequirements: answerRequirements,
          ),
        },
        {
          'role': 'user',
          'content': '''
用户问题：
$userText

独立问项（索引从 0 开始，facts 必须用 requirement_indexes 对应）：
${answerRequirements.asMap().entries.map((entry) {
            final cues = entry.value.directEvidenceCues.isEmpty
                ? '无额外限定'
                : '直接证据关系：${entry.value.directEvidenceCues.join('、')}';
            return '${entry.key}. ${entry.value.text}（$cues）';
          }).join('\n')}

本轮最低有效事实目标：$minimumFactTarget 条。${minimumSourceTarget > 1 ? '如果输入中有多个相关网页，事实应尽量覆盖至少 $minimumSourceTarget 个不同网页来源；每条 fact 应是自然可回答的信息块，不要为了凑数量把同一句话或紧密相连的同一原因拆成多个碎片。' : ''}只有原文确实不足时才可以少于这个数量并返回 partial；不得用旁支信息凑数。

${candidateRecoveryPass ? '这是同一批直达正文的唯一一次复核。首次抽取没有返回事实，请重新通读全文；如果没有直接频率、偏好或评价结论，但正文列出了真实候选、使用记录、特征或效果，必须按 bounded_candidates 输出，不能仅因缺少直接结论再次判 insufficient。' : ''}

${excludedFacts.isEmpty ? '' : '''
已采纳事实（本轮不要重复或换句话复述）：
${excludedFacts.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value.text}').join('\n')}
请继续通读同一批正文，只输出与上述事实语义不同、且与用户问项直接相关的补充事实。如果确实没有，返回 insufficient，不得拿旁支信息凑数。
'''}

搜索词：
$searchQuery

来源优先级：
${_doubaoSourcePriorityInstruction(profile, category)}

搜索结果：
$rawResults
''',
        },
      ];

      final chatResult = await _callFactExtractorChatCompletions(
        messages,
        maxTokens: _factExtractionMaxTokens(factLimit),
      );

      if (chatResult == null) {
        return const _DoubaoFactExtraction.empty();
      }

      final data = jsonDecode(utf8.decode(chatResult.response.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      if (content is! String || content.trim().isEmpty) {
        return const _DoubaoFactExtraction.empty();
      }

      final extraction = _parseDoubaoFactExtraction(
        content,
        category: category,
        provider: chatResult.provider,
        factLimit: factLimit,
        answerMode: answerMode,
        answerRequirements: answerRequirements,
      );
      final validated = _validateExtractedFactsAgainstSearchResults(
        extraction,
        userText: userText,
        items: items,
        category: category,
        preferEvidenceText: preferEvidenceText,
        factLimit: factLimit,
        answerMode: answerMode,
      );
      final augmented = _augmentPreferenceFactsFromSearchResults(
        validated,
        userText: userText,
        items: items,
        provider: '${chatResult.provider}+本地喜恶事实补充',
        factLimit: factLimit,
      );
      if (augmented.facts.length > validated.facts.length) {
        _logSearchVerbose(
          '本地喜恶事实补充: '
          '${_formatDoubaoFactsCompactForLog(augmented.facts.skip(validated.facts.length).toList())}',
        );
      }
      final mediaAugmented = _augmentMediaIdentityFactsFromSearchResults(
        augmented,
        userText: userText,
        items: items,
        provider: '${chatResult.provider}+本地书影音事实补充',
        factLimit: factLimit,
      );
      if (mediaAugmented.facts.length > augmented.facts.length) {
        _logSearchVerbose(
          '本地书影音事实补充: '
          '${_formatDoubaoFactsCompactForLog(mediaAugmented.facts.skip(augmented.facts.length).toList())}',
        );
      }
      if (validated.facts.isEmpty &&
          category == 'canon' &&
          _queryAsksMusicInfo(userText)) {
        final fallback = _fallbackMusicFactsFromSearchResults(
          items,
          provider: '${chatResult.provider}+本地曲目信息兜底',
          factLimit: factLimit,
        );
        if (fallback.facts.isNotEmpty) return fallback;
      }
      return mediaAugmented;
    } catch (e) {
      debugPrint('豆包事实提取异常: $e');
      return const _DoubaoFactExtraction.empty();
    }
  }

  static _DoubaoFactExtraction _augmentMediaIdentityFactsFromSearchResults(
    _DoubaoFactExtraction extraction, {
    required String userText,
    required List<_DoubaoSearchItem> items,
    required String provider,
    required int factLimit,
  }) {
    if (!_queryAsksMediaOrEntertainment(userText) ||
        extraction.facts.length >= 3 ||
        items.isEmpty) {
      return extraction;
    }

    final queryTerms = _mediaQueryAnchorTerms(userText);
    if (queryTerms.isEmpty) return extraction;
    final merged = [...extraction.facts];

    void addFact(_DoubaoSearchItem item, String fragment) {
      final cleaned = fragment.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.length < 12) return;
      if (_isNoisyRawFragment(cleaned)) return;
      final candidate = _DoubaoGroundedFact(
        text: cleaned,
        sourceTitle: item.title,
        sourceUrl: item.url,
        sourceExcerpt: cleaned,
        requirementIndexes: const [0],
        answerBasis: _answerBasisExplicitFact,
        directAnswerExcerpt: cleaned,
        isStrongEvidence: true,
      );
      if (_shouldFilterProductionMetaFact(
        candidate,
        category: 'general',
        userText: userText,
      )) {
        return;
      }
      if (!_mediaFragmentMatchesQuestion(cleaned, queryTerms)) return;
      _addUniqueDoubaoFacts(merged, [candidate], maxFacts: factLimit);
    }

    for (final item in items.take(_doubaoFactMaxResults)) {
      if (merged.length >= 3) break;
      if (_isUnwantedSearchResultUrl(item.url)) continue;
      final sourceText = _allSearchResultTextForFact(item)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (sourceText.isEmpty) continue;
      for (final fragment in _rawContentFragments(sourceText)) {
        if (merged.length >= 3) break;
        if (!_looksLikeMediaIdentityFragment(fragment)) continue;
        addFact(item, fragment);
      }
    }

    if (merged.length == extraction.facts.length) return extraction;
    return _DoubaoFactExtraction(
      status: merged.length >= 3 ? 'ok' : extraction.status,
      facts: merged.take(factLimit).toList(growable: false),
      discardReason: extraction.discardReason,
      provider: provider,
      answerBasis: _answerBasisForFacts(
        merged,
        fallback: extraction.answerBasis,
      ),
    );
  }

  static List<String> _mediaQueryAnchorTerms(String userText) {
    const stopWords = {
      '最近',
      '喜欢',
      '很喜欢',
      '姐姐',
      '应该',
      '不太',
      '了解',
      '什么',
      '番剧',
      '动画',
      '漫画',
      '电影',
      '电视剧',
      '作品',
      '歌曲',
      '乐队',
    };
    final terms = <String>[];
    void addTerm(String value) {
      var term = value
          .replaceAll(RegExp(r'^(?:我|最近|很|好|超|特别|挺|也|在)+'), '')
          .replaceAll(RegExp(r'^(?:喜欢看|喜欢听|喜欢|爱看|爱听|看|追|听)+'), '')
          .replaceAll(RegExp(r'(?:的)?(?:番|番剧|动画|漫画|电影|电视剧|剧|歌|歌曲|曲子|作品)$'), '')
          .replaceFirst(RegExp(r'的$'), '')
          .trim();
      if (term.length < 2 || stopWords.contains(term)) return;
      if (!terms.contains(term)) terms.add(term);
    }

    for (final match in RegExp(
      r'(?:喜欢看|喜欢听|爱看|爱听|最近在看|最近在听|看|追|听)([A-Za-z0-9!☆★∞_+\-\u4e00-\u9fff]{2,18})(?:的)?(?:番|番剧|动画|漫画|电影|电视剧|剧|歌|歌曲|曲子|作品)?',
      caseSensitive: false,
    ).allMatches(userText)) {
      addTerm(match.group(1) ?? '');
    }
    for (final match in RegExp(
      r'([A-Za-z0-9!☆★∞_+\-\u4e00-\u9fff]{2,18})的(?:番|番剧|动画|漫画|电影|电视剧|剧|歌|歌曲|曲子|作品)',
      caseSensitive: false,
    ).allMatches(userText)) {
      addTerm(match.group(1) ?? '');
    }

    for (final match in RegExp(r'[A-Za-z0-9!☆★∞_+-]{2,}|[\u4e00-\u9fff]{2,}')
        .allMatches(userText)) {
      addTerm(match.group(0) ?? '');
    }
    return terms.toSet().toList(growable: false);
  }

  static bool _looksLikeMediaIdentityFragment(String fragment) {
    return RegExp(
      r'TV动画|动画|番剧|漫画|电影|电视剧|剧集|作品|歌曲|乐队|バンド|团体|组合|成员|主角|题材|改编|讲述|围绕|构建',
      caseSensitive: false,
    ).hasMatch(fragment);
  }

  static bool _mediaFragmentMatchesQuestion(
    String fragment,
    List<String> queryTerms,
  ) {
    final normalized = _looseEvidenceKey(fragment).toLowerCase();
    return queryTerms.any(
      (term) => normalized.contains(_looseEvidenceKey(term).toLowerCase()),
    );
  }

  static _DoubaoFactExtraction _augmentPreferenceFactsFromSearchResults(
    _DoubaoFactExtraction extraction, {
    required String userText,
    required List<_DoubaoSearchItem> items,
    required String provider,
    required int factLimit,
  }) {
    if (!_queryAsksProfileTraits(userText) || items.isEmpty) {
      return extraction;
    }

    final fallbackFacts = <_DoubaoGroundedFact>[];
    for (final item in items.take(_doubaoFactMaxResults)) {
      final sourceText = item.bestText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (sourceText.isEmpty) continue;
      for (final fragment in _rawContentFragments(sourceText)) {
        final factText = _preferenceFactTextFromFragment(fragment);
        if (factText.isEmpty) continue;
        if (extraction.facts.isNotEmpty &&
            !_hasNegativePreferenceSignal(factText)) {
          continue;
        }
        final fallbackFact = _DoubaoGroundedFact(
          text: factText,
          sourceTitle: item.title,
          sourceUrl: item.url,
          sourceExcerpt: fragment,
        );
        if (_isBloatedProfileBoxFact(fallbackFact)) continue;
        if (!_preferenceFactMatchesSourceSubject(fallbackFact)) continue;
        fallbackFacts.add(fallbackFact);
        if (fallbackFacts.length >= 4) break;
      }
      if (fallbackFacts.length >= 4) break;
    }
    if (fallbackFacts.isEmpty) return extraction;

    final merged = [...extraction.facts];
    _addUniqueDoubaoFacts(merged, fallbackFacts, maxFacts: factLimit);
    if (merged.length == extraction.facts.length) return extraction;

    return _DoubaoFactExtraction(
      status:
          extraction.status == 'insufficient' ? 'partial' : extraction.status,
      facts: merged,
      discardReason: extraction.discardReason,
      provider: extraction.provider == 'none' ? provider : extraction.provider,
      answerBasis: extraction.answerBasis,
    );
  }

  static String _preferenceFactTextFromFragment(String fragment) {
    var cleaned = fragment.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length < 6) return '';
    if (_looksLikeGarbledText(cleaned)) return '';
    if (_isRealWorldProductionFragment(cleaned)) return '';
    if (_isNoisyRawFragment(cleaned) && !_hasPreferenceSignal(cleaned)) {
      return '';
    }
    if (!_hasPreferenceSignal(cleaned)) return '';

    cleaned = cleaned
        .replaceFirst(RegExp(r'^根据[^，,。]{1,40}[，,]'), '')
        .replaceFirst(RegExp(r'^据[^，,。]{1,40}[，,]'), '')
        .trim();
    if (cleaned.length < 6) return '';
    return _normalizeExtractedFactText(cleaned);
  }

  static _DoubaoFactExtraction _validateExtractedFactsAgainstSearchResults(
    _DoubaoFactExtraction extraction, {
    required String userText,
    required List<_DoubaoSearchItem> items,
    required String category,
    required bool preferEvidenceText,
    required int factLimit,
    required String answerMode,
  }) {
    if (extraction.facts.isEmpty) {
      return extraction;
    }

    final requireEvidence = preferEvidenceText;
    final validatedFacts = <_DoubaoGroundedFact>[];
    final droppedEvidenceFacts = <_DoubaoGroundedFact>[];
    final droppedSubjectFacts = <_DoubaoGroundedFact>[];
    final droppedBloatedProfileFacts = <_DoubaoGroundedFact>[];
    final chronologyScope = items
        .map((item) =>
            item.url.trim().isNotEmpty ? item.url.trim() : item.title.trim())
        .where((value) => value.isNotEmpty)
        .join('|');
    for (final fact in extraction.facts) {
      final sourcedFact = _attachFallbackSourceIfUnambiguous(fact, items);
      var sanitizedFact = _sanitizeExtractedFactForQuestion(
        sourcedFact,
        userText: userText,
      );
      sanitizedFact = sanitizedFact.copyWith(
        eventOrder: sanitizedFact.eventOrder > 0 &&
                sanitizedFact.eventOrderEvidence.trim().isNotEmpty
            ? sanitizedFact.eventOrder
            : 0,
        chronologyScope: sanitizedFact.eventOrder > 0 &&
                sanitizedFact.eventOrderEvidence.trim().isNotEmpty
            ? chronologyScope
            : '',
      );
      sanitizedFact = _reattachEvidenceExcerptIfPossible(
        sanitizedFact,
        items,
      );
      if (sanitizedFact.answerBasis == _answerBasisExplicitFact &&
          sanitizedFact.directAnswerExcerpt.isNotEmpty) {
        final sourceText = _sourceTextForFact(sanitizedFact, items);
        if (sourceText.isEmpty ||
            !_containsLooseText(
              sourceText,
              sanitizedFact.directAnswerExcerpt,
            )) {
          sanitizedFact = sanitizedFact.copyWith(
            answerBasis: _answerBasisBoundedCandidates,
            directAnswerExcerpt: '',
          );
        }
      }
      if (!_sourceExcerptIsSupported(
        sanitizedFact,
        items,
        requireExcerpt: requireEvidence,
      )) {
        droppedEvidenceFacts.add(sourcedFact);
      } else if (_shouldFilterProductionMetaFact(
        sanitizedFact,
        category: category,
        userText: userText,
      )) {
        droppedBloatedProfileFacts.add(sourcedFact);
      } else if (_queryAsksProfileTraits(userText) &&
          _isBloatedProfileBoxFact(sanitizedFact)) {
        droppedBloatedProfileFacts.add(sourcedFact);
      } else if (_queryAsksProfileTraits(userText) &&
          extraction.answerBasis != _answerBasisExplicitFact &&
          !_preferenceFactMatchesSourceSubject(sanitizedFact)) {
        droppedSubjectFacts.add(sourcedFact);
      } else {
        validatedFacts.add(sanitizedFact);
      }
    }

    if (droppedEvidenceFacts.isNotEmpty) {
      debugPrint(
        '豆包事实后校验丢弃证据片段不可定位的事实: '
        '${_formatDoubaoFactsCompactForLog(droppedEvidenceFacts)}',
      );
    }
    if (droppedSubjectFacts.isNotEmpty) {
      debugPrint(
        '豆包事实后校验丢弃喜好主体不匹配的事实: '
        '${_formatDoubaoFactsCompactForLog(droppedSubjectFacts)}',
      );
    }
    if (droppedBloatedProfileFacts.isNotEmpty) {
      debugPrint(
        '豆包事实后校验丢弃资料框大杂烩/制作信息事实: '
        '${_formatDoubaoFactsCompactForLog(droppedBloatedProfileFacts)}',
      );
    }
    if (!preferEvidenceText &&
        droppedEvidenceFacts.isEmpty &&
        droppedSubjectFacts.isEmpty &&
        droppedBloatedProfileFacts.isEmpty) {
      return extraction;
    }

    final finalFacts = [
      ...validatedFacts,
    ].take(factLimit).toList(growable: false);

    return _DoubaoFactExtraction(
      status: finalFacts.isEmpty
          ? 'insufficient'
          : answerMode == _answerModeBoundedRoleplay
              ? extraction.status
              : 'partial',
      facts: finalFacts,
      discardReason: extraction.discardReason,
      provider: extraction.provider,
      answerBasis: _answerBasisForFacts(
        finalFacts,
        fallback: extraction.answerBasis,
      ),
    );
  }

  static String _sourceTitleSubject(String sourceTitle) {
    var title = sourceTitle
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[_|｜].*$'), '')
        .trim();
    if (title.contains(' - ')) {
      title = title.split(' - ').first.trim();
    } else if (title.contains('-')) {
      title = title.split('-').first.trim();
    }
    title = title
        .replaceAll(RegExp(r'（[^）]*）'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .trim();
    if (title.runes.length > 24) return '';
    return title;
  }

  static bool _queryAsksMusicInfo(String userText) {
    return RegExp(
      r'歌|歌曲|曲|乐队|樂隊|バンド|音楽|music|song|mujica|mygo',
      caseSensitive: false,
    ).hasMatch(userText);
  }

  static _DoubaoFactExtraction _fallbackMusicFactsFromSearchResults(
    List<_DoubaoSearchItem> items, {
    required String provider,
    required int factLimit,
  }) {
    final facts = <_DoubaoGroundedFact>[];
    void addFact(_DoubaoSearchItem item, String text, String excerpt) {
      final cleanedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final cleanedExcerpt = excerpt.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanedText.length < 2 || cleanedExcerpt.length < 2) return;
      if (_looksLikeProductionMetaFact(cleanedText)) return;
      if (facts.any((fact) => fact.text == cleanedText)) return;
      facts.add(_DoubaoGroundedFact(
        text: cleanedText,
        sourceTitle: item.title,
        sourceUrl: item.url,
        sourceExcerpt: cleanedExcerpt,
      ));
    }

    for (final item in items.take(_doubaoFactMaxResults)) {
      final source = item.bestText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (source.isEmpty) continue;
      final title = item.title
          .replaceAll(RegExp(r'\s*[-－—|｜].*$'), '')
          .replaceAll(RegExp(r'_百度百科$'), '')
          .trim();

      final knownTitles = _extractKnownMusicTitles(source);
      if (knownTitles.isNotEmpty) {
        final excerpt = knownTitles.map((match) => match.sourceText).join(' ');
        final factText = '资料页面列出的曲目候选：'
            '${knownTitles.map((match) => match.chineseTitle).join('、')}';
        addFact(item, factText, excerpt);
      }

      final introMatch = RegExp(
        r'([^。！？.!?]{0,80}(?:歌曲|乐队|樂隊|演唱|曲名|成员|Members|debuted with the song|热门歌曲)[^。！？.!?]{0,160})',
        caseSensitive: false,
      ).firstMatch(source);
      if (introMatch != null) {
        final excerpt = introMatch.group(0) ?? '';
        final factText = title.isNotEmpty
            ? '资料页面提到的相关音乐信息：$title；${_shortenRunes(excerpt, 120)}'
            : '资料页面提到的相关音乐信息：${_shortenRunes(excerpt, 140)}';
        addFact(item, factText, excerpt);
      }

      final songListMatch = RegExp(
        r'(?:热门歌曲|曲目|音轨|Tracklist|Songs?)[：: ]([^。！？.!?]{2,180})',
        caseSensitive: false,
      ).firstMatch(source);
      if (songListMatch != null) {
        final excerpt = songListMatch.group(0) ?? '';
        addFact(
          item,
          '资料页面列出的曲目候选：${_shortenRunes(songListMatch.group(1) ?? excerpt, 120)}',
          excerpt,
        );
      }

      if (facts.length >= factLimit) break;
    }

    return _DoubaoFactExtraction(
      status: facts.isEmpty ? 'insufficient' : 'partial',
      facts: facts.take(factLimit).toList(growable: false),
      discardReason: facts.isEmpty ? '未能从搜索结果中提取曲目信息' : '',
      provider: provider,
    );
  }

  static List<_MusicTitleMatch> _extractKnownMusicTitles(String text) {
    if (text.trim().isEmpty) return const [];
    final matches = <_MusicTitleMatch>[];

    for (final entry in termNamePronunciations) {
      final variants = <String>{
        entry.chinese,
        entry.japanese,
        entry.compactJapanese,
        entry.reading,
        ...entry.aliases.keys,
      }.where((value) => value.trim().isNotEmpty).toList()
        ..sort((a, b) => b.length.compareTo(a.length));

      for (final variant in variants) {
        var start = 0;
        while (true) {
          final index = text.indexOf(variant, start);
          if (index < 0) break;
          matches.add(_MusicTitleMatch(
            chineseTitle: entry.chinese,
            sourceText: variant,
            index: index,
            length: variant.length,
          ));
          start = index + variant.length;
        }
      }
    }

    if (matches.isEmpty) return const [];
    matches.sort((a, b) {
      final indexCompare = a.index.compareTo(b.index);
      if (indexCompare != 0) return indexCompare;
      return b.length.compareTo(a.length);
    });

    final seen = <String>{};
    final ordered = <_MusicTitleMatch>[];
    for (final match in matches) {
      if (!seen.add(match.chineseTitle)) continue;
      ordered.add(match);
    }
    return ordered;
  }

  static _DoubaoGroundedFact _attachFallbackSourceIfUnambiguous(
    _DoubaoGroundedFact fact,
    List<_DoubaoSearchItem> items,
  ) {
    if (items.length != 1) return fact;
    if (fact.sourceTitle.trim().isNotEmpty ||
        fact.sourceUrl.trim().isNotEmpty) {
      return fact;
    }

    final item = items.single;
    return fact.copyWith(
      sourceTitle: item.title,
      sourceUrl: item.url,
    );
  }

  static bool _sourceExcerptIsSupported(
      _DoubaoGroundedFact fact, List<_DoubaoSearchItem> items,
      {required bool requireExcerpt}) {
    final excerpt = fact.sourceExcerpt.trim();
    if (excerpt.isEmpty) return !requireExcerpt;
    final sourceText = _sourceTextForFact(fact, items);
    if (sourceText.isEmpty) return false;
    if (_containsLooseText(sourceText, excerpt)) return true;
    if (_containsEllipsis(excerpt) &&
        _containsLooseText(sourceText, fact.text)) {
      return true;
    }
    return false;
  }

  static bool _containsLooseText(String sourceText, String excerpt) {
    final source = _looseEvidenceKey(sourceText);
    if (_containsEllipsis(excerpt)) {
      final parts = excerpt
          .split(RegExp(r'…+|\.{3,}|⋯+'))
          .map(_looseEvidenceKey)
          .where((part) => part.runes.length >= 12)
          .toList();
      if (parts.isNotEmpty) {
        final matched = parts.where(source.contains).length;
        final requiredMatches = parts.length >= 2 ? 2 : 1;
        if (matched >= requiredMatches) return true;
      }
    }

    final target = _looseEvidenceKey(excerpt);
    if (target.isEmpty) return true;
    if (source.contains(target)) return true;

    final targetRunes = target.runes.toList();
    if (targetRunes.length <= 30) return false;
    final head = String.fromCharCodes(targetRunes.take(30)).replaceAll(' ', '');
    return head.length >= 12 && source.contains(head);
  }

  static bool _containsEllipsis(String text) {
    return RegExp(r'…|\.{3,}|⋯').hasMatch(text);
  }

  static String _looseEvidenceKey(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[「」『』“”"（）()【】\[\]、，。．,.;；:：!！?？…·･・]'), '')
        .trim();
  }

  static _DoubaoGroundedFact _sanitizeExtractedFactForQuestion(
    _DoubaoGroundedFact fact, {
    required String userText,
  }) {
    final asksHabitPlace =
        RegExp(r'闲暇|空闲|休息日|休日|常去|经常去|地方|地点|场所|場所').hasMatch(userText);
    if (!asksHabitPlace) return fact;

    final text = fact.text.trim();
    final isPreferenceFact = RegExp(r'喜欢|喜好|爱好|興味|好き').hasMatch(text);
    final carriesIncidentalPlace = RegExp(
            r'第\s*[0-9一二三四五六七八九十]+|动画|剧情|曾经|曾|到.+(?:馆|館|院|校|店|屋|室|场|場|所)|去.+(?:馆|館|院|校|店|屋|室|场|場|所)')
        .hasMatch(text);
    if (!isPreferenceFact || !carriesIncidentalPlace) return fact;

    final clauses = text
        .split(RegExp(r'[，,；;。]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    String? firstPreferenceClause;
    for (final clause in clauses) {
      if (RegExp(r'喜欢|喜好|爱好|好き').hasMatch(clause)) {
        firstPreferenceClause = clause;
        break;
      }
    }
    if (firstPreferenceClause == null || firstPreferenceClause.length < 2) {
      return fact;
    }

    return fact.copyWith(text: firstPreferenceClause);
  }

  static String _sourceTextForFact(
    _DoubaoGroundedFact fact,
    List<_DoubaoSearchItem> items,
  ) {
    for (final item in items) {
      final titleMatches = fact.sourceTitle.isNotEmpty &&
          item.title.isNotEmpty &&
          (fact.sourceTitle.contains(item.title) ||
              item.title.contains(fact.sourceTitle));
      final urlMatches = fact.sourceUrl.isNotEmpty &&
          item.url.isNotEmpty &&
          fact.sourceUrl == item.url;
      if (titleMatches || urlMatches) return _allSearchResultTextForFact(item);
    }
    return items.map(_allSearchResultTextForFact).join(' ');
  }

  static String _allSearchResultTextForFact(_DoubaoSearchItem item) {
    return [
      item.title,
      item.snippet,
      item.summary,
      item.content,
      item.publishTime,
      item.url,
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  static bool _isBloatedProfileBoxFact(_DoubaoGroundedFact fact) {
    final text = fact.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.runes.length < 80) return false;
    if (!RegExp(r'喜好|喜欢|喜歡|兴趣|愛好|爱好').hasMatch(text)) return false;
    final unrelatedProfileFields = RegExp(
      r'本名|日语|日語|登场角色|登場角色|亲属|親屬|相关人|相關人|所属|所屬|个人状态|個人狀態|'
      r'级别|級別|呼吸法|身高|体重|體重|年龄|年齡|生日|星座|发色|髮色|瞳色',
    ).allMatches(text).length;
    return unrelatedProfileFields >= 3;
  }

  static bool _preferenceFactMatchesSourceSubject(_DoubaoGroundedFact fact) {
    final text = fact.text.trim();
    if (!_hasPreferenceSignal(text)) return true;
    if (RegExp(r'兴趣|愛好|爱好|喜好(?:动物|動物|食物)|好きな(?:動物|食べ物)').hasMatch(text)) {
      return true;
    }

    final subject = _sourceTitleSubject(fact.sourceTitle);
    if (subject.isEmpty) return true;
    final compactText = text.replaceAll(RegExp(r'\s+'), '');
    final aliases = _sourceSubjectAliases(subject);
    return aliases.any((alias) => compactText.contains(alias));
  }

  static bool _shouldFilterProductionMetaFact(
    _DoubaoGroundedFact fact, {
    required String category,
    required String userText,
  }) {
    final text = fact.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return false;
    if (category != 'canon' && !_queryAsksMediaOrEntertainment(userText)) {
      return false;
    }
    if (_mediaSourceLooksNoisy(fact)) return true;

    // 书影音/番剧问题可以保留“这是哪部作品、主角/成员/题材”这类识别事实；
    // 但制作团队、职务、厂牌、发行商品等现实制作流水账仍然不进入角色回答边界。
    final productionStaffOrBusiness = RegExp(
      r'导演|監督|编剧|脚本|系列构成|制作团队|制作组|制作委员会|制作人员|'
      r'由[^，。；;]{1,40}制作|动画制作|游戏制作|公司|出版社|唱片|厂牌|'
      r'声优|聲優|配音|演员|作词|作詞|作曲|编曲|編曲|'
      r'访谈|訪談|采访|活动|演唱会|特典|商品|周边|销量|榜单|排行|'
      r'PV|视觉图|片头影像|片尾影像|首播|连播|播出|上映|发售|发行|发布|公开|宣传|'
      r'\bwritten by\b|\blyricist\b|\bcomposer\b|\barranger\b|\bproducer\b|'
      r'\blabel\b|\bcredits?\b|\bpersonnel\b|\bcharts?\b',
      caseSensitive: false,
    );
    if (productionStaffOrBusiness.hasMatch(text)) return true;

    if (category == 'canon' && _looksLikeProductionMetaFact(text)) {
      return true;
    }
    return false;
  }

  static _DoubaoGroundedFact _reattachEvidenceExcerptIfPossible(
    _DoubaoGroundedFact fact,
    List<_DoubaoSearchItem> items,
  ) {
    if (_sourceExcerptIsSupported(fact, items, requireExcerpt: true)) {
      return fact;
    }
    final fragment = _bestEvidenceFragmentForFact(fact, items);
    if (fragment == null) return fact;
    return fact.copyWith(
      sourceExcerpt: fragment,
      directAnswerExcerpt:
          fact.answerBasis == _answerBasisExplicitFact ? fragment : '',
    );
  }

  static String? _bestEvidenceFragmentForFact(
    _DoubaoGroundedFact fact,
    List<_DoubaoSearchItem> items,
  ) {
    final terms = _factEvidenceTerms(fact.text);
    if (terms.length < 2) return null;
    String? best;
    var bestScore = 0;
    for (final item in items.take(_doubaoFactMaxResults)) {
      final sourceText = _allSearchResultTextForFact(item)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (sourceText.isEmpty) continue;
      for (final fragment in _rawContentFragments(sourceText)) {
        final normalized = _looseEvidenceKey(fragment).toLowerCase();
        final score = terms.where((term) => normalized.contains(term)).length;
        if (score > bestScore) {
          bestScore = score;
          best = fragment.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }
    }
    return bestScore >= 2 ? best : null;
  }

  static List<String> _factEvidenceTerms(String text) {
    const stopWords = {
      '相关',
      '内容',
      '信息',
      '旗下',
      '主角',
      '动画',
      '番剧',
      '作品',
      '企划',
      '少女',
      '乐团',
      '电视',
    };
    final terms = <String>[];
    for (final match in RegExp(r'[A-Za-z0-9!☆★∞_+-]{2,}|[\u4e00-\u9fff]{2,}')
        .allMatches(text)) {
      final raw = (match.group(0) ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = _looseEvidenceKey(raw).toLowerCase();
      if (normalized.length < 2 || stopWords.contains(normalized)) continue;
      terms.add(normalized);
    }
    return terms.toSet().toList(growable: false);
  }

  static bool _mediaSourceLooksNoisy(_DoubaoGroundedFact fact) {
    final source = '${fact.sourceTitle} ${fact.sourceUrl}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return RegExp(
      r'bilibili\.com|acfun\.cn|douyin\.com|youtube\.com|youtu\.be|'
      r'wenku\.|csdn\.net|/video/|视频|剪辑|吐槽|杂谈|补番推荐|点个关注|入驻',
      caseSensitive: false,
    ).hasMatch(source);
  }

  static bool _queryAsksMediaOrEntertainment(String userText) {
    return RegExp(
      r'书影音|番剧|新番|老番|动画|漫画|电影|电视剧|剧集|剧版|歌曲|曲子|音乐|乐队|作品|角色|剧情|设定|追番|补番|'
      r'(?:看|追|补|刷)[^，。！？,.!?]{0,12}番',
      caseSensitive: false,
    ).hasMatch(userText);
  }

  static bool _hasPreferenceSignal(String text) {
    return RegExp(
      r'喜好|喜欢|喜歡|愛好|爱好|興味|好き|不喜欢|不喜歡|讨厌|討厭|厌恶|厭惡|苦手|不擅长|不擅長',
    ).hasMatch(text);
  }

  static bool _hasNegativePreferenceSignal(String text) {
    return RegExp(
      r'不喜欢|不喜歡|讨厌|討厭|厌恶|厭惡|苦手|不擅长|不擅長',
    ).hasMatch(text);
  }

  static Set<String> _sourceSubjectAliases(String subject) {
    final compact = subject.replaceAll(RegExp(r'\s+'), '');
    final aliases = <String>{};
    if (compact.isEmpty) return aliases;
    aliases.add(compact);
    if (RegExp(r'^[\u4e00-\u9fff]{3,5}$').hasMatch(compact)) {
      aliases.add(compact.substring(compact.length - 1));
    }
    return aliases.where((alias) => alias.isNotEmpty).toSet();
  }

  static _DoubaoFactExtraction _parseDoubaoFactExtraction(
    String content, {
    required String category,
    required String provider,
    required int factLimit,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    final jsonText = _extractJsonObject(content);
    Object? strictParseError;
    if (jsonText != null) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map<String, dynamic>) {
          return _factExtractionFromDecodedJson(
            decoded,
            category: category,
            provider: provider,
            factLimit: factLimit,
            answerMode: answerMode,
            answerRequirements: answerRequirements,
          );
        }
      } catch (e) {
        strictParseError = e;
      }
    }

    final lenient = _parseDoubaoFactExtractionLenient(
      content,
      category: category,
      provider: provider,
      factLimit: factLimit,
      answerMode: answerMode,
      answerRequirements: answerRequirements,
    );
    if (strictParseError != null) {
      if (lenient.facts.isNotEmpty) {
        _logSearchVerbose(
          '豆包事实提取 JSON 不完整，已宽松恢复: '
          'facts=${lenient.facts.length}',
        );
      } else {
        _logSearch('豆包事实提取 JSON 解析失败且无法恢复: $strictParseError');
      }
    }
    return lenient;
  }

  static _DoubaoFactExtraction _factExtractionFromDecodedJson(
    Map<String, dynamic> decoded, {
    required String category,
    required String provider,
    required int factLimit,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    final facts = <_DoubaoGroundedFact>[];
    final rawFacts = decoded['facts'];
    if (rawFacts is List) {
      for (final rawFact in rawFacts) {
        if (rawFact is! Map) continue;
        var text = _normalizeExtractedFactText(
          _dynamicMapString(rawFact, 'text'),
        );
        text = _applyDoubaoGenderJudgementToFactText(text, rawFact);
        if (text.length < 2) continue;
        if (category == 'canon' && _looksLikeProductionMetaFact(text)) {
          continue;
        }
        final factBasis = _normalizeFactAnswerBasis(
          _dynamicMapString(rawFact, 'basis'),
        );
        final directAnswerExcerpt =
            _dynamicMapString(rawFact, 'direct_answer_excerpt');
        final rawEventOrder = rawFact['event_order'];
        final eventOrder = rawEventOrder is int
            ? rawEventOrder
            : int.tryParse('${rawEventOrder ?? ''}') ?? 0;
        final requirementIndexes = _jsonIntList(
          rawFact['requirement_indexes'],
          maxExclusive: answerRequirements.length,
        );
        final directEvidenceMatches = _directAnswerExcerptMatchesRequirements(
          directAnswerExcerpt,
          requirementIndexes: requirementIndexes,
          answerRequirements: answerRequirements,
        );
        facts.add(_DoubaoGroundedFact(
          text: text,
          sourceTitle: _dynamicMapString(rawFact, 'source_title'),
          sourceUrl: _dynamicMapString(rawFact, 'source_url'),
          sourceExcerpt: _dynamicMapString(rawFact, 'source_excerpt'),
          requirementIndexes: requirementIndexes,
          answerBasis: factBasis == _answerBasisExplicitFact &&
                  (directAnswerExcerpt.isEmpty || !directEvidenceMatches)
              ? _answerBasisBoundedCandidates
              : factBasis,
          isStrongEvidence:
              _dynamicMapString(rawFact, 'evidence_strength') == 'strong',
          directAnswerExcerpt: directAnswerExcerpt,
          eventOrder: eventOrder > 0 ? eventOrder : 0,
          eventOrderEvidence:
              _dynamicMapString(rawFact, 'event_order_evidence'),
        ));
      }
    }

    final status = _normalizeFactExtractionStatus(
      _dynamicMapString(decoded, 'status'),
      hasFacts: facts.isNotEmpty,
    );
    final reason = _dynamicMapString(decoded, 'discard_reason');
    final answerBasis = _normalizeAnswerBasis(
      _dynamicMapString(decoded, 'answer_basis'),
      answerMode: answerMode,
      hasFacts: facts.isNotEmpty,
    );
    return _DoubaoFactExtraction(
      status: status,
      facts: facts.take(factLimit).toList(),
      discardReason: reason,
      provider: provider,
      answerBasis: _answerBasisForFacts(
        facts,
        fallback: answerBasis,
      ),
    );
  }

  static bool _directAnswerExcerptMatchesRequirements(
    String directAnswerExcerpt, {
    required List<int> requirementIndexes,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    if (directAnswerExcerpt.trim().isEmpty) return false;
    if (answerRequirements.isEmpty) return true;
    if (requirementIndexes.isEmpty) return false;

    for (final index in requirementIndexes) {
      if (index < 0 || index >= answerRequirements.length) return false;
      final cues = answerRequirements[index].directEvidenceCues;
      if (cues.isEmpty) continue;
      final hasMatchingCue = cues.any(
        (cue) => _containsLooseText(directAnswerExcerpt, cue),
      );
      if (!hasMatchingCue) return false;
    }
    return true;
  }

  static String _applyDoubaoGenderJudgementToFactText(
    String text,
    Map rawFact,
  ) {
    var result = text;
    final people = rawFact['people'];
    if (people is! List) return result;

    final judgedPeople = <({String name, String gender})>[];
    for (final rawPerson in people) {
      if (rawPerson is! Map) continue;
      final name = _dynamicMapString(rawPerson, 'name').trim();
      final gender = _normalizeGenderMarker(
        _dynamicMapString(rawPerson, 'gender'),
      );
      if (name.isEmpty || gender == null) continue;
      judgedPeople.add((
        name: ApiService.normalizeKnownNamesForChineseText(name),
        gender: gender
      ));
    }
    judgedPeople.sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final person in judgedPeople) {
      if (person.name.isEmpty) continue;
      final alreadyMarked = RegExp(
        '${RegExp.escape(person.name)}[（(][男女][）)]',
      ).hasMatch(result);
      if (alreadyMarked) continue;
      final pattern = RegExp('${RegExp.escape(person.name)}(?![（(][男女][）)])');
      result = result.replaceFirst(pattern, '${person.name}（${person.gender}）');
    }
    return result;
  }

  static String? _normalizeGenderMarker(String rawGender) {
    final normalized = rawGender.trim();
    if (normalized == '女' ||
        normalized == '女性' ||
        normalized.toLowerCase() == 'female') {
      return '女';
    }
    if (normalized == '男' ||
        normalized == '男性' ||
        normalized.toLowerCase() == 'male') {
      return '男';
    }
    return null;
  }

  static _DoubaoFactExtraction _parseDoubaoFactExtractionLenient(
    String content, {
    required String category,
    required String provider,
    required int factLimit,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    final facts = <_DoubaoGroundedFact>[];
    String pendingText = '';
    String pendingTitle = '';
    String pendingUrl = '';
    String pendingExcerpt = '';
    var rawAnswerBasis = '';

    void flush() {
      final text = _normalizeExtractedFactText(pendingText.trim());
      if (text.length >= 2 &&
          !_looksLikeIncompleteExtractedFact(text) &&
          !(category == 'canon' && _looksLikeProductionMetaFact(text))) {
        facts.add(_DoubaoGroundedFact(
          text: text,
          sourceTitle: pendingTitle.trim(),
          sourceUrl: pendingUrl.trim(),
          sourceExcerpt: pendingExcerpt.trim(),
          requirementIndexes: answerRequirements.isEmpty ? const [] : const [0],
          answerBasis: answerMode == _answerModeAdaptive
              ? _answerBasisBoundedCandidates
              : _answerBasisInsufficient,
        ));
      }
      pendingText = '';
      pendingTitle = '';
      pendingUrl = '';
      pendingExcerpt = '';
    }

    String readJsonishLineValue(String line) {
      final colon = line.indexOf(':');
      if (colon < 0) return '';
      var value = line.substring(colon + 1).trim();
      if (value.endsWith(',')) value = value.substring(0, value.length - 1);
      value = value.trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      return value
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (RegExp(r'"text"\s*:').hasMatch(line)) {
        if (pendingText.isNotEmpty) flush();
        pendingText = readJsonishLineValue(line);
      } else if (RegExp(r'"source_title"\s*:').hasMatch(line)) {
        pendingTitle = readJsonishLineValue(line);
      } else if (RegExp(r'"source_url"\s*:').hasMatch(line)) {
        pendingUrl = readJsonishLineValue(line);
      } else if (RegExp(r'"source_excerpt"\s*:').hasMatch(line)) {
        pendingExcerpt = readJsonishLineValue(line);
      } else if (RegExp(r'"answer_basis"\s*:').hasMatch(line)) {
        rawAnswerBasis = readJsonishLineValue(line);
      }
    }
    if (pendingText.isNotEmpty) flush();

    if (facts.isNotEmpty) {
      return _DoubaoFactExtraction(
        status: 'ok',
        facts: facts.take(factLimit).toList(),
        discardReason: '',
        provider: '$provider/宽松解析',
        answerBasis: _normalizeAnswerBasis(
          rawAnswerBasis,
          answerMode: answerMode,
          hasFacts: true,
        ),
      );
    }

    return _DoubaoFactExtraction(
      status:
          content.contains('insufficient') ? 'insufficient' : 'parse_failed',
      facts: const [],
      discardReason: '事实抽取返回内容无法解析',
      provider: provider,
      answerBasis: _answerBasisInsufficient,
    );
  }

  static String _normalizeAnswerBasis(
    String rawBasis, {
    required String answerMode,
    required bool hasFacts,
  }) {
    if (!hasFacts) return _answerBasisInsufficient;
    switch (rawBasis.trim()) {
      case _answerBasisExplicitFact:
        return _answerBasisExplicitFact;
      case _answerBasisBoundedCandidates:
        return answerMode == _answerModeBoundedRoleplay ||
                answerMode == _answerModeAdaptive
            ? _answerBasisBoundedCandidates
            : _answerBasisInsufficient;
      case _answerBasisMixed:
        return answerMode == _answerModeAdaptive
            ? _answerBasisMixed
            : _answerBasisExplicitFact;
      default:
        return answerMode == _answerModeBoundedRoleplay ||
                answerMode == _answerModeAdaptive
            ? _answerBasisBoundedCandidates
            : _answerBasisExplicitFact;
    }
  }

  static String _normalizeFactAnswerBasis(String rawBasis) {
    return rawBasis.trim() == _answerBasisExplicitFact
        ? _answerBasisExplicitFact
        : rawBasis.trim() == _answerBasisBoundedCandidates
            ? _answerBasisBoundedCandidates
            : _answerBasisInsufficient;
  }

  static String _normalizeFactExtractionStatus(
    String rawStatus, {
    required bool hasFacts,
  }) {
    switch (rawStatus.trim()) {
      case 'ok':
      case 'partial':
        return hasFacts ? rawStatus.trim() : 'insufficient';
      case 'insufficient':
        return hasFacts ? 'partial' : 'insufficient';
      default:
        return hasFacts ? 'partial' : 'insufficient';
    }
  }

  static String _mergeAnswerBasis(String current, String incoming) {
    if (current == _answerBasisMixed || incoming == _answerBasisMixed) {
      return _answerBasisMixed;
    }
    if ((current == _answerBasisExplicitFact &&
            incoming == _answerBasisBoundedCandidates) ||
        (current == _answerBasisBoundedCandidates &&
            incoming == _answerBasisExplicitFact)) {
      return _answerBasisMixed;
    }
    if (current == _answerBasisExplicitFact ||
        incoming == _answerBasisExplicitFact) {
      return _answerBasisExplicitFact;
    }
    if (current == _answerBasisBoundedCandidates ||
        incoming == _answerBasisBoundedCandidates) {
      return _answerBasisBoundedCandidates;
    }
    return _answerBasisInsufficient;
  }

  static String _answerBasisForFacts(
    List<_DoubaoGroundedFact> facts, {
    String fallback = _answerBasisInsufficient,
  }) {
    var hasExplicit = false;
    var hasBounded = false;
    for (final fact in facts) {
      hasExplicit = hasExplicit || fact.answerBasis == _answerBasisExplicitFact;
      hasBounded =
          hasBounded || fact.answerBasis == _answerBasisBoundedCandidates;
    }
    if (hasExplicit && hasBounded) return _answerBasisMixed;
    if (hasExplicit) return _answerBasisExplicitFact;
    if (hasBounded) return _answerBasisBoundedCandidates;
    return facts.isEmpty ? _answerBasisInsufficient : fallback;
  }

  static String _normalizeExtractedFactText(String text) {
    var result = ApiService.normalizeKnownNamesForChineseText(text);
    result = _stripInlineNameReadings(result);
    result = result.replaceAllMapped(
      RegExp(r'用完[^，。；、]{1,50}后(中毒休克|中毒|受伤|昏迷|死亡)的([^，。；、]{1,16})'),
      (match) => '${match.group(2)}${match.group(1)}后',
    );
    result = result.replaceAllMapped(
      RegExp(r'([^，。；、]{1,16})用完[^，。；、]{1,50}后(中毒休克|中毒|受伤|昏迷|死亡)'),
      (match) => '${match.group(1)}${match.group(2)}',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  static String _stripInlineNameReadings(String text) {
    return text.replaceAllMapped(
      RegExp(
        r'([一-龥ぁ-ゖァ-ヺA-Za-z0-9・·ー々ヶヵ]{1,16})[（(]([一-龥ぁ-ゖァ-ヺA-Za-z0-9・·ー々ヶヵ]{1,8})[）)]',
      ),
      (match) {
        final name = match.group(1) ?? '';
        final note = match.group(2) ?? '';
        if (note == '男' || note == '女') return match.group(0) ?? '';
        if (name.endsWith(note)) return name;
        return match.group(0) ?? '';
      },
    );
  }

  static bool _looksLikeIncompleteExtractedFact(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^["“”‘’]+|["“”‘’]+$').hasMatch(trimmed)) return true;
    if (RegExp(r'[，、；：,;:]$').hasMatch(trimmed)) return true;
    return trimmed.length < 8 && !RegExp(r'[。！？!?]$').hasMatch(trimmed);
  }

  static int _factExtractionMaxTokens(int factLimit) {
    return 1200 + factLimit * 320;
  }

  static Future<_FactExtractorChatResult?> _callFactExtractorChatCompletions(
    List<Map<String, String>> messages, {
    int? maxTokens,
  }) async {
    final runState = _activeRunState;
    if (runState?.factExtractorUnavailable == true) return null;

    final arkApiKey = _doubaoTextApiKey;
    final arkEndpoint = _doubaoTextEndpoint;

    if (arkApiKey.isEmpty || arkEndpoint.isEmpty) {
      if (runState != null) runState.factExtractorUnavailable = true;
      _logSearch('豆包/火山方舟事实抽取未配置，本轮停止事实抽取，不切换其他模型');
      return null;
    }

    final response = await _postChatCompletions(
      baseUrl: _arkChatBaseUrl,
      apiKey: arkApiKey,
      model: arkEndpoint,
      messages: messages,
      providerName: '豆包/火山方舟事实抽取',
      includeThinkingField: false,
      maxTokens: maxTokens ?? 1200,
    );
    if (response != null) return response;

    if (runState != null) runState.factExtractorUnavailable = true;
    _logSearch('豆包/火山方舟事实抽取不可用，本轮停止事实抽取，不切换其他模型');
    return null;
  }

  static Future<_FactExtractorChatResult?> _postChatCompletions({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required String providerName,
    required bool includeThinkingField,
    int maxTokens = 1200,
  }) async {
    Future<http.Response> send({required bool jsonObjectMode}) {
      final body = <String, dynamic>{
        'model': model,
        if (includeThinkingField) 'thinking': {'type': 'disabled'},
        'messages': messages,
        if (jsonObjectMode) 'response_format': {'type': 'json_object'},
        'max_tokens': maxTokens,
        'temperature': 0,
        'stream': false,
      };

      final operation = providerName.contains('搜索计划')
          ? 'planner'
          : providerName.contains('时间线')
              ? 'timeline'
              : providerName.contains('事实抽取') || providerName.contains('事实提取')
                  ? 'facts'
                  : 'other';
      _activeTrace?.recordRemoteCall(
        kind: 'model',
        provider: providerName,
        operation: operation,
        requestLabel: model,
      );

      return http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_factExtractionTimeout);
    }

    try {
      var response = await send(jsonObjectMode: true);
      if (response.statusCode != 200 &&
          response.body.contains('response_format')) {
        debugPrint('$providerName 不支持 response_format，改用普通 JSON 提示重试');
        response = await send(jsonObjectMode: false);
      }

      if (response.statusCode != 200) {
        debugPrint('$providerName 失败: ${response.statusCode} ${response.body}');
        return null;
      }

      _logSearchVerbose('$providerName 成功: model=$model');
      return _FactExtractorChatResult(
        response: response,
        provider: providerName,
      );
    } catch (e) {
      debugPrint('$providerName 异常: $e');
      return null;
    }
  }

  static String _doubaoFactExtractorPrompt(
    _WebProfile profile,
    String category, {
    required int factLimit,
    required int minimumFactTarget,
    required int minimumSourceTarget,
    required String answerMode,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    final nameGlossary = ApiService.nameTranslationGlossaryForPrompt()
        .map((entry) => '- $entry')
        .join('\n');
    final canonRule = category == 'canon'
        ? '''
这是作品内事实检索。只保留作品世界内的事实：人物身份、关系、经历、剧情、地点、组织、学校、乐队、喜好、招式等。
丢弃所有三次元现实制作信息：导演、编剧、制作团队、企划、公司、声优、访谈、活动、演唱会、上映播出、现实发售、厂牌、特典、榜单、商业运营、网页 UI、导航、目录、注释、参考文献、编辑提示。
如果一条资料是在作品本体、官方角色资料或作品内补充栏目中呈现角色设定、喜恶、经历、关系或台词，即使原文带有出处说明，也仍然按作品内事实处理；不要把这种设定误判成三次元制作信息。
英文页面里的 opening theme、ending theme、released、label、limited edition、Blu-ray、lottery、ticket、live、chart、credits 等也属于三次元现实制作/发行信息；用户没有明确问现实发行或动画制作时不要抽取。
用户询问歌曲、乐队或曲目感想时，歌曲名、所属乐队、乐队成员、作品内曲目列表、歌词主题或氛围的简短概括属于可用事实；但不要长篇摘录歌词，不要抽取现实发售、动画 OP/ED 用途、厂牌、特典、榜单或现实演出信息。
只要搜索结果里有能回答用户问题某个关键部分的作品内事实，就必须输出 facts；不要因为资料来自百科、解说站、资讯站或不是官方站而直接判 insufficient。
当用户问“为什么、如何、经过、关系、有没有听说、怎么看某件事”时，可以从多个候选中抽取事件起因、关键经过、结果、相关人物和时间地点；不要求单条候选完整回答整个问题。
只有所有候选都与用户问题无关，或只剩三次元制作信息/UI 噪声时，才输出 status="insufficient"。
'''
        : '';
    final mediaRule = category != 'canon'
        ? '''
如果用户问书影音、番剧、动画、漫画、电影、电视剧、歌曲、乐队或作品感想：
- 可以抽取作品/条目本身的识别事实，例如正式标题、它属于哪类作品、围绕哪个对象、主要角色/成员、题材或用户理解该话题所需的简短背景。
- 不要抽取制作人员、制作公司、导演/监督、编剧/系列构成、声优、发行厂牌、特典、活动、榜单、商业运营等现实制作流水账，除非用户明确问这些现实制作信息。
- 如果同一句原文同时包含“作品是什么”和“制作/播出/发行信息”，优先截取能支持作品识别的最小连续片段；不要把制作人员表一起塞进 source_excerpt。
'''
        : '';
    final requirementCount = answerRequirements.length;
    const answerModeRule = '''
【检索后判级】
搜索计划没有预判任何问项能否自由发挥。你必须先完整阅读本次输入，再逐条判断：
- explicit_fact：source_excerpt 能直接支持问项中的完整命题，包括主体、对象、关系和所有限定条件，而不只是证明某个对象或动作存在。
- bounded_candidates：原文没有直接下结论，但提供了真实候选、长期行为、使用记录、特征或效果，足以限定角色自然回答的范围。
- insufficient：既没有直接答案，也没有足够限定范围的相关事实。
明确事实永远优先；不得因为候选更容易找到而跳过正文中的直接设定。
''';
    return '''
你是搜索结果事实提取器，不是聊天角色。
只能使用给定搜索结果，不得补充模型记忆。
$canonRule
$mediaRule
$answerModeRule
本轮共有 $requirementCount 个独立问项。每条 fact 必须通过 requirement_indexes 标明它支持哪些问项。
当前角色联网范围：
${profile.contextRule}

【专名翻译表】
如果搜索结果中出现下列日文名、假名名或别名，facts 里必须使用右侧中文名；不要自行猜测汉字。
$nameGlossary

请只输出 JSON 对象，不要 markdown，不要解释。
格式：
{
  "status": "ok、partial 或 insufficient",
  "answer_basis": "explicit_fact、bounded_candidates 或 insufficient",
  "facts": [
    {
      "text": "直接回答用户问题的一条事实，中文，短句",
      "source_excerpt": "能直接支持 text 的连续原文片段，必须从搜索结果内容中摘取，不要改写，不要用省略号拼接不连续片段",
      "source_title": "来自哪条搜索结果的标题",
      "source_url": "来自哪条搜索结果的 URL",
      "requirement_indexes": [0],
      "basis": "explicit_fact 或 bounded_candidates",
      "direct_answer_excerpt": "仅 explicit_fact 填写：直接表达该问项完整答案的最小连续原文；bounded_candidates 必须为空",
      "evidence_strength": "strong 或 supporting",
      "event_order": 1,
      "event_order_evidence": "仅事件存在明确先后时填写：说明该 fact 在本批相关事件中的顺序依据；非事件事实填空字符串",
      "people": [
        {
          "name": "本条 fact 中出现的人物中文名",
          "gender": "男、女 或 unknown",
          "gender_evidence": "支持性别判断的原文依据；无法确定时为空"
        }
      ]
    }
  ],
  "discard_reason": "资料不足或丢弃原因；status=ok 时可为空"
}

要求：
1. facts 最多 $factLimit 条，每条必须和用户问题直接相关。
2. 不要摘录网页菜单、欢迎语、查论编、目录、注释、链接残片、广告、图片说明、编辑提示。
3. 不要把不相关角色的资料当成当前问题答案。
4. “你听说过/认识/知道/记得/怎么看”这类说法通常只是聊天框架，不等于用户在问说话角色和对象的关系；除非用户明确询问关系，否则优先抽取被问对象、事件或主题本身的事实。
5. 不要从论坛讨论、同人创作、整活改写、剪辑视频说明、商品页、观众评论、二创设定中抽取作品设定；这些来源只能在用户明确问同人、二创、商品或社区讨论时使用。
6. 如果候选中出现用户问题的核心对象，并给出了相关经历、关系、喜好、行动、结果或地点，即使信息不完整，也要抽取出来，不要返回 insufficient。
7. 如果只找到零散相关事实，但不足以回答用户问的经过、原因、如何、关系变化或评价依据，status 使用 "partial"；如果已经足以支撑回答，status 使用 "ok"。
7a. 用户问“觉得某首歌怎么样/喜欢某乐队哪些歌”时，不要要求资料直接出现角色主观评价。只要资料列出歌曲名、所属乐队、演唱者、BPM、歌词主题/氛围、曲目列表或代表曲目，就必须抽取为“可供角色评价的素材”或“可供角色选择的曲目候选”，status 至少为 "partial"。
7b. 对曲目候选，只能写“资料列出/页面提到的曲目包括……”，不能写成“角色最喜欢……”。最终角色偏好由聊天模型结合人设表达。
8. facts 必须是搜索结果中明确出现或能从同一条结果直接概括出的内容；不要补充搜索结果没有的信息。
8a. 每条 fact 都必须提供 source_excerpt。source_excerpt 必须是搜索结果中的连续原文片段，直接支持 text 里的动作主体、动作对象、时间顺序和因果关系；不要用“……”拼接不连续原文。如果找不到能直接支持的连续原文片段，就不要输出这条 fact。
8aa. source_excerpt 和 direct_answer_excerpt 也必须遵守三次元信息过滤。若作品内事实后面紧跟制作、企划、宣传、官方玩梗或现实活动等附加分句，只截取前面能支持 fact 的最小连续作品内原文，不要把后面的三次元分句一并带入证据。
8b. 改写 text 时不得调换主语和宾语，不得把 A 对 B 做的事改成 B 对 A 做的事，不得把“被动/接受帮助”的角色改成“主动帮助”的角色。关系和经历类事实如果容易误改，优先让 text 贴近 source_excerpt 的原句结构。
8c. 对剧情经过、任务、战斗、救援、支援、恢复、解决类问题，每条 fact 写一个清晰动作节点或事实点；如果原文一句话同时包含发现、救助、交给后续人员、击败敌人、救出他人等多个动作，可以拆成多条 facts。对时事、新闻、金融、行业趋势等普通现实问题，不要把同一句话或同一个紧密原因链拆成多个碎片 facts，应保留为自然的信息块。
8d. 对同一事件过程或关系变化中的 facts，必须先通读全部输入，再按真实剧情顺序填写从 1 开始递增的 event_order；相同阶段可以相同。不得按搜索结果顺序、来源分组或重要程度编号。原文无法判断先后的 fact 不得猜测，event_order 填 0 且 event_order_evidence 为空。
8e. event_order_evidence 只说明原文中的先后依据，例如明确时间词、前后动作衔接或同一叙事段落的位置；不得用模型外部记忆补顺序。
9. 不要为了凑满 facts 输出旁支趣闻；如果用户只是在问名称、身份、地点、喜好等单点事实，只输出能直接回答这个点的事实和必要补充。
9a. 如果用户一句话中包含多个彼此独立的问项，必须逐项检查整份正文并尽量为每个问项抽取事实；只有所有问项都已被直接事实覆盖时，严格事实模式的 status 才能为 "ok"。不能因为其中一个问项已有答案就忽略其余问项。
9b. 回答喜好、习惯、频率或常去地点时，正文若同时存在直接设定和单次剧情举例，必须优先抽取直接设定。单次去过某地、某一集出现某行为，只能写成“曾经去过/做过”，不得代替正文中的习惯结论，也不得据此把 status 提升为 "ok"。
10. facts 本身不得把“使用过/资料列出/具有某种效果”改写成网页没有明确支持的频率、偏好或强弱结论。没有直接结论时，fact 仍应保持客观写成“使用过/资料列出”，并令 basis="bounded_candidates"，主观表达留给最终聊天模型。
10d. 判定 explicit_fact 时执行“完整命题蕴含”检查：把用户问项改写成一个可判断真假的陈述，再确认 source_excerpt 是否直接支持整个陈述。若证据只证明角色使用过某招式、去过某地点、接触过某对象或表达过一次态度，却没有直接支持问项中的频率、偏好、通常行为、强弱或评价限定，就必须标为 bounded_candidates，不能标为 explicit_fact。
10e. explicit_fact 必须额外填写 direct_answer_excerpt：它是 source_excerpt 中能直接表达问项完整答案的最小连续原文，而不是整段背景。若原文没有这样的短语或句子，direct_answer_excerpt 必须为空，并将 basis 改为 bounded_candidates。程序会把缺少 direct_answer_excerpt 的 explicit_fact 自动降级。
10f. 每个独立问项后附有“直接证据关系”。这些词只描述问项中的关系或限定，不代表资料已经存在答案。只有 direct_answer_excerpt 本身明确表达相应关系时才能标为 explicit_fact；仅有对象、动作、候选或一次经历时仍标为 bounded_candidates。程序会在读取结果后再次核验这一点。
10a. 在输出 bounded_candidates 前必须先通读所有输入，寻找同一问项的明确设定；找到时改用 explicit_fact。响应顶层 answer_basis 按本轮事实整体填写：只有明确事实则为 explicit_fact，只有候选事实则为 bounded_candidates，两者都有时填写 mixed，没有可用事实时填写 insufficient。
10b. evidence_strength="strong" 表示这一条事实单独就足以把该问项的回答限定在可靠范围内；否则写 supporting。不要为了减少搜索而夸大证据强度。
10c. status 只概括本批输入：所有独立问项都至少有 explicit_fact，或已有足够的 bounded_candidates 时使用 "ok"；只覆盖部分问项时使用 "partial"。程序还会根据 requirement_indexes、basis、evidence_strength 和最低 facts 数独立复核停止条件。
11. 必须严格区分时间顺序和因果关系。原文只表达“之后、随后、当时、期间”时，不要改写成“因为、由于、导致”；涉及受伤、中毒、死亡、失败等结果时，原因必须来自搜索结果明确表述。
12. 用户询问“喜欢什么、常去哪里、闲暇去哪”等喜好/习惯时，原文或同一条结果正文只要明确出现“喜欢、喜好、爱好、兴趣、常去、经常去、闲暇、休日、放课后”等语义，就必须抽取；简介、经历、关系、轶事、余谈里的明确作品内资料都可以作为依据。卡面标题、别号、萌点、标签、图片说明、服装/周边名称、角色比喻不能改写成“喜欢”或“经常”。如果只看到这些弱线索，最多写“资料只出现相关标签/称呼，不能确认是喜好”。
13. 必须区分“一次剧情中去过某地点”和“闲暇常去某地点”。如果原文只说某集、某事件、某次去了水族馆、学校、Livehouse 等地点，不能抽成“闲暇时会去/经常去”；只能写“曾经去过”。只有原文明确写出兴趣、闲暇、空闲、休息日、经常、常去等习惯语义，才能作为常去地点事实。
14. 用户询问人物关系、相互影响、救赎、关系变化或一段经历时，不要只抽取开头设定；必须尽量覆盖早期接触、关键转折、冲突/逃避、后续追回或和解、结果这几个阶段中搜索结果明确写到的事实。若同一问题涉及两个人，应优先抽取两个人各自主动采取的行动。
15. 对关系、救赎、关系变化或经历问题，凡是描述关系从冲突、逃避或断裂走向重新连接的事实，并且同时带有具体地点或直接台词，优先级高于普通背景设定；只要原文里有，就必须尽量抽取。
16. 如果用户问题限定了某个时期、形成过程、组成阶段、当初、前后或期间，facts 必须优先围绕这个时间范围；明确属于更晚阶段、另一个篇章、另一次后续事件或回顾性补充的信息不要抽取，除非用户明确追问后续发展。
17. 用户询问“经过、如何、怎么发生、怎么恢复、怎么解决、怎么支援、战斗过程”等事件经过时，不要用人物性格、身份、外貌等背景资料凑数；优先抽取与问题动作直接相关的触发、关键行动、使用手段、结果和后续反应。
18. 如果同一条搜索结果围绕同一事件连续写到了起因、关键动作、胜负/成败结果、后续反应或情绪变化，必须尽量拆成多条 facts 覆盖完整链路，而不是只抽第一句。
19. 本轮最低有效事实目标是 $minimumFactTarget 条。${minimumSourceTarget > 1 ? '同时尽量覆盖至少 $minimumSourceTarget 个不同网页来源；优先从不同来源各抽取自然信息块，不要在同一来源里把连续一句或同一原因链拆成多个原子 facts。' : '同一来源中存在多个彼此独立的相关命题时，可以拆成多条 facts；如果只是同一句里的紧密补充关系，保留为一个自然信息块。'}只有原文确实不足时才能少于最低目标并返回 partial，不得用旁支信息凑数。
20. 对战斗、任务、救援、恢复、解决类经过，若原文写到了使用的招式/手段、击败/救助/成败结果、相关人物生还或情绪变化，这些都属于经过本身，必须优先抽取。
20b. 用户问“如何支援/救援/协助/处理”时，facts 必须围绕这个动作目标：出发/介入、发现对象、使用手段、交给后续人员、解决敌人、救出对象可以拆成独立 facts；不要用后续审判、与被支援一方的旁支冲突、结局补充来凑数量。
21. 每条 fact 的 people 字段必须列出 text 中出现的具体人物；不要列团体、学校、乐队、组织或地点。
22. people.gender 必须由搜索结果资料判断：可依据资料框性别、学校/身份说明、亲属称谓、角色介绍中的明确代词或同一页面对该角色的稳定描述。能判断就写“男”或“女”，不能判断就写 unknown；不要因为现实声优、演员、制作访谈或页面分类来判断。
23. 如果 people.gender 是“男”或“女”，text 中该人物第一次出现时也必须在姓名后标注“（男）”或“（女）”，例如“千早爱音（女）”。后续重复出现同一人物时可以不再标注。性别标注只用于后续翻译和指代判断，不属于角色台词内容。
''';
  }

  static int _doubaoFactLimitForUserText(String userText) {
    return 10;
  }

  static const int _complexCanonFactTarget = 6;
  static const int _ordinaryFactTarget = 3;
  static const int _currentAffairsFactTarget = 5;
  static const int _ordinarySourceTarget = 1;
  static const int _currentAffairsSourceTarget = 3;

  static int _minimumDoubaoFactTarget({
    required String category,
    required _WebProfile profile,
    required String userText,
    required bool needsBroadFactCoverage,
    required bool eventProcessSearch,
  }) {
    if (needsBroadFactCoverage || eventProcessSearch) {
      return _complexCanonFactTarget;
    }
    if (_needsCurrentAffairsFactCoverage(category, profile, userText)) {
      return _currentAffairsFactTarget;
    }
    return _ordinaryFactTarget;
  }

  static int _minimumDoubaoSourceTarget({
    required String category,
    required _WebProfile profile,
    required String userText,
  }) {
    if (_needsCurrentAffairsFactCoverage(category, profile, userText)) {
      return _currentAffairsSourceTarget;
    }
    return _ordinarySourceTarget;
  }

  static bool _needsCurrentAffairsFactCoverage(
    String category,
    _WebProfile profile,
    String userText,
  ) {
    if (category == 'economy' || category == 'current') return true;
    if (category != 'general') return false;
    if (!_requiresAuthoritativeDoubaoSearch(category, profile)) return false;
    if (_queryAsksMediaOrEntertainment(userText)) return false;
    return _textLooksLikeCurrentAffairsQuestion(userText);
  }

  static bool _textLooksLikeCurrentAffairsQuestion(String userText) {
    if (_queryAsksMediaOrEntertainment(userText)) return false;
    return RegExp(
      r'新闻|时事|热点|政策|金融|财经|经济|市场|行业|趋势|前景|展望|元年|'
      r'今年|当前|近期|最近|怎么看|如何看待',
    ).hasMatch(userText);
  }

  static bool _hasEnoughDoubaoFactsForSearchStop(
    List<_DoubaoGroundedFact> facts, {
    required int factLimit,
    required int minimumFactTarget,
    required int minimumSourceTarget,
    required String extractionStatus,
    required List<_AnswerRequirement> answerRequirements,
  }) {
    if (facts.isEmpty) return false;
    final usableFacts = _selectDoubaoFactsForOutput(facts, factLimit);
    if (usableFacts.length < minimumFactTarget) return false;
    if (_uniqueDoubaoFactSourceCount(usableFacts) < minimumSourceTarget) {
      return false;
    }

    if (answerRequirements.isEmpty) {
      return extractionStatus == 'ok';
    }

    return _factsCoverAnswerRequirements(usableFacts, answerRequirements);
  }

  static bool _factsCoverAnswerRequirements(
    List<_DoubaoGroundedFact> facts,
    List<_AnswerRequirement> answerRequirements,
  ) {
    if (answerRequirements.isEmpty) return false;
    for (var index = 0; index < answerRequirements.length; index++) {
      final supportingFacts = facts
          .where((fact) => fact.requirementIndexes.contains(index))
          .toList(growable: false);
      if (supportingFacts.isEmpty) return false;
      if (supportingFacts
          .any((fact) => fact.answerBasis == _answerBasisExplicitFact)) {
        continue;
      }

      final boundedFacts = supportingFacts
          .where((fact) => fact.answerBasis == _answerBasisBoundedCandidates)
          .toList(growable: false);
      if (boundedFacts.any((fact) => fact.isStrongEvidence) ||
          boundedFacts.length >= 2) {
        continue;
      }
      return false;
    }
    return true;
  }

  static bool _needsBroadCanonFactCoverage(String userText) {
    final text = userText.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return false;
    if (_queryAsksMusicInfo(text) &&
        !RegExp(r'关系|相互|救赎|影响|变化|经过|如何|为什么|有耳闻|听说').hasMatch(text)) {
      return false;
    }
    return RegExp(
      r'关系|相互|救赎|影响|变化|经历|感情|在意|和解|冲突|矛盾|'
      r'组成|组建|为什么|为何|原因|原委',
    ).hasMatch(text);
  }

  static bool _isEventProcessCanonQuestion(String userText) {
    final text = userText.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return false;
    if (_needsBroadCanonFactCoverage(text)) return false;
    if (_queryAsksMusicInfo(text)) return false;
    return RegExp(r'经过|过程|如何|怎么|怎样|支援|救援|恢复|解决|战斗|出任务|处理').hasMatch(text);
  }

  @visibleForTesting
  static bool isEventProcessCanonQuestionForTest(String userText) =>
      _isEventProcessCanonQuestion(userText);

  @visibleForTesting
  static bool isDoubaoSearchBudgetAvailableForTest(int completedCalls) =>
      completedCalls < _maxDoubaoSearchApiCallsPerTurn;

  @visibleForTesting
  static bool textLooksLikeCurrentAffairsQuestionForTest(String userText) =>
      _textLooksLikeCurrentAffairsQuestion(userText);

  @visibleForTesting
  static bool doubaoFactsMeetStopConditionForTest({
    required List<Map<String, String>> facts,
    required int factLimit,
    required int minimumFactTarget,
    required int minimumSourceTarget,
    String extractionStatus = 'ok',
  }) {
    return _hasEnoughDoubaoFactsForSearchStop(
      [
        for (final fact in facts)
          _DoubaoGroundedFact(
            text: fact['text'] ?? '',
            sourceTitle: fact['sourceTitle'] ?? '',
            sourceUrl: fact['sourceUrl'] ?? '',
            sourceExcerpt: fact['sourceExcerpt'] ?? '',
          ),
      ],
      factLimit: factLimit,
      minimumFactTarget: minimumFactTarget,
      minimumSourceTarget: minimumSourceTarget,
      extractionStatus: extractionStatus,
      answerRequirements: const [],
    );
  }

  @visibleForTesting
  static List<String> doubaoCanonAttemptQueriesForTest({
    required String userText,
    required String characterId,
    required String characterName,
    required List<String> searchTargets,
  }) {
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );
    return _doubaoSearchAttempts(
      searchTargets.first,
      originalQuery: searchTargets.join(' '),
      userText: userText,
      category: 'canon',
      profile: profile,
      searchTargets: searchTargets,
    )
        .map((attempt) => '${attempt.priority}:${attempt.query}')
        .toList(growable: false);
  }

  static String _formatDoubaoRawResultsForModel(
    List<_DoubaoSearchItem> items,
  ) {
    final parts = <String>[];
    for (final item in items.take(_doubaoFactMaxResults)) {
      final text = item.bestText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty && item.title.isEmpty) continue;
      final shortened = text.runes.length > _doubaoFactPerResultMaxChars
          ? String.fromCharCodes(text.runes.take(_doubaoFactPerResultMaxChars))
          : text;
      parts.add('''
标题：${item.title}
站点：${item.siteName}
URL：${item.url}
发布时间：${item.publishTime}
采用字段：${item.bestTextSource}
字段长度：content=${item.content.runes.length}, summary=${item.summary.runes.length}, snippet=${item.snippet.runes.length}
内容：$shortened
''');
    }
    return parts.join('\n---\n');
  }

  static String _doubaoSourcePriorityInstruction(
    _WebProfile profile,
    String category,
  ) {
    if (category == 'canon' && profile.preferMoegirlCanonSearch) {
      return '优先参考萌娘百科等 A 站内容；只有 A 站没有覆盖用户问题所需事实时，才参考百度百科、维基百科、官方站或同系列资料站等 B 站内容。';
    }
    if (_requiresAuthoritativeDoubaoSearch(category, profile)) {
      return '优先参考官方、权威媒体和主流财经/新闻来源；丢弃论坛、营销号和无来源观点。';
    }
    return '优先参考与用户问题直接相关、来源清晰、正文完整的结果。';
  }

  static String _formatDoubaoItemsForLog(List<_DoubaoSearchItem> items) {
    final lines = <String>[];
    var index = 0;
    for (final item in items.take(4)) {
      index += 1;
      lines.add(
        '$index. ${item.title} | ${item.url} | '
        'source=${item.bestTextSource}, '
        'len(content=${item.content.runes.length}, summary=${item.summary.runes.length}, snippet=${item.snippet.runes.length})',
      );
    }
    if (items.length > 4) lines.add('... 其余 ${items.length - 4} 条省略');
    return lines.join('\n');
  }

  static String _formatSitesBriefForLog(String? sites) {
    final values = sites
        ?.split('|')
        .map((site) => site.trim())
        .where((site) => site.isNotEmpty)
        .toList(growable: false);
    if (values == null || values.isEmpty) return '';
    if (values.length <= 2) return ' | sites=${values.join('|')}';
    return ' | sites=${values.length}域(${values.take(2).join('|')}...)';
  }

  static String _searchLayerName(int priority, String label) {
    final meaning = switch (priority) {
      0 => '最高优先级来源',
      1 => '补充来源',
      2 => '全网兜底',
      3 => '开放搜索',
      _ => '搜索层',
    };
    final source = switch (label) {
      'Custom主站点' => '萌娘百科/主站点',
      'Global主站点' => '萌娘百科/主站点',
      'Custom次级站点补充' => '百度百科/维基/官方/资料站',
      'Global全网兜底' => '开放全网',
      '开放全网' => '开放全网',
      '本地百度/维基补充' => '百度百科/维基直达解析',
      _ => label,
    };
    return 'P$priority $meaning - $source';
  }

  static String _formatSourceHostsForLog(List<_DoubaoSearchItem> items) {
    final hosts = <String>{};
    for (final item in items) {
      final host = Uri.tryParse(item.url)
          ?.host
          .replaceFirst(RegExp(r'^www\.'), '')
          .trim();
      if (host != null && host.isNotEmpty) hosts.add(host);
    }
    if (hosts.isEmpty) return '';
    final values = hosts.toList()..sort();
    if (values.length <= 3) return '，来源=${values.join('|')}';
    return '，来源=${values.take(3).join('|')}等${values.length}域';
  }

  static String _formatDoubaoFactsUsageForLog(
    List<_DoubaoGroundedFact> facts,
    int displayLimit,
  ) {
    final effectiveFacts = _dedupeDoubaoFacts(facts);
    final safeDisplayLimit = displayLimit < 0 ? 0 : displayLimit;
    final displayed = effectiveFacts.length < safeDisplayLimit
        ? effectiveFacts.length
        : safeDisplayLimit;
    final sourceCount = _uniqueDoubaoFactSourceCount(effectiveFacts);
    final sourceText = sourceCount > 0 ? '，来源页=$sourceCount' : '';
    final rawText =
        effectiveFacts.length == facts.length ? '' : '，原始=${facts.length}';
    if (effectiveFacts.length <= displayed) {
      return '有效事实=${effectiveFacts.length}$rawText$sourceText';
    }
    return '有效事实=${effectiveFacts.length}$rawText$sourceText，下方摘要展示最多=$displayed条/组';
  }

  static int _uniqueDoubaoFactSourceCount(List<_DoubaoGroundedFact> facts) {
    final sources = <String>{};
    for (final fact in facts) {
      final key = _doubaoFactSourceKey(fact);
      if (key.isNotEmpty) sources.add(key);
    }
    return sources.length;
  }

  static String _doubaoFactSourceKey(_DoubaoGroundedFact fact) {
    final url = fact.sourceUrl.trim().toLowerCase();
    if (url.isNotEmpty) return url;
    return fact.sourceTitle.trim().toLowerCase();
  }

  static String _formatRequirementCoverageForLog(
    List<_DoubaoGroundedFact> facts,
    List<_AnswerRequirement> requirements,
  ) {
    if (requirements.isEmpty) return '问项覆盖=未拆分';
    final states = <String>[];
    for (var index = 0; index < requirements.length; index++) {
      final related =
          facts.where((fact) => fact.requirementIndexes.contains(index));
      final explicit = related
          .where((fact) => fact.answerBasis == _answerBasisExplicitFact)
          .length;
      final bounded = related
          .where((fact) => fact.answerBasis == _answerBasisBoundedCandidates)
          .length;
      final strong = related.where((fact) => fact.isStrongEvidence).length;
      states.add('$index:明确$explicit/候选$bounded/强证据$strong');
    }
    return '问项覆盖=${states.join('；')}';
  }

  static String _formatDoubaoFactsCompactForLog(
    List<_DoubaoGroundedFact> facts,
  ) {
    final previews = <String>[];
    for (var i = 0; i < facts.length && i < 3; i++) {
      previews.add('${i + 1}. ${_shortenRunes(facts[i].text, 70)}');
    }
    final suffix = facts.length > 3 ? ' ...' : '';
    return 'facts=${facts.length}; ${previews.join(' / ')}$suffix';
  }

  static void _addUniqueDoubaoFacts(
      List<_DoubaoGroundedFact> target, List<_DoubaoGroundedFact> source,
      {required int maxFacts}) {
    final indexesByIdentity = <String, int>{};
    final indexesByTextAndSource = <String, int>{};
    for (var i = 0; i < target.length; i++) {
      final identityKey = _doubaoFactIdentityKey(target[i]);
      if (identityKey.isNotEmpty) indexesByIdentity[identityKey] = i;
      final textAndSourceKey = _doubaoFactTextAndSourceKey(target[i]);
      if (textAndSourceKey.isNotEmpty) {
        indexesByTextAndSource[textAndSourceKey] = i;
      }
    }
    for (final fact in source) {
      final identityKey = _doubaoFactIdentityKey(fact);
      final textAndSourceKey = _doubaoFactTextAndSourceKey(fact);
      if (identityKey.isEmpty && textAndSourceKey.isEmpty) continue;
      final existingIndex = indexesByIdentity[identityKey] ??
          indexesByTextAndSource[textAndSourceKey];
      if (existingIndex != null) {
        target[existingIndex] = _mergeDoubaoDuplicateFact(
          target[existingIndex],
          fact,
        );
        if (identityKey.isNotEmpty) {
          indexesByIdentity[identityKey] = existingIndex;
        }
        if (textAndSourceKey.isNotEmpty) {
          indexesByTextAndSource[textAndSourceKey] = existingIndex;
        }
        continue;
      }
      target.add(fact);
      if (identityKey.isNotEmpty) {
        indexesByIdentity[identityKey] = target.length - 1;
      }
      if (textAndSourceKey.isNotEmpty) {
        indexesByTextAndSource[textAndSourceKey] = target.length - 1;
      }
      if (target.length >= maxFacts) return;
    }
  }

  static List<_DoubaoGroundedFact> _dedupeDoubaoFacts(
    List<_DoubaoGroundedFact> facts,
  ) {
    final result = <_DoubaoGroundedFact>[];
    _addUniqueDoubaoFacts(result, facts, maxFacts: facts.length);
    return result;
  }

  static String _doubaoFactIdentityKey(_DoubaoGroundedFact fact) {
    final textKey = _normalizeForDedupe(fact.text);
    final evidence =
        fact.sourceExcerpt.trim().isNotEmpty ? fact.sourceExcerpt : fact.text;
    final evidenceKey = _normalizeForDedupe(evidence);
    if (textKey.isEmpty || evidenceKey.isEmpty) return '';
    final sourceKey = _normalizeForDedupe(_doubaoFactSourceKey(fact));
    return '$sourceKey::$textKey::$evidenceKey';
  }

  static String _doubaoFactTextAndSourceKey(_DoubaoGroundedFact fact) {
    final textKey = _normalizeForDedupe(fact.text);
    if (textKey.isEmpty) return '';
    final sourceKey = _normalizeForDedupe(_doubaoFactSourceKey(fact));
    return '$sourceKey::$textKey';
  }

  static _DoubaoGroundedFact _mergeDoubaoDuplicateFact(
    _DoubaoGroundedFact existing,
    _DoubaoGroundedFact duplicate,
  ) {
    final mergedIndexes = <int>{
      ...existing.requirementIndexes,
      ...duplicate.requirementIndexes,
    }.toList()
      ..sort();
    return existing.copyWith(
      requirementIndexes: mergedIndexes,
      answerBasis: existing.answerBasis == _answerBasisExplicitFact ||
              duplicate.answerBasis == _answerBasisExplicitFact
          ? _answerBasisExplicitFact
          : existing.answerBasis == _answerBasisBoundedCandidates ||
                  duplicate.answerBasis == _answerBasisBoundedCandidates
              ? _answerBasisBoundedCandidates
              : _answerBasisInsufficient,
      isStrongEvidence: existing.isStrongEvidence || duplicate.isStrongEvidence,
      eventOrder:
          existing.eventOrder > 0 ? existing.eventOrder : duplicate.eventOrder,
      eventOrderEvidence: existing.eventOrderEvidence.isNotEmpty
          ? existing.eventOrderEvidence
          : duplicate.eventOrderEvidence,
      chronologyScope: existing.chronologyScope.isNotEmpty
          ? existing.chronologyScope
          : duplicate.chronologyScope,
    );
  }

  static Future<List<String>> _formatDoubaoFactsWithTimeline(
    List<_DoubaoGroundedFact> facts, {
    required String originalQuery,
    required int maxFacts,
    required bool separateFacts,
    required bool includeTimeline,
    required String userText,
    required _WebProfile profile,
  }) async {
    final formatted = _formatDoubaoFacts(
      facts,
      originalQuery: originalQuery,
      maxFacts: maxFacts,
      separateFacts: separateFacts,
    );
    if (!includeTimeline || facts.length < 2) return formatted;

    final selectedFacts = _selectDoubaoFactsForOutput(facts, maxFacts);
    final timeline = await _buildDoubaoTimeline(
      userText: userText,
      profile: profile,
      facts: selectedFacts,
    );
    if (timeline == null || timeline.nodes.isEmpty) {
      debugPrint('豆包时间线未通过结构化校验，限制为单节点事实回答');
      return [
        ...formatted,
        '$_doubaoTimelineResultPrefix【回答约束】\n'
            '- 时间线没有通过本地引用校验；不得自行排列或串联多个事件，只能选择一项有原文证据的事实自然回应。',
      ];
    }

    final timelineText = timeline.toPromptText().trim();
    if (timelineText.isEmpty) return formatted;

    return [
      ...formatted,
      '$_doubaoTimelineResultPrefix${timelineText.trim()}',
    ];
  }

  static Future<_DoubaoTimeline?> _buildDoubaoTimeline({
    required String userText,
    required _WebProfile profile,
    required List<_DoubaoGroundedFact> facts,
  }) async {
    final arkApiKey = _doubaoTextApiKey;
    final arkEndpoint = _doubaoTextEndpoint;
    if (arkApiKey.isEmpty || arkEndpoint.isEmpty) {
      debugPrint('豆包时间线整理未配置 key，跳过');
      return null;
    }

    final relationshipQuestion = _needsBroadCanonFactCoverage(userText);
    final eventProcessQuestion = _isEventProcessCanonQuestion(userText);
    final timelineFocusInstruction = relationshipQuestion
        ? '用户问的是人物关系、相互影响、救赎或关系变化。timeline 要优先覆盖关系变化的关键转折，包括相识/邀请、冲突/逃避、鼓励/追回、回归/和解、结果；资料不足时不要硬补。'
        : eventProcessQuestion
            ? '用户问的是事件经过、处理方式或支援方式。timeline 只整理和用户问点直接相关的核心步骤，包括出发/介入、使用的手段、救助或处理对象、阶段性结果；不要把后续审判、旁支冲突或结局补充强行放进主线。'
            : 'timeline 只整理和用户问题直接相关的事实顺序，不要扩展到无关旁支。';

    final factLines = <String>[];
    for (var i = 0; i < facts.length; i++) {
      final excerpt = facts[i].sourceExcerpt.trim();
      final authoritativeText = excerpt.isNotEmpty ? excerpt : facts[i].text;
      final chronologyHint = facts[i].eventOrder > 0
          ? '\n   本批剧情顺序：${facts[i].eventOrder}'
              '（依据：${facts[i].eventOrderEvidence}）'
          : '';
      factLines.add(
        '${i + 1}. $authoritativeText'
        '$chronologyHint',
      );
    }

    final messages = [
      {
        'role': 'system',
        'content': '''
你是事实时间线整理器，不是聊天角色。
只能使用给定的网页原文证据，不能补充外部记忆。上游模型生成的事实概括没有提供给你，也不得自行猜测概括中可能存在的内容。
任务是帮后续角色回复模型避免把不连续事件直接拼接、避免调换主客体、避免省略关键地点或台词。
注意：原文证据的输入顺序是搜索/抽取顺序，不一定是剧情时间顺序；必须根据原文内部的时间词、因果词、地点和人物动作重新排列。
如果 fact 带有“本批剧情顺序”，同一批资料内必须严格按该编号从小到大排列；不得自行颠倒。不同批资料的编号不能直接互相比较，只能结合各自原文判断。
$timelineFocusInstruction
请输出 JSON 对象，不要 markdown，不要解释。
格式：
{
  "timeline": [
    {
      "text": "按真实先后顺序整理的一条事实，中文短句",
      "fact_indexes": ["直接支持该节点的 facts 编号"]
    }
  ],
  "constraints": ["给后续回复模型的约束，中文短句，最多3条"]
}
要求：
1. timeline 只保留 facts 明确支持的真实阶段，通常输出2到8条；没有足够时间节点时宁可少写，绝对不能为了达到数量补写 facts 中不存在的事件。
1a. 每个 timeline 节点必须填写 fact_indexes，至少引用一条直接支持该节点的 fact。text 必须是所引用 facts 的保守改写，不能添加被引用事实没有提到的人物、事件、原因、地点或结果。
2. 如果 facts 中两个事件之间缺少连续关系，要在 constraints 里明确提醒不能用“然后/于是”直接连接。
3. 如果同一事件中有多个地点或关键台词，timeline 必须保留承载结果的地点和台词。
4. facts 里靠后的关键结果、回归、和解、重新连接、救助完成或处理结果不能被省略；如果它带有地点或台词，必须单独成为一个 timeline 阶段。
5. 如果 facts 不能确定先后顺序，只能写“资料只确认……”而不要强排顺序。
6. 保留人物动作主体和对象，不要把 A 对 B 做的事改成 B 对 A 做。
6b. 每个 timeline 阶段只写一个主要动作节点；如果 fact 同时包含救助、指挥后续处理、击败敌人、救出他人等多个动作，要拆成相邻阶段。
7. timeline 优先整理剧情里实际发生的行动、对话、冲突、鼓励、回归和和解。回顾性创作、资料总结或后续作品化信息不必放入 timeline，除非用户明确询问歌曲、作品、歌词或记录本身。
8. 如果有多次相同地点或相似互动，必须用触发原因区分，不要合并：谁逃避、谁被拒绝、谁追上谁、谁鼓励谁，都要保持原文主体。
9. 如果用户问题限定了某个时期、形成过程、组成阶段、当初、前后或期间，timeline 只整理该范围内的主线；明确属于更晚阶段、另一个篇章或后续补充的事实不要放入主时间线。
10. 如果用户问“如何支援/救援/协助/处理”，timeline 必须围绕支援/救援/处理动作本身；后续审判、与被支援一方的旁支冲突、结局补充不能作为主时间线阶段，除非用户明确问到。
11. 输出要短，给后续模型当结构化提示用。
''',
      },
      {
        'role': 'user',
        'content': '''
用户问题：$userText
当前角色范围：${profile.contextRule}

facts:
${factLines.join('\n')}
''',
      },
    ];

    final response = await _postChatCompletions(
      baseUrl: _arkChatBaseUrl,
      apiKey: arkApiKey,
      model: arkEndpoint,
      messages: messages,
      providerName: '豆包/火山方舟时间线整理',
      includeThinkingField: false,
      maxTokens: 1200,
    );
    if (response == null) return null;

    try {
      final decoded = jsonDecode(utf8.decode(response.response.bodyBytes));
      final content = decoded['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) return null;
      final timeline = _parseDoubaoTimelineContent(content, facts: facts);
      if (timeline == null) return null;
      return timeline;
    } catch (e) {
      debugPrint('豆包时间线整理解析失败: $e');
      return null;
    }
  }

  static _DoubaoTimeline? _parseDoubaoTimelineContent(
    String content, {
    required List<_DoubaoGroundedFact> facts,
  }) {
    final jsonText = _extractJsonObject(content);
    if (jsonText != null) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map<String, dynamic>) {
          final strictTimeline = _parseDoubaoTimelineFromDecodedJson(
            decoded,
            facts: facts,
          );
          if (strictTimeline != null) return strictTimeline;
        }
      } catch (_) {
        final lenientTimeline = _parseDoubaoTimelineLenient(
          content,
          facts: facts,
        );
        if (lenientTimeline != null) {
          debugPrint(
            '豆包时间线 JSON 不完整，已宽松恢复: '
            'timeline=${lenientTimeline.nodes.length}',
          );
        }
        return lenientTimeline;
      }
    }
    return _parseDoubaoTimelineLenient(content, facts: facts);
  }

  static _DoubaoTimeline? _parseDoubaoTimelineFromDecodedJson(
    Map<String, dynamic> decoded, {
    required List<_DoubaoGroundedFact> facts,
  }) {
    final timeline = <_DoubaoTimelineNode>[];
    final seenTimelineText = <String>{};
    final rawTimeline = decoded['timeline'];
    if (rawTimeline is List) {
      for (final rawEntry in rawTimeline) {
        if (rawEntry is! Map) continue;
        final text = ApiService.normalizeKnownNamesForChineseText(
          _dynamicMapString(rawEntry, 'text'),
        ).trim();
        final factIndexes = _jsonIntList(
          rawEntry['fact_indexes'],
          maxExclusive: facts.length + 1,
        ).where((index) => index > 0).toList(growable: false);
        if (text.isEmpty || factIndexes.isEmpty) continue;
        final groundingFailure = _timelineNodeGroundingFailure(
          text,
          factIndexes: factIndexes,
          facts: facts,
        );
        if (groundingFailure != null) {
          debugPrint(
            '豆包时间线节点未通过事实引用校验，已丢弃: '
            'reason=$groundingFailure，'
            'factIndexes=${factIndexes.join(',')}，'
            'text=${_shortenRunes(text, 90)}',
          );
          continue;
        }
        final key = _looseEvidenceKey(text);
        if (key.isEmpty || !seenTimelineText.add(key)) continue;
        timeline.add(_DoubaoTimelineNode(
          text: text,
          factIndexes: factIndexes,
        ));
        if (timeline.length >= 8) break;
      }
    }

    final constraints = _dynamicStringList(decoded['constraints'])
        .map(ApiService.normalizeKnownNamesForChineseText)
        .where((line) => line.trim().isNotEmpty)
        .take(3)
        .toList();
    if (timeline.isEmpty) return null;
    if (!_timelineOrderIsValid(timeline, facts)) {
      debugPrint('豆包时间线未通过剧情顺序校验，拒绝采用整条时间线');
      return null;
    }
    final result = _DoubaoTimeline(
      nodes: timeline,
      constraints: constraints,
    );
    debugPrint(
      '豆包时间线整理结果: '
      'timeline=${timeline.length}, constraints=${constraints.length}; '
      '${timeline.isEmpty ? '' : _shortenRunes(timeline.first.text, 90)}',
    );
    return result;
  }

  static _DoubaoTimeline? _parseDoubaoTimelineLenient(
    String content, {
    required List<_DoubaoGroundedFact> facts,
  }) {
    final timeline = <_DoubaoTimelineNode>[];
    final seenTimelineText = <String>{};
    final constraints = <String>[];
    String pendingText = '';
    List<int> pendingFactIndexes = const [];
    var inConstraints = false;

    void flushTimelineNode() {
      final text = ApiService.normalizeKnownNamesForChineseText(
        pendingText.trim(),
      ).trim();
      final factIndexes = pendingFactIndexes
          .where((index) => index > 0 && index <= facts.length)
          .toList(growable: false);
      if (text.isEmpty || factIndexes.isEmpty) {
        pendingText = '';
        pendingFactIndexes = const [];
        return;
      }
      final groundingFailure = _timelineNodeGroundingFailure(
        text,
        factIndexes: factIndexes,
        facts: facts,
      );
      if (groundingFailure != null) {
        debugPrint(
          '豆包时间线节点未通过事实引用校验，已丢弃: '
          'reason=$groundingFailure，'
          'factIndexes=${factIndexes.join(',')}，'
          'text=${_shortenRunes(text, 90)}',
        );
        pendingText = '';
        pendingFactIndexes = const [];
        return;
      }
      final key = _looseEvidenceKey(text);
      if (key.isNotEmpty && seenTimelineText.add(key)) {
        timeline.add(_DoubaoTimelineNode(
          text: text,
          factIndexes: factIndexes,
        ));
      }
      pendingText = '';
      pendingFactIndexes = const [];
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (RegExp(r'"text"\s*:').hasMatch(line)) {
        flushTimelineNode();
        pendingText = _readJsonishLineValue(line);
        continue;
      }
      if (RegExp(r'"fact_indexes"\s*:').hasMatch(line)) {
        pendingFactIndexes = _extractJsonishIntListFromLine(
          line,
          maxExclusive: facts.length + 1,
        );
        flushTimelineNode();
        continue;
      }
      if (RegExp(r'"constraints"\s*:').hasMatch(line)) {
        inConstraints = true;
        constraints.addAll(_extractJsonishStringListFromLine(line));
        continue;
      }
      if (inConstraints) {
        if (line.startsWith(']')) {
          inConstraints = false;
          continue;
        }
        constraints.addAll(_extractJsonishStringListFromLine(line));
      }
    }
    flushTimelineNode();

    final normalizedConstraints = constraints
        .map(ApiService.normalizeKnownNamesForChineseText)
        .where((line) => line.trim().isNotEmpty)
        .take(3)
        .toList();
    if (timeline.isEmpty) return null;
    if (!_timelineOrderIsValid(timeline, facts)) {
      debugPrint('豆包时间线未通过剧情顺序校验，拒绝采用整条时间线');
      return null;
    }
    final result = _DoubaoTimeline(
      nodes: timeline,
      constraints: normalizedConstraints,
    );
    debugPrint(
      '豆包时间线整理结果: '
      'timeline=${timeline.length}, constraints=${normalizedConstraints.length}; '
      '${timeline.isEmpty ? '' : _shortenRunes(timeline.first.text, 90)}',
    );
    return result;
  }

  static String _readJsonishLineValue(String line) {
    final colon = line.indexOf(':');
    if (colon < 0) return '';
    var value = line.substring(colon + 1).trim();
    if (value.endsWith(',')) value = value.substring(0, value.length - 1);
    value = value.trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<int> _extractJsonishIntListFromLine(
    String line, {
    required int maxExclusive,
  }) {
    final start = line.indexOf('[');
    final end = line.lastIndexOf(']');
    final segment =
        start >= 0 && end > start ? line.substring(start + 1, end) : line;
    return RegExp(r'-?\d+')
        .allMatches(segment)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .where((index) => index >= 0 && index < maxExclusive)
        .toSet()
        .toList(growable: false);
  }

  static List<String> _extractJsonishStringListFromLine(String line) {
    final start = line.indexOf('[');
    final end = line.lastIndexOf(']');
    final segment =
        start >= 0 && end > start ? line.substring(start + 1, end) : line;
    return RegExp(r'"([^"]+)"')
        .allMatches(segment)
        .map((match) => (match.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static bool _timelineNodeIsGrounded(
    String text, {
    required List<int> factIndexes,
    required List<_DoubaoGroundedFact> facts,
  }) =>
      _timelineNodeGroundingFailure(
        text,
        factIndexes: factIndexes,
        facts: facts,
      ) ==
      null;

  static String? _timelineNodeGroundingFailure(
    String text, {
    required List<int> factIndexes,
    required List<_DoubaoGroundedFact> facts,
  }) {
    if (text.trim().isEmpty) return '节点文本为空';
    if (factIndexes.isEmpty) return '没有事实引用编号';
    final referencedFacts = factIndexes
        .where((index) => index > 0 && index <= facts.length)
        .map((index) => facts[index - 1])
        .toList(growable: false);
    if (referencedFacts.length != factIndexes.length) {
      return '存在越界的事实引用编号';
    }

    final evidenceText = referencedFacts
        .map((fact) => fact.sourceExcerpt.trim().isNotEmpty
            ? fact.sourceExcerpt
            : fact.text)
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    if (evidenceText.trim().isEmpty) return '引用原文为空';

    final knownNames = <String>{
      ...ApiService.canonicalChineseNamesForSearch(),
      for (final entry in namePronunciationDictionary.entries)
        ...entry.key.split(RegExp(r'[\s　]+')),
    }.where((name) => name.trim().runes.length >= 2);
    for (final name in knownNames) {
      if (_containsLooseText(text, name) &&
          !_containsLooseText(evidenceText, name)) {
        return '人物“$name”未出现在引用原文';
      }
    }

    final quotedText = RegExp(r'[“「『"]([^”」』"]{2,40})[”」』"]')
        .allMatches(text)
        .map((match) => match.group(1) ?? '')
        .where((value) => value.isNotEmpty);
    for (final quote in quotedText) {
      if (!_containsLooseText(evidenceText, quote)) {
        return '引语“$quote”未出现在引用原文';
      }
    }
    return null;
  }

  static bool _timelineOrderIsValid(
    List<_DoubaoTimelineNode> nodes,
    List<_DoubaoGroundedFact> facts,
  ) {
    final factSnapshots = [
      for (var i = 0; i < facts.length; i++)
        GroundingFactSnapshot(
          index: i + 1,
          text: facts[i].text,
          eventOrder: facts[i].eventOrder,
          chronologyScope: facts[i].chronologyScope,
        ),
    ];
    final timelineSnapshots = [
      for (var i = 0; i < nodes.length; i++)
        GroundingTimelineSnapshot(
          index: i + 1,
          text: nodes[i].text,
          factIndexes: nodes[i].factIndexes,
        ),
    ];
    return GroundingContractValidator.validateTimeline(
      facts: factSnapshots,
      timeline: timelineSnapshots,
    ).isEmpty;
  }

  @visibleForTesting
  static String? parseDoubaoTimelineTextForTest({
    required String content,
    required List<String> factTexts,
    required List<String> sourceExcerpts,
  }) {
    if (factTexts.length != sourceExcerpts.length) {
      throw ArgumentError('factTexts and sourceExcerpts must have same length');
    }
    final facts = <_DoubaoGroundedFact>[
      for (var i = 0; i < factTexts.length; i++)
        _DoubaoGroundedFact(
          text: factTexts[i],
          sourceTitle: '测试来源',
          sourceUrl: 'https://example.test/source',
          sourceExcerpt: sourceExcerpts[i],
          eventOrder: i + 1,
          chronologyScope: 'test',
        ),
    ];
    return _parseDoubaoTimelineContent(content, facts: facts)?.toPromptText();
  }

  static List<String> _dynamicStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((item) => item.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<String> _formatDoubaoFacts(
    List<_DoubaoGroundedFact> facts, {
    required String originalQuery,
    required int maxFacts,
    bool separateFacts = false,
  }) {
    final selectedFacts = _selectDoubaoFactsForOutput(facts, maxFacts);
    if (separateFacts) {
      final lines = <String>[];
      for (var i = 0; i < selectedFacts.length; i++) {
        final fact = selectedFacts[i];
        final title = fact.sourceTitle.isEmpty ? '豆包搜索结果' : fact.sourceTitle;
        final source = fact.sourceUrl.isEmpty ? '' : '（来源：${fact.sourceUrl}）';
        lines.add(
          '${i + 1}. $title：相关事实：${_factContextText(fact)}$source',
        );
      }
      return lines;
    }

    final grouped = <String, List<String>>{};
    final urls = <String, String>{};
    for (final fact in selectedFacts) {
      final title = fact.sourceTitle.isEmpty ? '豆包搜索结果' : fact.sourceTitle;
      grouped.putIfAbsent(title, () => <String>[]).add(_factContextText(fact));
      if (fact.sourceUrl.isNotEmpty) urls[title] = fact.sourceUrl;
    }

    var index = 0;
    return grouped.entries.map((entry) {
      index += 1;
      final url = urls[entry.key] ?? '';
      final source = url.isEmpty ? '' : '（来源：$url）';
      return '$index. ${entry.key}：相关事实：${entry.value.join(' / ')}$source';
    }).toList();
  }

  static String _factContextText(_DoubaoGroundedFact fact) {
    final text = fact.text.trim();
    final excerpt = fact.sourceExcerpt.trim();
    if (excerpt.isEmpty) return text;
    final genderMetadata = _factGenderMetadata(text);
    return '原文证据：${_shortenRunes(excerpt, 800)}'
        '${genderMetadata.isEmpty ? '' : '（人物性别参考：$genderMetadata）'}';
  }

  static String _factGenderMetadata(String factText) {
    final people = <String>[];
    final names = ApiService.canonicalChineseNamesForSearch().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in names) {
      final match = RegExp(
        '${RegExp.escape(name)}[（(]([男女])[）)]',
      ).firstMatch(factText);
      if (match == null) continue;
      people.add('$name=${match.group(1)}');
    }
    return people.join('、');
  }

  static String _shortenRunes(String text, int maxRunes) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.runes.length <= maxRunes) return normalized;
    return '${String.fromCharCodes(normalized.runes.take(maxRunes))}...';
  }

  static List<_DoubaoGroundedFact> _selectDoubaoFactsForOutput(
    List<_DoubaoGroundedFact> facts,
    int maxFacts,
  ) {
    final uniqueFacts = _dedupeDoubaoFacts(facts);
    if (uniqueFacts.length <= maxFacts) return uniqueFacts;

    final grouped = <String, List<_DoubaoGroundedFact>>{};
    final sourceOrder = <String>[];
    for (final fact in uniqueFacts) {
      final key = fact.sourceUrl.isNotEmpty
          ? fact.sourceUrl
          : (fact.sourceTitle.isNotEmpty ? fact.sourceTitle : '豆包搜索结果');
      if (!grouped.containsKey(key)) {
        grouped[key] = <_DoubaoGroundedFact>[];
        sourceOrder.add(key);
      }
      grouped[key]!.add(fact);
    }

    final quotas = <String, int>{for (final source in sourceOrder) source: 0};
    var allocated = 0;
    while (allocated < maxFacts) {
      var changed = false;
      for (final source in sourceOrder) {
        final sourceFacts = grouped[source] ?? const <_DoubaoGroundedFact>[];
        final currentQuota = quotas[source] ?? 0;
        if (currentQuota >= sourceFacts.length) continue;
        quotas[source] = currentQuota + 1;
        allocated += 1;
        changed = true;
        if (allocated >= maxFacts) break;
      }
      if (!changed) break;
    }

    final sampledBySource = <String, List<_DoubaoGroundedFact>>{};
    for (final source in sourceOrder) {
      final sourceFacts = grouped[source] ?? const <_DoubaoGroundedFact>[];
      final quota = quotas[source] ?? 0;
      final indexes = _spreadSampleIndexes(sourceFacts.length, quota);
      sampledBySource[source] = [
        for (final index in indexes) sourceFacts[index]
      ];
    }

    final selected = <_DoubaoGroundedFact>[];
    var offset = 0;
    while (selected.length < maxFacts) {
      var added = false;
      for (final source in sourceOrder) {
        final sourceFacts =
            sampledBySource[source] ?? const <_DoubaoGroundedFact>[];
        if (offset >= sourceFacts.length) continue;
        selected.add(sourceFacts[offset]);
        added = true;
        if (selected.length >= maxFacts) break;
      }
      if (!added) break;
      offset += 1;
    }
    return selected;
  }

  static List<int> _spreadSampleIndexes(int total, int count) {
    if (total <= 0 || count <= 0) return const [];
    if (count >= total) return [for (var i = 0; i < total; i++) i];
    if (count == 1) return const [0];

    final indexes = <int>[];
    for (var i = 0; i < count; i++) {
      final index = (i * (total - 1) / (count - 1)).round();
      if (indexes.isEmpty || indexes.last != index) indexes.add(index);
    }
    return indexes;
  }

  @visibleForTesting
  static List<int> spreadSampleIndexesForTest(int total, int count) {
    return _spreadSampleIndexes(total, count);
  }

  @visibleForTesting
  static String factContextTextForTest({
    required String factText,
    required String sourceExcerpt,
  }) =>
      _factContextText(_DoubaoGroundedFact(
        text: factText,
        sourceTitle: '测试来源',
        sourceUrl: 'https://example.test/source',
        sourceExcerpt: sourceExcerpt,
      ));

  @visibleForTesting
  static bool timelineNodeGroundedForTest({
    required String timelineText,
    required String factText,
    required String sourceExcerpt,
  }) =>
      _timelineNodeIsGrounded(
        timelineText,
        factIndexes: const [1],
        facts: [
          _DoubaoGroundedFact(
            text: factText,
            sourceTitle: '测试来源',
            sourceUrl: 'https://example.test/source',
            sourceExcerpt: sourceExcerpt,
          ),
        ],
      );

  @visibleForTesting
  static String? timelineNodeGroundingFailureForTest({
    required String timelineText,
    required String factText,
    required String sourceExcerpt,
  }) =>
      _timelineNodeGroundingFailure(
        timelineText,
        factIndexes: const [1],
        facts: [
          _DoubaoGroundedFact(
            text: factText,
            sourceTitle: '测试来源',
            sourceUrl: 'https://example.test/source',
            sourceExcerpt: sourceExcerpt,
          ),
        ],
      );

  static bool _looksLikeProductionMetaFact(String text) {
    return RegExp(
      r'导演|監督|编剧|脚本|制作|企划|企畫|公司|武士道|Bushiroad|声优|聲優|配音|采访|访谈|訪談|播出|上映|剧场版|劇場版|动画制作|ゲーム制作|演唱会|LIVE|活动|商业|运营|'
      r'作词|作詞|作曲|编曲|編曲|片头曲|片頭曲|片尾曲|插曲|主题曲|主題曲|发售|发行|发行日期|数字独立单曲|单曲|专辑|唱片|销量|排行|'
      r'\bopening theme\b|\bending theme\b|\breleased?\b|\brelease\b|\blabel\b|\blimited edition\b|\bblu-ray\b|\blottery\b|\btickets?\b|'
      r'\bwritten by\b|\blyricist\b|\bcomposer\b|\barranger\b|\bproducer\b|\bcharts?\b|\baccolades?\b|\bcredits?\b|\bpersonnel\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static Future<_SiteSearchResult> _searchWikipediaSequence(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) async {
    final apiResult = await _searchWikipediaApi(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    );
    if (apiResult.results.isNotEmpty) return apiResult;

    final directResult = await _searchDirectWikipedia(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    );
    if (directResult.results.isNotEmpty) return directResult;

    return const _SiteSearchResult.empty();
  }

  static Future<_SiteSearchResult> _searchWikipediaApi(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) async {
    final titles = _canonDirectTitleVariants(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    );

    for (final title in titles) {
      final validationQuery = _directTitleValidationQuery(
        query,
        title,
        relatedCanonTerm,
      );
      final result = await _fetchWikipediaApiExtract(
        title: title,
        validationQuery: validationQuery,
      );
      if (result.isNotEmpty) {
        debugPrint('维基百科 API 直达成功: $title');
        return _SiteSearchResult(results: result, query: validationQuery);
      }
    }

    for (final searchQuery in _canonSearchQueryVariants(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    )) {
      final title = await _searchWikipediaApiTitle(searchQuery);
      if (title.isEmpty) continue;
      final result = await _fetchWikipediaApiExtract(
        title: title,
        validationQuery: searchQuery,
      );
      if (result.isNotEmpty) {
        debugPrint('维基百科 API 搜索成功: $searchQuery -> $title');
        return _SiteSearchResult(results: result, query: searchQuery);
      }
    }

    return const _SiteSearchResult.empty();
  }

  static Future<String> _searchWikipediaApiTitle(String query) async {
    try {
      final uri = Uri.https('zh.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'format': 'json',
        'utf8': '1',
        'srlimit': '3',
      });
      final response = await http
          .get(uri, headers: _browserSearchHeaders)
          .timeout(_searchTimeout);
      if (response.statusCode != 200) return '';
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final search = decoded['query']?['search'];
      if (search is! List) return '';
      for (final item in search) {
        if (item is! Map) continue;
        final title = '${item['title'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        final snippet = _cleanHtml('${item['snippet'] ?? ''}');
        if (_canonResultMatchesQueryFocus(title, snippet, query)) return title;
      }
    } catch (e) {
      debugPrint('维基百科 API 搜索失败: $query $e');
    }
    return '';
  }

  static Future<List<String>> _fetchWikipediaApiExtract({
    required String title,
    required String validationQuery,
  }) async {
    try {
      final uri = Uri.https('zh.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'prop': 'extracts',
        'explaintext': '1',
        'redirects': '1',
        'titles': title,
        'format': 'json',
        'utf8': '1',
        'variant': 'zh-cn',
      });
      final response = await http
          .get(uri, headers: _browserSearchHeaders)
          .timeout(_searchTimeout);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final pages = decoded['query']?['pages'];
      if (pages is! Map) return const [];

      for (final rawPage in pages.values) {
        if (rawPage is! Map) continue;
        if (rawPage.containsKey('missing')) continue;
        final pageTitle = '${rawPage['title'] ?? title}'.trim();
        final extract = '${rawPage['extract'] ?? ''}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (extract.length < 120 || _looksLikeGarbledText(extract)) continue;
        final snippet = _relevantRawSnippet(
          extract,
          validationQuery,
          pageTitle,
          maxLength: 900,
          maxFragments: 4,
          minLength: 180,
        );
        if (snippet.isEmpty) continue;
        final candidate = _SearchResultCandidate(
          title: pageTitle,
          content: '相关正文：$snippet',
          url:
              'https://zh.wikipedia.org/wiki/${Uri.encodeComponent(pageTitle)}',
          score: _searchResultScore(
            pageTitle,
            snippet,
            _snippetSearchTerms(validationQuery),
          ),
        );
        return _formatSearchCandidates([candidate], 'canon');
      }
    } catch (e) {
      debugPrint('维基百科 API 直达失败: $title $e');
    }
    return const [];
  }

  static List<String> _canonSearchQueryVariants(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) {
    final variants = <String>[];
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || variants.contains(trimmed)) return;
      variants.add(trimmed);
    }

    final explicitTitles =
        directTitleHints.where(_isExplicitCanonTitleTerm).toList();
    for (final title in explicitTitles) {
      add(title);
    }
    add(query);
    add(_focusedCanonSearchQuery(query));
    add(_primaryCanonFocusTerm(query));
    add(_relatedCanonSearchQuery(query, relatedCanonTerm));
    for (final title in directTitleHints) {
      add(_directTitleValidationQuery(query, title, relatedCanonTerm));
      add(title);
    }
    return variants;
  }

  static Future<_SiteSearchResult> _searchDirectMoegirl(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) async {
    for (final title in _canonDirectTitleVariants(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    )) {
      final validationQuery = _directTitleValidationQuery(
        query,
        title,
        relatedCanonTerm,
      );
      final uri = Uri(
        scheme: 'https',
        host: 'zh.moegirl.org.cn',
        pathSegments: [title],
        queryParameters: const {'variant': 'zh-cn'},
      );
      final results = await _searchDirectCanonPage(
        query: validationQuery,
        title: title,
        uri: uri,
        sourceName: '萌娘百科词条直达',
      );
      if (results.isNotEmpty) {
        return _SiteSearchResult(results: results, query: validationQuery);
      }
    }
    return const _SiteSearchResult.empty();
  }

  static Future<_SiteSearchResult> _searchDirectWikipedia(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) async {
    for (final title in _canonDirectTitleVariants(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    )) {
      final validationQuery = _directTitleValidationQuery(
        query,
        title,
        relatedCanonTerm,
      );
      final uri = Uri(
        scheme: 'https',
        host: 'zh.wikipedia.org',
        pathSegments: ['zh-hans', title],
      );
      var results = await _searchDirectCanonPage(
        query: validationQuery,
        title: title,
        uri: uri,
        sourceName: '维基百科词条直达',
      );
      if (results.isEmpty && _isExplicitCanonTitleTerm(title)) {
        results = await _searchDirectCanonPage(
          query: validationQuery,
          title: title,
          uri: Uri(
            scheme: 'https',
            host: 'en.wikipedia.org',
            pathSegments: ['wiki', title],
          ),
          sourceName: '英文维基百科词条直达',
        );
      }
      if (results.isNotEmpty) {
        return _SiteSearchResult(results: results, query: validationQuery);
      }
    }
    return const _SiteSearchResult.empty();
  }

  static List<String> _canonDirectTitleVariants(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) {
    final titles = <String>[];
    void add(String value) {
      final title = value.trim();
      if (title.isEmpty || titles.contains(title)) return;
      titles.add(title);
    }

    final explicitTitles =
        directTitleHints.where(_isExplicitCanonTitleTerm).toList();
    if (explicitTitles.isNotEmpty) {
      for (final title in explicitTitles) {
        add(title);
        for (final variant in _latinTitleCaseVariants(title)) {
          add(variant);
        }
      }
      return titles;
    }

    final primary = _primaryCanonFocusTerm(query);
    add(primary);
    if (primary.isNotEmpty) {
      for (final context in _canonQueryContextTerms) {
        if (context.length < 2) continue;
        if (!_canonTextContainsTerm(query, context)) continue;
        if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(context)) continue;
        add('$context$primary');
      }
    }
    add(relatedCanonTerm);
    for (final title in directTitleHints) {
      add(title);
    }
    return titles;
  }

  static bool _isExplicitCanonTitleTerm(String value) {
    return RegExp(r'[A-Za-z][A-Za-z0-9!☆_:\-]{2,}').hasMatch(value);
  }

  static List<String> _latinTitleCaseVariants(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9!☆_:\-]*$').hasMatch(trimmed)) {
      return const [];
    }
    final lower = trimmed.toLowerCase();
    final titleCase = lower.isEmpty
        ? ''
        : '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
    return [
      titleCase,
      lower,
      trimmed.toUpperCase(),
    ].where((variant) => variant.isNotEmpty && variant != trimmed).toList();
  }

  static String _directTitleValidationQuery(
    String query,
    String title,
    String relatedCanonTerm,
  ) {
    final primary = _primaryCanonFocusTerm(query);
    if (primary.isEmpty || title == primary) return query;

    return _dedupeSearchQueryTerms('$title $query');
  }

  static Future<List<String>> _searchDirectCanonPage({
    required String query,
    required String title,
    required Uri uri,
    required String sourceName,
  }) async {
    try {
      final candidate = _SearchResultCandidate(
        title: title,
        content: title,
        url: uri.toString(),
        score: 0,
      );
      var enriched = await _fetchReadableCanonCandidate(candidate, query);
      if (!enriched.content.startsWith('相关正文：')) {
        enriched = await _fetchReadableCanonCandidate(candidate, title);
      }
      if (!enriched.content.startsWith('相关正文：')) return [];
      debugPrint('$sourceName成功: $title');
      return _formatSearchCandidates([enriched], 'canon');
    } catch (e) {
      debugPrint('$sourceName失败: $title $e');
      return [];
    }
  }

  static Future<List<String>> _searchBaiduBaikeSequence(
    String query, {
    String relatedCanonTerm = '',
    List<String> directTitleHints = const [],
  }) async {
    for (final searchQuery in _canonSearchQueryVariants(
      query,
      relatedCanonTerm: relatedCanonTerm,
      directTitleHints: directTitleHints,
    )) {
      final results =
          await _searchBaiduBaike(searchQuery, originalQuery: query);
      if (results.isNotEmpty) {
        debugPrint('百度百科搜索成功: $searchQuery');
        return results;
      }
    }

    final directResults = await _searchBaiduBaikeDirect(
      query,
      directTitleHints: directTitleHints,
    );
    if (directResults.isNotEmpty) return directResults;

    return [];
  }

  static Future<List<String>> _searchBaiduBaikeDirect(
    String query, {
    List<String> directTitleHints = const [],
  }) async {
    final titleCandidates = <String>[];
    void addTitle(String value) {
      final title = value.trim();
      if (title.isEmpty || titleCandidates.contains(title)) return;
      titleCandidates.add(title);
    }

    addTitle(_primaryCanonFocusTerm(query));
    for (final title in directTitleHints) {
      addTitle(title);
    }

    for (final title in titleCandidates) {
      try {
        final uri = Uri(
          scheme: 'https',
          host: 'wapbaike.baidu.com',
          pathSegments: ['item', title],
        );
        final response = await http
            .get(uri, headers: _browserSearchHeaders)
            .timeout(_searchTimeout);
        if (response.statusCode != 200) continue;

        final html = utf8.decode(response.bodyBytes, allowMalformed: true);
        final pageTitle = _baiduBaikePageTitle(html, title);
        if (pageTitle.isEmpty || !_canonTextContainsTerm(pageTitle, title)) {
          continue;
        }

        final pageText = _extractBaiduBaikeReadableText(html);
        if (pageText.isEmpty) continue;
        if (!_canonResultMatchesQueryFocus(pageTitle, pageText, query)) {
          continue;
        }

        var snippet = pageText.length <= 1200
            ? pageText
            : _relevantRawSnippet(
                pageText,
                query,
                pageTitle,
                maxLength: 1200,
                maxFragments: 10,
                minLength: 240,
              );
        if (snippet.isEmpty) {
          snippet = _relevantRawSnippet(
            pageText,
            title,
            pageTitle,
            maxLength: 1200,
            maxFragments: 10,
            minLength: 240,
          );
        }
        if (snippet.isEmpty) continue;

        final candidate = _SearchResultCandidate(
          title: pageTitle,
          content: '相关正文：$snippet',
          url: uri.toString(),
          score: _searchResultScore(
            pageTitle,
            snippet,
            _snippetSearchTerms(query),
          ),
        );
        debugPrint('百度百科词条直达成功: $title');
        return _formatSearchCandidates([candidate], 'canon');
      } catch (e) {
        debugPrint('百度百科词条直达失败: $title $e');
      }
    }

    return [];
  }

  static Future<List<String>> _searchBaiduBaike(
    String query, {
    required String originalQuery,
  }) async {
    try {
      var html = await _fetchBaiduSearchHtml(query, mobile: false);
      var candidates = _parseBaiduBaikeSearchResults(html, originalQuery);

      if (candidates.isEmpty) {
        debugPrint(
          '百度百科 PC 搜索无百科候选，改用移动搜索: '
          'query=$query, htmlLength=${html.length}',
        );
        html = await _fetchBaiduSearchHtml(query, mobile: true);
        candidates = _parseBaiduBaikeSearchResults(html, originalQuery);
      }

      if (candidates.isEmpty) {
        debugPrint('百度百科搜索无百科候选: query=$query, htmlLength=${html.length}');
        return [];
      }

      final candidatesToEnrich = candidates.take(3).toList();
      final enriched = await Future.wait(
        candidatesToEnrich.map(
          (candidate) => _enrichBaiduBaikeCandidate(candidate, originalQuery),
        ),
      );

      final merged = <_SearchResultCandidate>[];
      for (var i = 0; i < enriched.length; i++) {
        final enrichedCandidate = enriched[i];
        merged.add(enrichedCandidate.content.isNotEmpty
            ? enrichedCandidate
            : candidatesToEnrich[i]);
      }

      final useful = merged.where((candidate) {
        if (candidate.content.isEmpty) return false;
        return _canonResultMatchesQueryFocus(
          candidate.title,
          candidate.content,
          originalQuery,
        );
      }).toList();

      if (useful.isEmpty) {
        debugPrint(
            '百度百科搜索候选正文不可用: query=$query, candidates=${candidates.length}');
        return [];
      }
      return _formatSearchCandidates(useful, 'canon');
    } catch (e) {
      debugPrint('百度百科搜索失败: $e');
      return [];
    }
  }

  static Future<_SearchResultCandidate> _enrichBaiduBaikeCandidate(
    _SearchResultCandidate candidate,
    String query,
  ) async {
    try {
      final uri = Uri.tryParse(candidate.url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return candidate;
      }

      final requestUri = _baiduBaikeReadableUri(uri);
      final response = await http
          .get(requestUri, headers: _browserSearchHeaders)
          .timeout(_searchTimeout);
      if (response.statusCode != 200) return candidate;

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final pageTitle = _baiduBaikePageTitle(html, candidate.title);
      if (pageTitle.isEmpty) return candidate;

      final pageText = _extractBaiduBaikeReadableText(html);
      if (pageText.isEmpty) return candidate;

      var snippet = pageText.length <= 1200
          ? pageText
          : _relevantRawSnippet(
              pageText,
              query,
              pageTitle,
              maxLength: 1200,
              maxFragments: 10,
              minLength: 240,
            );
      if (snippet.isEmpty) {
        snippet = _relevantRawSnippet(
          pageText,
          pageTitle,
          pageTitle,
          maxLength: 1200,
          maxFragments: 10,
          minLength: 240,
        );
      }
      if (snippet.isEmpty) return candidate;

      final content = '相关正文：$snippet';
      return _SearchResultCandidate(
        title: pageTitle,
        content: content,
        url: requestUri.toString(),
        score: _searchResultScore(
          pageTitle,
          content,
          _snippetSearchTerms(query),
        ),
      );
    } catch (e) {
      debugPrint('百度百科候选正文抓取失败: ${candidate.url} $e');
      return candidate;
    }
  }

  static Future<String> _fetchBaiduSearchHtml(
    String query, {
    required bool mobile,
  }) async {
    final uri = mobile
        ? Uri.https('m.baidu.com', '/s', {'word': query})
        : Uri.https('www.baidu.com', '/s', {
            'wd': query,
            'rn': '10',
            'ie': 'utf-8',
          });
    final headers = Map<String, String>.from(
      mobile ? _mobileBrowserSearchHeaders : _browserSearchHeaders,
    );

    if (!mobile) {
      final client = http.Client();
      try {
        final homeResponse = await client
            .get(Uri.https('www.baidu.com', '/'), headers: headers)
            .timeout(_timeout);
        final cookie = _responseCookieHeader(homeResponse);
        if (cookie.isNotEmpty) headers['Cookie'] = cookie;

        final response =
            await client.get(uri, headers: headers).timeout(_searchTimeout);
        if (response.statusCode != 200) {
          debugPrint(
            '百度百科搜索失败: HTTP ${response.statusCode} '
            'query=$query, mobile=$mobile',
          );
          return '';
        }
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      } finally {
        client.close();
      }
    }

    final response =
        await http.get(uri, headers: headers).timeout(_searchTimeout);
    if (response.statusCode != 200) {
      debugPrint(
        '百度百科搜索失败: HTTP ${response.statusCode} '
        'query=$query, mobile=$mobile',
      );
      return '';
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static String _responseCookieHeader(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.trim().isEmpty) return '';
    final cookies = <String>[];
    for (final part in setCookie.split(RegExp(r',\s*(?=[^;,]+=)'))) {
      final cookie = part.split(';').first.trim();
      if (cookie.isNotEmpty) cookies.add(cookie);
    }
    return cookies.join('; ');
  }

  static List<_SearchResultCandidate> _parseBaiduBaikeSearchResults(
    String html,
    String query,
  ) {
    final candidates = <_SearchResultCandidate>[];
    final seenUrls = <String>{};
    final decodedHtml = _decodeHtml(html);
    final urlPatterns = [
      RegExp(
        r'(?:mu|originalUrl)="(https?://baike\.baidu\.com/[^"]+)"',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:data-url|data-log-url)="(https?://baike\.baidu\.com/[^"]+)"',
        caseSensitive: false,
      ),
      RegExp(
        r'"(?:originalUrl|titleUrl|lemmaUrl|url|src)"\s*:\s*"((?:https?:)?\\?/\\?/baike\.baidu\.com/(?:item|lemma|subview)[^"\\]*)"',
        caseSensitive: false,
      ),
      RegExp(
        r"""https?:\\?/\\?/baike\.baidu\.com\\?/(?:item|lemma|subview)[^"'<>\s&\\]*""",
        caseSensitive: false,
      ),
      RegExp(
        r"""https?://baike\.baidu\.com/(?:item|lemma|subview)[^"'<>\s&\\]*""",
        caseSensitive: false,
      ),
    ];

    void addCandidate({
      required String sourceHtml,
      required int start,
      required int end,
      required String rawUrl,
      String titleHint = '',
      String contentHint = '',
    }) {
      final url = _normalizeBaiduSearchUrl(rawUrl);
      if (url.isEmpty || seenUrls.contains(url)) return;
      seenUrls.add(url);

      final block = _nearbySearchResultBlock(sourceHtml, start, end);
      final blockTitle = _baiduBaikeTitleFromBlock(block, url);
      final title = titleHint.isNotEmpty ? titleHint : blockTitle;
      final blockContent = _baiduSearchSnippetFromBlock(block);
      final content = contentHint.isNotEmpty ? contentHint : blockContent;
      if (title.isEmpty && content.isEmpty) return;
      if (!_canonResultMatchesQueryFocus(title, content, query)) return;

      candidates.add(_SearchResultCandidate(
        title: title.isEmpty ? _baiduBaikeTitleFromUrl(url) : title,
        content: content,
        url: url,
        score: _searchResultScore(title, content, _snippetSearchTerms(query)),
      ));
    }

    void collectLemmaInfoFrom(String sourceHtml) {
      final lemmaPattern = RegExp(
        r'"lemmaInfo"\s*:\s*\{(.*?)\}',
        dotAll: true,
        caseSensitive: false,
      );
      for (final match in lemmaPattern.allMatches(sourceHtml)) {
        final block = match.group(1) ?? '';
        final id = RegExp(r'"lemmaId"\s*:\s*"?(\d+)"?', caseSensitive: false)
            .firstMatch(block)
            ?.group(1);
        final rawTitle = RegExp(
          r'"lemmaTitle"\s*:\s*"((?:\\.|[^"\\])*)"',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(block)?.group(1);
        final rawUrl = RegExp(
          r'"lemmaUrl"\s*:\s*"((?:\\.|[^"\\])*)"',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(block)?.group(1);
        final rawDesc = RegExp(
          r'"lemmaDesc"\s*:\s*"((?:\\.|[^"\\])*)"',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(block)?.group(1);

        final title = _decodeBaiduSearchValue(rawTitle ?? '');
        var url = _decodeJsonishSearchValue(rawUrl ?? '');
        if (url.isEmpty && title.isNotEmpty && id != null) {
          url =
              'https://baike.baidu.com/item/${Uri.encodeComponent(title)}/$id';
        }
        if (url.isEmpty) continue;

        addCandidate(
          sourceHtml: sourceHtml,
          start: match.start,
          end: match.end,
          rawUrl: url,
          titleHint: title,
          contentHint: _decodeBaiduSearchValue(rawDesc ?? ''),
        );
        if (candidates.length >= 5) break;
      }
    }

    void collectUrlsFrom(String sourceHtml) {
      for (final pattern in urlPatterns) {
        for (final match in pattern.allMatches(sourceHtml)) {
          final rawUrl = match.groupCount >= 1
              ? match.group(1) ?? ''
              : match.group(0) ?? '';
          final url = _normalizeBaiduSearchUrl(rawUrl);
          if (url.isEmpty) continue;
          addCandidate(
            sourceHtml: sourceHtml,
            start: match.start,
            end: match.end,
            rawUrl: url,
          );
          if (candidates.length >= 5) break;
        }
        if (candidates.length >= 5) break;
      }
    }

    collectLemmaInfoFrom(html);
    if (candidates.length < 5) collectUrlsFrom(html);
    if (candidates.length < 5 && decodedHtml != html) {
      collectLemmaInfoFrom(decodedHtml);
      if (candidates.length < 5) collectUrlsFrom(decodedHtml);
    }

    return candidates;
  }

  static String _normalizeBaiduSearchUrl(String rawUrl) {
    var decoded = _decodeHtml(rawUrl)
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(RegExp(r'\\+$'), '')
        .trim();
    if (RegExp(r'^https?%3a%2f%2f', caseSensitive: false).hasMatch(decoded)) {
      decoded = Uri.decodeFull(decoded);
    }
    final delimiter = RegExp(r"""["'<>\s]""").firstMatch(decoded);
    if (delimiter != null) decoded = decoded.substring(0, delimiter.start);
    if (decoded.startsWith('//')) decoded = 'https:$decoded';
    final uri = Uri.tryParse(decoded);
    if (uri == null || uri.host != 'baike.baidu.com') return '';
    return uri.toString();
  }

  static String _nearbySearchResultBlock(String html, int start, int end) {
    final fallbackStart = start - 3000 < 0 ? 0 : start - 3000;
    final fallbackEnd = end + 7000 > html.length ? html.length : end + 7000;
    final fallback = html.substring(fallbackStart, fallbackEnd);

    final blockStart = html.lastIndexOf('<div', start);
    final blockEnd = html.indexOf('</div>', end);
    if (blockStart >= 0 && blockEnd > blockStart) {
      final block = html.substring(blockStart, blockEnd + 6);
      if (block.length >= 1000) return block;
    }

    return fallback;
  }

  static String _baiduBaikeTitleFromBlock(String block, String url) {
    final decodedBlock = _decodeHtml(block);
    final patterns = [
      RegExp(r'"lemmaTitle"\s*:\s*"([^"]+)"'),
      RegExp(r'"tools"\s*:\s*\{[^}]*"title"\s*:\s*"([^"]+)"', dotAll: true),
      RegExp(r'"title"\s*:\s*"([^"]+?)\s*-\s*百度百科"'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(decodedBlock);
      final title = _decodeBaiduSearchValue(match?.group(1) ?? '');
      if (title.isNotEmpty) return title;
    }

    return _baiduBaikeTitleFromUrl(url);
  }

  static String _baiduBaikeTitleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const <String>[];
    final itemIndex = segments.indexOf('item');
    if (itemIndex >= 0 && itemIndex + 1 < segments.length) {
      try {
        return Uri.decodeComponent(segments[itemIndex + 1]);
      } catch (_) {
        return segments[itemIndex + 1];
      }
    }
    return '';
  }

  static String _baiduBaikePageTitle(String html, String fallback) {
    final patterns = [
      RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false),
      RegExp(
        r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final title = _decodeBaiduSearchValue(match?.group(1) ?? '')
          .replaceFirst(RegExp(r'_百度百科$'), '')
          .trim();
      if (title.isNotEmpty) return title;
    }
    return fallback;
  }

  static String _baiduSearchSnippetFromBlock(String block) {
    final decodedBlock = _decodeHtml(block);
    final values = <String>[];
    final patterns = [
      RegExp(r'"brief"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'"description"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'"lemmaDesc"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'"introduction"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'"text"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(decodedBlock)) {
        final value =
            _cleanHtml(_decodeJsonishSearchValue(match.group(1) ?? ''));
        if (value.isEmpty || values.contains(value)) continue;
        values.add(value);
        if (values.length >= 5) break;
      }
    }

    return _truncateSearchSnippet(values.join(' / '), maxLength: 900);
  }

  static String _decodeJsonishSearchValue(String value) {
    if (value.isEmpty) return '';
    try {
      return jsonDecode('"${value.replaceAll('"', r'\"')}"') as String;
    } catch (_) {
      return value
          .replaceAll(r'\"', '"')
          .replaceAll(r'\/', '/')
          .replaceAll(r'\n', ' ')
          .replaceAll(r'\t', ' ');
    }
  }

  static String _decodeBaiduSearchValue(String value) {
    var decoded = _cleanHtml(_decodeJsonishSearchValue(value));
    if (decoded.contains('%')) {
      try {
        decoded = Uri.decodeFull(decoded);
      } catch (_) {
        // Keep the readable part we already have.
      }
    }
    return decoded
        .replaceFirst(RegExp(r'\s*-\s*百度百科\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _relevantRawSnippet(
    String rawContent,
    String query,
    String title, {
    int maxLength = 650,
    int maxFragments = 3,
    bool includeLeadingFacts = false,
    int minLength = 0,
    List<String> anchorTerms = const [],
  }) {
    final terms = _snippetSearchTerms(query);
    if (terms.isEmpty) {
      return '';
    }
    final aspectTerms = terms.where(_isCanonAspectTerm).toList();

    final fragments = _rawContentFragments(rawContent);
    final windows = <_SnippetWindow>[];
    for (var i = 0; i < fragments.length; i++) {
      final fragment = fragments[i];
      if (_isNoisyRawFragment(fragment)) continue;
      if (anchorTerms.isNotEmpty &&
          !anchorTerms.any((term) => _canonTextContainsTerm(fragment, term))) {
        continue;
      }
      if (!_canonFragmentHasRequiredEvidence(fragment, title, terms)) continue;
      if (aspectTerms.isNotEmpty &&
          !_canonFragmentMatchesAnyAspect(fragment, aspectTerms)) {
        continue;
      }
      final titleScore = aspectTerms.isEmpty ? _snippetScore(title, terms) : 0;
      final score = _snippetScore(fragment, terms) + titleScore;
      if (score < _minimumCanonFragmentScore(terms)) continue;
      windows.add(_SnippetWindow(text: fragment, score: score, index: i));
    }

    if (windows.isEmpty) return '';

    final factualWindows =
        windows.where((window) => _canonFactScore(window.text) > 0).toList();
    final rankedWindows = factualWindows.isNotEmpty ? factualWindows : windows;
    rankedWindows.sort((a, b) => b.score.compareTo(a.score));

    final chosen = <String>[];
    final seen = <String>{};
    var totalLength = 0;
    var chosenWindows = 0;

    for (final window in rankedWindows) {
      var addedFromWindow = false;
      for (final fragment in _contextFragmentsAround(fragments, window.index)) {
        final key = _normalizeForDedupe(fragment);
        if (seen.contains(key)) continue;
        if (_isNoisyRawFragment(fragment)) continue;
        if (totalLength + fragment.length > maxLength && chosen.isNotEmpty) {
          continue;
        }
        seen.add(key);
        chosen.add(fragment);
        totalLength += fragment.length;
        addedFromWindow = true;
      }
      if (addedFromWindow) chosenWindows++;
      if (chosenWindows >= maxFragments || totalLength >= maxLength) break;
    }

    if (aspectTerms.isEmpty &&
        includeLeadingFacts &&
        totalLength < maxLength ~/ 2) {
      for (final fragment in _rawContentFragments(rawContent)) {
        if (_isNoisyRawFragment(fragment)) continue;
        if (_canonFactScore(fragment) <= 0) continue;

        final key = _normalizeForDedupe(fragment);
        if (seen.contains(key)) continue;
        if (totalLength + fragment.length > maxLength && chosen.isNotEmpty) {
          continue;
        }
        seen.add(key);
        chosen.add(fragment);
        totalLength += fragment.length;
        if (chosen.length >= 2 || totalLength >= maxLength ~/ 2) break;
      }
    }

    if (minLength > 0 && totalLength < minLength) {
      for (final fragment in _rawContentFragments(rawContent)) {
        if (_isNoisyRawFragment(fragment)) continue;
        if (aspectTerms.isNotEmpty &&
            !_canonFragmentMatchesAnyAspect(fragment, aspectTerms)) {
          continue;
        }
        if (anchorTerms.isNotEmpty &&
            !anchorTerms
                .any((term) => _canonTextContainsTerm(fragment, term))) {
          continue;
        }

        final key = _normalizeForDedupe(fragment);
        if (seen.contains(key)) continue;
        seen.add(key);

        if (totalLength + fragment.length > maxLength && chosen.isNotEmpty) {
          continue;
        }
        chosen.add(fragment);
        totalLength += fragment.length;
        if (totalLength >= minLength || totalLength >= maxLength) break;
      }
    }

    return _truncateSearchSnippet(chosen.join(' / '), maxLength: maxLength);
  }

  static List<String> _contextFragmentsAround(
    List<String> fragments,
    int index,
  ) {
    final start = index > 0 ? index - 1 : index;
    final end = index + 1 < fragments.length ? index + 1 : index;
    return fragments.sublist(start, end + 1);
  }

  static List<String> _snippetSearchTerms(String query) {
    final terms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .where((term) => !_canonQueryNoiseTerms.contains(term.toLowerCase()))
        .where((term) => !_isQuestionIntentTerm(term))
        .toSet()
        .toList();

    terms.sort((a, b) => b.length.compareTo(a.length));
    return terms.take(8).toList();
  }

  static String _focusedCanonSearchQuery(String query) {
    final rawTerms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .where((term) => !_canonQueryNoiseTerms.contains(term.toLowerCase()))
        .where((term) => !_isQuestionIntentTerm(term))
        .toList();
    if (rawTerms.isEmpty) return query.trim();

    final focus = _primaryCanonFocusTerm(query);
    final ordered = <String>[];
    if (focus.isNotEmpty) ordered.add(focus);
    for (final term in rawTerms) {
      if (term == focus) continue;
      if (ordered.contains(term)) continue;
      ordered.add(term);
      if (ordered.length >= 4) break;
    }

    return ordered.join(' ').trim();
  }

  static String _relatedCanonSearchQuery(String query, String relatedTerm) {
    final related = relatedTerm.trim();
    if (related.isEmpty || _canonTextContainsTerm(query, related)) return '';

    final focus = _primaryCanonFocusTerm(query);
    if (focus.isEmpty || focus == related) return '';

    final contextTerms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => _canonQueryContextTerms.contains(term.toLowerCase()))
        .toList();

    return _dedupeSearchQueryTerms(
      '$focus $related ${contextTerms.join(' ')}',
    );
  }

  static bool _canonResultMatchesQueryFocus(
    String title,
    String content,
    String query,
  ) {
    final focus = _primaryCanonFocusTerm(query);
    if (focus.isEmpty) return true;

    final titleMatchesFocus = _canonTitleMatchesFocus(title, focus);
    final combined = '$title $content';
    final contextTerms = _canonQueryContextTerms
        .where((term) => _canonTextContainsTerm(query, term))
        .toList();
    final focusIsShortCjk = RegExp(r'^[\u4e00-\u9fff]{1,2}$').hasMatch(focus);
    if (contextTerms.isNotEmpty &&
        (!titleMatchesFocus ||
            focusIsShortCjk ||
            RegExp(r'^[a-z0-9!★☆*._-]+$').hasMatch(focus)) &&
        !contextTerms.any((term) => _canonTextContainsTerm(combined, term))) {
      return false;
    }

    if (titleMatchesFocus) return true;

    final terms = _snippetSearchTerms(query);
    final matchedCount =
        terms.where((term) => _canonTextContainsTerm(combined, term)).length;
    final aspectTerms = terms.where(_isCanonAspectTerm).toList();
    if (aspectTerms.isNotEmpty &&
        !_canonFragmentMatchesAnyAspect(content, aspectTerms)) {
      return false;
    }

    // 标题没有对上主对象时，至少要有多个查询词共同命中正文，
    // 否则很容易把“别的角色页面里顺口提到目标地点/事件”的结果误收进来。
    return _canonTextContainsTerm(content, focus) && matchedCount >= 2;
  }

  static bool _isCanonAspectTerm(String term) {
    final normalized = term.toLowerCase().trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'原因|为什么|关系|人物关系|羁绊|救赎|相互救赎|经过|如何|怎么|'
      r'恢复|恢復|记忆|記憶|想起|喜欢|动物|食物|地点|地方|常去|歌曲|评价|'
      r'设定|性格|经历|剧情',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static bool _canonFragmentMatchesAnyAspect(
    String fragment,
    List<String> aspectTerms,
  ) {
    for (final term in aspectTerms) {
      if (_canonTextContainsTerm(fragment, term)) return true;
      if (term.contains('记忆') || term.contains('記憶')) {
        if (RegExp(r'记忆|記憶|想起|思い出|取り戻').hasMatch(fragment)) {
          return true;
        }
      }
      if (term.contains('恢复') || term.contains('恢復')) {
        if (RegExp(r'恢复|恢復|取回|想起|思い出|取り戻').hasMatch(fragment)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _canonTitleMatchesFocus(String title, String focus) {
    final normalizedTitle = _normalizeForDedupe(title);
    final normalizedFocus = _normalizeForDedupe(focus);
    if (normalizedFocus.isEmpty) return false;
    if (normalizedTitle == normalizedFocus) return true;

    final titleWithoutSource =
        normalizedTitle.replaceAll(RegExp(r'(萌娘百科|百度百科|维基百科|wiki)$'), '');
    if (titleWithoutSource == normalizedFocus) return true;

    final suffix = titleWithoutSource.startsWith(normalizedFocus)
        ? titleWithoutSource.substring(normalizedFocus.length)
        : '';
    return suffix.startsWith('（') || suffix.startsWith('(');
  }

  static String _primaryCanonFocusTerm(String query) {
    final rawTerms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .where((term) => !_canonQueryNoiseTerms.contains(term.toLowerCase()));

    for (final term in rawTerms) {
      if (_isQuestionIntentTerm(term)) continue;
      final possessivePrefix = _chinesePossessivePrefix(term);
      if (possessivePrefix.isNotEmpty) return possessivePrefix;
      return term;
    }
    return '';
  }

  static String _chinesePossessivePrefix(String term) {
    final index = term.indexOf('的');
    if (index < 2) return '';
    final prefix = term.substring(0, index).trim();
    if (prefix.length < 2) return '';
    if (_canonQueryNoiseTerms.contains(prefix.toLowerCase())) return '';
    return prefix;
  }

  static bool _isQuestionIntentTerm(String term) {
    final normalized = term.toLowerCase().trim();
    if (_canonQueryNoiseTerms.contains(normalized)) return true;
    if (RegExp(r'^[0-9一二三四五六七八九十百千万两]+[个位名只条本人种件]').hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  static List<String> _canonTargetAnchorTerms(String query, String title) {
    final candidates = _snippetSearchTerms(query)
        .where((term) => _looksLikeSpecificCanonTarget(term))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    if (candidates.isEmpty) return const [];

    final anchors = <String>[];
    for (final term in candidates) {
      if (anchors.any((existing) => _canonTextContainsTerm(existing, term))) {
        continue;
      }
      anchors.add(term);
      if (anchors.length >= 2) break;
    }

    return anchors;
  }

  static bool _looksLikeSpecificCanonTarget(String term) {
    final normalized = term.toLowerCase().trim();
    if (normalized.length < 2) return false;
    if (_canonQueryNoiseTerms.contains(normalized)) return false;
    if (RegExp(r'^[a-z0-9!★☆*]+$', caseSensitive: false).hasMatch(term)) {
      return term.length >= 5 &&
          !RegExp(r'bang|dream|mygo|ave|mujica', caseSensitive: false)
              .hasMatch(term);
    }
    return RegExp(r'[\u4e00-\u9fffぁ-んァ-ンー]').hasMatch(term);
  }

  static List<String> _rawContentFragments(String rawContent) {
    final fragments = <String>[];
    final pattern = RegExp(r'[^。！？!?；;\n]{12,180}[。！？!?；;]?');
    for (final match in pattern.allMatches(rawContent)) {
      final fragment = match.group(0)?.trim() ?? '';
      if (fragment.length >= 12) fragments.add(fragment);
    }
    return fragments;
  }

  static bool _isNoisyRawFragment(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 12) return true;
    if (_looksLikeGarbledText(normalized)) return true;
    if (_isRealWorldProductionFragment(normalized)) return true;
    return RegExp(
          r'广告|赞助|App|APP|下载|登录|注册|'
          r'编辑|目录|目次|导航|导航菜单|隐私|Cookie|页面|设置|链接|文件|引用|导出|打印'
          r'下载为PDF|可打印版|机械翻译|版权协议|讨论页|编辑摘要|Translated page|'
          r'action=edit|redlink=1|oldformat=true|请扩充此条目|'
          r'播放|弹幕|评论|分享|收藏|投币|点赞|更多|展开|收起|'
          r'新人成长|进阶成长|任务广场|百科|首页|权威合作|合作模式|常见问题|联系方式|个人中心'
          r'免责声明|版权所有|Copyright|Access Denied|Just a moment|'
          r'角色列表|其他登场乐团|主要角色的家人|其他人物|姓氏|'
          r'查·论·编|查论编|登场角色|主要角色|历代形象|注释|外部链接|图片|文件:|File:|'
          r'称呼一览|卡面|画廊|property=|og:title|Deutsch|English|'
          r'RLCONF|RLSTATE|RLPAGEMODULES|Jump to content|Toggle search|Toggle menu|'
          r'There is currently no text in this page|Retrieved from|wgPageName|wgTitle|'
          r'Song Information|Single Information|Digital Single Information|Album Information|'
          r'Tracklist|Release Date|Link Album|cite note|Creditless Opening Video|'
          r'二创|漫画|杂志|连载|视频|配音|声优|CV|PV|BD|OVA|发售|发布会|人气|角色荣誉'
          r'bkimg|bcebos|x-bce-process|image/format|f_auto|maxl_',
          caseSensitive: false,
        ).hasMatch(normalized) ||
        RegExp(r'\{\{[^}]{10,}\}\}|\{"[^"]+"\s*:|"wt"\s*:', dotAll: true)
            .hasMatch(normalized) ||
        RegExp(r'&[a-z]+;|&#\d+;', caseSensitive: false)
                .allMatches(normalized)
                .length >=
            2 ||
        RegExp(r'[{}"\[\]]').allMatches(normalized).length >= 12 ||
        RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(normalized) ||
        RegExp(r'https?://|]\(|#').hasMatch(normalized) ||
        '|'.allMatches(normalized).length >= 3 ||
        '/'.allMatches(normalized).length >= 5;
  }

  static bool _looksLikeGarbledText(String text) {
    final meaningful =
        RegExp(r'[\u4e00-\u9fffぁ-んァ-ンーA-Za-z0-9]').allMatches(text).length;
    if (meaningful == 0) return true;

    final mojibake =
        RegExp(r'[ȫջʩӡǾͳﲿݰչ̨ϸ˽ҵλĸ߶ϿɣƼݷ縺Ĺ廯硱༭]').allMatches(text).length;
    if (mojibake >= 8 && mojibake / meaningful > 0.18) return true;

    final replacement = '�'.allMatches(text).length;
    return replacement >= 3;
  }

  static bool _isRealWorldProductionFragment(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    final productionSignals = RegExp(
      r'导演|监督|監督|编剧|脚本|剧本|制作团队|制作组|制作委员会|制作人员|'
      r'企划|企画|策划|製作|制作|动画制作|游戏制作|原案|原作方|'
      r'采访|访谈|访問|透露|表示|指出|根据.*说法|'
      r'设定.*展开|角色设定|初期设定|初期剧情|故事走向|剧情方向|剧本内容|'
      r'集数|第\d+集|第\d+话|第\d+話|第一季|第二季|总集篇|剧场版|'
      r'播出|上映|发售|发行|发布|公开|宣传|商业|联动|活动|'
      r'现实世界|三次元|线下|举办|主办|巡演|舞台活动|见面会|'
      r'公司|出版社|唱片|事务所|声优|配音|演员|作词家|动画师|编曲|'
      r'\bwritten by\b|\blyricist\b|\bcomposer\b|\barranger\b|\bproducer\b|'
      r'\bcharts?\b|\baccolades?\b|\bcredits?\b|\bpersonnel\b|'
      r'\breleased?\b|\brelease\b|\bannounced\b|\blimited\b|\bblu-ray\b|'
      r'\bfirst print\b|\blottery\b|\btickets?\b|\brecorded footage\b|'
      r'参考了|创作|撰写|改写|重写|调整|构筑|企划中|企划里|跨媒体',
      caseSensitive: false,
    );
    if (!productionSignals.hasMatch(normalized)) return false;

    final inUniverseSignals = RegExp(
      r'学生|学校|学园|学園|年级|班|乐队|バンド|成员|所属|主唱|吉他手|鼓手|贝斯手|键盘手|'
      r'性格|兴趣|喜欢|讨厌|关系|青梅竹马|同学|会长|身份|经历|过去|现在|'
      r'歌词|作词|作曲|演奏|排练|Livehouse|livehouse',
      caseSensitive: false,
    );

    final productionMatches = productionSignals.allMatches(normalized).length;
    final inUniverseMatches = inUniverseSignals.allMatches(normalized).length;
    return productionMatches >= 2 || inUniverseMatches == 0;
  }

  static int _searchResultScore(
    String title,
    String content,
    List<String> terms,
  ) {
    final titleScore = _snippetScore(title, terms) * 3;
    final contentScore = _snippetScore(content, terms);
    return titleScore + contentScore;
  }

  static bool _canonFragmentHasRequiredEvidence(
    String fragment,
    String title,
    List<String> terms,
  ) {
    if (terms.isEmpty) return true;
    final combined = '$title $fragment';
    return terms.any((term) => _canonTextContainsTerm(combined, term));
  }

  static int _minimumCanonFragmentScore(List<String> terms) {
    if (terms.length <= 1) return 2;
    return 4;
  }

  static int _snippetScore(String text, List<String> terms) {
    var score = 0;
    for (final term in terms) {
      if (_canonTextContainsTerm(text, term)) {
        score += term.length >= 4 ? 3 : 2;
      }
    }
    return score + _canonFactScore(text);
  }

  static int _canonFactScore(String text) {
    var score = 0;
    final factPatterns = [
      RegExp(r'是由|是.*登场角色|登场角色|登場人物|角色之一'),
      RegExp(r'所属|成员|组合|团体|乐队|バンド|グループ'),
      RegExp(r'吉他手|主唱|鼓手|贝斯手|键盘手|作词|作曲|ボーカル|ギター|ドラム|ベース|キーボード'),
      RegExp(r'学生|生徒|年级|学校|学园|学園|高校|中学|大学'),
    ];
    for (final pattern in factPatterns) {
      if (pattern.hasMatch(text)) score += 3;
    }
    return score;
  }

  static const List<String> _trustedCanonDomains = [
    // 官方站
    'bang-dream.com',
    'anime.bang-dream.com',
    'bang-dream.bushimo.jp',
    'bushiroad-music.com',
    'bandori.party',
    'bandori.miraheze.org',
    'kimetsu.com',
    // 成熟百科 / wiki
    'wikipedia.org',
    'fandom.com',
    'moegirl.org',
    'moegirl.org.cn',
    'zh.moegirl.org.cn',
    'baike.baidu.com',
    'wapbaike.baidu.com',
  ];

  static int _maxResultsForCategory(String category) {
    if (category == 'economy') return 5;
    if (category == 'canon') return 4;
    return 4;
  }

  static String _stripSearchIndex(String text) {
    return text.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '');
  }

  static bool _isTrustedCanonResultDomain(String domain) {
    final normalized = domain.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
    if (normalized.isEmpty) return false;
    if (_isUnwantedSearchMirrorDomain(normalized)) return false;
    return _trustedCanonDomains.any(
        (trusted) => normalized == trusted || normalized.endsWith('.$trusted'));
  }

  static bool _isUnwantedSearchMirrorDomain(String domain) {
    final normalized = domain.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
    return normalized.endsWith('moegirl.tw') ||
        normalized == 'mobile.moegirl.org.cn' ||
        normalized == 'mzh.moegirl.org.cn';
  }

  static bool _isUnwantedSearchResultUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
    if (host == 'tw' || host.endsWith('.tw')) return true;
    if (_isUnwantedSearchMirrorDomain(host)) return true;
    if (host.startsWith('wenku.') || host == 'wenku.csdn.net') return true;
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();
    if (RegExp(r'/(zh-tw|zh-hant|zh-hk)(/|$)').hasMatch(path) ||
        RegExp(r'(?:^|[?&;])variant=zh-(?:tw|hant|hk)(?:$|[&;])')
            .hasMatch(query)) {
      return true;
    }
    return host.endsWith('moegirl.org.cn') &&
        (RegExp(r'/(zh-tw|zh-hant|zh-hk)(/|$)').hasMatch(path) ||
            RegExp(r'(?:^|[?&;])variant=zh-(?:tw|hant|hk)(?:$|[&;])')
                .hasMatch(query));
  }

  static bool _canonTextContainsTerm(String text, String term) {
    final normalizedText = _normalizeForDedupe(text);
    final normalizedTerm = _normalizeForDedupe(term);
    if (normalizedTerm.isEmpty) return false;
    return normalizedText.contains(normalizedTerm);
  }

  static String _normalizeForDedupe(String text) {
    return text
        .toLowerCase()
        .replaceAll('蝴蝶', '胡蝶')
        .replaceFirst(RegExp(r'\s*[-－—|｜].*(萌娘百科|wiki|wikipedia|fandom).*'), '')
        .replaceAll(RegExp(r'[\s\-_｜|:：,，.。#]+'), '')
        .trim();
  }

  static Future<_SearchResultCandidate> _fetchReadableCanonCandidate(
    _SearchResultCandidate candidate,
    String query,
  ) async {
    try {
      final uri = Uri.tryParse(candidate.url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return candidate;
      }
      if (_isUnwantedSearchResultUrl(candidate.url)) {
        return _SearchResultCandidate(
          title: candidate.title,
          content: '',
          url: candidate.url,
          score: 0,
        );
      }

      final requestUri = _isMoegirlUrl(candidate.url)
          ? _moegirlSimplifiedUri(uri)
          : _isBaiduBaikeUrl(candidate.url)
              ? _baiduBaikeReadableUri(uri)
              : uri;
      final response = await http
          .get(
            requestUri,
            headers: _browserSearchHeaders,
          )
          .timeout(_searchTimeout);
      if (response.statusCode != 200) return candidate;

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final isMoegirl = _isMoegirlUrl(requestUri.toString());
      final pageText = isMoegirl
          ? _preferredMoegirlSectionText(html)
          : _cleanExternalCanonRawText(html, candidate.url);
      final focusTerm = _primaryCanonFocusTerm(query);
      final isFocusedTitle = focusTerm.isNotEmpty &&
          _canonTitleMatchesFocus(candidate.title, focusTerm);
      final targetAnchors = _canonTargetAnchorTerms(query, candidate.title);
      var pageSnippet = _relevantRawSnippet(
        pageText,
        query,
        candidate.title,
        maxLength:
            isMoegirl || _isBaiduBaikeUrl(requestUri.toString()) ? 1200 : 650,
        maxFragments:
            isMoegirl || _isBaiduBaikeUrl(requestUri.toString()) ? 6 : 3,
        includeLeadingFacts: isMoegirl,
        minLength: isMoegirl ? 800 : 200,
        anchorTerms: isMoegirl && !isFocusedTitle && focusTerm.isNotEmpty
            ? [focusTerm]
            : targetAnchors,
      );
      if (pageSnippet.isEmpty && !isMoegirl) {
        pageSnippet = _relevantRawSnippet(
          pageText,
          query,
          candidate.title,
          maxLength: 650,
          maxFragments: 3,
          minLength: 200,
        );
      }
      if (pageSnippet.isEmpty) {
        return _SearchResultCandidate(
          title: candidate.title,
          content: '',
          url: requestUri.toString(),
          score: 0,
        );
      }

      final content = '相关正文：$pageSnippet';
      return _SearchResultCandidate(
        title: candidate.title,
        content: content,
        url: requestUri.toString(),
        score: _searchResultScore(
          candidate.title,
          content,
          _snippetSearchTerms(query),
        ),
      );
    } catch (e) {
      debugPrint('直达结果正文抓取失败: ${candidate.url} $e');
      return candidate;
    }
  }

  static List<String> _formatSearchCandidates(
    List<_SearchResultCandidate> candidates,
    String category,
  ) {
    final sorted = category == 'canon'
        ? ([...candidates]..sort((a, b) => b.score.compareTo(a.score)))
        : candidates;
    final results = <String>[];

    for (final candidate in sorted) {
      if (candidate.title.isEmpty && candidate.content.isEmpty) continue;
      final snippet = _truncateSearchSnippet(
        candidate.content,
        maxLength: category == 'canon' ? 1200 : 220,
      );
      final source = candidate.url.isEmpty ? '' : '（来源：${candidate.url}）';
      results.add('${results.length + 1}. ${candidate.title}：$snippet$source');
      if (results.length >= _maxResultsForCategory(category)) break;
    }

    return results;
  }

  static String _domainFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    return host.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
  }

  static bool _isMoegirlUrl(String url) {
    final domain = _domainFromUrl(url);
    return domain.endsWith('moegirl.org.cn') ||
        domain.endsWith('moegirl.org') ||
        domain.endsWith('moegirl.tw');
  }

  static Uri _moegirlSimplifiedUri(Uri uri) {
    final params = Map<String, String>.from(uri.queryParameters);
    params['variant'] = 'zh-cn';

    var path = uri.path;
    path = path.replaceFirst(RegExp(r'^/(zh-cn|zh-hans)(?=/|$)'), '');
    if (path.isEmpty) path = '/';

    return uri.replace(
      scheme: 'https',
      host: 'zh.moegirl.org.cn',
      path: path,
      queryParameters: params,
    );
  }

  // Open-Meteo 返回的是天气代码，这里把代码翻译成人话。
  static String _weatherCodeText(dynamic codeValue) {
    final code = codeValue is num ? codeValue.toInt() : -1;
    if (code == 0) return '晴';
    if (code == 1) return '基本晴朗';
    if (code == 2) return '局部多云';
    if (code == 3) return '阴天';
    if ([45, 48].contains(code)) return '有雾';
    if ([51, 53, 55, 56, 57].contains(code)) return '毛毛雨';
    if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) return '有雨';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return '有雪';
    if ([95, 96, 99].contains(code)) return '雷雨';
    return '天气状况不明';
  }

  static bool _isPrecipitatingCode(dynamic codeValue) {
    final code = codeValue is num ? codeValue.toInt() : -1;
    return [
      51,
      53,
      55,
      56,
      57,
      61,
      63,
      65,
      66,
      67,
      71,
      73,
      75,
      77,
      80,
      81,
      82,
      85,
      86,
      95,
      96,
      99,
    ].contains(code);
  }

  static bool _isPositiveNumber(dynamic value) {
    return value is num && value > 0;
  }

  static bool _isPositiveNumberString(dynamic value) {
    if (value is num) return value > 0;
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed > 0;
    }
    return false;
  }

  static bool _weatherTextMentionsPrecipitation(String text) {
    return RegExp(r'雨|雪|雷|阵雨|雷阵雨|降水|冰雹').hasMatch(text);
  }

  // 搜索摘要只需要给模型“够用的事实线索”，不需要整段网页。
  // 这里限制长度，可以省 token，也能减少网页里无关内容干扰角色回复。
  static String _truncateSearchSnippet(String text, {int maxLength = 220}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  static String _cleanExternalCanonRawText(String text, String url) {
    if (_isBaiduBaikeUrl(url)) {
      final baiduText = _extractBaiduBaikeReadableText(text);
      if (baiduText.isNotEmpty) return baiduText;
    }

    var cleaned = _stripGenericArticleUiHtml(text);
    cleaned = _cleanCanonRawText(cleaned);

    if (_isWikipediaUrl(url)) {
      cleaned = _cleanWikipediaContentText(cleaned);
    } else if (_isFandomUrl(url)) {
      cleaned = _cleanFandomContentText(cleaned);
    } else if (_isBaiduBaikeUrl(url)) {
      cleaned = _cleanBaiduBaikeContentText(cleaned);
    }

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isWikipediaUrl(String url) {
    return _domainFromUrl(url).endsWith('wikipedia.org');
  }

  static bool _isFandomUrl(String url) {
    return _domainFromUrl(url).endsWith('fandom.com');
  }

  static bool _isBaiduBaikeUrl(String url) {
    final domain = _domainFromUrl(url);
    return domain == 'baike.baidu.com' || domain == 'wapbaike.baidu.com';
  }

  static Uri _baiduBaikeReadableUri(Uri uri) {
    if (uri.host == 'wapbaike.baidu.com') return uri;
    return uri.replace(
      scheme: 'https',
      host: 'wapbaike.baidu.com',
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
  }

  static String _stripGenericArticleUiHtml(String html) {
    return html
        .replaceAll(
            RegExp(r'<script.*?</script>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<style.*?</style>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<nav.*?</nav>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<header.*?</header>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<footer.*?</footer>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<figure.*?</figure>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<aside.*?</aside>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'<table[^>]*(?:infobox|navbox|toc|metadata|ambox|vertical-navbox|sidebar)[^>]*>.*?</table>',
                dotAll: true,
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'<div[^>]*(?:toc|navbox|metadata|reference|references|mw-editsection|printfooter|catlinks|portal|thumb|gallery|advert|ads|footer|header|sidebar)[^>]*>.*?</div>',
                dotAll: true,
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<ol[^>]*(?:references|mw-references)[^>]*>.*?</ol>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<sup[^>]*(?:reference|noprint)[^>]*>.*?</sup>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), ' ');
  }

  static String _cleanWikipediaContentText(String text) {
    return text
        .replaceAll(RegExp(r'下载为PDF\s*可打印版'), ' ')
        .replaceAll(RegExp(r'请勿直接提交机械翻译[^。]*。'), ' ')
        .replaceAll(RegExp(r'依版权协议[^。]*。'), ' ')
        .replaceAll(RegExp(r'请扩充此条目相关信息[^。]*。'), ' ')
        .replaceAll(RegExp(r'Translated page'), ' ')
        .replaceAll(RegExp(r'摘要注明来源|讨论页顶部标记|编辑摘要'), ' ')
        .replaceAll(RegExp(r'相关正文：'), ' ')
        .replaceAll(RegExp(r'\baction=edit\b|\bredlink=1\b'), ' ')
        .replaceAll(RegExp(r'\[\s*\d+\s*\]'), ' ')
        .replaceAll(RegExp(r'\[[^\]]{0,16}编辑[^\]]{0,16}\]'), ' ')
        .replaceAll(RegExp(r'#{1,6}\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanFandomContentText(String text) {
    return text
        .replaceAll(RegExp(r'Fandom Apps|Take your favorite fandoms.*?go'), ' ')
        .replaceAll(
            RegExp(r'Explore properties|Community content.*?CC-BY-SA'), ' ')
        .replaceAll(
            RegExp(r'Advertisement|Fan Feed', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanBaiduBaikeContentText(String text) {
    return text
        .replaceAll(RegExp(r'百度百科[^。]*'), ' ')
        .replaceAll(RegExp(r'播报|编辑|收藏|点赞|分享'), ' ')
        .replaceAll(RegExp(r'图集|概述图册|参考资料'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _extractBaiduBaikeReadableText(String html) {
    final values = <String>[];

    void addValue(String value) {
      final cleaned = _cleanBaiduBaikeContentText(_cleanHtml(value));
      if (cleaned.length < 2 || values.contains(cleaned)) return;
      if (_isRealWorldProductionFragment(cleaned)) return;
      values.add(cleaned);
    }

    final metaPatterns = [
      RegExp(r'<meta[^>]+name="description"[^>]+content="([^"]+)"',
          caseSensitive: false),
      RegExp(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"',
          caseSensitive: false),
      RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false),
    ];
    for (final pattern in metaPatterns) {
      final match = pattern.firstMatch(html);
      if (match != null) addValue(match.group(1) ?? '');
    }

    final paragraphPattern = RegExp(
      r'<div[^>]+data-tag="paragraph"[^>]*>(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in paragraphPattern.allMatches(html)) {
      addValue(match.group(1) ?? '');
    }

    return values.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _cleanCanonRawText(String text) {
    var cleaned = _stripMarkdownAndUrlResidue(text);
    cleaned = _cleanHtml(cleaned);
    cleaned = cleaned
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'\S*%[0-9A-Fa-f]{2}\S*'), ' ')
        .replaceAll(RegExp(r'(?:^|\s)/[A-Za-z0-9_~!%.,;:+?=&@#\-/]+'), ' ')
        .replaceAll(RegExp(r'\[\s*\d+\s*\]'), ' ')
        .replaceAll(RegExp(r'\[[^\]]{0,16}编辑[^\]]{0,16}\]'), ' ')
        .replaceAll(
            RegExp(r'\b(?:action=edit|redlink=1|oldformat=true)\b'), ' ')
        .replaceAll(RegExp(r'&action=edit[^ ]*'), ' ')
        .replaceAll(
            RegExp(
                r'(?:bkimg|bcebos|x-bce-process|image/format|f_auto|maxl_)\S*',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[#*_`]+'), ' ')
        .replaceAll(RegExp(r'\s*[+*]\s+'), ' ')
        .replaceAll(RegExp(r'\|{2,}|-{3,}'), ' ')
        .replaceAll(RegExp(r'目次|目录|编辑|导航|外部链接|参考资料'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static String _stripMarkdownAndUrlResidue(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]{0,120})\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\[([^\]]{0,120})\]'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\([^)]*%[0-9A-Fa-f]{2}[^)]*\)'), ' ')
        .replaceAll(RegExp(r'"[^"]*%[0-9A-Fa-f]{2}[^"]*"'), ' ')
        .replaceAll(RegExp(r'\S*%[0-9A-Fa-f]{2}\S*'), ' ');
    return cleaned;
  }

  static const List<String> _preferredMoegirlSectionTitles = [
    '基本资料',
    '基本資料',
    '简介',
    '经历',
    '人际关系',
    '能力',
    '轶事',
    '余谈',
    '餘談',
  ];

  static String _preferredMoegirlSectionText(String rawText) {
    if (rawText.trim().isEmpty) return '';

    final structuralText = _stripMoegirlUiHtml(rawText);
    final profileText = _preferredMoegirlProfileText(rawText);
    final htmlSections = _preferredMoegirlHtmlSections(structuralText);
    if (htmlSections.isNotEmpty) {
      return [
        if (profileText.isNotEmpty) profileText,
        ...htmlSections,
      ].join(' ');
    }

    final plainSections = _preferredMoegirlPlainTextSections(structuralText);
    return [
      if (profileText.isNotEmpty) profileText,
      ...plainSections,
    ].join(' ');
  }

  static String _preferredMoegirlProfileText(String rawText) {
    final titleMatches = [
      RegExp(r'基本资料', caseSensitive: false).firstMatch(rawText),
      RegExp(r'基本資料', caseSensitive: false).firstMatch(rawText),
    ].whereType<Match>().toList();
    if (titleMatches.isEmpty) return '';
    titleMatches.sort((a, b) => a.start.compareTo(b.start));

    final start = titleMatches.first.start;
    var end = rawText.length;
    final nextHeading = RegExp(r'<h[2-4][^>]*>', caseSensitive: false)
        .firstMatch(rawText.substring(start));
    if (nextHeading != null) end = start + nextHeading.start;
    final segment = rawText.substring(start, end);
    final fieldText = _moegirlProfileFieldText(segment);
    if (fieldText.runes.length >= 20) return _shortenRunes(fieldText, 1800);

    final cleaned = _cleanCanonRawText(segment);
    if (cleaned.runes.length < 20) return '';
    return _shortenRunes(cleaned, 1800);
  }

  static String _moegirlProfileFieldText(String html) {
    final fields = <String>[];

    void addField(String labelHtml, String valueHtml) {
      final label = _cleanHtml(labelHtml);
      final value = _cleanHtml(valueHtml);
      if (label.isEmpty || value.isEmpty) return;
      final compactLabel = label.replaceAll(RegExp(r'\s+'), '');
      final compactValue = value.replaceAll(RegExp(r'\s+'), '');
      if (compactLabel.isEmpty || compactValue.isEmpty) return;
      final line = '$compactLabel：$compactValue。';
      if (!fields.contains(line)) fields.add(line);
    }

    final flexRowPattern = RegExp(
      r'<div[^>]*display:\s*flex;[^>]*margin:\s*3px 0;[^>]*>\s*'
      r'<div[^>]*>\s*(?:<span[^>]*>)?(.*?)(?:</span>)?\s*</div>\s*'
      r'<div[^>]*>\s*(.*?)\s*</div>\s*</div>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in flexRowPattern.allMatches(html)) {
      addField(match.group(1) ?? '', match.group(2) ?? '');
    }

    final blockTitlePattern = RegExp(
      r'<div[^>]*font-weight:\s*bold[^>]*text-align:\s*center[^>]*>\s*'
      r'(?!<span>)(.*?)</div>\s*'
      r'<div[^>]*padding:\s*0 2px 0 7px;[^>]*>\s*(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in blockTitlePattern.allMatches(html)) {
      addField(match.group(1) ?? '', match.group(2) ?? '');
    }

    if (fields.isEmpty) return '';
    return _cleanCanonRawText(fields.join(' '));
  }

  static List<String> _preferredMoegirlHtmlSections(String rawText) {
    final headingPattern = RegExp(
      r'<h([2-4])[^>]*>.*?</h[2-4]>',
      dotAll: true,
      caseSensitive: false,
    );
    final headings = headingPattern.allMatches(rawText).toList();
    if (headings.isEmpty) return [];

    final sections = <String>[];
    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final headingText = _cleanHtml(heading.group(0) ?? '');
      if (!_isPreferredMoegirlSectionTitle(headingText)) continue;

      final headingLevel = int.tryParse(heading.group(1) ?? '') ?? 2;
      final start = heading.end;
      var end = rawText.length;
      for (var j = i + 1; j < headings.length; j++) {
        final nextLevel = int.tryParse(headings[j].group(1) ?? '') ?? 2;
        if (nextLevel <= headingLevel) {
          end = headings[j].start;
          break;
        }
      }
      if (end <= start) continue;

      final section = _cleanMoegirlContentText(rawText.substring(start, end));
      if (section.isNotEmpty) sections.add(section);
    }

    return sections;
  }

  static List<String> _preferredMoegirlPlainTextSections(String rawText) {
    final cleaned = _cleanMoegirlContentText(rawText);
    if (cleaned.isEmpty) return [];

    final sections = <String>[];
    for (final title in _preferredMoegirlSectionTitles) {
      final match = RegExp('(?:^|\\s)${RegExp.escape(title)}(?:\\s|\$)')
          .firstMatch(cleaned);
      if (match == null) continue;

      final start = match.end;
      if (start >= cleaned.length) continue;

      final end = _nextMoegirlSectionBoundary(cleaned, start);
      final section = cleaned.substring(start, end).trim();
      if (section.isEmpty) continue;
      sections
          .add(section.length > 1200 ? section.substring(0, 1200) : section);
    }

    return sections;
  }

  static bool _isPreferredMoegirlSectionTitle(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    return _preferredMoegirlSectionTitles.any(normalized.contains);
  }

  static const List<String> _blockedMoegirlSectionTitles = [
    '目录',
    '查·论·编',
    '查论编',
    '注释',
    '人气',
    '历代形象',
    '称呼一览',
    '漫画',
    '图片',
    '画廊',
    '卡面',
    '外部链接',
    '参考资料',
    '导航',
  ];

  static String _stripMoegirlUiHtml(String html) {
    return html
        .replaceAll(
            RegExp(r'<script.*?</script>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<style.*?</style>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<nav.*?</nav>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<figure.*?</figure>', dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<gallery.*?</gallery>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'<table[^>]*(?:navbox|toc|metadata|ambox|vertical-navbox)[^>]*>.*?</table>',
                dotAll: true,
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'<div[^>]*(?:toc|navbox|metadata|mw-references-wrap|reference|thumb|gallery|notice|infotemplatebox)[^>]*>.*?</div>',
                dotAll: true,
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<sup[^>]*(?:reference|noprint)[^>]*>.*?</sup>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), ' ');
  }

  static String _cleanMoegirlContentText(String text) {
    var cleaned = _cleanCanonRawText(_stripMoegirlUiHtml(text));
    cleaned = cleaned
        .replaceAll(
            RegExp(r'查\s*[·・･]?\s*论\s*[·・･]?\s*编.*$', dotAll: true), ' ')
        .replaceAll(RegExp(r'Live House CiRCLE.*?祝您在萌娘百科度过愉快的时光。'), ' ')
        .replaceAll(RegExp(r'欢迎正在阅读.*?协助[^。]*。'), ' ')
        .replaceAll(RegExp(r'编辑前请阅读[^。]*。'), ' ')
        .replaceAll(RegExp(r'诚邀各位加入[^。]*。'), ' ')
        .replaceAll(RegExp(r'(?:文件|File):\S+'), ' ')
        .replaceAll(
            RegExp(r'\.(?:jpg|jpeg|png|gif|webp|svg)', caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static int _nextMoegirlSectionBoundary(String text, int start) {
    var end = text.length;
    final sectionTitles = [
      ..._preferredMoegirlSectionTitles,
      ..._blockedMoegirlSectionTitles,
    ];
    for (final title in sectionTitles) {
      final match = RegExp('(?:^|\\s)${RegExp.escape(title)}(?:\\s|\$)')
          .firstMatch(text.substring(start));
      if (match == null || match.start == 0) continue;
      final absoluteStart = start + match.start;
      if (absoluteStart < end) end = absoluteStart;
    }
    return end;
  }

  // 把数字格式化得好看一点：
  // 23.0 -> 23
  // 23.6 -> 23.6
  static String _formatNumber(dynamic value) {
    if (value is num) return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return '?';
  }

  // 去掉网页 HTML 标签，只留下可读文字。
  static String _cleanHtml(String html) {
    final withoutTags = html
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeHtml(withoutTags).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // 把常见 HTML 实体还原：
  // &amp; -> &
  // &quot; -> "
  // &#123; -> 对应字符
  static String _decodeHtml(String text) {
    var decoded = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    decoded = decoded.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1) ?? '');
      if (codePoint == null) return match.group(0) ?? '';
      return String.fromCharCode(codePoint);
    });

    return decoded;
  }
}

// ========================================
// 搜索计划数据结构
// ========================================
// 它表示“这条用户消息到底要不要补充外部信息”。
//
// 例子：
// 用户：“你那边外面冷吗？”
// _SearchPlan(
//   includeWeather: true,
//   weatherCity: '东京',
//   includeFestivals: false,
//   includePhenology: true,
//   searchQuery: null,
//   category: 'weather',
// )
//
// 用户：“她后来和灯怎么样了？”
// _SearchPlan(
//   includeWeather: false,
//   includeFestivals: false,
//   includePhenology: false,
//   searchQuery: 'BanG Dream Ave Mujica 丰川祥子 灯 后来 关系',
//   category: 'canon',
// )
class _SearchPlan {
  // 是否需要查实时天气。
  final bool includeWeather;

  // 天气城市。为空时用角色默认城市。
  final String? weatherCity;

  // 是否需要加入近期节日。
  final bool includeFestivals;

  // 是否需要查真实物候。
  final bool includePhenology;

  // 网页搜索词。为空表示不进行网页搜索。
  final String? searchQuery;

  // 搜索类别，用来做角色权限过滤。
  // 常见值：none / weather / festival / canon / slang / economy / current / general
  final String category;

  // strict_fact：最终结论必须由资料直接支持。
  // bounded_roleplay：资料限定真实候选，角色可在边界内自然表达主观选择。
  final String answerMode;

  // 描述需要网页回答的独立问项及其完整命题关系，不预判网页是否有答案。
  final List<_AnswerRequirement> answerRequirements;

  final List<String> primarySearchObjects;
  final List<String> secondarySearchObjects;

  const _SearchPlan({
    required this.includeWeather,
    required this.weatherCity,
    required this.includeFestivals,
    required this.includePhenology,
    required this.searchQuery,
    required this.category,
    this.answerMode = WebContextService._answerModeStrictFact,
    this.answerRequirements = const [],
    this.primarySearchObjects = const [],
    this.secondarySearchObjects = const [],
  });

  // 没有任何任务时，buildContext 可以直接返回空字符串。
  bool get hasAnyTask =>
      includeWeather ||
      includeFestivals ||
      includePhenology ||
      (searchQuery != null && searchQuery!.isNotEmpty);
}

class _AnswerRequirement {
  final String text;
  final List<String> directEvidenceCues;

  const _AnswerRequirement({
    required this.text,
    this.directEvidenceCues = const [],
  });
}

enum _FestivalScope {
  kimetsuTaishoJapan,
  modernJapanNonPolitical,
  chinaInternational,
  internationalOnly,
}

// ========================================
// 单个角色的联网权限配置
// ========================================
// 你以后如果想改“某个角色能查什么”，主要就改这个类下面的
// _WebProfile.forCharacter()。
//
// 设计思路：
// 不同角色不应该共享同一套现实信息。
// 比如：
// - 鬼灭角色生活在日本背景里，不应该突然懂中国股市。
// - 祥子在东京，知道日本/国际节日就够了，不需要经济行情。
// - 安迪是现代上海金融精英，所以经济、新闻、书、天气都可以查。
class _WebProfile {
  // characterId 来自 character_config.dart，比如 shinobu / sakiko / andy。
  final String characterId;

  // 当前角色所属作品/番剧名。
  // 节日搜索和本地兜底列表必须按这个字段划分，而不是按角色名划分。
  final String seriesName;

  // 角色显示名，比如 蝴蝶忍 / 丰川祥子 / 安迪。
  // 主要用于拼搜索词。
  final String characterName;

  // 默认天气查询城市。
  // 鬼灭用东京作为日本现实天气参考，祥子是东京，安迪是上海。
  final String weatherCity;

  // 物候搜索地区。
  // 可以比天气城市更宽，比如鬼灭用“日本 东京”，方便搜到日本季节景物。
  final String phenologyRegion;

  // 搜原作/剧情时使用的作品前缀。
  // 注意这里不放当前聊天角色名，否则问别的角色时会把搜索结果带偏。
  final String canonSearchPrefix;

  // 搜“最近/新闻/热点”时附加的地区提示。
  // 祥子偏日本，安迪偏中国。
  final String searchRegionHint;

  // 是否允许查天气。
  final bool includeWeather;

  // 是否允许加入节日信息。
  final bool includeFestivals;

  // 节日范围。
  // 这是“按作品名划分节日逻辑”的核心字段。
  final _FestivalScope festivalScope;

  // 是否允许查物候信息。
  final bool includePhenology;

  // 是否允许经济金融搜索。
  // 当前只有安迪是 true。
  final bool allowEconomySearch;

  // 是否“只允许原作搜索”。
  // 鬼灭角色是 true，用来阻止它们搜现代新闻/网络热梗/经济等。
  final bool onlyCanonSearch;

  // 是否允许用户指定天气城市。
  // 安迪是 true，所以你问“北京天气”她会查北京。
  // 祥子/鬼灭是 false，所以无论你提什么城市，都按东京查。
  final bool allowUserWeatherCity;

  final bool preferMoegirlCanonSearch;

  // 给 DeepSeek 看的角色联网范围说明。
  // 即使前面已经限制了搜索，这里再提醒模型一次，避免它自由发挥串台。
  String get contextRule {
    if (seriesName == '鬼灭之刃') {
      return '【角色联网范围】只使用日本天气、大正时期已存在的日本民俗/季节行事和《鬼灭之刃》原作/剧情资料。天气查询地点只是现实数据参考，不代表原作角色所在地。';
    }
    if (seriesName == 'BanG Dream') {
      return '【角色联网范围】使用东京天气、现代日本非政治节日/行事、国际节日、网络流行语、书影音和 BanG Dream/Ave Mujica 的作品内资料。不得使用现实企划、商业运营、现实活动安排或官方运营日程等三次元信息。';
    }
    if (seriesName == '欢乐颂') {
      return '【角色联网范围】使用上海天气、中国节日、国际节日、经济金融、书影音、网络热点和《欢乐颂》相关资料。角色表达偏理性克制，对年轻人娱乐和二次元流行语不要默认她非常熟，但也不要把她写成完全不懂。';
    }
    return '【角色联网范围】只使用与当前对话直接相关的现实信息，不要主动扩展到经济金融或无关新闻。';
  }

  String get weatherContextName {
    if (seriesName == '鬼灭之刃') return '日本现实天气参考';
    return weatherCity;
  }

  String get weatherSpeechRule {
    if (seriesName == '鬼灭之刃') {
      return '东京只是查询现实天气用的参考点，不是《鬼灭之刃》故事地点。回复时禁止说“东京”“東京”“东京都”或任何具体城市；只能说“こちら”“この辺り”“蝶屋のあたり”“山のほう”等模糊地点。';
    }
    return '';
  }

  // 普通构造函数：只是把上面的配置字段存起来。
  const _WebProfile({
    required this.characterId,
    required this.seriesName,
    required this.characterName,
    required this.weatherCity,
    required this.phenologyRegion,
    required this.canonSearchPrefix,
    required this.searchRegionHint,
    required this.includeWeather,
    required this.includeFestivals,
    required this.festivalScope,
    required this.includePhenology,
    required this.allowEconomySearch,
    required this.onlyCanonSearch,
    required this.allowUserWeatherCity,
    required this.preferMoegirlCanonSearch,
  });

  // ========================================
  // 按角色 id 选择联网配置
  // ========================================
  // 这里是最重要、也最适合你以后自己改的地方。
  //
  // 如果你之后新增角色，例如 id: 'new_character'：
  // 可以仿照 sakiko 或 andy 再加一个 if 分支。
  factory _WebProfile.forCharacter({
    required String characterId,
    required String characterName,
  }) {
    final seriesName = _seriesNameForCharacterId(characterId);

    if (seriesName == '鬼灭之刃') {
      // 鬼灭角色：
      // - 固定用东京查询天气，代表日本现实天气参考，但回复不能说东京
      // - 节日只知道大正时期已经存在的日本民俗/季节行事
      // - 网页搜索只搜《鬼灭之刃》原作/剧情资料
      // - 不允许经济、国际节日、网络热点
      return _WebProfile(
        characterId: characterId,
        seriesName: seriesName,
        characterName: characterName,
        weatherCity: '东京',
        phenologyRegion: '日本 东京',
        canonSearchPrefix: '鬼灭之刃',
        searchRegionHint: '日本',
        includeWeather: true,
        includeFestivals: true,
        festivalScope: _FestivalScope.kimetsuTaishoJapan,
        includePhenology: true,
        allowEconomySearch: false,
        onlyCanonSearch: true,
        allowUserWeatherCity: false,
        preferMoegirlCanonSearch: true,
      );
    }

    if (seriesName == 'BanG Dream') {
      // BanG Dream 角色：
      // - 固定东京天气
      // - 现代日本非政治节日/行事 + 国际节日
      // - 允许搜网络流行语、书影音、BanG Dream/Ave Mujica 资料
      // - 不允许经济金融搜索
      return _WebProfile(
        characterId: characterId,
        seriesName: seriesName,
        characterName: characterName,
        weatherCity: '东京',
        phenologyRegion: '东京',
        canonSearchPrefix: 'BanG Dream',
        searchRegionHint: '日本',
        includeWeather: true,
        includeFestivals: true,
        festivalScope: _FestivalScope.modernJapanNonPolitical,
        includePhenology: true,
        allowEconomySearch: false,
        onlyCanonSearch: false,
        allowUserWeatherCity: false,
        preferMoegirlCanonSearch: true,
      );
    }

    if (seriesName == '欢乐颂') {
      // 欢乐颂角色：
      // - 默认上海天气
      // - 允许用户问其他城市天气
      // - 中国节日 + 国际节日
      // - 允许经济、金融、新闻、书影音、原剧资料等完整搜索
      // - 角色口味偏高知和理性，不把自己写成很懂年轻人娱乐圈/二次元圈的“懂王”
      return _WebProfile(
        characterId: characterId,
        seriesName: seriesName,
        characterName: characterName,
        weatherCity: '上海',
        phenologyRegion: '上海',
        canonSearchPrefix: '欢乐颂',
        searchRegionHint: '中国',
        includeWeather: true,
        includeFestivals: true,
        festivalScope: _FestivalScope.chinaInternational,
        includePhenology: true,
        allowEconomySearch: true,
        onlyCanonSearch: false,
        allowUserWeatherCity: true,
        preferMoegirlCanonSearch: false,
      );
    }

    // 兜底规则：
    // 如果以后新增角色但忘记单独配置，就走这里。
    // 默认比较保守：允许天气和国际节日，不主动查经济金融。
    return _WebProfile(
      characterId: characterId,
      seriesName: seriesName,
      characterName: characterName,
      weatherCity: '上海',
      phenologyRegion: '上海',
      canonSearchPrefix: characterName,
      searchRegionHint: '',
      includeWeather: true,
      includeFestivals: true,
      festivalScope: _FestivalScope.internationalOnly,
      includePhenology: true,
      allowEconomySearch: false,
      onlyCanonSearch: false,
      allowUserWeatherCity: true,
      preferMoegirlCanonSearch: false,
    );
  }

  static String _seriesNameForCharacterId(String characterId) {
    const seriesByCharacterId = {
      'shinobu': '鬼灭之刃',
      'muichirou': '鬼灭之刃',
      'giyu': '鬼灭之刃',
      'sakiko': 'BanG Dream',
      'tomori': 'BanG Dream',
      'andy': '欢乐颂',
    };

    return seriesByCharacterId[characterId] ?? '未分类';
  }
}

// 一个简单的数据结构，保存天气 API 查询前需要用到的地理信息。
// 天气接口通常不直接接受“东京/上海”这样的文字城市名，
// 所以前面会先把城市名转换成经纬度，再把经纬度传给天气接口。
class _WeatherLocation {
  final String name;
  final double latitude;
  final double longitude;

  // 百度天气国内/海外是两个不同接口。
  // true：走 /weather_abroad/v1/，例如东京。
  // false：走 /weather/v1/，例如上海。
  final bool isBaiduAbroad;

  const _WeatherLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.isBaiduAbroad,
  });
}

// 原作网页正文里可能有很多段，先把命中搜索词附近的片段打分，
// 再挑最相关的 1-2 段塞给聊天模型。
class _SnippetWindow {
  final String text;
  final int score;
  final int index;

  const _SnippetWindow({
    required this.text,
    required this.score,
    required this.index,
  });
}

class _MusicTitleMatch {
  final String chineseTitle;
  final String sourceText;
  final int index;
  final int length;

  const _MusicTitleMatch({
    required this.chineseTitle,
    required this.sourceText,
    required this.index,
    required this.length,
  });
}

// 网页候选会先按 query 命中程度排序。
// 原作资料尤其需要把“用户提到的对象”排到前面，而不是完全信搜索结果原始顺序。
class _SearchResultCandidate {
  final String title;
  final String content;
  final String url;
  final int score;

  const _SearchResultCandidate({
    required this.title,
    required this.content,
    required this.url,
    required this.score,
  });
}

class _SiteSearchResult {
  final List<String> results;
  final String query;

  const _SiteSearchResult({
    required this.results,
    required this.query,
  });

  const _SiteSearchResult.empty()
      : results = const [],
        query = '';
}

class _WebContextRunState {
  bool factExtractorUnavailable = false;
  bool factExtractorStopLogged = false;
}

class _DoubaoSearchAttempt {
  final String query;
  final String? sites;
  final int authInfoLevel;
  final bool useGlobal;
  final String label;
  final int priority;

  const _DoubaoSearchAttempt({
    required this.query,
    this.sites,
    this.authInfoLevel = 0,
    this.useGlobal = false,
    required this.label,
    required this.priority,
  });
}

class _DoubaoSearchItem {
  final String title;
  final String snippet;
  final String siteName;
  final String url;
  final String summary;
  final String content;
  final String publishTime;

  const _DoubaoSearchItem({
    required this.title,
    required this.snippet,
    required this.siteName,
    required this.url,
    required this.summary,
    required this.content,
    required this.publishTime,
  });

  String get bestText {
    if (content.isNotEmpty) return content;
    if (summary.isNotEmpty) return summary;
    return snippet;
  }

  String get bestTextSource {
    if (content.isNotEmpty) return 'Content';
    if (summary.isNotEmpty) return 'Summary';
    if (snippet.isNotEmpty) return 'Snippet';
    return 'Empty';
  }

  _DoubaoSearchItem copyWith({
    String? title,
    String? snippet,
    String? siteName,
    String? url,
    String? summary,
    String? content,
    String? publishTime,
  }) {
    return _DoubaoSearchItem(
      title: title ?? this.title,
      snippet: snippet ?? this.snippet,
      siteName: siteName ?? this.siteName,
      url: url ?? this.url,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      publishTime: publishTime ?? this.publishTime,
    );
  }

  factory _DoubaoSearchItem.fromMap(Map item) {
    String read(String pascal, String camel) {
      final pascalValue = item[pascal];
      if (pascalValue is String && pascalValue.trim().isNotEmpty) {
        return pascalValue.trim();
      }
      final camelValue = item[camel];
      return camelValue is String ? camelValue.trim() : '';
    }

    return _DoubaoSearchItem(
      title: read('Title', 'title'),
      snippet: read('Snippet', 'snippet'),
      siteName: read('SiteName', 'siteName'),
      url: read('Url', 'url'),
      summary: read('Summary', 'summary'),
      content: read('Content', 'content'),
      publishTime: read('PublishTime', 'publishTime'),
    );
  }
}

class _DoubaoGroundedFact {
  final String text;
  final String sourceTitle;
  final String sourceUrl;
  final String sourceExcerpt;
  final List<int> requirementIndexes;
  final String answerBasis;
  final bool isStrongEvidence;
  final String directAnswerExcerpt;
  final int eventOrder;
  final String eventOrderEvidence;
  final String chronologyScope;

  const _DoubaoGroundedFact({
    required this.text,
    required this.sourceTitle,
    required this.sourceUrl,
    this.sourceExcerpt = '',
    this.requirementIndexes = const [],
    this.answerBasis = 'insufficient',
    this.isStrongEvidence = false,
    this.directAnswerExcerpt = '',
    this.eventOrder = 0,
    this.eventOrderEvidence = '',
    this.chronologyScope = '',
  });

  _DoubaoGroundedFact copyWith({
    String? text,
    String? sourceTitle,
    String? sourceUrl,
    String? sourceExcerpt,
    List<int>? requirementIndexes,
    String? answerBasis,
    bool? isStrongEvidence,
    String? directAnswerExcerpt,
    int? eventOrder,
    String? eventOrderEvidence,
    String? chronologyScope,
  }) {
    return _DoubaoGroundedFact(
      text: text ?? this.text,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceExcerpt: sourceExcerpt ?? this.sourceExcerpt,
      requirementIndexes: requirementIndexes ?? this.requirementIndexes,
      answerBasis: answerBasis ?? this.answerBasis,
      isStrongEvidence: isStrongEvidence ?? this.isStrongEvidence,
      directAnswerExcerpt: directAnswerExcerpt ?? this.directAnswerExcerpt,
      eventOrder: eventOrder ?? this.eventOrder,
      eventOrderEvidence: eventOrderEvidence ?? this.eventOrderEvidence,
      chronologyScope: chronologyScope ?? this.chronologyScope,
    );
  }
}

class _DoubaoTimelineNode {
  final String text;
  final List<int> factIndexes;

  const _DoubaoTimelineNode({
    required this.text,
    required this.factIndexes,
  });
}

class _DoubaoTimeline {
  final List<_DoubaoTimelineNode> nodes;
  final List<String> constraints;

  const _DoubaoTimeline({
    required this.nodes,
    required this.constraints,
  });

  String toPromptText() {
    final lines = <String>['【时间线】'];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final references = node.factIndexes.map((index) => '#$index').join('、');
      lines.add('${i + 1}. ${node.text}（依据事实：$references）');
    }
    if (constraints.isNotEmpty) {
      lines.add('【回答约束】');
      for (final constraint in constraints) {
        lines.add('- $constraint');
      }
    }
    return lines.join('\n');
  }
}

class _DoubaoFactExtraction {
  final String status;
  final List<_DoubaoGroundedFact> facts;
  final String discardReason;
  final String provider;
  final String answerBasis;

  const _DoubaoFactExtraction({
    required this.status,
    required this.facts,
    required this.discardReason,
    required this.provider,
    this.answerBasis = 'insufficient',
  });

  const _DoubaoFactExtraction.empty()
      : status = 'insufficient',
        facts = const [],
        discardReason = '',
        provider = 'none',
        answerBasis = 'insufficient';
}

class _FactExtractorChatResult {
  final http.Response response;
  final String provider;

  const _FactExtractorChatResult({
    required this.response,
    required this.provider,
  });
}

// 一个简单的数据结构，表示“某个节日叫什么、在哪一天”。
class _Festival {
  final String name;
  final DateTime date;

  const _Festival(this.name, this.date);
}
