import 'dart:ui';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'character_config.dart';
import 'storage_service.dart';
import 'api_service.dart';

// ========================================
// 自定义配置区域 - 在这里修改你的UI设置
// ========================================

// 对话框最大宽度占屏幕的比例（0.0-1.0）
const double MESSAGE_MAX_WIDTH_RATIO = 0.80;

// 注意：AI消息气泡的颜色配置（渐变色、边框色、发光色）已移至 character_config.dart 中
// 每个角色可以在那里配置自己独立的对话框颜色样式

// AI消息气泡发光效果参数（全局参数，所有角色共用）
const double AI_BUBBLE_GLOW_BLUR = 30.0; // 发光范围（越大越扩散，0-50）
const double AI_BUBBLE_GLOW_OPACITY = 0.8; // 发光强度（0.0-1.0，0为无发光，1为最强）

// 对话框圆角大小
const double MESSAGE_BUBBLE_RADIUS = 18.0; // 主圆角
const double MESSAGE_BUBBLE_CORNER_RADIUS = 4.0; // 靠近发送者的小圆角

// 对话框内边距
const double MESSAGE_BUBBLE_HORIZONTAL_PADDING = 16.0; // 左右内边距
const double MESSAGE_BUBBLE_VERTICAL_PADDING = 12.0; // 上下内边距

// 注意：背景图配置（路径、模糊度、不透明度）已移至 character_config.dart 中
// 每个角色可以在那里配置自己独立的背景图和效果参数

// 全局背景图片路径（如果角色没有设置专属背景，则使用此路径）
const String BACKGROUND_IMAGE_PATH = ''; // 例如: 'assets/images/bg.jpg'
// 注意：需要在 pubspec.yaml 中添加 assets 配置

// 聊天区域背景渐变色（当没有背景图时使用）
const List<Color> CHAT_BACKGROUND_GRADIENT = [
  Color(0xFFF5F7FA), // 顶部颜色
  Color(0xFFE8EDF2), // 中部颜色
  Color(0xFFDDE3E9), // 底部颜色
];

// 字体配置 - AI消息原文（日文）
const String AI_ORIGINAL_FONT_FAMILY = 'Yu Mincho'; // 原文字体
const double AI_ORIGINAL_FONT_SIZE = 13.0; // 原文字号
const FontWeight AI_ORIGINAL_FONT_WEIGHT = FontWeight.w500; // 原文粗细

// 字体配置 - AI消息翻译（中文）
const String AI_TRANSLATION_FONT_FAMILY = 'FangSong'; // 翻译字体
const double AI_TRANSLATION_FONT_SIZE = 13.0; // 翻译字号
const FontWeight AI_TRANSLATION_FONT_WEIGHT = FontWeight.normal; // 翻译粗细

// 用户头像路径（填写本地文件路径）
const String USER_AVATAR_PATH =
    'C:\\anime_chat\\我的头像.jpg'; // 例如: 'C:\\Users\\YourName\\Pictures\\avatar.jpg'
// 留空则显示默认头像

// 注音词典配置
// 用于修正GPT-SoVITS发音不准确的词汇
// 格式：'原词': '假名注音'
const Map<String, String> PRONUNCIATION_DICT = {
  // 人名示例
  '炭治郎': 'たんじろう',
  '禰豆子': 'ねずこ',
  '善逸': 'ぜんいつ',
  '伊之助': 'いのすけ',
  '冨岡': 'とみおか',
  '胡蝶': 'こちょう',
  '悲鳴嶼': 'ひめじま',
  '不死川': 'しなずがわ',
  '伊黒': 'いぐろ',
  '甘露寺': 'かんろじ',
  '宇髄': 'うずい',
  '煉獄': 'れんごく',
  '時透': 'ときとう',
  '香奈惠': 'かなえ',
  '葵': 'あおい',
  '童磨': 'どうま',
  '猗窝座': 'あかざ',
  '玉壶': 'ぎょっこ',
  '半天狗': 'はんてんぐ',
  '累': 'るい',
  'お館様': 'おやかたさま',
  '鬼舞辻　無惨': 'きぶつじ　むざん',
  '錆兎': 'さびと',
  '鱗滝': 'うろこだき',

  // 地名、组织名示例
  '鬼殺隊': 'きさつたい',
  '無限城': 'むげんじょう',
  '蜘蛛山': 'なだくもやま',
  '刀鍛冶の里': 'かたなかじのさと',
  '遊郭': 'ゆうかく',
  '十二鬼月': 'じゅうにきづき',
  '上弦の鬼': 'じょうげんのおに',
  '下弦の鬼': 'かげんのおに',
  '藤の花': 'ふじのはな',

  // 其他易读错的词
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

  // 可以继续添加更多...
};

// 是否启用注音功能
const bool ENABLE_PRONUNCIATION_CORRECTION = true;

// 注音模式
// 'replace': 把易读错的汉字直接替换为假名发送给gpt-sovits
const String PRONUNCIATION_MODE = 'replace';

// ========================================
// 聊天页面主组件
// ========================================
class ChatPage extends StatefulWidget {
  final Character character; // 当前聊天的角色信息

