import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_keys.dart';
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
  // 每个联网请求最多等 8 秒。
  // 如果天气或搜索服务太慢，就放弃这部分信息，避免聊天一直卡住。
  static const Duration _timeout = Duration(seconds: 8);

  // 用 DeepSeek 做“是否需要联网”的智能判断。
  // 注意：这里不是正式聊天回复，只是让模型输出一小段 JSON 搜索计划。
  static const String _deepSeekApiKey = ApiKeys.deepseekApiKey;
  static const String _deepSeekModel = 'deepseek-v4-flash';
  static const String _deepSeekBaseUrl = 'https://api.deepseek.com/v1';
  static const String _baiduMapAk = ApiKeys.baiduMapAk;
  static const String _tavilyApiKey = ApiKeys.tavilyApiKey;

  // 普通网页搜索的内存缓存。
  //
  // 只缓存 Tavily/DuckDuckGo 的网页搜索结果，不缓存实时天气。
  // 作用：
  // - 同一话题连续追问时更快
  // - 少花 Tavily 调用额度
  // - 搜索结果更稳定，不会每句话都换一批网页
  static final Map<String, _CachedSearchResult> _searchCache = {};
  static const int _maxSearchCacheEntries = 40;

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
    final text = userMessage.trim();
    if (text.isEmpty) return '';

    // 根据角色 id 生成“联网权限配置”。
    // 这是本文件最核心的分流逻辑：
    // 鬼灭角色、祥子、安迪会拿到不同的天气城市、节日范围、搜索权限。
    final profile = _WebProfile.forCharacter(
      characterId: characterId,
      characterName: characterName,
    );

    // 先让 DeepSeek 判断这句话需不需要现实/原作资料。
    // 这样可以覆盖很多关键词法抓不到的情况：
    // - “她后来怎么样了？” -> 可能需要原作剧情
    // - “你那边外面怎么样？” -> 可能需要天气
    // - “这个说法最近很火吗？” -> 可能需要网页搜索
    // - “外面是不是已经有秋天的感觉了？” -> 可能需要物候搜索
    //
    // 如果这个小判定失败，会自动回退到关键词规则，保证功能不会直接断掉。
    final plan = await _buildSearchPlan(text, profile, conversationHistory);
    print(
      '联网计划: character=${profile.characterId}, '
      'weather=${plan.includeWeather}, city=${plan.weatherCity}, '
      'festival=${plan.includeFestivals}, phenology=${plan.includePhenology}, '
      'category=${plan.category}, query=${plan.searchQuery}',
    );

    if (!plan.hasAnyTask) return '';

    // sections 用来收集本次查到的所有现实信息。
    // 比如用户问“上海今天天气怎么样，快到什么节日了？”
    // sections 里可能会有：
    // - 近期节日
    // - 实时天气
    // 最后再合并成一整段上下文。
    final sections = <String>[];

    // 节日信息：
    // 现在优先联网搜索近期节日，让它随年份和地区自动更新。
    // 本地节日表仍然保留，只有联网搜索失败时才作为兜底。
    if (profile.includeFestivals && plan.includeFestivals) {
      final rawFestivalResults = await _searchWeb(
        _buildFestivalSearchQuery(DateTime.now(), profile),
        category: 'festival',
      );
      final festivalResults = _filterFestivalSearchResults(
        rawFestivalResults,
        profile.festivalScope,
      );
      if (festivalResults.isNotEmpty) {
        sections.add('【联网节日信息】\n${festivalResults.join('\n')}');
      } else {
        final festivalContext = _buildFestivalContext(DateTime.now(), profile);
        if (festivalContext.isNotEmpty) {
          sections.add(festivalContext);
        }
      }
    }

    // 天气信息：
    // 只有 DeepSeek 搜索计划认为这句话需要天气背景时才查。
    // 比如“你那边外面怎么样？”没有“天气”二字，也可以触发。
    // 具体城市由 profile 控制：
    // - 鬼灭角色：固定东京，不跟着用户乱跳城市
    // - 祥子：固定东京
    // - 安迪：默认上海，但允许用户问其他城市
    if (profile.includeWeather && plan.includeWeather) {
      final city = plan.weatherCity ?? profile.weatherCity;
      final weather = await _fetchWeather(city);
      if (weather.isNotEmpty) {
        sections.add(weather);
      } else {
        sections.add('''
【实时天气查询失败】
本轮没有成功取得 $city 的实时天气数据。
天气表述限制：不要编造晴天、阴天、下雨、雷雨、打雷、降温、升温、带伞等具体天气情况；如果必须回应天气问题，只能自然表示“暂时不太确定/刚才没查到实时天气”。
''');
      }
    }

    // 物候信息：
    // 物候指现实世界里“花开、发芽、蝉鸣、红叶、落叶”等季节现象。
    // 天气接口本身不提供物候，所以这里用网页搜索补充。
    // 规则：
    // - 用户直接问外面景色、季节感、花、树、红叶等，才查物候
    // - 单纯问“今天天气如何”只查天气，避免物候搜索里的梅雨/季节描述干扰实时天气
    // - 地区仍然按角色 profile 限制，鬼灭/祥子查东京或日本，安迪查上海
    if (profile.includePhenology && plan.includePhenology) {
      final phenologyResults = await _searchWeb(
        _buildPhenologySearchQuery(DateTime.now(), profile),
        category: 'phenology',
      );
      if (phenologyResults.isNotEmpty) {
        sections.add('【联网物候信息】\n${phenologyResults.join('\n')}');
      }
    }

    // 网页搜索：
    // 天气有专门接口，普通天气问题不走网页搜索。
    // 原剧剧情、网络流行语、经济新闻等才可能走网页搜索。
    // 是否允许搜索某类内容，也由 profile 决定。
    if (plan.searchQuery != null && plan.searchQuery!.isNotEmpty) {
      final results = await _searchWeb(
        plan.searchQuery!,
        category: plan.category,
      );
      if (results.isNotEmpty) {
        sections.add('【网页搜索摘要】\n搜索词：${plan.searchQuery}\n${results.join('\n')}');
      } else {
        sections.add('''
【网页搜索失败】
本轮尝试搜索：${plan.searchQuery}
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

【使用这些信息的规则】
- 这些信息是给你理解现实世界用的，不要机械地说“根据搜索结果”。
- 只挑和用户问题最相关的 1-2 个事实自然带入，不要像天气预报、财经新闻或百科词条一样铺开讲。
- 角色说话要像日常聊天：可以像你刚看到、刚查到、或本来就知道一样自然提起，但不要背资料。
- 如果搜索摘要不够确定，就用“不太确定”“我印象里”“好像”这类自然表达，不要编造细节。
- 回答原作/剧情事实时，只能使用搜索摘要里明确支持的信息；摘要没说清楚就表达不确定，不要用模型记忆补成确定事实。
- 禁止提到搜索摘要里没有明确出现的台词、招式、战斗结果、治疗地点、醒来后的反应或后续发展。
- 不要在回复里列链接，除非用户明确要求来源。
''';
  }

  // ========================================
  // 智能搜索计划：先让 DeepSeek 判断“要不要查”
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
  // 所以这里先调用一次 DeepSeek，让它输出一个 JSON 搜索计划。
  // 然后本程序再按角色权限执行搜索。
  static Future<_SearchPlan> _buildSearchPlan(
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
    final llmPlan =
        await _buildSearchPlanWithDeepSeek(text, profile, conversationHistory);
    if (llmPlan != null) {
      return await _applySemanticCanonGuard(
        _applyProfileRules(llmPlan, text, profile),
        text,
        profile,
        conversationHistory,
      );
    }

    // 如果 DeepSeek 判定失败，比如网络错误、JSON 解析失败，就回退到旧的关键词规则。
    // 这样最差也只是“没那么聪明”，不会让聊天直接坏掉。
    return await _applySemanticCanonGuard(
      _applyProfileRules(_keywordSearchPlan(text, profile), text, profile),
      text,
      profile,
      conversationHistory,
    );
  }

  // 调 DeepSeek 生成搜索计划。
  // 返回 null 表示这一步失败，让上层回退关键词规则。
  static Future<_SearchPlan?> _buildSearchPlanWithDeepSeek(
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
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
              ],
              'max_tokens': 300,
              'temperature': 0.1,
              'stream': false,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        print('搜索计划 DeepSeek 判定失败: ${response.statusCode}');
        print('错误内容: ${response.body}');
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
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
      );
    } catch (e) {
      print('搜索计划 DeepSeek 判定异常: $e');
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
  "query": "需要网页搜索时使用的搜索词；不需要则空字符串"
}

