import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'character_config.dart';
import 'storage_service.dart';
import 'api_service.dart';

// ========================================
// 全局主动消息服务（单例）
// ========================================
// App 启动时初始化一次，所有角色的计时器在后台持续运行。
//
// 与上一版本的核心区别：
// 新增 _getEffectiveSettings()，在每次定时器触发时从 SharedPreferences 读取
// 该角色的用户自定义设置（主动消息开关、间隔、概率），而不是固定读取
// character_config.dart 中的静态字段。
// 这样，用户在设置页修改参数后，无需重启 App 即可在下一次触发时生效。

class ProactiveMessageService {
  static final ProactiveMessageService _instance =
      ProactiveMessageService._internal();
  factory ProactiveMessageService() => _instance;
  ProactiveMessageService._internal();

  final Map<String, Timer> _timers = {};
  final Map<String, int> _nextFireMinutes = {};
  final Map<String, void Function(int)> _unreadCallbacks = {};
  final Map<String, Future<void> Function(String, String)> _activeCallbacks =
      {};
  // 离线消息收取状态回调：通知聊天页当前是否正在为该角色收取离线消息
  // key 是 characterId，value 是接收 bool 的回调（true=正在收取，false=收取完毕）
  final Map<String, void Function(bool)> _fetchingCallbacks = {};
  bool _initialized = false;

  // ----------------------------------------
  // App 启动时调用一次，为所有角色启动定时器
  // ----------------------------------------
  void initialize(List<Character> characters) {
    if (_initialized) return;
    _initialized = true;

    for (final character in characters) {
      _scheduleNextCheck(character);
    }
    print(
        'ProactiveMessageService initialized for ${characters.length} characters');
    _checkOfflineMessages(characters);
  }

  // ========================================
  // 读取角色的有效设置（核心新增方法）
  // ========================================
  // 优先从 SharedPreferences 读取用户在设置页保存的覆盖值；
  // 未设置时回退到 character_config.dart 中该角色的默认配置字段。
  //
  // 返回 Map 包含：
  //   'enabled'       - bool   主动消息总开关
  //   'intervalHours' - int    两次发送之间的最短间隔（小时）
  //   'chance'        - double 触发时实际发送的概率（0.0~1.0）
  //
  // 在 _onTimerFired() 和 _checkOfflineMessages() 的开头调用，
  // 确保每次触发前都读取最新的用户设置，无需重启 App。
  Future<Map<String, dynamic>> _getEffectiveSettings(
      Character character) async {
    final prefs = await SharedPreferences.getInstance();
    final id = character.id;
    return {
      // 主动消息总开关：用户可在设置页关闭，默认开启
      'enabled': prefs.getBool('proactive_enabled_$id') ?? true,
      // 最短发送间隔：用户可修改，默认使用 character_config.dart 中的值
      'intervalHours': prefs.getInt('proactive_interval_$id') ??
          character.proactiveMinIntervalHours,
      // 触发概率：用户可修改，默认使用 character_config.dart 中的值
      'chance': prefs.getDouble('proactive_chance_$id') ??
          character.proactiveIdleChance,
    };
  }

