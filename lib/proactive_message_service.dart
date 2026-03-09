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
// App 启动时初始化一次，所有角色的计时器在后台持续运行，
// 与当前打开的是哪个页面完全无关。
//
// 两种情况：
// A. 用户正在看这个角色的聊天页：通过注册的回调直接把消息发出去
// B. 用户不在聊天页（主页或其他角色）：生成消息后存入"离线消息"队列，
//    用户下次打开该角色聊天页时自动读取并显示

class ProactiveMessageService {
  // 单例
  static final ProactiveMessageService _instance =
      ProactiveMessageService._internal();
  factory ProactiveMessageService() => _instance;
  ProactiveMessageService._internal();

  // 每个角色一个定时器，key 是 character.id
  final Map<String, Timer> _timers = {};

  // 每个角色下次触发的计划时间（持久化到 prefs，热重载后依然可读）
  final Map<String, int> _nextFireMinutes = {};

  // 未读数变化回调：存入离线消息时触发，_CharacterCard 收到后立即刷新红点
  final Map<String, void Function(int)> _unreadCallbacks = {};

  // 当前"活跃"角色的回调：ChatPage 打开时注册，关闭时注销
  // 如果某角色的回调存在，说明用户正在看它的聊天页，直接调用回调发消息
  // 回调参数：(japanese, chinese)
  final Map<String, Future<void> Function(String, String)> _activeCallbacks =
      {};

  // 是否已经初始化
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