  const ChatPage({Key? key, required this.character}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// ========================================
// 聊天页面状态类
// ========================================
class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  // 控制器
  final TextEditingController _textController =
      TextEditingController(); // 输入框控制器
  final ScrollController _scrollController = ScrollController(); // 消息列表滚动控制器
  late AudioPlayer _audioPlayer; // 音频播放器

  // 状态变量
  List<Message> _messages = []; // 对话历史消息列表
  bool _isLoading = false; // 是否正在等待AI回复
  bool _isPlaying = false; // 是否正在播放语音
  bool _modelSwitched = false; // GPT-SoVITS模型是否切换成功
  String? _characterAvatarPath; // 角色自定义头像路径
  String? _backgroundImagePath; // 自定义背景图片路径

  // 消息队列系统
  final List<String> _userMessageQueue = []; // 用户消息队列
  bool _isProcessingQueue = false; // 是否正在处理队列

  // 主动消息系统
  Timer? _proactiveMessageTimer; // 主动消息定时器

  // 新增：重新生成语音的状态跟踪
  final Map<Message, bool> _regeneratingAudio = {}; // 记录每条消息是否正在重新生成
  Message? _currentPlayingMessage; // 当前正在播放的消息

  late AnimationController _typingAnimationController; // "AI正在输入"动画控制器
  late AnimationController _soundWaveController; // 声波动画控制器

  // ========================================
  // 页面初始化
  // ========================================
  @override
  void initState() {
    super.initState();
    _initAudioPlayer(); // 初始化音频播放器
    _loadConversation(); // 加载历史对话记录
    _switchModel(); // 切换到当前角色的GPT-SoVITS模型
    _loadCharacterAvatar(); // 加载自定义角色头像
    _loadBackgroundImage(); // 加载自定义背景图

    // 初始化"AI正在输入"的动画控制器
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // 初始化声波动画控制器
    _soundWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // 2秒一个循环
    );

    // 启动随机主动消息定时器（程序运行期间随时可能触发）
    _scheduleNextProactiveCheck();
  }

  // 初始化音频播放器
  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer.setReleaseMode(ReleaseMode.release);