  // ----------------------------------------
  // 主动消息指令构建
  // ----------------------------------------
  // 根据对话元信息（距上次对话多久、最后一条是谁发的）生成不同模式的指令。
  // 不传入对话内容本身，避免 AI 接续旧话题。
  //
  // 参数：
  //   conversationMeta - 由 _buildConversationMeta() 生成的元信息字符串，
  //                      描述距上次对话的时间间隔和最后发言方，不包含对话内容。
  //                      如果对话记录为空，传空字符串。
  String _buildProactiveInstruction({String conversationMeta = ''}) {
    // ----------------------------------------
    // 基础指令：所有主动消息都必须遵守的通用规则
    // ----------------------------------------
    final StringBuffer instruction = StringBuffer();
    instruction.writeln('现在你主动给对方发一条消息。');
    instruction.writeln('对方叫凛野，不是炭治郎。称呼用"凛野"或不称呼均可。');
    instruction.writeln('用你的角色说话方式，说一句自然的话。');

    // ----------------------------------------
    // 根据元信息决定主动消息的"语气模式"
    // ----------------------------------------
    // 这里只根据元信息里的关键词来判断场景，不解析具体数值，
    // 因为元信息字符串是由 _buildConversationMeta() 按固定格式生成的。
    //
    // 三种场景：
    //   1. "好久不见"模式：距上次对话超过 _longAbsenceThresholdDays 天
    //   2. "追问关心"模式：最后一条是 AI 发的且对方没回复
    //   3. 普通新话题模式：其他情况
    if (conversationMeta.contains('【好久不见模式】')) {
      // ----------------------------------------
      // 好久不见模式
      // ----------------------------------------
      // AI 知道距离上次对话很久了，可以自然地表达"好久不见"的感觉，
      // 然后接一个新话题，不要只说"好久不见"就完了。
      instruction.writeln('');
      instruction.writeln(conversationMeta);
      instruction.writeln('');
      instruction.writeln('请先自然地表达"好久不见"的感觉（用你自己的说话方式，不要直接说"好久不见"这四个字），');
      instruction.writeln('然后接一个全新的话题，言之有物。');
      instruction.writeln('不要只说问候就结束，要有实质内容。');
    } else if (conversationMeta.contains('【追问关心模式】')) {
      // ----------------------------------------
      // 追问关心模式
      // ----------------------------------------
      // 上次是 AI 主动发了消息，但对方一直没回复。
      // AI 可以自然地表达关心（"怎么了吗""忙吗"之类），
      // 然后可以接一个新话题，不要让对方感到被追问的压力。
      instruction.writeln('');
      instruction.writeln(conversationMeta);
      instruction.writeln('');
      instruction.writeln('你之前给对方发了消息但对方没有回复。');
      instruction.writeln('请自然地表达一点关心（比如是不是在忙、有没有怎样之类），用你自己的说话方式，');
      instruction.writeln('语气要轻松，不要给对方造成"被追问"的压力。');
      instruction.writeln('然后可以接一个全新的话题，也可以不接，视你的角色性格而定。');
    } else {
      // ----------------------------------------
      // 普通新话题模式（原来的逻辑）
      // ----------------------------------------
      instruction.writeln('话题必须是全新的：今天发生的事情、想与对方分享的事、任务的情况、突然想到的感想、');
      instruction.writeln('想邀请对方同做的事、今天的天气感受、季节或自然相关的话题等，言之有物。');
    }

    // ----------------------------------------
    // 通用限制：所有模式都必须遵守
    // ----------------------------------------
    instruction.writeln('');
    instruction.writeln('【必须遵守的限制】');
    instruction.writeln('- 禁止提及或引用之前对话中出现过的任何具体事件、节日、人物行为或话题');
    instruction.writeln('- 禁止单纯说"你好""在吗""明天见""祝您愉快"之类空洞的问候');
    // "好久不见模式"和"追问关心模式"下，这条限制仍然生效，
    // 但 AI 可以在问候之后接新话题，所以不冲突
    if (!conversationMeta.contains('【好久不见模式】') &&
        !conversationMeta.contains('【追问关心模式】')) {
      instruction.writeln('- 必须开启一个与以往对话毫无关联的全新话题');
    }

    return instruction.toString();
  }

  // ----------------------------------------
  // 构建对话元信息摘要（不含对话内容）
  // ----------------------------------------
  // 从对话历史中提取"距上次对话多久""最后一条是谁发的"等结构化信息，
  // 供 _buildProactiveInstruction() 判断应该用哪种语气模式。
  //
  // 关键设计：只传递时间间隔和发言方，不传递任何对话内容，
  // 这样 AI 不会接续旧话题，但能感知"好久不见"和"对方没回复"。
  //
  // _longAbsenceThresholdDays：
  //   超过这个天数视为"好久不见"，可以根据需要调整。
  //   默认 3 天。设得太小会导致频繁触发"好久不见"模式，
  //   设得太大则需要很久没聊天才会触发。
  static const int _longAbsenceThresholdDays = 14;