    // App 启动时补发检查：模拟 App 关闭期间流逝的时间
    _checkOfflineMessages(characters);
  }

  // ========================================
  // [修复1] 时间戳与内容一致性
  // ========================================
  // 原来的写法：先用 DateTime.now() 生成时间上下文，API 生成完内容后，
  // 再随机挑一个"合理时段"的时间戳 —— 两者可能落在不同时段（比如内容是
  // "早上好"，时间戳却是下午）。
  //
  // 修复方法：在调用 API 之前先确定显示时间戳，然后把这个时间戳传给
  // _generateTimeContext()，让内容生成与时间戳保持一致。
  //
  // [修复2] AI 回复自己上一条消息
  // ========================================
  // 原来的写法：把最近几条历史（含末尾的 assistant 消息）原样传给 API，
  // 再追加一条空 user 消息，API 看到 "...assistant, user:''" 就会顺着
  // 自己上一条继续说，造成"AI 回复自己"的感觉。
  //
  // 修复方法：用 _trimProactiveHistory() 去掉历史末尾连续的 assistant 消息，
  // 让历史以 user 消息结尾，AI 生成主动消息时才有"重新开口"的语境。
  //
  // [修复3] 义勇不断提起旧话题（情人节等）
  // ========================================
  // 原来的写法：proactiveInstruction 里只说"不要重复上一次内容"，
  // 但没有明确禁止引用历史中的具体事件，义勇这种话少、每句话都有所指
  // 的角色容易反复提已知的记忆锚点。
  //
  // 修复方法：在 _buildProactiveInstruction() 里加入明确禁令——
  // "禁止提及历史对话中出现过的任何具体事件、节日或话题"。

  // ----------------------------------------
  // 主动消息指令构建（集中管理，各触发路径统一使用）
  // 相比原来分散的字符串字面量，这里加入了对"引用旧话题"的明确禁令，
  // 解决义勇等角色反复提起情人节等具体事件的问题。
  // ----------------------------------------
  String _buildProactiveInstruction() {
    return '''
现在你主动给对方发一条消息。
对方叫凛野，不是炭治郎。称呼用"凛野"或不称呼均可。
用你的角色说话方式，说一句自然的话。
话题必须是全新的：今天的天气感受、任务途中看到的事物、突然想到的感想、季节或自然相关的话题等，言之有物。

【必须遵守的限制】
- 禁止提及或引用对话历史中出现过的任何具体事件、节日、人物行为或话题（例如不得再提情人节、赠礼、上次的任务等）
- 禁止单纯说"你好""在吗""明天见""祝您愉快"之类空洞的问候
- 必须开启一个与以往对话毫无关联的全新话题
''';
  }

  // ----------------------------------------
  // 生成时间上下文
  //
  // forTime 参数：传入则基于该时刻生成，不传则使用 DateTime.now()
  //
  // 修复原因：消息内容（如"早上好"）必须与显示的时间戳对应同一时段，
  // 因此调用方应先确定时间戳，再把它传入此方法，确保两者一致。
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
    return []; // 不传历史，AI 无法感知任何旧话题
  }

  // ----------------------------------------
  // 启动时补发检查（模拟 App 关闭期间的计时）
  // ----------------------------------------
  Future<void> _checkOfflineMessages(List<Character> characters) async {
    // 稍微延迟一下，等 App UI 初始化完再跑，避免抢占启动资源
    await Future.delayed(const Duration(seconds: 3));

    final prefs = await SharedPreferences.getInstance();

    for (final character in characters) {
      final lastProactiveKey = 'last_proactive_${character.id}';
      final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;

      // 从未发过主动消息：没有参照基准时间，跳过补发
      if (lastProactiveMs == 0) {
        print(
            '[${character.name}] No previous proactive message, skipping startup check');
        continue;
      }

      final lastProactive =
          DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
      final hoursSinceLast = DateTime.now().difference(lastProactive).inHours;

      // 未超过冷却期，跳过
      if (hoursSinceLast < character.proactiveMinIntervalHours) continue;

      // 概率判断
      if (Random().nextDouble() >= character.proactiveIdleChance) continue;

      print(
          '[${character.name}] ${hoursSinceLast}h since last message, sending catch-up');

      // 先确定显示时间戳，再生成与之匹配的时间上下文
      // earliest: 上次发送时间 + 最小冷却时长
      // latest  : 当前时刻
      // 这样可以保证"早上好"配的是早上的时间戳，不会出现内容与时间错位
      final fakeTimestamp = _pickReasonableTimestamp(
        earliest: lastProactive
            .add(Duration(hours: character.proactiveMinIntervalHours)),
        latest: DateTime.now(),
      );
      // 用显示时间戳生成时间上下文，保证内容与时间戳所在时段一致
      final timeContext = _generateTimeContext(forTime: fakeTimestamp);

      final latestMessages =
          await StorageService.loadConversation(character.id);

      // 去掉末尾的 assistant 消息，避免 API 把它当成"用户最后一句"来回应
      final proactiveHistory = _trimProactiveHistory(
        StorageService.getRecentMessages(latestMessages, maxMessages: 5),
      );

      try {
        final responseMap = await ApiService.generateResponse(
          characterPersonality: character.personality,
          conversationHistory: proactiveHistory,
          userMessage: '',
          timeContext: timeContext,
          proactiveInstruction: _buildProactiveInstruction(),
        );

        final japanese = responseMap['japanese'] ?? '';
        final chinese = responseMap['chinese'] ?? '';
        if (_isInvalidProactiveContent(japanese)) {
          print('[${character.name}] Invalid content, discarding: $japanese');
          continue;
        }

        // 使用之前已确定的时间戳存储，保证内容与时间戳一致
        await _saveOfflineMessagesWithTimestamp(
            character.id, japanese, chinese, latestMessages, fakeTimestamp);

        await prefs.setInt(
            lastProactiveKey, DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        print('[${character.name}] Error generating catch-up message: $e');
      }
    }
  }

  // 带自定义时间戳的离线消息存储
  // 内部重新 load 最新历史，避免外部传入的快照与实际历史不一致
  Future<void> _saveOfflineMessagesWithTimestamp(
      String characterId,
      String japanese,
      String chinese,
      List<Message> _ignored, // 保留参数签名兼容性，内部不使用
      DateTime timestamp) async {
    // 重新 load 最新历史，防止覆盖 API 调用期间发生的新消息
    final latestMessages = await StorageService.loadConversation(characterId);
    final updatedMessages = List<Message>.from(latestMessages);

    // 清理多余空行
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

    // 累加未读数（ChatPage 打开时会清零）
    final prefs = await SharedPreferences.getInstance();
    final unreadKey = 'unread_$characterId';
    final current = prefs.getInt(unreadKey) ?? 0;
    final newCount = current + 1;
    await prefs.setInt(unreadKey, newCount);

    // 通知 _CharacterCard 刷新红点
    _unreadCallbacks[characterId]?.call(newCount);

    print(
        '[$characterId] Offline message saved (timestamp: $timestamp), unread: $newCount');
  }

  // ----------------------------------------
  // ChatPage 打开时注册回调（让服务知道用户正在看哪个角色）
  // ----------------------------------------
  void registerActiveChat(
      String characterId, Future<void> Function(String, String) callback) {
    _activeCallbacks[characterId] = callback;
  }

  // ChatPage 关闭时注销回调
  void unregisterActiveChat(String characterId) {
    _activeCallbacks.remove(characterId);
  }

  // _CharacterCard 注册未读数变化监听，存入离线消息时实时刷新红点
  void registerUnreadCallback(String characterId, void Function(int) callback) {
    _unreadCallbacks[characterId] = callback;
  }

  void unregisterUnreadCallback(String characterId) {
    _unreadCallbacks.remove(characterId);
  }

  // ----------------------------------------
  // 为单个角色调度下一次检查
  // ----------------------------------------
  void _scheduleNextCheck(Character character) {
    _timers[character.id]?.cancel();

    final randomMinutes = 60 + Random().nextInt(300);
    _nextFireMinutes[character.id] = randomMinutes;

    // 持久化"下次触发时间点"，热重载后调试面板仍能显示
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
  Future<void> _onTimerFired(Character character) async {
    // 检查冷却时间
    final prefs = await SharedPreferences.getInstance();
    final lastProactiveKey = 'last_proactive_${character.id}';
    final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;
    final lastProactive = DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
    final hoursSinceLast = DateTime.now().difference(lastProactive).inHours;

    if (hoursSinceLast < character.proactiveMinIntervalHours) {
      print('[${character.name}] Only ${hoursSinceLast}h since last, skipping');
      return;
    }

    // 概率判断
    if (Random().nextDouble() >= character.proactiveIdleChance) {
      print('[${character.name}] Probability not met, skipping');
      return;
    }

    print('[${character.name}] Proactive message triggered');

    final latestMessages = await StorageService.loadConversation(character.id);

    // 去掉末尾的 assistant 消息，避免 AI 把自己上一条当成"用户发言"来回应
    final proactiveHistory = _trimProactiveHistory(
      StorageService.getRecentMessages(latestMessages, maxMessages: 5),
    );

    // 在调用 API 之前先确定显示时间戳，再生成与之对应的时间上下文。
    // 这样可以保证生成的内容（如"早上好""傍晚了"）与最终显示的时间戳在同一时段。
    //
    // 在线（用户在聊天页）：消息立即送达，时间戳 = 当前时刻。
    // 离线（用户不在聊天页）：消息存入队列，从最近 1 小时内的合理时段取一个时间戳。
    //
    // 注意：isOnlineBeforeCall 仅用于确定时间戳策略，实际投递仍在 API 返回后
    // 再次检查回调是否存在（防止用户在 API 调用期间关闭聊天页的竞争条件）。
    final bool isOnlineBeforeCall = _activeCallbacks.containsKey(character.id);

    final DateTime displayTimestamp;
    if (isOnlineBeforeCall) {
      // 在线投递：消息时间戳就是当前时刻，内容与时间一定匹配
      displayTimestamp = DateTime.now();
    } else {
      // 离线存储：从合理时段内选一个时间戳，再用它生成内容
      displayTimestamp = _pickReasonableTimestamp(
        earliest: DateTime.now().subtract(const Duration(hours: 1)),
        latest: DateTime.now().add(const Duration(minutes: 1)),
      );
    }

    // 用显示时间戳生成时间上下文，保证内容中的时间描述与时间戳一致
    final timeContext = _generateTimeContext(forTime: displayTimestamp);

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: character.personality,
        conversationHistory: proactiveHistory,
        userMessage: '',
        timeContext: timeContext,
        proactiveInstruction: _buildProactiveInstruction(),
      );

      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';
      if (_isInvalidProactiveContent(japanese)) {
        print('[${character.name}] Invalid content, discarding: $japanese');
        return;
      }

      // 记录触发时间
      await prefs.setInt(
          lastProactiveKey, DateTime.now().millisecondsSinceEpoch);

      // API 调用完成后再次检查回调，处理用户在等待期间关闭聊天页的情况
      final callback = _activeCallbacks[character.id];
      if (callback != null) {
        // 情况 A：用户在聊天页，直接投递
        // ChatPage 内部会用 DateTime.now() 作为消息时间戳，与生成内容的时段一致
        print('[${character.name}] User in chat, delivering directly');
        await callback(japanese, chinese);
      } else {
        // 情况 B：用户不在聊天页，存入离线队列
        // 使用之前已确定的 displayTimestamp，保证内容与时间戳一致
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
  // 发消息的合理时段：早上8点 ~ 晚上22点
  // 如果 earliest ~ latest 范围内没有合理时段，
  // 就取最近一个合理时段的随机时间点
  static const int _reasonableStartHour = 8;
  static const int _reasonableEndHour = 22;

  DateTime _pickReasonableTimestamp({
    required DateTime earliest,
    required DateTime latest,
  }) {
    // 在 earliest..latest 范围内收集所有合理分钟点（步长15分钟）
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

    // 范围内没有合理时段时，在今天或明天的合理时段内随机选一个
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
  // 检测 AI 返回的无效内容（占位符、系统描述、空括号等）
  // ----------------------------------------
  bool _isInvalidProactiveContent(String japanese) {
    if (japanese.isEmpty) return true;
    // 纯括号内容（去掉全角/半角括号后为空）
    final stripped = japanese
        .replaceAll(RegExp(r'（[^）]*）'), '')
        .replaceAll(RegExp(r'\([^\)]*\)'), '')
        .replaceAll(RegExp(r'「[^」]*」'), '')
        .trim();
    if (stripped.isEmpty) return true;
    // 含系统性关键词（AI 自我暴露了它在"触发"某个行为）
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
  // 调试：获取所有角色的计时状态（供 UI 展示）
  // ----------------------------------------
  Future<List<Map<String, dynamic>>> getDebugInfo(
      List<Character> characters) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <Map<String, dynamic>>[];

    for (final character in characters) {
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
        hoursSinceStr =
            '${hours}h / 冷却 ${character.proactiveMinIntervalHours}h';
        cooldownOk = hours >= character.proactiveMinIntervalHours;
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
        'idleChance':
            '${(character.proactiveIdleChance * 100).toStringAsFixed(0)}%',
        'serviceRunning': _timers.isNotEmpty,
        'nextFire': nextFireStr,
        'unread': unread,
      });
    }
    return result;
  }

  // ----------------------------------------
  // 调试：强制立刻触发某个角色的主动消息检查（跳过冷却和概率）
  // ----------------------------------------
  Future<void> debugForceProactive(Character character) async {
    print('[DEBUG] Force triggering proactive for ${character.name}');

    final latestMessages = await StorageService.loadConversation(character.id);

    // 去掉末尾的 assistant 消息（与正常触发路径保持一致）
    final proactiveHistory = _trimProactiveHistory(
      StorageService.getRecentMessages(latestMessages, maxMessages: 5),
    );

    // 先确定时间戳，再生成对应内容（与正常触发路径保持一致）
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
        proactiveInstruction: _buildProactiveInstruction(),
      );
      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';
      if (_isInvalidProactiveContent(japanese)) {
        print('[DEBUG] Invalid content, discarding: $japanese');
        return;
      }

      // 写入触发时间戳，调试面板刷新后能看到"上次发送"
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_proactive_${character.id}',
          DateTime.now().millisecondsSinceEpoch);

      // API 完成后再次检查回调（防止竞争条件）
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
    }
  }

  // ----------------------------------------
  // 释放所有定时器（App 退出时调用，可选）
  // ----------------------------------------
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _activeCallbacks.clear();
    _initialized = false;
  }
}