判断原则：
1. 如果用户问“你那边外面怎么样、冷不冷、下雨了吗、热吗”等，即使没说天气，也应该 weather=true。
2. 如果用户问今天、最近、假期、节日、生日氛围等，festival=true。
3. 如果用户问外面景色、季节感、花、树、发芽、落叶、红叶、樱花、紫藤、桂花、银杏等，phenology=true。单纯问“今天天气如何/冷不冷/热不热/下雨吗”时，weather=true 但 phenology=false。
4. 如果用户提到角色经历、关系、过去事件、后来发展、某个角色“她/他/你”与其他人的关系，可能需要作品原作资料，web_search=true，category="canon"。
5. 如果用户问网络流行语、梗、最近流行说法，web_search=true，category="slang"。
6. 如果用户问经济、金融、股市、投资、房价、汇率，category="economy"。
7. 如果当前角色范围不允许某类搜索，也仍然按“用户意图”填写 category；程序之后会二次过滤。
8. query 要写成适合搜索引擎的中文关键词，不要太长。
9. 经济、新闻、政策类问题如果用户没有指定年份，query 必须包含当前年份 ${now.year} 和“最新/近期”等词。
10. 只要当前消息或最近对话涉及作品内事实，宁可 web_search=true、category="canon"，不要让聊天模型凭记忆回答。作品内事实包括人物、人物关系、乐队/组织/学校/店铺/地点、事件、台词、口头禅、喜好、食物、身份、职位、集数、剧情和设定。
11. 如果当前消息出现新对象，query 必须围绕新对象，不要沿用最近对话里的旧对象。
12. 原作 query 必须包含用户真正询问的对象；不要因为当前聊天角色是 ${profile.characterName} 就把 ${profile.characterName} 放进 query，除非用户确实在问 ${profile.characterName} 本人。
13. 如果问题是“当前角色是否记得/认识/救过/见过某人”，query 优先写“被问到的那个人 + 事件/地点/关系 + 作品名”；当前角色名只能作为辅助词，不能重复出现。
''';
  }

  // DeepSeek 有时会用 ```json 包起来。
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

  static String _recentHistoryForPlanner(List<Message> conversationHistory) {
    if (conversationHistory.isEmpty) return '（无）';

    return conversationHistory.reversed
        .take(6)
        .toList()
        .reversed
        .map((message) {
      final role = message.role == 'assistant' ? '角色' : '用户';
      final content = message.content
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final shortened = content.length > 180 ? '${content.substring(0, 180)}...' : content;
      return '$role：$shortened';
    }).join('\n');
  }

  // 旧关键词方案：作为 DeepSeek 搜索计划失败时的兜底。
  static _SearchPlan _keywordSearchPlan(String text, _WebProfile profile) {
    return _SearchPlan(
      includeWeather: _asksWeather(text),
      weatherCity: _extractWeatherCity(text, profile),
      includeFestivals: _shouldMentionDateOrFestival(text),
      includePhenology: _asksPhenology(text),
      searchQuery:
          _shouldSearchWeb(text, profile) ? _buildSearchQuery(text, profile) : null,
      category: _asksCanon(text)
          ? 'canon'
          : _asksEconomy(text)
              ? 'economy'
              : 'general',
    );
  }

  // 二次过滤：无论 DeepSeek 怎么判断，最终都必须服从角色权限。
  // 这能避免“祥子去查股市”或“鬼灭角色去查现代热点”。
  static _SearchPlan _applyProfileRules(
    _SearchPlan plan,
    String text,
    _WebProfile profile,
  ) {
    // 天气问题用“大模型判断 + 本地关键词”双保险。
    //
    // 原因：
    // DeepSeek planner 偶尔会把“今天天气如何”这种很短的日常问句
    // 当成普通寒暄，返回 weather=false。那样后面就完全不会查天气，
    // 角色只能按人设和想象发挥，很容易说出“雷雨/下雨”。
    //
    // 所以：只要本地关键词明确命中天气，就强制 includeWeather=true。
    final keywordWeather = _asksWeather(text);
    final includeWeather =
        profile.includeWeather && (plan.includeWeather || keywordWeather);
    final weatherCity = includeWeather
        ? profile.allowUserWeatherCity
            ? (plan.weatherCity ?? _extractWeatherCity(text, profile) ?? profile.weatherCity)
            : profile.weatherCity
        : null;

    final includeFestivals = profile.includeFestivals && plan.includeFestivals;
    final includePhenology = profile.includePhenology && plan.includePhenology;

    String? searchQuery = plan.searchQuery;
    final category = plan.category;
    final isPlainWeatherQuestion =
        keywordWeather && !RegExp(r'新闻|台风|暴雨|预警|灾害|最近|近期').hasMatch(text);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      // 天气和节日都有专门的数据来源：
      // - 天气走天气 API，拿“当前状态/降水量”
      // - 节日走受角色作品限制的节日搜索和本地兜底列表
      //
      // 所以这里故意关掉普通网页搜索。
      // 否则搜索摘要里只要出现“雷雨/阵雨/梅雨”等词，
      // DeepSeek 就可能把它和天气 API 混在一起，误说正在下雨。
      if (isPlainWeatherQuestion || category == 'weather' || category == 'festival') {
        searchQuery = null;
      } else if (category == 'economy' && !profile.allowEconomySearch) {
        searchQuery = null;
      } else if (profile.onlyCanonSearch && category != 'canon') {
        searchQuery = null;
      } else {
        searchQuery = _normalizeSearchQuery(searchQuery, category, text, profile);
      }
    }

    return _SearchPlan(
      includeWeather: includeWeather,
      weatherCity: weatherCity,
      includeFestivals: includeFestivals,
      includePhenology: includePhenology,
      searchQuery: searchQuery,
      category: category,
    );
  }

  // 把 DeepSeek 给出的搜索词再整理一下：
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
    var trimmed = query.trim().isEmpty ? _buildSearchQuery(text, profile) : query.trim();

    if (category == 'canon') {
      if (!trimmed.contains(profile.canonSearchPrefix)) {
        trimmed = '${profile.canonSearchPrefix} $trimmed';
      }
      trimmed = _enrichCanonSearchQuery(trimmed, text, profile);
      trimmed = _deemphasizeCurrentCharacterInCanonQuery(trimmed, text, profile);
      return _dedupeSearchQueryTerms(trimmed);
    }

    if (category == 'economy' || category == 'current') {
      // “最近/现在/今年”这类问题必须按运行时当前年份理解。
      // DeepSeek planner 有时会受训练语料影响，把最近经济形势写成 2025。
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

  static String _deemphasizeCurrentCharacterInCanonQuery(
    String query,
    String text,
    _WebProfile profile,
  ) {
    final characterName = profile.characterName.trim();
    if (characterName.isEmpty) return query;
    if (_isCurrentCharacterRelationQuestion(text, profile)) return query;

    final terms = query.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
    final otherTerms = terms.where((term) {
      final cleaned = term.trim();
      if (cleaned.isEmpty) return false;
      if (cleaned == profile.canonSearchPrefix) return false;
      if (cleaned == characterName) return false;
      if (_canonQueryNoiseTerms.contains(cleaned.toLowerCase())) return false;
      return true;
    }).toList();

    // 如果 query 里已经有“善逸/山吹沙绫/那田蜘蛛山”这类更具体对象，
    // 当前聊天角色名就不再作为主搜索词，避免搜索结果被当前角色百科带偏。
    if (otherTerms.length >= 2) {
      return terms.where((term) => term.trim() != characterName).join(' ');
    }

    return query;
  }

  static String _enrichCanonSearchQuery(
    String query,
    String text,
    _WebProfile profile,
  ) {
    final additions = <String>[];

    if (_isCurrentCharacterRelationQuestion(text, profile)) {
      additions.add(profile.characterName);
    }

    // “救/治疗/解毒”这类问法如果只搜“被救”，搜索结果很容易跑到泛泛剧情页。
    // 加上更具体的医学/中毒词，可以把结果拉回真正的事件细节。
    if (RegExp(r'救|救过|救過|治疗|治療|医治|醫治|解毒|中毒|毒').hasMatch(text)) {
      additions.addAll(['中毒', '下毒', '解毒', '治疗']);
    }

    if (additions.isEmpty) return query;
    return '$query ${additions.join(' ')}';
  }

  static bool _isCurrentCharacterRelationQuestion(
    String text,
    _WebProfile profile,
  ) {
    final characterName = profile.characterName.trim();
    if (characterName.isEmpty) return false;
    final shortName = characterName.length > 1
        ? characterName.substring(characterName.length - 1)
        : characterName;
    final mentionsCurrentCharacter =
        text.contains(characterName) || text.contains(shortName) || RegExp(r'你|妳').hasMatch(text);
    final asksRelationOrEvent =
        RegExp(r'记得|記得|认识|認識|见过|見過|救|救过|救過|治疗|治療|解毒|关系|一起|当初|當初')
            .hasMatch(text);
    return mentionsCurrentCharacter && asksRelationOrEvent;
  }

  static const Set<String> _canonQueryNoiseTerms = {
    '鬼灭之刃',
    '鬼滅之刃',
    'bang',
    'dream',
    '欢乐颂',
    '角色设定',
    '剧情',
    '设定',
    '关系',
    '救',
    '救过',
    '记得',
    '认识',
    '见过',
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
  static Future<_SearchPlan> _applySemanticCanonGuard(
    _SearchPlan plan,
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) async {
    final localPlan = _applyFollowUpRules(plan, text, profile, conversationHistory);
    if (localPlan.hasAnyTask) return localPlan;

    final guardPlan = await _buildCanonGuardPlanWithDeepSeek(
      text,
      profile,
      conversationHistory,
    );
    if (guardPlan == null) return localPlan;

    final filteredPlan = _applyProfileRules(guardPlan, text, profile);
    if (filteredPlan.searchQuery != null && filteredPlan.searchQuery!.isNotEmpty) {
      print('原作事实守门员触发 canon 搜索: ${filteredPlan.searchQuery}');
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
        print('原作事实守门员判定失败: ${response.statusCode}');
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
      );
    } catch (e) {
      print('原作事实守门员异常: $e');
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
  "query": "需要搜索时给出简短搜索词；不需要则空字符串"
}

必须 canon_search=true 的情况：
- 用户提到或追问作品内的人物、人物关系、乐队/组织/学校/店铺/地点、事件、台词、口头禅、喜好、食物、道具、身份、职位、集数、剧情和设定。
- 用户没有明确说作品名，但最近对话正在聊作品设定，而当前消息用“她/他/这个/那个/同学/那家店/那句话”等继续追问。
- 当前问题只要回答错会造成角色、关系、归属、喜好、地点或剧情事实错误，就应该搜索。

必须 canon_search=false 的情况：
- 纯问候、闲聊感受、情绪陪伴、现实天气/节日/经济等非原作内容。

query 规则：
- 用当前作品名 + 当前消息里最核心的人物/地点/物品/事件 + 设定类型。
- query 要短，不要整句复制用户消息，不要把最近历史里的旧话题强行带入新话题。
- 如果当前消息出现新对象，优先搜索新对象，不要沿用历史旧对象。
''';
  }

  static _SearchPlan _applyFollowUpRules(
    _SearchPlan plan,
    String text,
    _WebProfile profile,
    List<Message> conversationHistory,
  ) {
    final currentTopic = _currentCanonTopic(text);
    final recentTopic = _recentCanonTopic(conversationHistory, profile);

    if (!plan.hasAnyTask && _shouldForceCanonSearch(text, recentTopic)) {
      final topic = currentTopic ?? recentTopic ?? text;
      final query = _buildCanonFollowUpSearchQuery(text, topic, profile);
      print('检测到原作相关内容，强制 canon 搜索: $query');
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
    print('检测到原作资料追问，补充 canon 搜索: $query');

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
  // 搜索词越接近日常检索习惯，Tavily/DuckDuckGo 越不容易跑偏或超时。
  static String _buildCanonFollowUpSearchQuery(
    String text,
    String topic,
    _WebProfile profile,
  ) {
    final seriesPrefix = _canonSeriesSearchPrefix(profile);
    final subject = _compactCanonSearchTerms(topic);
    final focus = _canonFollowUpFocus(text, topic);
    return '$seriesPrefix $subject $focus'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _canonSeriesSearchPrefix(_WebProfile profile) {
    if (profile.seriesName == 'BanG Dream') return 'BanG Dream';
    if (profile.seriesName == '鬼灭之刃') return '鬼灭之刃';
    if (profile.seriesName == '欢乐颂') return '欢乐颂';
    return profile.seriesName == '未分类' ? profile.characterName : profile.seriesName;
  }

  static String _canonFollowUpFocus(String text, String topic) {
    if (RegExp(r'喜欢|喜歡|爱吃|愛吃|常吃|食物|面包|麵包|甜点|点心|零食|料理|饮料|飲料')
        .hasMatch(text)) {
      return '喜欢的食物 角色设定';
    }
    if (RegExp(r'地点|地方|店|学校|学园|學園|商店街|家|住宅|面包房|烘焙坊|ライブハウス|场所')
        .hasMatch(text)) {
      return '地点 角色设定 剧情';
    }
    if (RegExp(r'独特|氣質|气质|雰囲気|氛围').hasMatch(text)) {
      return '性格 气质 说话方式';
    }
    if (RegExp(r'什么意思|指什么|怎么理解').hasMatch(text)) {
      return '台词 含义 角色性格';
    }
    if (RegExp(r'关系|羁绊|仲間|伙伴').hasMatch(text)) {
      return '人物关系 伙伴 羁绊';
    }
    if (RegExp(r'为什么|為什麼|原因').hasMatch(text)) {
      return '原因 角色性格 剧情';
    }
    return '角色设定 性格';
  }

  static bool _looksLikeFollowUpQuestion(String text) {
    // “这个我知道……”通常是在补充新信息，不是追问。
    // 这种情况下如果句子里出现新角色，应优先让 planner 或当前实体识别处理。
    if (RegExp(r'^这个我知道|^這個我知道|^这个我懂|^這個我懂').hasMatch(text.trim())) {
      return _currentCanonTopic(text) != null;
    }
    return RegExp(
      r'这个|這個|这是什么意思|什么意思|指什么|怎么理解|为什么|為什麼|她|他|那|刚才|剛才|上面|前面|这种|那种|独特|氣質|气质|关系|后来|之后',
    ).hasMatch(text);
  }

  // 当前用户消息里明确提到的新原作对象，优先级高于历史话题。
  // 这里不维护角色名单，而是抓“名字称呼、地点、事件、台词、设定词”等结构。
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

    for (final match in RegExp(r'[“"「『《]([^”"」』》]{2,24})[”"」』》]').allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(r"([A-Za-z][A-Za-z0-9!'’ ._-]{2,30})").allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r'([\u4e00-\u9fa5ぁ-んァ-ンー]{1,8})(?:同学|同學|同窗|さん|桑|ちゃん|君|前辈|前輩|老师|先生|小姐)',
    ).allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r"([\u4e00-\u9fa5ぁ-んァ-ンーA-Za-z0-9!'’ ._-]{2,18}(?:乐队|樂隊|学校|学园|學園|学院|面包房|麵包房|烘焙坊|商店街|店|家|社团|社團|livehouse|ライブハウス))",
      caseSensitive: false,
    ).allMatches(text)) {
      addTerm(match.group(1)!);
    }

    for (final match in RegExp(
      r"([\u4e00-\u9fa5ぁ-んァ-ンーA-Za-z0-9!'’ ._-]{2,18}(?:台词|台詞|口头禅|口癖|名言|称呼|关系|事件|设定|設定|剧情|食物|面包|麵包|料理|鼓手|吉他手|主唱|键盘手|鍵盤手|贝斯手|貝斯手))",
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
      r'BanG|Poppin|Afterglow|Ave Mujica|MyGO|CRYCHIC|鬼灭|鬼滅|欢乐颂|'
      r'同学|同學|さん|ちゃん|前辈|前輩|乐队|樂隊|学校|学园|學園|'
      r'面包房|麵包房|烘焙坊|商店街|livehouse|ライブハウス|'
      r'鼓手|吉他手|主唱|键盘手|鍵盤手|贝斯手|貝斯手|台词|台詞|设定|設定|剧情|人物关系|'
      r'食物|面包|麵包|喜欢吃|喜歡吃|爱吃|愛吃|口头禅|口癖|名言|事件',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _containsCanonFollowUpSignal(String text) {
    return RegExp(
      r'这个|這個|她|他|那|关系|喜欢|喜歡|食物|地点|地方|店|学校|乐队|樂隊|成员|成員|为什么|為什麼|什么意思|指什么|设定|設定|剧情|台词|台詞',
    ).hasMatch(text);
  }

  // ========================================
  // 下面这些 _asksXXX 方法：判断用户这句话想问什么
  // ========================================
  // 这里是模型判定失败时的本地兜底。
  // 主路径仍然由 DeepSeek planner / 原作事实守门员做语义判断。

  // 判断是否和日期/节日有关。
  static bool _shouldMentionDateOrFestival(String text) {
    return RegExp(r'今天|现在|日期|星期|周几|节日|假期|最近|近期|明天|后天').hasMatch(text);
  }

  // 判断是否和天气有关。
  static bool _asksWeather(String text) {
    return RegExp(r'天气|气温|下雨|降雨|冷不冷|热不热|温度|台风|空气质量').hasMatch(text);
  }

  // 判断是否和物候有关。
  // 物候就是季节变化在自然界里的表现，比如开花、发芽、蝉鸣、红叶、落叶。
  static bool _asksPhenology(String text) {
    return RegExp(r'物候|花|开花|花期|花开|花谢|樱花|紫藤|梅花|桂花|银杏|红叶|枫叶|落叶|发芽|新绿|蝉|蝉鸣|梅雨|季节|景色|外面')
        .hasMatch(text);
  }

  // 判断是否和原作/原剧/角色设定有关。
  // 鬼灭角色的网页搜索只允许这一类问题。
  static bool _asksCanon(String text) {
    return RegExp(
      r'原作|原剧|剧情|设定|設定|人物关系|台词|台詞|出处|出處|动画|漫画|电视剧|'
      r'欢乐颂|鬼灭|鬼滅|BanG|MyGO|Ave Mujica|CRYCHIC|Afterglow|Poppin|'
      r'角色|同学|同學|さん|ちゃん|前辈|前輩|乐队|樂隊|学校|学园|學園|'
      r'面包房|麵包房|烘焙坊|商店街|livehouse|ライブハウス|'
      r'鼓手|吉他手|主唱|键盘手|鍵盤手|贝斯手|貝斯手|'
      r'喜欢吃|喜歡吃|爱吃|愛吃|口头禅|口癖|名言|第\d+集|第[一二三四五六七八九十]+集',
      caseSensitive: false,
    )
        .hasMatch(text);
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

  // 联网搜索节日时使用的搜索词。
  //
  // 注意：节日范围按“番剧/作品名”划分，而不是按单个角色划分。
  // - 鬼灭之刃：只搜大正时期已经存在的日本民俗/季节行事
  // - BanG Dream：搜现代日本非政治节日/行事
  // - 欢乐颂：搜中国 + 国际近期节日
  //
  // 日本角色统一排除天皇、建国、昭和、宪法等政治色彩较强的节日。
  static String _buildFestivalSearchQuery(DateTime now, _WebProfile profile) {
    final month = now.month;

    switch (profile.festivalScope) {
      case _FestivalScope.kimetsuTaishoJapan:
        return '$month月 日本 大正時代 传统 民俗 季节 年中行事 节日 -天皇 -建国 -昭和 -宪法 -憲法 -政治 -国民の祝日';
      case _FestivalScope.modernJapanNonPolitical:
        return '${now.year}年$month月 日本 现代 民俗 季节 行事 樱花季 夏日祭 花火大会 十五夜 国际节日 -天皇 -建国 -昭和 -宪法 -憲法 -政治';
      case _FestivalScope.chinaInternational:
        return '${now.year}年$month月 中国 国际 近期 节日 假期';
      case _FestivalScope.internationalOnly:
        return '${now.year}年$month月 近期 国际 节日';
    }
  }

  // 联网搜索物候时使用的搜索词。
  // 这里会把角色所在地区和当月放进去，尽量搜到“当下真实状态”。
  static String _buildPhenologySearchQuery(DateTime now, _WebProfile profile) {
    final month = now.month;
    return '${profile.phenologyRegion} ${now.year}年$month月 物候 花期 开花 红叶 落叶 季节 景色';
  }

  static List<String> _filterFestivalSearchResults(
    List<String> results,
    _FestivalScope scope,
  ) {
    if (scope == _FestivalScope.chinaInternational ||
        scope == _FestivalScope.internationalOnly) {
      return results;
    }

    final forbidden = <RegExp>[
      RegExp(r'天皇|皇室|建国|建國|紀元節|纪元节|昭和|宪法|憲法|政治'),
    ];

    if (scope == _FestivalScope.kimetsuTaishoJapan) {
      forbidden.addAll([
        RegExp(r'成人の日|成人之日|海の日|海之日|山の日|山之日'),
        RegExp(r'敬老の日|敬老之日|体育の日|体育之日|スポーツの日|运动之日'),
        RegExp(r'みどりの日|绿之日|勤労感謝の日|勤劳感谢日|国民の祝日|国定假日'),
      ]);
    }

    return results.where((result) {
      return !forbidden.any((pattern) => pattern.hasMatch(result));
    }).toList();
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
  static Future<String> _fetchWeather(String city) async {
    try {
      final location = _knownWeatherLocation(city) ?? await _geocodeCity(city);
      if (location == null) return '';

      final baiduWeather = await _fetchBaiduWeather(location);
      if (baiduWeather.isNotEmpty) return baiduWeather;

      return await _fetchOpenMeteoWeather(location);
    } catch (e) {
      print('获取天气失败: $e');
      return '';
    }
  }

  // 常用角色固定城市的本地经纬度兜底。
  //
  // 这样即使 Open-Meteo 的地理编码接口临时失败，
  // 也还能直接拿经纬度去查天气，不会让角色凭空编天气。
  static _WeatherLocation? _knownWeatherLocation(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.contains('东京') || normalized.contains('東京') || normalized.contains('tokyo')) {
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
      final responseSource =
          location.isBaiduAbroad ? '百度地图海外天气' : '百度地图天气';
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
        print('百度天气 API 返回异常: ${data['status']} ${data['message'] ?? ''}');
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
      final isPrecipitating =
          _weatherTextMentionsPrecipitation('$text') || _isPositiveNumberString(precipitation);
      final precipitationRule = isPrecipitating
          ? '当前允许提及降水，但仍要以数据为准，不要夸大雨势。'
          : '当前不允许说正在下雨、快要下雨、雨要来了或建议因为下雨带伞。';

      return '''
【实时天气】
$cityName：数据源 $responseSource；数据时间 ${now['uptime'] ?? '未知时间'}；当前状态 $text；气温 ${now['temp'] ?? '?'}℃，体感 ${now['feels_like'] ?? '?'}℃，湿度 ${now['rh'] ?? '?'}%，${now['wind_dir'] ?? '风向未知'} ${now['wind_class'] ?? ''}，当前1小时降水量 ${precipitation ?? '?'} mm。
天气表述限制：必须按“当前状态”和“当前1小时降水量”描述天气；不要凭湿度高、多云或季节信息推测下雨。$precipitationRule
''';
    } catch (e) {
      print('百度天气请求失败，退回 Open-Meteo: $e');
      return '';
    }
  }

  static Future<String> _fetchOpenMeteoWeather(_WeatherLocation location) async {
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

  // ========================================
  // 网页搜索
  // ========================================
  // 普通联网搜索的统一入口。
  //
  // 优先级：
  // 1. Tavily：正规搜索 API，返回结构化 JSON，适合 AI/RAG 使用。
  // 2. DuckDuckGo HTML：无需 key 的兜底方案，稳定性略差。
  //
  // 这样你只要在 ApiKeys.tavilyApiKey 填 key，就会自动升级搜索质量；
  // 不填 key 时，旧功能仍然能跑。
  static Future<List<String>> _searchWeb(
    String query, {
    String category = 'general',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final cacheKey = _searchCacheKey(trimmed, category);
    final cached = _readSearchCache(cacheKey, category);
    if (cached != null) {
      print(
        '网页搜索缓存命中: source=${cached.source}, '
        'category=$category, query=$trimmed, results=${cached.results.length}',
      );
      return cached.results;
    }

    List<String> results = [];
    String source = 'DuckDuckGo';

    if (_tavilyApiKey.trim().isNotEmpty) {
      final tavilyResults = await _searchTavily(
        trimmed,
        category: category,
      );
      if (tavilyResults.isNotEmpty) {
        results = tavilyResults;
        source = 'Tavily';
      }
    }

    if (results.isEmpty) {
      results = await _searchDuckDuckGo(trimmed);
      source = 'DuckDuckGo';
    }

    final cleaned = _postProcessSearchResults(results, category);
    if (cleaned.isNotEmpty) {
      _writeSearchCache(cacheKey, cleaned, source);
      print(
        '网页搜索结果: source=$source, category=$category, '
        'query=$trimmed, results=${cleaned.length}',
      );
    } else {
      print('网页搜索无可用结果: category=$category, query=$trimmed');
    }
    return cleaned;
  }

  // Tavily Search API。
  //
  // 为什么比 DuckDuckGo HTML 抓取更好：
  // - 返回 JSON，不依赖网页 class 名，不容易因为页面改版失效。
  // - 面向 AI agent/RAG 场景，摘要通常比普通搜索页 snippet 更适合塞进 prompt。
  // - 可以拿到 URL，方便模型知道信息来源，但回复时仍不主动列链接。
  static Future<List<String>> _searchTavily(
    String query, {
    String category = 'general',
  }) async {
    try {
      final requestBody = _buildTavilyRequestBody(
        query,
        category: category,
        preferTrustedSources: true,
      );
      final response = await http
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {
              'Authorization': 'Bearer $_tavilyApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        print('Tavily 搜索失败: ${response.statusCode} ${response.body}');
        return [];
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return [];

      var results = _parseTavilyResults(data, category: category, query: query);

      // 经济/原作类第一轮会优先限定可信来源。
      // 如果限定域名后没有结果，再放宽搜一次，避免完全搜不到。
      if (results.isEmpty &&
          (category == 'economy' || category == 'canon') &&
          requestBody.containsKey('include_domains')) {
        final retryResults =
            await _searchTavilyWithoutDomainLimit(query, category);
        if (retryResults.isNotEmpty) return retryResults;
      }

      if (results.isNotEmpty) {
        print('Tavily 搜索成功: $query');
      }
      return results;
    } catch (e) {
      print('Tavily 搜索异常，退回 DuckDuckGo: $e');
      return [];
    }
  }

  static Future<List<String>> _searchTavilyWithoutDomainLimit(
    String query,
    String category,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {
              'Authorization': 'Bearer $_tavilyApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_buildTavilyRequestBody(
              query,
              category: category,
              preferTrustedSources: false,
            )),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        print('Tavily 放宽搜索失败: ${response.statusCode} ${response.body}');
        return [];
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return [];

      final results = _parseTavilyResults(data, category: category, query: query);
      if (results.isNotEmpty) {
        print('Tavily 放宽搜索成功: $query');
      }
      return results;
    } catch (e) {
      print('Tavily 放宽搜索异常: $e');
      return [];
    }
  }

  static Map<String, dynamic> _buildTavilyRequestBody(
    String query, {
    required String category,
    required bool preferTrustedSources,
  }) {
    final body = <String, dynamic>{
      'query': query,
      'search_depth':
          (category == 'economy' || category == 'canon') ? 'advanced' : 'basic',
      'max_results': category == 'economy' ? 6 : 5,
      'include_answer': false,
      'include_raw_content': category == 'canon',
      'include_images': false,
    };

    if (category == 'economy') {
      body['topic'] = 'finance';
      body['time_range'] = 'year';
      if (preferTrustedSources) {
        body['include_domains'] = _trustedEconomyDomains;
      }
    } else if (category == 'canon') {
      body['topic'] = 'general';
      if (preferTrustedSources) {
        body['include_domains'] = _trustedCanonDomains;
      }
    } else if (category == 'current' || category == 'slang') {
      body['topic'] = 'news';
      body['time_range'] = 'month';
    } else {
      body['topic'] = 'general';
    }

    return body;
  }

  static List<String> _parseTavilyResults(
    Map<String, dynamic> data, {
    String category = 'general',
    String query = '',
  }) {
    final rawResults = data['results'];
    if (rawResults is! List) return [];

    final terms = _snippetSearchTerms(query);
    final candidates = <_SearchResultCandidate>[];
    for (final item in rawResults.take(6)) {
      if (item is! Map<String, dynamic>) continue;
      final title = _mapString(item, 'title');
      final content = _bestTavilyContent(item, category, query, title);
      final url = _mapString(item, 'url');
      if (title.isEmpty && content.isEmpty) continue;
      final score = category == 'canon'
          ? _searchResultScore(title, content, terms)
          : 0;
      if (category == 'canon' && score < _minimumCanonResultScore(terms)) {
        continue;
      }

      candidates.add(_SearchResultCandidate(
        title: title,
        content: content,
        url: url,
        score: score,
      ));
    }

    if (category == 'canon') {
      candidates.sort((a, b) => b.score.compareTo(a.score));
    }

    final results = <String>[];
    for (final candidate in candidates) {
      final snippet = _truncateSearchSnippet(
        candidate.content,
        // 原作细节题需要更多上下文，但这里已经是“短句筛选后的相关片段”，
        // 不是网页开头或整页正文。
        maxLength: category == 'canon' ? 900 : 220,
      );
      final source = candidate.url.isEmpty ? '' : '（来源：${candidate.url}）';
      results.add('${results.length + 1}. ${candidate.title}：$snippet$source');
    }

    return results;
  }

  static String _bestTavilyContent(
    Map<String, dynamic> item,
    String category,
    String query,
    String title,
  ) {
    final content = _mapString(item, 'content');
    final rawContent = _mapString(item, 'raw_content');

    if (category != 'canon' || rawContent.isEmpty) {
      return content;
    }

    // Tavily 的 content 通常是相关摘要，raw_content 是更长正文。
    // 原作细节题更怕摘要漏掉关键情节，所以 canon 搜索会从正文中找 query 命中的片段。
    final cleanedRaw = rawContent
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'目次|目录|编辑|編輯'), ' ')
        .trim();
    if (cleanedRaw.isEmpty || cleanedRaw == content) return content;

    final rawSnippet = _relevantRawSnippet(cleanedRaw, query, title);
    if (rawSnippet.isNotEmpty) return '相关正文：$rawSnippet';
    return _contentIsRelevantEnough(content, query, title) ? content : '';
  }

  static String _relevantRawSnippet(
    String rawContent,
    String query,
    String title,
  ) {
    final terms = _snippetSearchTerms(query);
    if (terms.isEmpty) {
      return '';
    }

    final windows = <_SnippetWindow>[];
    for (final fragment in _rawContentFragments(rawContent)) {
      if (_isNoisyRawFragment(fragment)) continue;
      if (!_canonFragmentHasRequiredEvidence(fragment, title, terms)) continue;
      final score = _snippetScore(fragment, terms) + _snippetScore(title, terms);
      if (score < _minimumCanonFragmentScore(terms)) continue;
      windows.add(_SnippetWindow(text: fragment, score: score));
    }

    if (windows.isEmpty) return '';

    windows.sort((a, b) => b.score.compareTo(a.score));
    final chosen = <String>[];
    final seen = <String>{};
    var totalLength = 0;
    for (final window in windows) {
      final key = _normalizeForDedupe(window.text);
      if (seen.contains(key)) continue;
      seen.add(key);
      if (totalLength + window.text.length > 900 && chosen.isNotEmpty) continue;
      chosen.add(window.text);
      totalLength += window.text.length;
      if (chosen.length >= 5 || totalLength >= 900) break;
    }

    return _truncateSearchSnippet(chosen.join(' / '), maxLength: 900);
  }

  static List<String> _snippetSearchTerms(String query) {
    final terms = query
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:()（）「」『』“”"《》]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .where((term) => !_canonQueryNoiseTerms.contains(term.toLowerCase()))
        .toSet()
        .toList();

    terms.sort((a, b) => b.length.compareTo(a.length));
    return terms.take(8).toList();
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
    return RegExp(
      r'广告|廣告|赞助|贊助|App|APP|下载|下載|登录|登入|注册|註冊|'
      r'编辑|編輯|目录|目次|导航|导航菜单|隐私|Cookie|'
      r'播放|弹幕|评论|分享|收藏|投币|点赞|更多|展开|收起|'
      r'免责声明|版权所有|Copyright|Access Denied|Just a moment',
      caseSensitive: false,
    ).hasMatch(normalized);
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
    final asksTreatment = terms.any(_isTreatmentEvidenceTerm);
    if (!asksTreatment) return true;

    final combined = '$title $fragment'.toLowerCase();
    final hasTreatmentEvidence = _canonTreatmentEvidenceTerms.any(
      (term) => combined.contains(term.toLowerCase()),
    );
    if (!hasTreatmentEvidence) return false;

    final actorTerms = terms
        .where((term) => !_isTreatmentEvidenceTerm(term))
        .where((term) => !_canonLocationOrGenericTerms.contains(term.toLowerCase()))
        .toList();
    if (actorTerms.isEmpty) return true;
    return actorTerms.any((term) => combined.contains(term.toLowerCase()));
  }

  static bool _isTreatmentEvidenceTerm(String term) {
    return _canonTreatmentEvidenceTerms.contains(term.toLowerCase());
  }

  static const Set<String> _canonTreatmentEvidenceTerms = {
    '中毒',
    '下毒',
    '解毒',
    '解毒剂',
    '解毒劑',
    '治疗',
    '治療',
    '医治',
    '醫治',
  };

  static const Set<String> _canonLocationOrGenericTerms = {
    '那田蜘蛛山',
    '事件',
    '篇',
    '章',
    '被救',
  };

  static int _minimumCanonResultScore(List<String> terms) {
    if (terms.length <= 1) return 2;
    return 5;
  }

  static int _minimumCanonFragmentScore(List<String> terms) {
    if (terms.length <= 1) return 2;
    return 4;
  }

  static bool _contentIsRelevantEnough(
    String content,
    String query,
    String title,
  ) {
    final terms = _snippetSearchTerms(query);
    if (terms.isEmpty) return false;
    if (!_canonFragmentHasRequiredEvidence(content, title, terms)) return false;
    final score = _snippetScore(content, terms) + _snippetScore(title, terms);
    return score >= _minimumCanonResultScore(terms);
  }

  static int _snippetScore(String text, List<String> terms) {
    final lowerText = text.toLowerCase();
    var score = 0;
    for (final term in terms) {
      final lowerTerm = term.toLowerCase();
      if (lowerText.contains(lowerTerm)) {
        score += term.length >= 4 ? 3 : 2;
      }
    }
    return score;
  }

  static String _mapString(Map<String, dynamic> item, String key) {
    final value = item[key];
    return value is String ? value.trim() : '';
  }

  static const List<String> _trustedEconomyDomains = [
    // 官方/半官方宏观数据和政策来源
    'stats.gov.cn',
    'pbc.gov.cn',
    'gov.cn',
    'www.gov.cn',
    // 主流媒体和财经媒体
    'xinhuanet.com',
    'news.cn',
    'people.com.cn',
    'cctv.com',
    'caixin.com',
    'yicai.com',
    'stcn.com',
    'cs.com.cn',
    '21jingji.com',
    'reuters.com',
    'bloomberg.com',
  ];

  static const List<String> _trustedCanonDomains = [
    // 官方站
    'bang-dream.com',
    'anime.bang-dream.com',
    'bang-dream.bushimo.jp',
    'kimetsu.com',
    // 成熟百科 / wiki
    'wikipedia.org',
    'fandom.com',
    'moegirl.org.cn',
    'zh.moegirl.org.cn',
    'zh.moegirl.tw',
    'baike.baidu.com',
  ];

  static String _searchCacheKey(String query, String category) {
    return '$category::${query.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';
  }

  static _CachedSearchResult? _readSearchCache(String cacheKey, String category) {
    final cached = _searchCache[cacheKey];
    if (cached == null) return null;

    final age = DateTime.now().difference(cached.createdAt);
    if (age > _searchCacheTtl(category)) {
      _searchCache.remove(cacheKey);
      return null;
    }

    return cached;
  }

  static void _writeSearchCache(
    String cacheKey,
    List<String> results,
    String source,
  ) {
    if (_searchCache.length >= _maxSearchCacheEntries) {
      final oldestKey = _searchCache.entries
          .reduce((a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _searchCache.remove(oldestKey);
    }

    _searchCache[cacheKey] = _CachedSearchResult(
      results: results,
      source: source,
      createdAt: DateTime.now(),
    );
  }

  static Duration _searchCacheTtl(String category) {
    if (category == 'economy' || category == 'current' || category == 'slang') {
      return const Duration(minutes: 20);
    }
    if (category == 'festival' || category == 'phenology') {
      return const Duration(hours: 6);
    }
    if (category == 'canon') {
      return const Duration(hours: 12);
    }
    return const Duration(hours: 1);
  }

  // 搜索结果降噪：
  // - 去掉空摘要、纯导航文字、明显太短的结果
  // - 同一域名 + 相似标题只保留一个
  // - 重新编号，避免过滤后出现 1、3、4 这种跳号
  static List<String> _postProcessSearchResults(
    List<String> results,
    String category,
  ) {
    final cleaned = <String>[];
    final seen = <String>{};

    for (final raw in results) {
      final item = _stripSearchIndex(raw).trim();
      if (item.isEmpty || _isNoisySearchResult(item)) continue;

      final title = item.split('：').first.trim();
      final domain = _canonicalSearchDomain(_extractDomain(item));
      final dedupeKey = '${domain.isEmpty ? 'unknown' : domain}|${_normalizeForDedupe(title)}';
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);

      cleaned.add('${cleaned.length + 1}. $item');
      if (cleaned.length >= _maxResultsForCategory(category)) break;
    }

    return cleaned;
  }

  static int _maxResultsForCategory(String category) {
    if (category == 'economy') return 5;
    if (category == 'canon') return 4;
    return 4;
  }

  static String _stripSearchIndex(String text) {
    return text.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '');
  }

  static bool _isNoisySearchResult(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 18) return true;
    return RegExp(
      r'登录|註冊|注册|客户端下载|隐私政策|cookie|403|404|Access Denied|Just a moment',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static String _extractDomain(String text) {
    final match = RegExp(r'https?://([^/\s）)]+)').firstMatch(text);
    if (match == null) return '';
    return match.group(1)!.replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
  }

  static String _canonicalSearchDomain(String domain) {
    if (domain.endsWith('moegirl.org.cn') || domain.endsWith('moegirl.tw')) {
      return 'moegirl';
    }
    if (domain.endsWith('fandom.com')) {
      return 'fandom';
    }
    return domain;
  }

  static String _normalizeForDedupe(String text) {
    return text
        .toLowerCase()
        .replaceFirst(RegExp(r'\s*[-－—|｜].*(萌娘百科|wiki|wikipedia|fandom).*'), '')
        .replaceAll(RegExp(r'[\s\-_｜|:：,，.。#]+'), '')
        .trim();
  }

  // 这里用 DuckDuckGo 的 HTML 搜索页做“无需 API key”的简易兜底搜索。
  // 优点：不用注册搜索服务。
  // 缺点：网页结构可能变化，稳定性不如 Tavily / Brave Search / SerpAPI。
  //
  // 现在它只作为 Tavily 不可用时的备用方案。
  static Future<List<String>> _searchDuckDuckGo(String query) async {
    try {
      final uri = Uri.https('duckduckgo.com', '/html/', {'q': query});
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(_timeout);
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes);

      // 从 HTML 里粗略提取标题和摘要。
      // 这是“轻量版实现”，不是完整浏览器解析。
      final resultPattern = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      );
      final matches = resultPattern.allMatches(html).take(4).toList();
      final results = <String>[];

      for (var i = 0; i < matches.length; i++) {
        final title = _cleanHtml(matches[i].group(2) ?? '');
        final snippet = _cleanHtml(matches[i].group(3) ?? '');
        if (title.isEmpty && snippet.isEmpty) continue;
        results.add('${i + 1}. $title：$snippet');
      }

      return results;
    } catch (e) {
      print('网页搜索失败: $e');
      return [];
    }
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
    return _decodeHtml(withoutTags)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

  const _SearchPlan({
    required this.includeWeather,
    required this.weatherCity,
    required this.includeFestivals,
    required this.includePhenology,
    required this.searchQuery,
    required this.category,
  });

  // 没有任何任务时，buildContext 可以直接返回空字符串。
  bool get hasAnyTask =>
      includeWeather ||
      includeFestivals ||
      includePhenology ||
      (searchQuery != null && searchQuery!.isNotEmpty);
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

  // 默认天气城市。
  // 鬼灭和祥子是东京，安迪是上海。
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

  // 给 DeepSeek 看的角色联网范围说明。
  // 即使前面已经限制了搜索，这里再提醒模型一次，避免它自由发挥串台。
  String get contextRule {
    if (seriesName == '鬼灭之刃') {
      return '【角色联网范围】只使用日本天气、大正时期已存在的日本民俗/季节行事和《鬼灭之刃》原作/剧情资料。';
    }
    if (seriesName == 'BanG Dream') {
      return '【角色联网范围】使用东京天气、现代日本非政治节日/行事、国际节日、网络流行语、书影音和 BanG Dream/Ave Mujica 相关资料。';
    }
    if (seriesName == '欢乐颂') {
      return '【角色联网范围】使用上海天气、中国节日、国际节日、经济金融、书影音、网络热点和《欢乐颂》相关资料。';
    }
    return '【角色联网范围】只使用与当前对话直接相关的现实信息，不要主动扩展到经济金融或无关新闻。';
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
      // - 固定东京天气，代表日本现实天气参考
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
      );
    }

    if (seriesName == '欢乐颂') {
      // 欢乐颂角色：
      // - 默认上海天气
      // - 允许用户问其他城市天气
      // - 中国节日 + 国际节日
      // - 允许经济、金融、新闻、书影音、原剧资料等完整搜索
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
    );
  }

  static String _seriesNameForCharacterId(String characterId) {
    const seriesByCharacterId = {
      'shinobu': '鬼灭之刃',
      'muichirou': '鬼灭之刃',
      'giyu': '鬼灭之刃',
      'sakiko': 'BanG Dream',
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

  const _SnippetWindow({
    required this.text,
    required this.score,
  });
}

// Tavily 返回的网页结果会先按 query 命中程度排序。
// 原作资料尤其需要把“用户提到的对象”排到前面，而不是完全信搜索引擎原始顺序。
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

// 普通网页搜索缓存项。
// 只存在于本次 app 运行内，重启后自动清空。
class _CachedSearchResult {
  final List<String> results;
  final String source;
  final DateTime createdAt;

  const _CachedSearchResult({
    required this.results,
    required this.source,
    required this.createdAt,
  });
}

// 一个简单的数据结构，表示“某个节日叫什么、在哪一天”。
class _Festival {
  final String name;
  final DateTime date;

  const _Festival(this.name, this.date);
}