  String _buildConversationMeta(List<Message> messages) {
    if (messages.isEmpty) return '';

    final now = DateTime.now();

    // 找到最后一条用户消息和最后一条 AI 消息的时间
    DateTime? lastUserMsgTime;
    DateTime? lastAssistantMsgTime;
    String? lastMsgRole; // 整个对话记录中最后一条消息是谁发的

    for (int i = messages.length - 1; i >= 0; i--) {
      lastMsgRole ??= messages[i].role;
      if (messages[i].role == 'user' && lastUserMsgTime == null) {
        lastUserMsgTime = messages[i].timestamp;
      }
      if (messages[i].role == 'assistant' && lastAssistantMsgTime == null) {
        lastAssistantMsgTime = messages[i].timestamp;
      }
      if (lastUserMsgTime != null && lastAssistantMsgTime != null) break;
    }

    // 计算距离上次有人说话过了多久（取用户和 AI 中较晚的那个）
    final DateTime? lastActivity =
        (lastUserMsgTime != null && lastAssistantMsgTime != null)
            ? (lastUserMsgTime.isAfter(lastAssistantMsgTime)
                ? lastUserMsgTime
                : lastAssistantMsgTime)
            : (lastUserMsgTime ?? lastAssistantMsgTime);

    if (lastActivity == null) return '';

    final Duration gap = now.difference(lastActivity);

    // ----------------------------------------
    // 判断是否进入"好久不见模式"
    // ----------------------------------------
    if (gap.inDays >= _longAbsenceThresholdDays) {
      final String gapDescription = _formatDuration(gap);
      return '【好久不见模式】距离你们上一次对话已经过了$gapDescription。';
    }

    // ----------------------------------------
    // 判断是否进入"追问关心模式"
    // ----------------------------------------
    // 条件：最后一条消息是 AI 发的（对方没回复），且距离那条消息已经过了一定时间。
    // _noReplyThresholdHours 控制"多久没回复才算没回复"，
    // 太短的话 AI 会在对方刚看完消息还没来得及回复时就追问，不自然。
    if (lastMsgRole == 'assistant' && lastAssistantMsgTime != null) {
      final Duration sinceLastAI = now.difference(lastAssistantMsgTime);
      if (sinceLastAI.inHours >= _noReplyThresholdHours) {
        final String gapDescription = _formatDuration(sinceLastAI);
        return '【追问关心模式】你上次给对方发了消息，已经过了$gapDescription，对方还没有回复。';
      }
    }

    // 其他情况：普通新话题模式，不需要额外元信息
    return '';
  }

  // "多久没回复才触发追问关心模式"的阈值（小时）
  static const int _noReplyThresholdHours = 72;

  // 格式化时间间隔为自然语言描述
  static String _formatDuration(Duration duration) {
    if (duration.inDays >= 365) {
      final years = (duration.inDays / 365).floor();
      return '约${years}年';
    } else if (duration.inDays >= 30) {
      final months = (duration.inDays / 30).floor();
      return '约${months}个月';
    } else if (duration.inDays >= 1) {
      return '${duration.inDays}天';
    } else if (duration.inHours >= 1) {
      return '${duration.inHours}小时';
    } else {
      return '${duration.inMinutes}分钟';
    }
  }

  // ----------------------------------------
  // 生成时间上下文
  // ----------------------------------------
  String _generateTimeContext({DateTime? forTime}) {
    final now = forTime ?? DateTime.now();
    final hour = now.hour;
    String timeOfDay;
    if (hour >= 5 && hour < 11) {
      timeOfDay = '早上';
    } else if (hour >= 11 && hour < 13) {
      timeOfDay = '中午';
    } else if (hour >= 13 && hour < 17) {
      timeOfDay = '下午';
    } else if (hour >= 17 && hour < 19) {
      timeOfDay = '傍晚';
    } else if (hour >= 19 && hour < 23) {
      timeOfDay = '晚上';
    } else {
      timeOfDay = '深夜';
    }
    return '現在は${now.year}年${now.month}月${now.day}日、$timeOfDay（${now.hour}:${now.minute.toString().padLeft(2, '0')}）です。';
  }

  List<Message> _trimProactiveHistory(List<Message> messages) {
    return [];
  }