    // 监听播放完成事件
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null; // 清除当前播放的消息
        });
      }
    });
  }

  // 页面销毁时释放资源
  @override
  void dispose() {
    _proactiveMessageTimer?.cancel(); // 取消主动消息定时器
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    _soundWaveController.dispose();
    super.dispose();
  }

  // ========================================
  // 模型和数据加载相关方法
  // ========================================

  // 切换到当前角色的GPT-SoVITS模型
  Future<void> _switchModel() async {
    print('正在切换到 ${widget.character.name} 的模型...');

    final success = await ApiService.switchCharacterModel(
      gptModelPath: widget.character.gptModelPath,
      sovitsModelPath: widget.character.sovitsModelPath,
    );

    if (mounted) {
      setState(() {
        _modelSwitched = success;
      });

      // 只在控制台输出结果，不显示UI提示
      if (success) {
        print('✅ ${widget.character.name} 的模型切换成功');
      } else {
        print('⚠️ 模型切换失败，可能使用默认模型');
      }
    }
  }

  // 从本地存储加载历史对话记录
  Future<void> _loadConversation() async {
    final messages = await StorageService.loadConversation(widget.character.id);
    if (mounted) {
      setState(() {
        _messages = messages;
      });
    }
    _scrollToBottom();
  }

  // 加载用户自定义的角色头像
  Future<void> _loadCharacterAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_${widget.character.id}');
    if (avatarPath != null && mounted) {
      setState(() {
        _characterAvatarPath = avatarPath;
      });
    }
  }

  // 加载角色专属的聊天背景图
  Future<void> _loadBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    // 使用角色ID作为键名，每个角色有独立的背景图设置
    final bgPath = prefs.getString('background_${widget.character.id}');
    if (bgPath != null && mounted) {
      setState(() {
        _backgroundImagePath = bgPath;
      });
    }
  }

  // ========================================
  // 图片和背景设置相关方法
  // ========================================

  // 选择角色专属的聊天背景图片（从相册）
  Future<void> _pickBackgroundImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // 保存到角色专属的键名，每个角色的背景图独立存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_${widget.character.id}', image.path);

      if (mounted) {
        setState(() {
          _backgroundImagePath = image.path;
        });
      }
    }
  }

  // 清除角色专属的背景图片（恢复默认渐变背景）
  Future<void> _clearBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    // 删除角色专属的背景图设置
    await prefs.remove('background_${widget.character.id}');

    if (mounted) {
      setState(() {
        _backgroundImagePath = null;
      });
    }
  }

  // 选择角色头像（从相册）
  Future<void> _pickCharacterAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // 保存头像路径到本地存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_${widget.character.id}', image.path);

      if (mounted) {
        setState(() {
          _characterAvatarPath = image.path;
        });
      }
    }
  }

  // ========================================
  // 消息发送和处理相关方法
  // ========================================

  // 发送用户消息（加入队列）
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // 创建用户消息对象
    final userMessage = Message(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    // 将用户消息添加到消息列表
    setState(() {
      _messages.add(userMessage);
      _userMessageQueue.add(text); // 加入消息队列
    });

    _textController.clear(); // 清空输入框
    _scrollToBottom(); // 滚动到底部
    await StorageService.saveConversation(widget.character.id, _messages);

    // 如果队列没在处理，开始处理
    if (!_isProcessingQueue) {
      _processMessageQueue();
    }
  }

  // 处理消息队列
  Future<void> _processMessageQueue() async {
    if (_userMessageQueue.isEmpty) {
      setState(() {
        _isProcessingQueue = false;
      });

      // 队列处理完毕，检查是否需要主动发起话题
      _checkForProactiveTopic();
      return;
    }

    setState(() {
      _isProcessingQueue = true;
      _isLoading = true;
    });

    // 取出第一条消息
    final userMessage = _userMessageQueue.removeAt(0);

    // 生成AI回复
    final timeContext = _generateTimeContext();
    final recentMessages = StorageService.getRecentMessages(_messages);

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: widget.character.personality,
        conversationHistory: recentMessages,
        userMessage: userMessage,
        timeContext: timeContext,
      );

      // 提取日文和中文
      final japaneseText = responseMap['japanese'] ?? '';
      final chineseText = responseMap['chinese'] ?? '';

      // 检查是否包含多消息分隔符
      final multiMessages = _parseMultiMessages(japaneseText, chineseText);

      // 依次发送每条消息
      for (var msgData in multiMessages) {
        await _sendAIMessage(msgData['japanese']!, msgData['chinese']!);
        if (multiMessages.length > 1) {
          await Future.delayed(Duration(milliseconds: 800)); // 多消息间隔
        }
      }
    } catch (e) {
      print('⚠️ 生成回复时出错: $e');
    }

    setState(() {
      _isLoading = false;
    });

    // 继续处理下一条
    await _processMessageQueue();
  }

  // 解析多消息回复
  List<Map<String, String>> _parseMultiMessages(
      String japanese, String chinese) {
    // 检查是否包含 <MULTI_MESSAGE> 标签
    if (japanese.contains('<MULTI_MESSAGE>')) {
      final japaneseParts = japanese
          .split('<MULTI_MESSAGE>')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final chineseParts = chinese.contains('<MULTI_MESSAGE>')
          ? chinese
              .split('<MULTI_MESSAGE>')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : [chinese];

      List<Map<String, String>> messages = [];
      for (int i = 0; i < japaneseParts.length; i++) {
        messages.add({
          'japanese': japaneseParts[i],
          'chinese': i < chineseParts.length ? chineseParts[i] : '',
        });
      }
      return messages;
    }

    // 单条消息
    return [
      {'japanese': japanese, 'chinese': chinese}
    ];
  }

  // 发送单条AI消息
  Future<void> _sendAIMessage(String japanese, String chinese) async {
    if (japanese.isEmpty) return;

    final displayContent = '$japanese\n\n中文：$chinese';

    // 生成语音
    print('🎤 生成音频中...');
    final correctedText = _applyPronunciationCorrection(japanese);
    print('原文: $japanese');
    print('注音后: $correctedText');

    final audioPath = await ApiService.generateSpeech(
      text: correctedText,
      referWavPath: widget.character.referWavPath,
      promptText: widget.character.promptText,
      promptLanguage: widget.character.promptLanguage,
    );

    // 创建消息
    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPath,
    );

    if (mounted) {
      setState(() {
        _messages.add(assistantMessage);
      });
    }

    _scrollToBottom();
    await StorageService.saveConversation(widget.character.id, _messages);

    // 自动播放语音
    if (audioPath != null && mounted) {
      print('✅ 语音生成成功，自动播放');
      setState(() {
        _currentPlayingMessage = assistantMessage;
        _isPlaying = true;
      });
      await _playAudioFromPath(audioPath);

      // 等待播放完成后再继续
      while (_isPlaying && mounted) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    } else {
      print('⚠️ 语音生成失败');
    }
  }

  // 检查是否应该主动发起话题（回复完成后）
  // 回复完成后检查是否主动抛出新话题
  Future<void> _checkForProactiveTopic() async {
    // 使用角色配置的概率决定是否主动抛出话题
    if (Random().nextDouble() < widget.character.proactiveTopicChance &&
        mounted &&
        !_isLoading) {
      // 随机延迟2-5秒，模拟思考后再说话
      //final delay = 2 + Random().nextInt(4);
      //await Future.delayed(Duration(seconds: delay));
      if (mounted && !_isLoading && !_isProcessingQueue) {
        await _sendProactiveMessage('topic');
      }
    }
  }

  // 调度下一次随机主动消息检查
  // 每次触发后重新随机设定下一次时间，形成不规律的触发节奏
  void _scheduleNextProactiveCheck() {
    _proactiveMessageTimer?.cancel();

    // 随机间隔：1-6小时之间随机选一个时间点触发检查
    // 触发时不一定发消息，还要经过概率判断
    final randomMinutes = 60 + Random().nextInt(300); // 60-360分钟（1-6小时）
    print('下一次主动消息检查将在 $randomMinutes 分钟后');

    _proactiveMessageTimer = Timer(
      Duration(minutes: randomMinutes),
      () async {
        await _tryProactiveIdleMessage();
        // 发完或者没发，都重新调度下一次
        if (mounted) {
          _scheduleNextProactiveCheck();
        }
      },
    );
  }

  // 尝试发送随机主动消息（随时触发，但受概率和间隔限制）
  Future<void> _tryProactiveIdleMessage() async {
    if (!mounted || _isProcessingQueue || _isLoading) return;

    // 检查距离上次主动消息的时间，避免太频繁
    final prefs = await SharedPreferences.getInstance();
    final lastProactiveKey = 'last_proactive_${widget.character.id}';
    final lastProactiveMs = prefs.getInt(lastProactiveKey) ?? 0;
    final lastProactive = DateTime.fromMillisecondsSinceEpoch(lastProactiveMs);
    final hoursSinceLast = DateTime.now().difference(lastProactive).inHours;

    // 未达到最短间隔，不发送
    if (hoursSinceLast < widget.character.proactiveMinIntervalHours) {
      print(
          '距上次主动消息仅 $hoursSinceLast 小时，最短间隔为 ${widget.character.proactiveMinIntervalHours} 小时，跳过');
      return;
    }

    // 用角色配置的概率决定是否真的发送
    if (Random().nextDouble() >= widget.character.proactiveIdleChance) return;

    print('触发主动消息 (${widget.character.name})');

    // 记录本次主动消息的时间
    await prefs.setInt(lastProactiveKey, DateTime.now().millisecondsSinceEpoch);

    await _sendProactiveMessage('idle');
  }

  // 统一的主动消息发送入口
  // _isLoading 被移到 API 调用前设置：
  // 概率判断阶段（调用此方法之前）不显示省略号气泡，
  // 只有确认要发送、即将请求 DeepSeek 时才出现加载指示器
  Future<void> _sendProactiveMessage(String type) async {
    if (!mounted || _isLoading) return;

    // 主动消息指令注入到system层，不作为user消息传入，避免AI用中文回复
    String proactiveInstruction = '';

    switch (type) {
      case 'topic':
        proactiveInstruction = '''
【自発的な話題継続】
会話が一段落した。あなたから自然に話を続けてください。
前の話題の延長、ふと思ったこと、相手の近況を聞く、何かを提案するなど、何でも構いません。
友達同士の気軽なチャットのように、自然体で話しかけてください。
複数のことを言いたい場合は <MULTI_MESSAGE> で区切って複数メッセージに分けてください。''';
        break;

      case 'idle':
        proactiveInstruction = '''
【自発的なメッセージ】
今、ふと相手のことを思い出してメッセージを送ることにした。
現在の時間帯を踏まえて、自然な理由でメッセージを送ってください。
例：以前話したことを思い出した、今日面白いことがあった、相手のことが気になった、など。
「元気？」「おはよう」だけでなく、具体的な内容を含めてください。
あなたのキャラクターらしい言い方で、自然に話しかけてください。
複数のことを言いたい場合は <MULTI_MESSAGE> で区切ってください。''';
        break;
    }

    final timeContext = _generateTimeContext();
    final recentMessages = StorageService.getRecentMessages(_messages);

    // 概率判断已在调用方完成，确认发送后才在这里开启加载指示器
    setState(() {
      _isLoading = true;
    });

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: widget.character.personality,
        conversationHistory: recentMessages,
        userMessage: '', // 主动消息模式下不需要userMessage
        timeContext: timeContext,
        proactiveInstruction: proactiveInstruction, // 指令注入system层
      );

      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';

      final multiMessages = _parseMultiMessages(japanese, chinese);
      for (var msgData in multiMessages) {
        await _sendAIMessage(msgData['japanese']!, msgData['chinese']!);
        if (multiMessages.length > 1) {
          await Future.delayed(Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      print('⚠️ 生成主动消息时出错: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  // 发送主动问候（首次打开/久未联系）
  // 同 _sendProactiveMessage，_isLoading 移到 API 调用前
  Future<void> _sendProactiveGreeting(String greetingType) async {
    if (!mounted || _isLoading) return;

    // 同样注入system层，避免中文指令导致AI用中文回复
    String proactiveInstruction = '';
    switch (greetingType) {
      case 'initial':
        proactiveInstruction = '''
【初めての挨拶】
これが最初の会話です。自然に挨拶して、自己紹介し、相手の様子を聞いてください。
温かく親しみやすい雰囲気で話しかけてください。
複数のことを言いたい場合は <MULTI_MESSAGE> で区切ってください。''';
        break;
      case 'long_time':
        proactiveInstruction = '''
【久しぶりの連絡】
しばらく話していなかった相手に、自分から連絡することにした。
久しぶりの気持ちを伝え、相手の近況を気にかけてください。
前回話した内容があれば自然に触れても構いません。
複数のことを言いたい場合は <MULTI_MESSAGE> で区切ってください。''';
        break;
    }

    final timeContext = _generateTimeContext();
    final recentMessages = StorageService.getRecentMessages(_messages);

    // 准备完成，即将调用 API，才开启加载指示器
    setState(() {
      _isLoading = true;
    });

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: widget.character.personality,
        conversationHistory: recentMessages,
        userMessage: '',
        timeContext: timeContext,
        proactiveInstruction: proactiveInstruction,
      );

      final japanese = responseMap['japanese'] ?? '';
      final chinese = responseMap['chinese'] ?? '';

      final multiMessages = _parseMultiMessages(japanese, chinese);
      for (var msgData in multiMessages) {
        await _sendAIMessage(msgData['japanese']!, msgData['chinese']!);
        if (multiMessages.length > 1) {
          await Future.delayed(Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      print('⚠️ 生成问候时出错: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  // ========================================
  // 音频播放相关方法
  // ========================================

  // 从本地文件路径播放音频
  Future<void> _playAudioFromPath(String audioPath) async {
    try {
      await _audioPlayer.stop(); // 先停止当前播放

      if (!mounted) return;

      setState(() {
        _isPlaying = true; // 更新播放状态
      });

      // 启动声波动画（循环播放）
      _soundWaveController.repeat();

      // 检查音频文件是否存在
      final file = File(audioPath);
      if (!await file.exists()) {
        print('❌ 音频文件不存在: $audioPath');
        _soundWaveController.stop();
        _soundWaveController.reset();
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
        return;
      }

      print('🔊 播放音频: $audioPath');

      // 设置音频源并播放
      await _audioPlayer.setSource(DeviceFileSource(audioPath));
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.resume();

      // 监听播放完成事件
      _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
        if (state == PlayerState.completed) {
          print('✅ 播放完成');
          if (mounted) {
            setState(() {
              _isPlaying = false;
            });
          }
        }
      });
    } catch (e) {
      print('❌ 播放失败: $e');
      _soundWaveController.stop();
      _soundWaveController.reset();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null;
        });
      }
    }
  }

  // 切换播放/停止（点击播放按钮时调用）
  Future<void> _togglePlayAudio(Message message) async {
    // 如果正在播放这条消息，则停止
    if (_currentPlayingMessage == message && _isPlaying) {
      await _stopAudio();
    } else {
      // 否则播放
      await _playAudio(message);
    }
  }

  // 停止播放音频
  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
      _soundWaveController.stop();
      _soundWaveController.reset();

      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null;
        });
      }
      print('⏹️ 停止播放');
    } catch (e) {
      print('❌ 停止播放失败: $e');
    }
  }

  // 播放指定消息的音频（点击音量图标时调用）
  Future<void> _playAudio(Message message) async {
    try {
      await _audioPlayer.stop(); // 先停止当前播放

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
        _currentPlayingMessage = message; // 记录当前播放的消息
      });

      // 优先使用缓存的音频文件
      if (message.audioPath != null) {
        final file = File(message.audioPath!);
        if (await file.exists()) {
          print('📂 使用缓存的音频: ${message.audioPath}');
          await _playAudioFromPath(message.audioPath!);
          return;
        } else {
          print('⚠️ 缓存的音频文件不存在，重新生成');
        }
      }

      // 如果没有缓存或缓存失效，重新生成音频
      print('🔄 重新生成音频...');

      // 提取日文原文（去掉中文翻译部分）
      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      // 调用GPT-SoVITS API生成语音（应用注音修正）
      final correctedText = _applyPronunciationCorrection(japaneseText);

      final audioPath = await ApiService.generateSpeech(
        text: correctedText, // 使用注音修正后的文本
        referWavPath: widget.character.referWavPath,
        promptText: widget.character.promptText,
        promptLanguage: widget.character.promptLanguage,
      );

      if (audioPath == null) {
        print('❌ 音频生成失败');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentPlayingMessage = null;
          });
        }
        return;
      }

      // 更新消息的音频路径缓存
      final messageIndex = _messages.indexOf(message);
      if (messageIndex != -1) {
        _messages[messageIndex] = message.copyWith(audioPath: audioPath);
        await StorageService.saveConversation(widget.character.id, _messages);
      }

      // 播放生成的音频
      await _playAudioFromPath(audioPath);
    } catch (e) {
      print('❌ 播放错误: $e');
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null;
        });
      }
    }
  }

  // 重新生成指定消息的语音（不重新生成文字）
  Future<void> _regenerateAudio(Message message) async {
    try {
      // 设置重新生成状态（用于显示旋转动画）
      if (mounted) {
        setState(() {
          _regeneratingAudio[message] = true;
        });
      }

      // 提取日文原文（去掉中文翻译部分）
      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      print('🔄 重新生成音频: $japaneseText');

      // 调用GPT-SoVITS API生成语音（应用注音修正）
      final correctedText = _applyPronunciationCorrection(japaneseText);
      print('注音后: $correctedText');

      final audioPath = await ApiService.generateSpeech(
        text: correctedText, // 使用注音修正后的文本
        referWavPath: widget.character.referWavPath,
        promptText: widget.character.promptText,
        promptLanguage: widget.character.promptLanguage,
      );

      // 清除重新生成状态
      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }

      if (audioPath == null) {
        print('❌ 语音生成失败');
        return;
      }

      // 删除旧的音频文件（如果存在）
      if (message.audioPath != null) {
        final oldFile = File(message.audioPath!);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
            print('🗑️ 已删除旧音频文件');
          } catch (e) {
            print('⚠️ 删除旧音频文件失败: $e');
          }
        }
      }

      // 更新消息的音频路径缓存
      final messageIndex = _messages.indexOf(message);
      if (messageIndex != -1) {
        _messages[messageIndex] = message.copyWith(audioPath: audioPath);
        await StorageService.saveConversation(widget.character.id, _messages);

        print('✅ 语音重新生成成功');

        // 自动播放新生成的语音
        if (mounted) {
          setState(() {
            _currentPlayingMessage = _messages[messageIndex];
            _isPlaying = true;
          });
        }
        await _playAudioFromPath(audioPath);
      }
    } catch (e) {
      print('❌ 重新生成语音错误: $e');
      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }
    }
  }

  // 构建带翻译的AI消息（将原文和翻译分开显示，并应用不同字体）
  List<Widget> _buildTranslatedMessage(String content) {
    final parts = content.split('\n\n中文：');
    if (parts.length != 2) {
      return [
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF2D3142),
            height: 1.5,
          ),
        ),
      ];
    }

    return [
      // 原文部分（日文）- 使用原文字体配置
      Text(
        parts[0],
        style: const TextStyle(
          fontFamily: AI_ORIGINAL_FONT_FAMILY,
          fontSize: AI_ORIGINAL_FONT_SIZE,
          fontWeight: AI_ORIGINAL_FONT_WEIGHT,
          color: Color(0xFF2D3142),
          height: 1.5,
        ),
      ),
      const SizedBox(height: 8),
      // 翻译部分（中文）- 磨砂玻璃质感
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Text(
              parts[1],
              style: const TextStyle(
                fontFamily: AI_TRANSLATION_FONT_FAMILY,
                fontSize: AI_TRANSLATION_FONT_SIZE,
                fontWeight: AI_TRANSLATION_FONT_WEIGHT,
                color: Color(0xFF2D3142),
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ========================================
  // 辅助工具方法
  // ========================================

  // 应用注音修正（将文本中的词汇替换为带假名注音的格式）
  String _applyPronunciationCorrection(String text) {
    if (!ENABLE_PRONUNCIATION_CORRECTION) {
      return text;
    }

    String correctedText = text;

    // 遍历注音词典，替换匹配的词汇
    PRONUNCIATION_DICT.forEach((word, pronunciation) {
      if (correctedText.contains(word)) {
        if (PRONUNCIATION_MODE == 'bracket') {
          // 方括号模式：词汇[假名] - 需要GPT-SoVITS支持
          correctedText =
              correctedText.replaceAll(word, '$word[$pronunciation]');
        } else {
          // 直接替换模式：直接用假名替换汉字 - 更稳定
          correctedText = correctedText.replaceAll(word, pronunciation);
        }
      }
    });

    return correctedText;
  }

  // 生成时间上下文信息（让AI感知时间）
  String _generateTimeContext() {
    final now = DateTime.now();
    final weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final monthNames = [
      '一月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '十一月',
      '十二月'
    ];

    // 当前日期时间
    final year = now.year;
    final month = monthNames[now.month - 1];
    final day = now.day;
    final weekday = weekdayNames[now.weekday - 1];
    final hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');

    // 判断时间段
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

    // 判断季节
    String season;
    if (now.month >= 3 && now.month <= 5) {
      season = '春天';
    } else if (now.month >= 6 && now.month <= 8) {
      season = '夏天';
    } else if (now.month >= 9 && now.month <= 11) {
      season = '秋天';
    } else {
      season = '冬天';
    }

    // 计算距离上次对话的时间
    String lastChatInfo = '';
    if (_messages.length >= 2) {
      // 找到上一条assistant消息
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].role == 'assistant') {
          final lastChatTime = _messages[i].timestamp;
          final difference = now.difference(lastChatTime);

          if (difference.inMinutes < 1) {
            lastChatInfo = '距离上次对话：刚刚';
          } else if (difference.inMinutes < 60) {
            lastChatInfo = '距离上次对话：${difference.inMinutes}分钟前';
          } else if (difference.inHours < 24) {
            lastChatInfo = '距离上次对话：${difference.inHours}小时前';
          } else if (difference.inDays < 30) {
            lastChatInfo = '距离上次对话：${difference.inDays}天前';
          } else if (difference.inDays < 365) {
            final months = (difference.inDays / 30).floor();
            lastChatInfo = '距离上次对话：约${months}个月前';
          } else {
            final years = (difference.inDays / 365).floor();
            lastChatInfo = '距离上次对话：约${years}年前';
          }
          break;
        }
      }
    }

    // 构建完整的时间上下文
    String context = '''【当前时间信息】
现在的时间是：${year}年${month}${day}日（${weekday}）${timeOfDay} ${hour}:${minute}
当前季节：${season}''';

    if (lastChatInfo.isNotEmpty) {
      context += '\n$lastChatInfo';
    }

    context += '''

【重要提示】
- 请根据当前时间来调整你的回答和态度
- 如果用户在不合适的时间说了不合时宜的问候（如中午说"早上好"），可以温和地指出
- 如果距离上次对话时间很久，可以自然地表达"好久不见"的感觉
- 可以根据季节和时间提及相关的话题（如冬天提到寒冷、晚上提醒早点休息等）
- 保持自然，不要刻意强调时间信息，只在合适的时候提及
''';

    return context;
  }

  // 格式化消息时间（像微信那样）
  String _formatMessageTime(DateTime messageTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay =
        DateTime(messageTime.year, messageTime.month, messageTime.day);

    final hour = messageTime.hour.toString().padLeft(2, '0');
    final minute = messageTime.minute.toString().padLeft(2, '0');
    final timeString = '$hour:$minute';

    // 判断是今天、昨天还是更早
    if (messageDay == today) {
      // 今天：只显示时间
      return timeString;
    } else if (messageDay == yesterday) {
      // 昨天：显示"昨天 HH:mm"
      return '昨天 $timeString';
    } else if (messageDay.year == now.year) {
      // 今年：显示"MM月DD日 HH:mm"
      return '${messageTime.month}月${messageTime.day}日 $timeString';
    } else {
      // 去年或更早：显示"YYYY年MM月DD日 HH:mm"
      return '${messageTime.year}年${messageTime.month}月${messageTime.day}日 $timeString';
    }
  }

  // 滚动消息列表到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 清空当前角色的所有对话记录
  Future<void> _clearConversation() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '确认清空',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3142),
          ),
        ),
        content: const Text(
          '确定要清空所有对话记录吗？',
          style: TextStyle(color: Color(0xFF5A5F73)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '取消',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red[700],
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    // 用户确认后执行清空操作
    if (confirm == true) {
      await StorageService.clearConversation(widget.character.id);
      setState(() {
        _messages.clear();
      });
      _loadConversation();
    }
  }

  // ========================================
  // 单条消息删除
  // ========================================

  // 删除指定下标的单条消息
  // 弹确认对话框 -> 确认后从列表移除 -> 删除音频缓存文件 -> 持久化保存
  // index 为该消息在 _messages 列表中的下标
  Future<void> _deleteMessage(int index) async {
    if (index < 0 || index >= _messages.length) return;

    // 弹出确认对话框，防止误触
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '删除消息',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3142),
          ),
        ),
        content: const Text(
          '确定要删除这条消息吗？',
          style: TextStyle(color: Color(0xFF5A5F73)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '取消',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              // 确认按钮颜色（危险操作用红色，可自行修改）
              foregroundColor: Colors.red[700],
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final targetMessage = _messages[index];

    // 如果正在播放这条消息，先停止播放再删除
    if (_currentPlayingMessage == targetMessage && _isPlaying) {
      await _stopAudio();
    }

    // 删除关联的音频缓存文件（如果存在），避免临时目录堆积
    if (targetMessage.audioPath != null) {
      final audioFile = File(targetMessage.audioPath!);
      if (await audioFile.exists()) {
        try {
          await audioFile.delete();
          print('已删除消息音频缓存: ${targetMessage.audioPath}');
        } catch (e) {
          // 删除失败不阻断主流程，只打印日志
          print('删除音频缓存失败: $e');
        }
      }
    }

    // 从列表移除并刷新UI
    setState(() {
      _messages.removeAt(index);
    });

    // 持久化：将更新后的列表写回本地存储
    await StorageService.saveConversation(widget.character.id, _messages);
    print('消息已删除（下标: $index）');
  }

  // ========================================
  // 气泡右键上下文菜单
  // ========================================

  // 在鼠标右键位置弹出菜单，当前只有"删除消息"一项
  // 如需添加更多操作（如复制文字），在 items 列表里继续追加 PopupMenuItem
  void _showMessageContextMenu(
    BuildContext context,
    Offset globalPosition, // 菜单弹出的屏幕坐标（跟随鼠标位置）
    int index,
    Message message,
  ) async {
    // RelativeRect 描述菜单相对于屏幕四边的距离
    // 用鼠标坐标构造一个 1x1 的矩形，showMenu 会把菜单贴着它弹出
    final RelativeRect position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx + 1,
      globalPosition.dy + 1,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      // 菜单圆角大小（可自行修改）
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      // 菜单背景色（可自行修改）
      color: Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              // 菜单项图标颜色（可自行修改）
              Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
              const SizedBox(width: 10),
              // 菜单项文字颜色（可自行修改）
              Text(
                '删除消息',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[400],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == 'delete') {
      await _deleteMessage(index);
    }
  }

  // 显示背景设置菜单（底部弹出菜单）
  void _showBackgroundMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('选择背景图片'),
              onTap: () {
                Navigator.pop(context);
                _pickBackgroundImage();
              },
            ),
            if (_backgroundImagePath != null)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('清除背景图片'),
                onTap: () {
                  Navigator.pop(context);
                  _clearBackgroundImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // UI构建方法
  // ========================================

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('0xFF${widget.character.color}'));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      // ========================================
      // 顶部标题栏
      // ========================================
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // 返回按钮
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3142)),
          onPressed: () => Navigator.pop(context),
        ),
        // 角色头像和名称显示区域
        title: Row(
          children: [
            // 角色头像（点击可更换）
            GestureDetector(
              onTap: _pickCharacterAvatar,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: _characterAvatarPath != null
                      ? Image.file(
                          File(_characterAvatarPath!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withOpacity(0.7)],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              widget.character.avatar,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 角色名称（中文+日文）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.character.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3142),
                  ),
                ),
                Text(
                  widget.character.nameJp,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Times New Roman',
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        // 右侧操作按钮区域
        actions: [
          // 背景设置按钮
          IconButton(
            icon: const Icon(Icons.wallpaper, color: Color(0xFF2D3142)),
            onPressed: _showBackgroundMenu,
            tooltip: '背景设置',
          ),
          // 停止播放按钮（播放时显示）
          if (_isPlaying)
            IconButton(
              icon: Icon(Icons.stop, color: color),
              onPressed: () async {
                await _audioPlayer.stop();
                if (mounted) {
                  setState(() {
                    _isPlaying = false;
                  });
                }
              },
            ),
          // 清空对话按钮
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.grey[700]),
            onPressed: _clearConversation,
          ),
        ],
      ),
      // ========================================
      // 页面主体
      // ========================================
      body: Stack(
        children: [
          // 主聊天区域（背景+消息列表）
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // 聊天背景层（渐变或图片）
                    _buildChatBackground(),

                    // 消息列表
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: 100, // 留出输入框的空间
                      ),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        // 显示"AI正在输入"指示器
                        if (_isLoading && index == _messages.length) {
                          return _buildTypingIndicator();
                        }

                        // 显示消息气泡
                        final message = _messages[index];
                        final isUser = message.role == 'user';

                        return _buildMessageBubble(
                            message, isUser, color, index);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ========================================
          // 底部输入框（毛玻璃效果）
          // ========================================
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.25),
                    Colors.white.withOpacity(0.15),
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          // 文本输入框
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: color.withOpacity(0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: TextField(
                                controller: _textController,
                                style: const TextStyle(
                                  color: Color(0xFF2D3142),
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: '输入消息...',
                                  hintStyle: TextStyle(
                                    color: const Color.fromARGB(
                                        255, 128, 128, 128),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                maxLines: null, // 允许多行输入
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 发送按钮
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.8)],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send,
                                  color: Colors.white, size: 20),
                              onPressed: _isLoading ? null : _sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // 辅助UI组件构建方法
  // ========================================

  // 构建聊天背景（支持自定义图片或默认渐变）
  Widget _buildChatBackground() {
    // 情况1：使用用户从UI选择的角色专属背景图片
    if (_backgroundImagePath != null &&
        File(_backgroundImagePath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // 背景图片
          Image.file(
            File(_backgroundImagePath!),
            fit: BoxFit.cover,
          ),
          // 模糊和半透明遮罩（使用角色配置的效果参数）
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.character.backgroundBlurSigma, // 使用角色配置的模糊度
                sigmaY: widget.character.backgroundBlurSigma,
              ),
              child: Container(
                color: Colors.white.withOpacity(
                  1.0 - widget.character.backgroundOpacity, // 使用角色配置的不透明度
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 情况2：使用全局配置的背景图路径（从assets）
    if (BACKGROUND_IMAGE_PATH.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            BACKGROUND_IMAGE_PATH,
            fit: BoxFit.cover,
          ),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.character.backgroundBlurSigma,
                sigmaY: widget.character.backgroundBlurSigma,
              ),
              child: Container(
                color: Colors.white.withOpacity(
                  1.0 - widget.character.backgroundOpacity,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 情况3：默认渐变背景
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: CHAT_BACKGROUND_GRADIENT,
        ),
      ),
    );
  }

  // 构建"AI正在输入"动画指示器
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 角色头像
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Color(int.parse('0xFF${widget.character.color}'))
                    .withOpacity(0.3),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: _characterAvatarPath != null
                  ? Image.file(
                      File(_characterAvatarPath!),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(int.parse('0xFF${widget.character.color}')),
                            Color(int.parse('0xFF${widget.character.color}'))
                                .withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          widget.character.avatar,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // 三个闪烁的点（循环动画）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(MESSAGE_BUBBLE_CORNER_RADIUS),
                topRight: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                bottomLeft: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                bottomRight: Radius.circular(MESSAGE_BUBBLE_RADIUS),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _typingAnimationController,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    // 每个点有不同的延迟，产生波浪效果
                    final delay = index * 0.3;
                    final value =
                        (_typingAnimationController.value - delay) % 1.0;
                    final opacity = (value < 0.5) ? value * 2 : (1 - value) * 2;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3 + opacity * 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 构建单个消息气泡（包含头像、文本、语音按钮）
  Widget _buildMessageBubble(
      Message message, bool isUser, Color color, int index) {
    // 判断是否需要显示时间标签（间隔超过5分钟或是第一条消息）
    bool shouldShowTime = false;
    if (index == 0) {
      // 第一条消息总是显示时间
      shouldShowTime = true;
    } else {
      // 计算与上一条消息的时间间隔
      final previousMessage = _messages[index - 1];
      final timeDifference =
          message.timestamp.difference(previousMessage.timestamp);
      // 间隔超过5分钟则显示时间
      shouldShowTime = timeDifference.inMinutes >= 5;
    }

    return Column(
      children: [
        // 时间标签（间隔超过5分钟才显示）
        if (shouldShowTime)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _formatMessageTime(message.timestamp),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color.fromARGB(255, 49, 49, 49),
              ),
            ),
          ),
        // 消息内容
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            // 用户消息靠右，AI消息靠左
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI消息才显示头像（在左侧）
              if (!isUser) ...[
                // 角色头像
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: _characterAvatarPath != null
                        ? Image.file(
                            File(_characterAvatarPath!),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.7)],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                widget.character.avatar,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // 消息气泡主体
              Flexible(
                child: ConstrainedBox(
                  // 限制对话框最大宽度（避免太宽）
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        MESSAGE_MAX_WIDTH_RATIO,
                  ),
                  // GestureDetector：右键点击气泡弹出上下文菜单
                  // onSecondaryTapUp 捕获右键抬起时的屏幕坐标，
                  // 用于在鼠标位置附近显示菜单
                  child: GestureDetector(
                    onSecondaryTapUp: (details) {
                      _showMessageContextMenu(
                        context,
                        details.globalPosition, // 菜单弹出位置（跟随鼠标）
                        index,
                        message,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal:
                            MESSAGE_BUBBLE_HORIZONTAL_PADDING, // 在顶部配置区修改
                        vertical: MESSAGE_BUBBLE_VERTICAL_PADDING, // 在顶部配置区修改
                      ),
                      decoration: BoxDecoration(
                        // AI消息：自定义渐变色 + 发光效果
                        gradient: isUser
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget
                                    .character.aiBubbleGradient, // 在顶部配置区修改
                              ),
                        // 用户消息：主题色纯色背景
                        color: isUser ? color.withOpacity(0.6) : null,
                        // 圆角设置（靠近发送者一侧用小圆角）
                        borderRadius: isUser
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                                topRight: Radius.circular(
                                    MESSAGE_BUBBLE_CORNER_RADIUS),
                                bottomLeft:
                                    Radius.circular(MESSAGE_BUBBLE_RADIUS),
                                bottomRight:
                                    Radius.circular(MESSAGE_BUBBLE_RADIUS),
                              )
                            : const BorderRadius.only(
                                topLeft: Radius.circular(
                                    MESSAGE_BUBBLE_CORNER_RADIUS),
                                topRight:
                                    Radius.circular(MESSAGE_BUBBLE_RADIUS),
                                bottomLeft:
                                    Radius.circular(MESSAGE_BUBBLE_RADIUS),
                                bottomRight:
                                    Radius.circular(MESSAGE_BUBBLE_RADIUS),
                              ),
                        // AI消息边框
                        border: !isUser
                            ? Border.all(
                                color: widget
                                    .character.aiBubbleBorderColor, // 在顶部配置区修改
                                width: 1.5,
                              )
                            : null,
                        boxShadow: [
                          // 基础阴影
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                          // AI消息发光效果
                          if (!isUser)
                            BoxShadow(
                              color: widget.character.aiBubbleGlowColor
                                  .withOpacity(
                                      AI_BUBBLE_GLOW_OPACITY), // 在顶部配置区修改
                              blurRadius: AI_BUBBLE_GLOW_BLUR, // 在顶部配置区修改
                              spreadRadius: -2,
                              offset: const Offset(0, 0),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 消息文本（AI消息如果有翻译则分开显示）
                          if (!isUser && message.content.contains('\n\n中文：'))
                            ..._buildTranslatedMessage(message.content)
                          else
                            Text(
                              message.content,
                              style: TextStyle(
                                fontSize: 14,
                                color: isUser
                                    ? Colors.white
                                    : const Color(0xFF2D3142),
                                height: 1.5,
                              ),
                            ),
                          // AI消息底部的按钮区域（播放 / 重新生成）
                          if (!isUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 语音播放/停止按钮
                                  GestureDetector(
                                    onTap: () => _togglePlayAudio(message),
                                    child: _buildPlayButton(message),
                                  ),
                                  const SizedBox(width: 8),
                                  // 重新生成语音按钮（带旋转动画）
                                  GestureDetector(
                                    onTap: () => _regenerateAudio(message),
                                    child: _buildRegenerateButton(message),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ), // GestureDetector
                ),
              ),
              // 用户消息才显示头像（在右侧）
              if (isUser) ...[
                const SizedBox(width: 10),
                // 用户头像
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: USER_AVATAR_PATH.isNotEmpty &&
                            File(USER_AVATAR_PATH).existsSync()
                        ? Image.file(
                            File(USER_AVATAR_PATH),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.7)],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ========================================
  // 按钮构建辅助方法
  // ========================================

  // 构建播放按钮（扇形扩散声波动画）
  Widget _buildPlayButton(Message message) {
    final isPlaying = _currentPlayingMessage == message && _isPlaying;

    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 声波动画层（播放时显示）
          if (isPlaying)
            AnimatedBuilder(
              animation: _soundWaveController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(20, 20),
                  painter: SoundWavePainter(
                    animationValue: _soundWaveController.value,
                    color: widget.character.aiBubbleBorderColor,
                  ),
                );
              },
            ),
          // 喇叭图标
          Icon(
            Icons.volume_down, // 喇叭图标
            size: 18,
            color: widget.character.aiBubbleBorderColor,
          ),
        ],
      ),
    );
  }

  // 构建重新生成按钮（持续旋转动画）
  Widget _buildRegenerateButton(Message message) {
    final isRegenerating = _regeneratingAudio[message] == true;

    if (isRegenerating) {
      // 生成中显示持续旋转动画
      return RotationTransition(
        turns: _typingAnimationController,
        child: Icon(
          Icons.refresh,
          size: 18,
          color: Colors.blue[600],
        ),
      );
    } else {
      // 未生成显示普通刷新图标
      return Icon(
        Icons.refresh,
        size: 18,
        color: Colors.grey[600],
      );
    }
  }
}

// ========================================
// 自定义声波绘制器
// ========================================
class SoundWavePainter extends CustomPainter {
  final double animationValue;
  final Color color;

  SoundWavePainter({
    required this.animationValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);

    // 根据动画值计算当前显示的声波数量（0-4个）
    final waveCount = _calculateWaveCount(animationValue);

    // 绘制多个扇形声波
    for (int i = 0; i < waveCount; i++) {
      // 从图标边缘开始，逐渐扩散
      final radius = size.width * (0.4 + i * 0.18);

      // 绘制弧线（扇形）
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -0.6, // 起始角度
        1.2, // 扫过的角度
        false,
        paint,
      );
    }
  }

  // 计算当前应该显示的声波数量
  int _calculateWaveCount(double value) {
    // 让声波数量在0-3之间循环变化
    // 0.0-0.5: 0->3 (从里到外逐条出现)
    // 0.5-1.0: 3->0 (从外到里逐条消失)
    if (value < 0.5) {
      return (value * 2 * 3).floor().clamp(0, 3); // 0->3
    } else {
      return (3 - (value - 0.5) * 2 * 3).floor().clamp(0, 3); // 3->0
    }
  }

  @override
  bool shouldRepaint(SoundWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