  // ----------------------------------------
  // 启动时补发检查
  // ----------------------------------------
  // 模拟 App 关闭期间的计时，补发遗漏的主动消息。
  // 现在使用 _getEffectiveSettings() 读取用户最新的设置值，
  // 而非直接读取 character.proactiveMinIntervalHours 等字段。
  Future<void> _checkOfflineMessages(List<Character> characters) async {
    await Future.delayed(const Duration(seconds: 3));

    // 通知首页：开始收取离线消息（显示"消息收取中..."提示条）
    _fetchingCallbacks['__global__']?.call(true);

    final prefs = await SharedPreferences.getInstance();

    for (final character in characters) {
      // 读取该角色的有效设置（含用户覆盖值）
      final settings = await _getEffectiveSettings(character);
      final bool enabled = settings['enabled'] as bool;
      final int intervalHours = settings['intervalHours'] as int;
      final double chance = settings['chance'] as double;

      // 主动消息已被用户关闭时，跳过该角色
      if (!enabled) {
        print('[${character.name}] 主动消息已在设置中关闭，跳过补发检查');
        continue;
      }

      final lastProactiveKey = 'last_proactive_${character.id}';
      final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;

      if (lastProactiveMs == 0) {
        print(
            '[${character.name}] No previous proactive message, skipping startup check');
        continue;
      }

      final lastProactive =
          DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
      final hoursSinceLast = DateTime.now().difference(lastProactive).inHours;

      // 使用从 prefs 读取的 intervalHours，而不是 character.proactiveMinIntervalHours
      if (hoursSinceLast < intervalHours) continue;

      // 使用从 prefs 读取的 chance，而不是 character.proactiveIdleChance
      if (Random().nextDouble() >= chance) continue;

      print(
          '[${character.name}] ${hoursSinceLast}h since last message, sending catch-up');

      final fakeTimestamp = _pickReasonableTimestamp(
        earliest: lastProactive.add(Duration(hours: intervalHours)),
        latest: DateTime.now(),
      );
      final timeContext = _generateTimeContext(forTime: fakeTimestamp);

      final latestMessages =
          await StorageService.loadConversation(character.id);
      final proactiveHistory = _trimProactiveHistory(
        StorageService.getRecentMessages(latestMessages, maxMessages: 5),
      );

      // 从对话记录中提取元信息（距上次对话多久、最后谁发的），
      // 不传内容本身，避免 AI 接续旧话题
      final conversationMeta = _buildConversationMeta(latestMessages);

      try {
        final responseMap = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: proactiveHistory,
          userMessage: '',
          timeContext: timeContext,
          proactiveInstruction: _buildProactiveInstruction(
            conversationMeta: conversationMeta,
          ),
        );

        final japanese = responseMap['japanese'] ?? '';
        final chinese = responseMap['chinese'] ?? '';
        if (_isInvalidProactiveContent(japanese)) {
          print('[${character.name}] Invalid content, discarding: $japanese');
          continue;
        }

        await _saveOfflineMessagesWithTimestamp(
            character.id, japanese, chinese, latestMessages, fakeTimestamp);

        await prefs.setInt(
            lastProactiveKey, DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        print('[${character.name}] Error generating catch-up message: $e');
      }
    }

    // 所有角色检查完毕，通知首页收取结束（隐藏提示条）
    _fetchingCallbacks['__global__']?.call(false);
  }

  Future<void> _saveOfflineMessagesWithTimestamp(
      String characterId,
      String japanese,
      String chinese,
      List<Message> _ignored,
      DateTime timestamp) async {
    final latestMessages = await StorageService.loadConversation(characterId);
    final updatedMessages = List<Message>.from(latestMessages);

    final cleanJp = japanese.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    final cleanZh = chinese.replaceAll(RegExp(r'\n{2,}'), '\n').trim();

    if (cleanJp.isEmpty) return;

    final displayContent =
        cleanZh.isNotEmpty ? '$cleanJp\n\n中文：$cleanZh' : cleanJp;

    updatedMessages.add(Message(
      role: 'assistant',
      content: displayContent,
      timestamp: timestamp,
      audioPath: null,
    ));

    await StorageService.saveConversation(characterId, updatedMessages);

    final prefs = await SharedPreferences.getInstance();
    final unreadKey = 'unread_$characterId';
    final current = prefs.getInt(unreadKey) ?? 0;
    final newCount = current + 1;
    await prefs.setInt(unreadKey, newCount);

    _unreadCallbacks[characterId]?.call(newCount);

    print(
        '[$characterId] Offline message saved (timestamp: $timestamp), unread: $newCount');
  }

  // ----------------------------------------
  // ChatPage 打开时注册回调
  // ----------------------------------------
  void registerActiveChat(
      String characterId, Future<void> Function(String, String) callback) {
    _activeCallbacks[characterId] = callback;
  }

  void unregisterActiveChat(String characterId) {
    _activeCallbacks.remove(characterId);
  }

  void registerUnreadCallback(String characterId, void Function(int) callback) {
    _unreadCallbacks[characterId] = callback;
  }

  void unregisterUnreadCallback(String characterId) {
    _unreadCallbacks.remove(characterId);
  }

  // ----------------------------------------
  // 离线消息收取状态回调
  // ----------------------------------------
  // ChatPage 打开时注册，用于在顶栏显示"消息收取中..."提示
  void registerFetchingCallback(
      String characterId, void Function(bool) callback) {
    _fetchingCallbacks[characterId] = callback;
  }

  void unregisterFetchingCallback(String characterId) {
    _fetchingCallbacks.remove(characterId);
  }

  // ----------------------------------------
  // 为单个角色调度下一次检查
  // ----------------------------------------
  void _scheduleNextCheck(Character character) {
    _timers[character.id]?.cancel();

    final randomMinutes = 60 + Random().nextInt(300);
    _nextFireMinutes[character.id] = randomMinutes;

    SharedPreferences.getInstance().then((prefs) {
      final nextFireAt = DateTime.now().add(Duration(minutes: randomMinutes));
      prefs.setString(
          'next_fire_${character.id}', nextFireAt.toIso8601String());
    });

    print('[${character.name}] Next check in $randomMinutes minutes');

    _timers[character.id] = Timer(
      Duration(minutes: randomMinutes),
      () async {
        await _onTimerFired(character);
        _scheduleNextCheck(character);
      },
    );
  }

  // ----------------------------------------
  // 定时器触发时的处理逻辑
  // ----------------------------------------
  // 与原版的核心区别：使用 _getEffectiveSettings() 读取用户在设置页保存的
  // 最新配置，而不是直接读取 character.proactiveMinIntervalHours 等静态字段。
  // 这样用户修改设置后，下一次定时器触发时就会立即生效，无需重启 App。
  Future<void> _onTimerFired(Character character) async {
    // 读取该角色的有效设置（含用户在设置页的覆盖值）
    final settings = await _getEffectiveSettings(character);
    final bool enabled = settings['enabled'] as bool;
    final int intervalHours = settings['intervalHours'] as int;
    final double chance = settings['chance'] as double;

    // 主动消息已被用户在设置页关闭时，跳过本次触发
    if (!enabled) {
      print('[${character.name}] 主动消息已在设置中关闭，跳过本次触发');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastProactiveKey = 'last_proactive_${character.id}';
    final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;
    final lastProactive = DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
    final hoursSinceLast = DateTime.now().difference(lastProactive).inHours;

    // 使用从 prefs 读取的 intervalHours，而不是 character.proactiveMinIntervalHours
    if (hoursSinceLast < intervalHours) {
      print('[${character.name}] Only ${hoursSinceLast}h since last, skipping');
      return;
    }

    // 使用从 prefs 读取的 chance，而不是 character.proactiveIdleChance
    if (Random().nextDouble() >= chance) {
      print('[${character.name}] Probability not met, skipping');
      return;
    }

    print('[${character.name}] Proactive message triggered');

    final latestMessages = await StorageService.loadConversation(character.id);
    final proactiveHistory = _trimProactiveHistory(
      StorageService.getRecentMessages(latestMessages, maxMessages: 5),
    );

    // 从对话记录中提取元信息（距上次对话多久、最后谁发的），
    // 不传内容本身，避免 AI 接续旧话题
    final conversationMeta = _buildConversationMeta(latestMessages);

    final bool isOnlineBeforeCall = _activeCallbacks.containsKey(character.id);

    final DateTime displayTimestamp;
    if (isOnlineBeforeCall) {
      displayTimestamp = DateTime.now();
    } else {
      displayTimestamp = _pickReasonableTimestamp(
        earliest: DateTime.now().subtract(const Duration(hours: 1)),
        latest: DateTime.now().add(const Duration(minutes: 1)),
      );
    }

    final timeContext = _generateTimeContext(forTime: displayTimestamp);

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: character.personality,
        conversationHistory: proactiveHistory,
        userMessage: '',
        timeContext: timeContext,
        proactiveInstruction: _buildProactiveInstruction(
          conversationMeta: conversationMeta,
        ),
      );

      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';
      if (_isInvalidProactiveContent(japanese)) {
        print('[${character.name}] Invalid content, discarding: $japanese');
        return;
      }

      await prefs.setInt(
          lastProactiveKey, DateTime.now().millisecondsSinceEpoch);

      final callback = _activeCallbacks[character.id];
      if (callback != null) {
        print('[${character.name}] User in chat, delivering directly');
        await callback(japanese, chinese);
      } else {
        print('[${character.name}] User not in chat, saving offline');
        await _saveOfflineMessagesWithTimestamp(
            character.id, japanese, chinese, latestMessages, displayTimestamp);
      }
    } catch (e) {
      print('[${character.name}] Error generating proactive message: $e');
    }
  }

  // ----------------------------------------
  // 工具：在合理时段内选一个随机时间戳
  // ----------------------------------------
  static const int _reasonableStartHour = 8;
  static const int _reasonableEndHour = 22;

  DateTime _pickReasonableTimestamp({
    required DateTime earliest,
    required DateTime latest,
  }) {
    final candidates = <DateTime>[];
    var cursor = earliest;
    while (cursor.isBefore(latest)) {
      if (cursor.hour >= _reasonableStartHour &&
          cursor.hour < _reasonableEndHour) {
        candidates.add(cursor);
      }
      cursor = cursor.add(const Duration(minutes: 15));
    }

    if (candidates.isNotEmpty) {
      return candidates[Random().nextInt(candidates.length)];
    }

    final base = latest.hour < _reasonableStartHour
        ? latest
        : latest.add(const Duration(days: 1));
    final dayStart =
        DateTime(base.year, base.month, base.day, _reasonableStartHour);
    final dayEnd =
        DateTime(base.year, base.month, base.day, _reasonableEndHour);
    final span = dayEnd.difference(dayStart).inMinutes;
    return dayStart.add(Duration(minutes: Random().nextInt(span)));
  }

  // ----------------------------------------
  // 检测 AI 返回的无效内容
  // ----------------------------------------
  bool _isInvalidProactiveContent(String japanese) {
    if (japanese.isEmpty) return true;
    final stripped = japanese
        .replaceAll(RegExp(r'（[^）]*）'), '')
        .replaceAll(RegExp(r'\([^\)]*\)'), '')
        .replaceAll(RegExp(r'「[^」]*」'), '')
        .trim();
    if (stripped.isEmpty) return true;
    final systemKeywords = [
      'システムトリガー',
      'システム',
      'トリガー',
      '[DEBUG]',
      '触发',
      'trigger'
    ];
    for (final kw in systemKeywords) {
      if (japanese.toLowerCase().contains(kw.toLowerCase())) return true;
    }
    return false;
  }

  // ----------------------------------------
  // 调试：获取所有角色的计时状态
  // ----------------------------------------
  Future<List<Map<String, dynamic>>> getDebugInfo(
      List<Character> characters) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <Map<String, dynamic>>[];

    for (final character in characters) {
      // 读取有效设置，调试面板也显示用户覆盖后的值
      final settings = await _getEffectiveSettings(character);
      final int effectiveInterval = settings['intervalHours'] as int;
      final double effectiveChance = settings['chance'] as double;
      final bool proactiveEnabled = settings['enabled'] as bool;

      final lastProactiveKey = 'last_proactive_${character.id}';
      final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;
      final unread = prefs.getInt('unread_${character.id}') ?? 0;

      String lastProactiveStr;
      String hoursSinceStr;
      bool cooldownOk;
      if (lastProactiveMs == 0) {
        lastProactiveStr = '从未发过';
        hoursSinceStr = '-';
        cooldownOk = true;
      } else {
        final lastProactive =
            DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
        final hours = DateTime.now().difference(lastProactive).inHours;
        lastProactiveStr = lastProactive.toString().substring(0, 16);
        hoursSinceStr = '${hours}h / 冷却 ${effectiveInterval}h';
        cooldownOk = hours >= effectiveInterval;
      }

      String nextFireStr = '-';
      final nextFireIso = prefs.getString('next_fire_${character.id}');
      if (nextFireIso != null) {
        final nextFire = DateTime.tryParse(nextFireIso);
        if (nextFire != null) {
          final minutesLeft = nextFire.difference(DateTime.now()).inMinutes;
          nextFireStr = minutesLeft > 0
              ? '$minutesLeft 分钟后（${nextFire.toString().substring(11, 16)}）'
              : '即将触发';
        }
      }

      result.add({
        'name': character.name,
        'id': character.id,
        'lastProactive': lastProactiveStr,
        'hoursSince': hoursSinceStr,
        'cooldownOk': cooldownOk,
        'idleChance': '${(effectiveChance * 100).toStringAsFixed(0)}%',
        'serviceRunning': _timers.isNotEmpty,
        'nextFire': nextFireStr,
        'unread': unread,
        // 在调试面板额外显示主动消息是否被关闭
        'proactiveEnabled': proactiveEnabled,
      });
    }
    return result;
  }

  // ----------------------------------------
  // 调试：强制立刻触发某个角色的主动消息（跳过冷却和概率）
  // ----------------------------------------
  Future<void> debugForceProactive(Character character) async {
    print('[DEBUG] Force triggering proactive for ${character.name}');

    // 通知首页显示"消息收取中..."
    _fetchingCallbacks['__global__']?.call(true);

    final latestMessages = await StorageService.loadConversation(character.id);
    final proactiveHistory = _trimProactiveHistory(
      StorageService.getRecentMessages(latestMessages, maxMessages: 5),
    );

    // 调试触发也使用元信息，这样可以测试"好久不见"和"追问关心"模式
    final conversationMeta = _buildConversationMeta(latestMessages);

    final bool isOnlineBeforeCall = _activeCallbacks.containsKey(character.id);
    final DateTime displayTimestamp;
    if (isOnlineBeforeCall) {
      displayTimestamp = DateTime.now();
    } else {
      displayTimestamp = _pickReasonableTimestamp(
        earliest: DateTime.now().subtract(const Duration(hours: 1)),
        latest: DateTime.now().add(const Duration(minutes: 1)),
      );
    }
    final timeContext = _generateTimeContext(forTime: displayTimestamp);

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: character.personality,
        conversationHistory: proactiveHistory,
        userMessage: '',
        timeContext: timeContext,
        proactiveInstruction: _buildProactiveInstruction(
          conversationMeta: conversationMeta,
        ),
      );
      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';
      if (_isInvalidProactiveContent(japanese)) {
        print('[DEBUG] Invalid content, discarding: $japanese');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_proactive_${character.id}',
          DateTime.now().millisecondsSinceEpoch);

      final callback = _activeCallbacks[character.id];
      if (callback != null) {
        await callback(japanese, chinese);
      } else {
        await _saveOfflineMessagesWithTimestamp(
            character.id, japanese, chinese, latestMessages, displayTimestamp);
      }
      print('[DEBUG] Force trigger complete');
    } catch (e) {
      print('[DEBUG] Force trigger failed: $e');
    } finally {
      // 无论成功失败都通知首页收取结束
      _fetchingCallbacks['__global__']?.call(false);
    }
  }

  // ----------------------------------------
  // 释放所有定时器
  // ----------------------------------------
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _activeCallbacks.clear();
    _fetchingCallbacks.clear();
    _initialized = false;
  }
}
