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
import 'proactive_message_service.dart';
import 'emotion_analyzer.dart';
import 'character_settings_page.dart';

// ========================================
// 自定义配置区域
// ========================================

const double MESSAGE_MAX_WIDTH_RATIO = 0.80;

const double AI_BUBBLE_GLOW_BLUR = 30.0;
const double AI_BUBBLE_GLOW_OPACITY = 0.8;

const double MESSAGE_BUBBLE_RADIUS = 18.0;
const double MESSAGE_BUBBLE_CORNER_RADIUS = 4.0;

const double MESSAGE_BUBBLE_HORIZONTAL_PADDING = 16.0;
const double MESSAGE_BUBBLE_VERTICAL_PADDING = 12.0;

const String BACKGROUND_IMAGE_PATH = '';

const List<Color> CHAT_BACKGROUND_GRADIENT = [
  Color(0xFFF5F7FA),
  Color(0xFFE8EDF2),
  Color(0xFFDDE3E9),
];

// 字体配置 - AI消息原文（日文）
const String AI_ORIGINAL_FONT_FAMILY = 'Yu Mincho';
const double AI_ORIGINAL_FONT_SIZE = 13.0;
const FontWeight AI_ORIGINAL_FONT_WEIGHT = FontWeight.w500;

// 字体配置 - AI消息翻译（中文）
const String AI_TRANSLATION_FONT_FAMILY = 'FangSong';
const double AI_TRANSLATION_FONT_SIZE = 13.0;
const FontWeight AI_TRANSLATION_FONT_WEIGHT = FontWeight.normal;

const String USER_AVATAR_PATH = 'C:\\anime_chat\\我的头像.jpg';

const Map<String, String> PRONUNCIATION_DICT = {
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
};

const bool ENABLE_PRONUNCIATION_CORRECTION = true;
const String PRONUNCIATION_MODE = 'replace';

class ChatPage extends StatefulWidget {
  final Character character;

  const ChatPage({Key? key, required this.character}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AudioPlayer _audioPlayerPrimary = AudioPlayer();
  AudioPlayer _audioPlayerSecondary = AudioPlayer();
  bool _primaryIsActive = true;
  AudioPlayer get _activePlayer =>
      _primaryIsActive ? _audioPlayerPrimary : _audioPlayerSecondary;
  AudioPlayer get _standbyPlayer =>
      _primaryIsActive ? _audioPlayerSecondary : _audioPlayerPrimary;
  Future<void>? _preloadFuture;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _modelSwitched = false;
  String? _characterAvatarPath;
  String? _backgroundImagePath;

  final List<Map<String, String?>> _userMessageQueue = [];
  bool _isProcessingQueue = false;

  // 当前这轮对话中 AI 已经追加了几条连续消息
  // 每次用户发消息时重置为 0，每次 AI 成功追加一条就 +1，
  // 达到 _maxConsecutiveFollowUps 后不再追加
  int _consecutiveCount = 0;

  final Map<Message, bool> _regeneratingAudio = {};
  Message? _currentPlayingMessage;
  Completer<void>? _segmentCompleter;

  String? _pendingImagePath;

  late AnimationController _typingAnimationController;
  late AnimationController _soundWaveController;

  // 设置变量缓存
  String? _personalityOverride;
  String? _userNameOverride;
  String? _userNamePronunciation; // 新增：缓存用户的称呼读音

  bool _showOriginal = true; // 新增：是否显示日文原文
  bool _showTranslation = true;

  bool _emotionAnalysisEnabled = true;
  double _ttsSpeed = 1.0;

  String get _effectivePersonality {
    String base =
        (_personalityOverride != null && _personalityOverride!.isNotEmpty)
            ? _personalityOverride!
            : widget.character.personality;

    if (_userNameOverride != null && _userNameOverride!.isNotEmpty) {
      base += '\n\n[用户称呼设置] 请在对话中用"$_userNameOverride"称呼用户，'
          '忽略以上提示词中的其他称呼设定。';
    }

    return base;
  }

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _loadConversation();
    _switchModel();
    _loadCharacterAvatar();
    _loadBackgroundImage();
    _loadCharacterSettings();

    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _soundWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    ProactiveMessageService().registerActiveChat(
      widget.character.id,
      _onProactiveMessageFromService,
    );

    _clearUnreadCount();
  }

  Future<void> _loadCharacterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    final personalityOverride = prefs.getString('personality_override_$id');
    final userNameOverride = prefs.getString('user_name_$id');
    final userNamePronunciation =
        prefs.getString('user_name_pronunciation_$id');

    final showOriginal = prefs.getBool('show_original_$id') ?? true;
    final showTranslation = prefs.getBool('show_translation_$id') ?? true;

    final emotionAnalysisEnabled =
        prefs.getBool('emotion_analysis_enabled_$id') ?? true;
    final ttsSpeed = prefs.getDouble('tts_speed_$id') ?? 1.0;

    if (mounted) {
      setState(() {
        _personalityOverride =
            (personalityOverride != null && personalityOverride.isNotEmpty)
                ? personalityOverride
                : null;
        _userNameOverride =
            (userNameOverride != null && userNameOverride.isNotEmpty)
                ? userNameOverride
                : null;
        _userNamePronunciation =
            (userNamePronunciation != null && userNamePronunciation.isNotEmpty)
                ? userNamePronunciation
                : null;
        _showOriginal = showOriginal;
        _showTranslation = showTranslation;
        _emotionAnalysisEnabled = emotionAnalysisEnabled;
        _ttsSpeed = ttsSpeed;
      });
    }

    print('已加载角色设置：'
        'userName=$_userNameOverride, '
        'pronunciation=$_userNamePronunciation, '
        'showOriginal=$_showOriginal, '
        'showTranslation=$_showTranslation, '
        'emotionAnalysis=$_emotionAnalysisEnabled, '
        'ttsSpeed=$_ttsSpeed');
  }

  Future<void> _clearUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_${widget.character.id}', 0);
  }

  Future<void> _onProactiveMessageFromService(
      String japanese, String chinese) async {
    if (!mounted || _isLoading || _isProcessingQueue) return;
    await _sendAIMessage(japanese, chinese);
  }

  void _initAudioPlayer() {
    _audioPlayerPrimary.setReleaseMode(ReleaseMode.release);
    _audioPlayerSecondary.setReleaseMode(ReleaseMode.release);
  }

  @override
  void dispose() {
    ProactiveMessageService().unregisterActiveChat(widget.character.id);
    _audioPlayerPrimary.dispose();
    _audioPlayerSecondary.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    _soundWaveController.dispose();
    super.dispose();
  }

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
      if (success) {
        print('${widget.character.name} 的模型切换成功');
      } else {
        print('模型切换失败，可能使用默认模型');
      }
    }
  }

  Future<void> _loadConversation() async {
    final messages = await StorageService.loadConversation(widget.character.id);
    if (mounted) {
      setState(() {
        _messages = messages;
      });
    }
    _scrollToBottom();
  }

  Future<void> _loadCharacterAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_${widget.character.id}');
    if (avatarPath != null && mounted) {
      setState(() {
        _characterAvatarPath = avatarPath;
      });
    }
  }

  Future<void> _loadBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    final bgPath = prefs.getString('background_${widget.character.id}');
    if (bgPath != null && mounted) {
      setState(() {
        _backgroundImagePath = bgPath;
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CharacterSettingsPage(character: widget.character),
      ),
    );
    await _loadCharacterSettings();
  }

  Future<void> _pickBackgroundImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_${widget.character.id}', image.path);
      if (mounted) {
        setState(() {
          _backgroundImagePath = image.path;
        });
      }
    }
  }

  Future<void> _clearBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('background_${widget.character.id}');
    if (mounted) {
      setState(() {
        _backgroundImagePath = null;
      });
    }
  }

  Future<void> _pickCharacterAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_${widget.character.id}', image.path);
      if (mounted) {
        setState(() {
          _characterAvatarPath = image.path;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final imagePath = _pendingImagePath;
    if (text.isEmpty && imagePath == null) return;

    // 用户发了新消息，重置连续追加计数器
    // 这样 AI 对这条新消息的回复之后，又可以重新开始尝试追加
    _consecutiveCount = 0;

    final displayContent = (imagePath != null && text.isEmpty)
        ? '[图片]'
        : (imagePath != null ? '[图片] $text' : text);

    final userMessage = Message(
      role: 'user',
      content: displayContent,
      timestamp: DateTime.now(),
      imagePath: imagePath,
    );

    _textController.clear();
    setState(() {
      _messages.add(userMessage);
      _userMessageQueue.add({'text': text, 'imagePath': imagePath});
      _pendingImagePath = null;
    });

    _scrollToBottom();
    await StorageService.saveConversation(widget.character.id, _messages);

    if (!_isProcessingQueue) {
      _processMessageQueue();
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (image != null && mounted) {
      setState(() {
        _pendingImagePath = image.path;
      });
    }
  }

  Future<void> _processMessageQueue() async {
    if (_userMessageQueue.isEmpty) {
      setState(() {
        _isProcessingQueue = false;
      });
      return;
    }

    setState(() {
      _isProcessingQueue = true;
      _isLoading = true;
    });

    final item = _userMessageQueue.removeAt(0);
    final userMessage = item['text'] ?? '';
    final imagePath = item['imagePath'];

    final timeContext = _generateTimeContext();
    final recentMessages = StorageService.getRecentMessages(_messages);

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: _effectivePersonality,
        conversationHistory: recentMessages,
        userMessage: userMessage,
        timeContext: timeContext,
        imagePath: imagePath,
      );

      final japaneseText = responseMap['japanese'] ?? '';
      final chineseText = responseMap['chinese'] ?? '';

      final imageDescription = responseMap['imageDescription'] ?? '';
      if (imageDescription.isNotEmpty && _messages.isNotEmpty) {
        final idx = _messages
            .lastIndexWhere((m) => m.role == 'user' && m.imagePath != null);
        if (idx != -1) {
          setState(() {
            _messages[idx] =
                _messages[idx].copyWith(imageDescription: imageDescription);
          });
          await StorageService.saveConversation(widget.character.id, _messages);
        }
      }

      await _sendAIMessage(japaneseText, chineseText);

      // ========================================
      // 连续消息判定：AI 回复后有概率追加消息
      // ========================================
      // 每次用户发消息时 _consecutiveCount 被重置为 0（见 _sendMessage），
      // 这里每追加成功一条就 +1，达到 _maxConsecutiveFollowUps 后停止，
      // 防止 AI 无限连发。
      //
      // 只在用户消息队列已空时才尝试追加：
      // 如果用户连续发了好几条消息，AI 应该优先逐条回复，
      // 全部回完之后再考虑是否追加。
      if (_userMessageQueue.isEmpty &&
          _consecutiveCount < _maxConsecutiveFollowUps) {
        _consecutiveCount++;
        await _sendProactiveMessage('follow_up');
      }
    } catch (e) {
      print('生成回复时出错: $e');
    }

    setState(() {
      _isLoading = false;
    });

    await _processMessageQueue();
  }

  Future<void> _sendAIMessage(String japanese, String chinese) async {
    if (japanese.isEmpty) return;

    final cleanJapanese = japanese.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    final cleanChinese = chinese.replaceAll(RegExp(r'\n{2,}'), '\n').trim();

    // 根据设置，组装最终要存入记录的字符串。
    // 即便当前隐藏了翻译，底层文本仍然保存两部分，以便用户随时在设置里开关
    final displayContent = cleanChinese.isNotEmpty
        ? '$cleanJapanese\n\n中文：$cleanChinese'
        : cleanJapanese;

    // 使用统一的情绪分析 + 逐句 TTS 方法生成音频
    final List<String> audioPaths = await _generateEmotionAudio(cleanJapanese);

    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPaths.isNotEmpty ? audioPaths.first : null,
      audioPaths: audioPaths.isNotEmpty ? audioPaths : null,
    );

    if (mounted) {
      setState(() {
        _messages.add(assistantMessage);
        // 消息已生成并加入列表，立即关闭"对方正在输入..."提示
        // 后续的音频播放不需要显示输入状态
        _isLoading = false;
      });
    }

    _scrollToBottom();
    await StorageService.saveConversation(widget.character.id, _messages);

    if (audioPaths.isNotEmpty && mounted) {
      print('开始顺序播放 ${audioPaths.length} 段情绪化语音...');
      await _playAudioSequentially(
        paths: audioPaths,
        forMessage: assistantMessage,
      );
      print('所有音频段播放完毕');
    } else {
      print('没有成功生成的音频段');
    }
  }

  Future<void> _sendProactiveMessage(String type) async {
    // ========================================
    // AI 连续发送多条消息的逻辑
    // ========================================
    // 在 AI 回复用户之后，有一定概率再追加一条消息，模拟"话多时连续发好几条"的感觉。
    // 由 _processMessageQueue 在每次 AI 回复后调用。
    //
    // type 参数目前固定传 'follow_up'，预留给以后扩展其他类型（如 'reaction' 等）。
    //
    // 触发概率由角色配置中的 proactiveTopicChance 控制：
    //   - 蝴蝶忍: 0.35
    //   - 时透无一郎: 0.25
    //   - 富冈义勇: 0.15
    // 可在 character_config.dart 中调整每个角色的 proactiveTopicChance。
    //
    // 连续发送上限由 _maxConsecutiveFollowUps 控制，防止无限连发。
    if (!mounted || _isLoading) return;

    // 概率判定：不满足则跳过，不追加消息
    final double chance = widget.character.proactiveTopicChance;
    if (Random().nextDouble() >= chance) {
      print('连续消息概率未命中（${(chance * 100).toStringAsFixed(0)}%），不追加');
      return;
    }

    print('连续消息概率命中，AI 将追加一条消息');

    setState(() {
      _isLoading = true;
    });

    try {
      final timeContext = _generateTimeContext();
      final recentMessages = StorageService.getRecentMessages(_messages);

      // 追加消息使用正常的对话上下文（包含完整历史），
      // 因为这是同一轮对话中的连续发言，不是隔了很久的主动消息，
      // AI 接着之前的话题说是合理的。
      //
      // proactiveInstruction 传入追加消息的指令，
      // userMessage 传空字符串表示这不是用户发起的对话。
      final responseMap = await ApiService.generateResponse(
          characterPersonality: _effectivePersonality,
          conversationHistory: recentMessages,
          userMessage: '',
          timeContext: timeContext,
          proactiveInstruction: '你刚刚回复了对方的消息，现在你想再补充一句。\n'
              '可以是对刚才话题的延伸、突然想到的相关事情、'
              '或者一个轻松的追加评论。\n'
              '说话方式和语气保持你的角色风格，自然地接上去，不要重复刚才说过的内容。\n');

      final japaneseText = responseMap['japanese'] ?? '';
      final chineseText = responseMap['chinese'] ?? '';

      if (japaneseText.isNotEmpty) {
        // 追加消息和主回复之间加一个短暂延迟，模拟"打字中..."的自然感
        // _followUpDelayMs 控制延迟时长（毫秒），可根据需要调整
        await Future.delayed(Duration(milliseconds: _followUpDelayMs));
        await _sendAIMessage(japaneseText, chineseText);
      }
    } catch (e) {
      print('生成连续消息时出错: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 追加消息和主回复之间的延迟时长（毫秒）
  // 太短（如 500ms）会让两条消息几乎同时出现，不自然
  // 太长（如 5000ms）会让用户等太久
  // 建议 1500~3000ms
  static const int _followUpDelayMs = 2000;

  // 单次对话中最多连续追加几条消息
  // 防止 AI 无限连发。设为 1 表示最多追加 1 条（加上主回复共 2 条），
  // 设为 2 表示最多追加 2 条（共 3 条），以此类推。
  static const int _maxConsecutiveFollowUps = 4;

  // 距离上次对话超过多少天视为"好久不见"，触发 _generateTimeContext 里的强化 prompt
  // AI 会在回复用户消息时自然地带上"好久没聊了"的意思。
  static const int _longAbsenceDays = 14;

  Future<void> _playAudioSequentially({
    required List<String> paths,
    required Message forMessage,
  }) async {
    if (mounted) {
      setState(() {
        _currentPlayingMessage = forMessage;
        _isPlaying = true;
      });
    }

    _primaryIsActive = true;
    _preloadFuture = null;

    for (int i = 0; i < paths.length; i++) {
      if (!_isPlaying || !mounted) {
        print('用户停止播放，中断后续音频段（已播 $i/${paths.length} 段）');
        break;
      }

      print('顺序播放第 ${i + 1}/${paths.length} 段：${paths[i]}');

      _segmentCompleter = Completer<void>();
      await _resumeActivePlayer(paths[i]);
      await _segmentCompleter!.future;

      print('第 ${i + 1}/${paths.length} 段播放完毕');
      _primaryIsActive = !_primaryIsActive;
    }

    _segmentCompleter = null;
    _preloadFuture = null;

    if (mounted) {
      setState(() {
        _isPlaying = false;
        _currentPlayingMessage = null;
      });
      _soundWaveController.stop();
      _soundWaveController.reset();
    }
  }

  Future<void> _resumeActivePlayer(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        print('播放：文件不存在，跳过（$audioPath）');
        if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
          _segmentCompleter!.complete();
        }
        return;
      }

      _soundWaveController.repeat();

      await _activePlayer.setVolume(1.0);
      await _activePlayer.setReleaseMode(ReleaseMode.release);
      await _activePlayer.setSource(DeviceFileSource(audioPath));

      _activePlayer.onPlayerComplete.take(1).listen((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
            _segmentCompleter!.complete();
          }
        });
      });

      await _activePlayer.resume();
    } catch (e) {
      print('播放失败（$audioPath）: $e');
      _soundWaveController.stop();
      _soundWaveController.reset();
      if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
        _segmentCompleter!.complete();
      }
    }
  }

  Future<void> _togglePlayAudio(Message message) async {
    if (_currentPlayingMessage == message && _isPlaying) {
      await _stopAudio();
    } else {
      await _playAudio(message);
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayerPrimary.stop();
      await _audioPlayerSecondary.stop();

      _soundWaveController.stop();
      _soundWaveController.reset();

      if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
        _segmentCompleter!.complete();
      }

      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null;
        });
      }
      print('停止播放');
    } catch (e) {
      print('停止播放失败: $e');
    }
  }

  Future<void> _playAudio(Message message) async {
    try {
      await _audioPlayerPrimary.stop();
      await _audioPlayerSecondary.stop();

      if (!mounted) return;

      if (message.audioPaths != null && message.audioPaths!.isNotEmpty) {
        final existingPaths = <String>[];
        for (final p in message.audioPaths!) {
          if (await File(p).exists()) {
            existingPaths.add(p);
          } else {
            print('音频文件不存在，跳过：$p');
          }
        }

        if (existingPaths.isNotEmpty) {
          print('使用缓存的多段音频，共 ${existingPaths.length} 段');
          await _playAudioSequentially(
            paths: existingPaths,
            forMessage: message,
          );
          return;
        }
        print('多段音频缓存均已失效，重新生成');
      }

      if (message.audioPath != null) {
        final file = File(message.audioPath!);
        if (await file.exists()) {
          print('使用旧版单段缓存音频：${message.audioPath}');
          await _playAudioSequentially(
            paths: [message.audioPath!],
            forMessage: message,
          );
          return;
        }
        print('旧版单段缓存已失效，重新生成');
      }

      // ========================================
      // 缓存音频不存在时的重新生成逻辑
      // ========================================
      // 使用统一的 _generateEmotionAudio 方法，和发送消息、重新生成按钮走完全相同的流程
      print('缓存音频不存在，重新生成...');
      setState(() {
        _isPlaying = true;
        _currentPlayingMessage = message;
      });

      // 提取日文部分（去掉中文翻译）
      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      // 调用统一方法：分句 -> 情绪分析 -> 逐句 TTS
      final newAudioPaths = await _generateEmotionAudio(japaneseText);

      if (newAudioPaths.isEmpty) {
        print('所有句子音频生成均失败');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentPlayingMessage = null;
          });
        }
        return;
      }

      // 更新消息的音频缓存路径，下次点击播放可以直接使用
      // 使用 _findMessageIndex 按时间戳+内容匹配，避免对象引用失效导致找不到消息
      final messageIndex = _findMessageIndex(message);
      if (messageIndex != -1) {
        final updatedMessage = _messages[messageIndex].copyWith(
          audioPath: newAudioPaths.first,
          audioPaths: newAudioPaths,
        );
        if (mounted) {
          setState(() {
            _messages[messageIndex] = updatedMessage;
          });
        }
        await StorageService.saveConversation(widget.character.id, _messages);

        print('开始顺序播放 ${newAudioPaths.length} 段情绪化语音...');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: updatedMessage,
        );
      } else {
        // 即使找不到原消息（极端情况），也尝试播放已生成的音频
        print('未在消息列表中找到原消息，仍尝试播放');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: message,
        );
      }
    } catch (e) {
      print('播放错误: $e');
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingMessage = null;
        });
      }
    }
  }

  Future<void> _regenerateAudio(Message message) async {
    // ========================================
    // 重新生成音频的入口
    // ========================================
    // 先记录消息在列表中的索引位置，用于后续更新消息对象。
    // 使用 _findMessageIndex 按时间戳+内容匹配，而非 _messages.indexOf 的对象引用匹配，
    // 解决"消息对象被替换后 indexOf 返回 -1 导致情绪分析流程被跳过"的问题。
    // 例如：第一次点重新生成后 _messages[i] 被 copyWith 替换成了新对象，
    // 但 UI 层持有的 message 引用仍然是旧对象，indexOf 就找不到了。
    final int messageIndex = _findMessageIndex(message);

    try {
      if (mounted) {
        setState(() {
          _regeneratingAudio[message] = true;
        });
      }

      // 提取日文部分（去掉中文翻译）
      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      print('重新生成情绪化语音...');

      // 调用统一方法：分句 -> 情绪分析 -> 逐句 TTS
      final List<String> newAudioPaths =
          await _generateEmotionAudio(japaneseText);

      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }

      if (newAudioPaths.isEmpty) {
        print('所有句子重新生成均失败');
        return;
      }

      // 删除旧的缓存音频文件
      final oldPaths = message.audioPaths ??
          (message.audioPath != null ? [message.audioPath!] : []);
      for (final oldPath in oldPaths) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
          } catch (e) {
            print('删除旧音频失败: $e');
          }
        }
      }

      if (messageIndex != -1) {
        final updatedMessage = _messages[messageIndex].copyWith(
          audioPath: newAudioPaths.first,
          audioPaths: newAudioPaths,
        );
        if (mounted) {
          setState(() {
            _messages[messageIndex] = updatedMessage;
          });
        }
        await StorageService.saveConversation(widget.character.id, _messages);

        if (!mounted) return;

        try {
          await _audioPlayerPrimary.stop();
          await _audioPlayerSecondary.stop();
        } catch (e) {
          print('停止播放器失败（忽略）: $e');
        }

        if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
          _segmentCompleter!.complete();
        }
        _segmentCompleter = null;
        _preloadFuture = null;
        _primaryIsActive = true;

        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentPlayingMessage = null;
          });
        }

        print('重新生成完成，开始顺序播放 ${newAudioPaths.length} 段...');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: updatedMessage,
        );
      } else {
        // 找不到原消息时的兜底：仍然播放已生成的音频，但无法更新缓存
        print('未在消息列表中找到原消息（index=-1），仍尝试播放');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: message,
        );
      }
    } catch (e) {
      print('重新生成语音错误: $e');
      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }
    }
  }

  // ========================================
  // 核心改动：分离组合原文与译文显示
  // ========================================
  List<Widget> _buildTranslatedMessage(String content) {
    final parts = content.split('\n\n中文：');
    final widgets = <Widget>[];

    // 如果文本中没有拆分出译文，或者译文部分为空
    if (parts.length != 2) {
      if (_showOriginal) {
        widgets.add(Text(
          content,
          style: const TextStyle(
            fontFamily: AI_ORIGINAL_FONT_FAMILY,
            fontSize: AI_ORIGINAL_FONT_SIZE,
            fontWeight: AI_ORIGINAL_FONT_WEIGHT,
            color: Color(0xFF2D3142),
            height: 1.5,
          ),
        ));
      } else {
        // 都没开或者只有翻译开但没翻译数据时，进行占位兜底
        widgets.add(Text('[消息内容已隐藏]',
            style: TextStyle(
                color: Colors.grey[400], fontStyle: FontStyle.italic)));
      }
      return widgets;
    }

    // 存在两部分：parts[0] 是日文，parts[1] 是中文
    if (_showOriginal) {
      widgets.add(
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
      );
    }

    if (_showTranslation) {
      // 只有在同时显示原文时才需要加间距
      if (_showOriginal) widgets.add(const SizedBox(height: 8));
      widgets.add(
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
      );
    }

    // 两者均关闭时的兜底
    if (!_showOriginal && !_showTranslation) {
      widgets.add(Text('[文本内容被用户设置隐藏]',
          style:
              TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic)));
    }

    return widgets;
  }

  // ========================================
  // 辅助工具方法
  // ========================================

  // ----------------------------------------
  // 按时间戳和内容查找消息在 _messages 列表中的索引
  // ----------------------------------------
  // 为什么不用 _messages.indexOf(message)：
  //   Message 是不可变对象，每次 copyWith 都会产生新对象。
  //   当 _playAudio 或 _regenerateAudio 更新消息的 audioPaths 后，
  //   UI 层（GestureDetector.onTap）持有的 message 引用仍是旧对象，
  //   再次调用 indexOf 就会因为对象不同而返回 -1，导致后续更新和播放被跳过。
  //   按时间戳 + 内容匹配可以稳定找到同一条逻辑消息，不受对象替换影响。
  //
  // 匹配规则：同时比对 timestamp 和 content，两者都相同才认为是同一条消息。
  //   - timestamp 精确到毫秒，实际发生碰撞的概率极低
  //   - 加上 content 双重保险，避免极端情况下的误匹配
  int _findMessageIndex(Message message) {
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].timestamp == message.timestamp &&
          _messages[i].content == message.content) {
        return i;
      }
    }
    return -1;
  }

  // ========================================
  // 统一的情绪分析 + 逐句 TTS 生成方法
  // ========================================
  // 三个调用场景（_sendAIMessage / _playAudio / _regenerateAudio）共用此方法，
  // 确保分句、情绪分析、逐句生成、调试输出的逻辑完全一致，不会出现
  // 某个入口漏掉情绪分析或使用不同参数的情况。
  //
  // 参数：
  //   japaneseText - 纯日文文本（不含中文翻译部分）
  //
  // 返回：
  //   生成成功的音频文件路径列表，可能为空（全部失败时）
  //   调用方需要自行处理空列表的情况
  Future<List<String>> _generateEmotionAudio(String japaneseText) async {
    // --- 第一步：分句 ---
    final List<String> sentences = EmotionAnalyzer.splitSentences(japaneseText);

    print('TTS 分句结果（共 ${sentences.length} 句）：');
    for (int i = 0; i < sentences.length; i++) {
      print('  [$i] ${sentences[i]}');
    }

    // --- 第二步：情绪分析 ---
    // 根据 _emotionAnalysisEnabled 开关决定是调用 DeepSeek 分析还是直接用默认情绪
    final List<SpeechEmotion> emotions;
    if (_emotionAnalysisEnabled) {
      print('正在进行情绪分析...');
      emotions = await EmotionAnalyzer.analyzeEmotions(
        sentences: sentences,
        character: widget.character,
      );
    } else {
      // 情绪分析关闭时，使用角色的默认情绪（优先 neutral）
      final fallback = widget.character.emotionAudioMap?.availableEmotions
                  .contains(SpeechEmotion.neutral) ==
              true
          ? SpeechEmotion.neutral
          : (widget.character.emotionAudioMap?.availableEmotions.first ??
              SpeechEmotion.neutral);
      emotions = List.filled(sentences.length, fallback);
      print('情绪分析已关闭，全部使用 ${fallback.name}');
    }

    // --- 第三步：逐句生成 TTS 音频 ---
    print('开始逐句生成情绪化语音...');
    final List<String> audioPaths = [];

    for (int i = 0; i < sentences.length; i++) {
      final String sentence = sentences[i];
      final SpeechEmotion emotion = emotions[i];
      final referenceAudio = await _getValidReferenceAudio(emotion);

      print('句子 [$i] 情绪：${emotion.name}，参考音频：${referenceAudio.referWavPath}');

      // 进行发音替换（包括注音词典和用户名的自动替换）
      final correctedSentence = _applyPronunciationCorrection(sentence);

      final String? audioPath = await ApiService.generateSpeech(
        text: correctedSentence,
        referWavPath: referenceAudio.referWavPath,
        promptText: referenceAudio.promptText,
        promptLanguage: referenceAudio.promptLanguage,
        speedFactor: _ttsSpeed,
      );

      if (audioPath != null) {
        audioPaths.add(audioPath);
        print('句子 [$i] 音频生成成功：$audioPath');
      } else {
        print('句子 [$i] 音频生成失败，跳过该段');
      }
    }

    return audioPaths;
  }

  Future<EmotionReferenceAudio> _getValidReferenceAudio(
      SpeechEmotion emotion) async {
    final audio = widget.character.getReferenceAudio(emotion);
    if (await File(audio.referWavPath).exists()) {
      return audio;
    }
    print('情绪音频文件不存在（${emotion.name}）：${audio.referWavPath}，回退到默认参考音频');
    return EmotionReferenceAudio(
      referWavPath: widget.character.referWavPath,
      promptText: widget.character.promptText,
      promptLanguage: widget.character.promptLanguage,
      description: '默认参考音频（情绪文件缺失时回退）',
    );
  }

  String _applyPronunciationCorrection(String text) {
    String correctedText = text;

    // 1. 处理用户名的读音替换。
    // 如果设置了"用户称呼(汉字)"且设置了"读音(假名)"，就在发送给 TTS 之前将其在文本中替换。
    if (_userNameOverride != null &&
        _userNameOverride!.isNotEmpty &&
        _userNamePronunciation != null &&
        _userNamePronunciation!.isNotEmpty) {
      correctedText =
          correctedText.replaceAll(_userNameOverride!, _userNamePronunciation!);
    }

    // 2. 原有的鬼灭之刃专有名词注音纠正逻辑
    if (ENABLE_PRONUNCIATION_CORRECTION) {
      PRONUNCIATION_DICT.forEach((word, pronunciation) {
        if (correctedText.contains(word)) {
          if (PRONUNCIATION_MODE == 'bracket') {
            correctedText =
                correctedText.replaceAll(word, '$word[$pronunciation]');
          } else {
            correctedText = correctedText.replaceAll(word, pronunciation);
          }
        }
      });
    }

    return correctedText;
  }

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

    final year = now.year;
    final month = monthNames[now.month - 1];
    final day = now.day;
    final weekday = weekdayNames[now.weekday - 1];
    final hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');

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

    String lastChatInfo = '';
    // ----------------------------------------
    // 判断距离上次对话过了多久（用于"好久不见"功能）
    // ----------------------------------------
    // 这里找的是最后一条 assistant 消息的时间戳，代表"上次 AI 和用户对话"的时间点。
    // 之所以找 assistant 而不是 user，是因为如果用户连续发了几条消息还没收到回复，
    // "上次对话"应该算上一次有来有回的时间，而不是用户刚刚单方面发的消息。
    bool isLongAbsence = false;
    if (_messages.length >= 2) {
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
            // 超过 _longAbsenceDays 天视为"好久不见"
            if (difference.inDays >= _longAbsenceDays) {
              isLongAbsence = true;
            }
          } else if (difference.inDays < 365) {
            final months = (difference.inDays / 30).floor();
            lastChatInfo = '距离上次对话：约${months}个月前';
            isLongAbsence = true;
          } else {
            final years = (difference.inDays / 365).floor();
            lastChatInfo = '距离上次对话：约${years}年前';
            isLongAbsence = true;
          }
          break;
        }
      }
    }

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
- 可以根据季节和时间提及相关的话题（如冬天提到寒冷、晚上提醒早点休息等，但也不必每次都提及）
- 保持自然，不要刻意强调时间信息，只在合适的时候提及
''';

    // ----------------------------------------
    // "好久不见"强化指令
    // ----------------------------------------
    // 当距离上次对话超过 _longAbsenceDays 天时，追加一段更强硬的指令，
    // 要求 AI 必须在回复的开头自然地表达"好久不见"的意思。
    //
    // 为什么不把这个逻辑放在上面的"【重要提示】"里？
    // 因为如果每次都带着"如果距离很久就说好久不见"这样的弱提示，
    // AI 大概率会忽略，尤其是 DeepSeek 对条件型指令的遵从度不高。
    // 只有在确实需要的时候才追加这段强指令，效果更好，也不会干扰正常对话。
    //
    // _longAbsenceDays 控制"多少天算好久不见"，可在下方调整。
    if (isLongAbsence) {
      context += '''
【久别重逢】
你们已经很久没有聊天了（$lastChatInfo）。
在回复用户这条消息时，你要用自己的说话方式自然地加入"好久没聊了"的感觉。
注意：
- 用你角色自己的语气和措辞，不要直接说"好久不见"这四个字，要符合你的性格
- 这个表达要自然地融入回复，不要生硬地单独一句
- 同时也要正常回应用户的消息内容，不要只说问候就结束
''';
    }

    return context;
  }

  String _formatMessageTime(DateTime messageTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay =
        DateTime(messageTime.year, messageTime.month, messageTime.day);

    final hour = messageTime.hour.toString().padLeft(2, '0');
    final minute = messageTime.minute.toString().padLeft(2, '0');
    final timeString = '$hour:$minute';

    if (messageDay == today) {
      return timeString;
    } else if (messageDay == yesterday) {
      return '昨天 $timeString';
    } else if (messageDay.year == now.year) {
      return '${messageTime.month}月${messageTime.day}日 $timeString';
    } else {
      return '${messageTime.year}年${messageTime.month}月${messageTime.day}日 $timeString';
    }
  }

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

  Future<void> _clearConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认清空',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        content: const Text('确定要清空所有对话记录吗？',
            style: TextStyle(color: Color(0xFF5A5F73))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.clearConversation(widget.character.id);
      setState(() {
        _messages.clear();
      });
      _loadConversation();
    }
  }

  Future<void> _deleteMessage(int index) async {
    if (index < 0 || index >= _messages.length) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除消息',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        content: const Text('确定要删除这条消息吗？',
            style: TextStyle(color: Color(0xFF5A5F73))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final targetMessage = _messages[index];

    if (_currentPlayingMessage == targetMessage && _isPlaying) {
      await _stopAudio();
    }

    final pathsToDelete = targetMessage.audioPaths ??
        (targetMessage.audioPath != null ? [targetMessage.audioPath!] : []);
    for (final p in pathsToDelete) {
      final f = File(p);
      if (await f.exists()) {
        try {
          await f.delete();
          print('已删除音频缓存: $p');
        } catch (e) {
          print('删除音频缓存失败: $e');
        }
      }
    }

    setState(() {
      _messages.removeAt(index);
    });

    await StorageService.saveConversation(widget.character.id, _messages);
    print('消息已删除（下标: $index）');
  }

  void _showMessageContextMenu(
    BuildContext context,
    Offset globalPosition,
    int index,
    Message message,
  ) async {
    final RelativeRect position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx + 1,
      globalPosition.dy + 1,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
              const SizedBox(width: 10),
              Text('删除消息',
                  style: TextStyle(fontSize: 14, color: Colors.red[400])),
            ],
          ),
        ),
      ],
    );

    if (selected == 'delete') {
      await _deleteMessage(index);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('0xFF${widget.character.color}'));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Stack(
        children: [
          // ========================================
          // 第一层：聊天消息区域（铺满全屏，在 bar 下方也可见）
          // ========================================
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _buildChatBackground(),
                    ListView.builder(
                      controller: _scrollController,
                      // --- top padding 要大于 bar 高度，避免第一条消息被 bar 遮住 ---
                      // kToolbarHeight 约 56，加上状态栏高度和额外间距
                      // 可调：如果 bar 高度有变化，相应调整这里的 top 值
                      padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: MediaQuery.of(context).padding.top +
                              kToolbarHeight +
                              12,
                          bottom: 100),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
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
          // 第二层：底部输入栏（保持原有逻辑不变）
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
                        color: Colors.white.withOpacity(0.3), width: 1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -5)),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_pendingImagePath != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                            File(_pendingImagePath!),
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                              () => _pendingImagePath = null),
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle),
                                            child: const Icon(Icons.close,
                                                size: 11, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  Text('已选择图片，可直接发送或加文字',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _isLoading ? null : _pickImage,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.7),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: color.withOpacity(0.3),
                                        width: 1.5),
                                  ),
                                  child: Icon(Icons.image_outlined,
                                      size: 20, color: color.withOpacity(0.8)),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                        color: color.withOpacity(0.2),
                                        width: 1.5),
                                  ),
                                  child: TextField(
                                    controller: _textController,
                                    style: const TextStyle(
                                        color: Color(0xFF2D3142), fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: _pendingImagePath != null
                                          ? '给图片配上文字（可选）...'
                                          : '输入消息...',
                                      hintStyle: const TextStyle(
                                          color: Color.fromARGB(
                                              255, 128, 128, 128),
                                          fontSize: 14),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 12),
                                    ),
                                    maxLines: null,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [color, color.withOpacity(0.8)]),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: color.withOpacity(0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4))
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ========================================
          // 第三层：顶部悬浮栏 -- 磨砂陶瓷质感，底部圆角，阴影悬浮
          // ========================================
          // 放在 Stack 最顶层，浮在聊天内容和背景之上。
          // 不使用 Scaffold.appBar，这样 bar 底部圆角可以直接露出背景，
          // 不会被系统 AppBar 的不透明矩形背景层遮挡。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              // --- 外层 Container 只负责投射阴影，不裁切 ---
              // 因为 ClipRRect 会把 boxShadow 也裁掉，
              // 所以阴影放在 ClipRRect 外面的这个 Container 上
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                boxShadow: [
                  // 外层浅阴影：制造悬浮离地感
                  // blurRadius 控制阴影扩散范围（可调 6~20），opacity 控制深浅（可调 0.04~0.15）
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                  // 第二层更柔和的远距离阴影，增加空间层次感
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                // --- 底部圆角半径（可调范围 0~24，0 为直角）---
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                child: BackdropFilter(
                  // --- 磨砂模糊程度（可调范围 10~40，越大越模糊越朦胧）---
                  filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                  child: Container(
                    decoration: BoxDecoration(
                      // --- 陶瓷底色渐变：从上到下由浅白到微灰白，模拟真实陶瓷的柔和光泽 ---
                      // 上方 opacity 可调 0.7~0.92（越大越白实），下方 0.55~0.8
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.92),
                          Colors.white.withOpacity(0.72),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                      // --- 统一颜色的边框（borderRadius 要求四边颜色一致）---
                      // 用极淡的灰线勾勒整体轮廓，让 bar 边界更清晰
                      // opacity 可调 0.04~0.12，越大轮廓越明显
                      border: Border.all(
                        color: Colors.black.withOpacity(0.06),
                        width: 0.8,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Color(0xFF2D3142)),
                                onPressed: () => Navigator.pop(context),
                              ),
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
                                        width: 2),
                                  ),
                                  child: ClipOval(
                                    child: _characterAvatarPath != null
                                        ? Image.file(
                                            File(_characterAvatarPath!),
                                            fit: BoxFit.cover)
                                        : Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(colors: [
                                                color,
                                                color.withOpacity(0.7)
                                              ]),
                                            ),
                                            child: Center(
                                              child: Text(
                                                  widget.character.avatar,
                                                  style: const TextStyle(
                                                      fontSize: 20)),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 角色名称 + 状态提示
                              // 正在生成回复时显示"对方正在输入..."（类似微信）
                              // 正常状态显示角色日文名
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.character.name,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2D3142))),
                                    if (_isLoading)
                                      // AI 正在生成回复时的提示
                                      // 颜色可调：目前使用深灰色，和角色日文名的灰色保持统一风格
                                      Text('对方正在输入...',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: const Color.fromARGB(
                                                  255, 42, 42, 42)))
                                    else
                                      // 正常状态显示角色日文名
                                      Text(widget.character.nameJp,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'Times New Roman',
                                              color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                              // 右侧操作按钮
                              IconButton(
                                icon: const Icon(Icons.wallpaper,
                                    color: Color(0xFF2D3142)),
                                onPressed: _showBackgroundMenu,
                                tooltip: '背景设置',
                              ),
                              if (_isPlaying)
                                IconButton(
                                  icon: Icon(Icons.stop, color: color),
                                  onPressed: _stopAudio,
                                ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.grey[700]),
                                onPressed: _clearConversation,
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined,
                                    color: Color(0xFF2D3142)),
                                onPressed: _openSettings,
                                tooltip: '角色设置',
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildChatBackground() {
    if (_backgroundImagePath != null &&
        File(_backgroundImagePath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_backgroundImagePath!), fit: BoxFit.cover),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.character.backgroundBlurSigma,
                sigmaY: widget.character.backgroundBlurSigma,
              ),
              child: Container(
                  color: Colors.white
                      .withOpacity(1.0 - widget.character.backgroundOpacity)),
            ),
          ),
        ],
      );
    }

    if (BACKGROUND_IMAGE_PATH.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(BACKGROUND_IMAGE_PATH, fit: BoxFit.cover),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.character.backgroundBlurSigma,
                sigmaY: widget.character.backgroundBlurSigma,
              ),
              child: Container(
                  color: Colors.white
                      .withOpacity(1.0 - widget.character.backgroundOpacity)),
            ),
          ),
        ],
      );
    }

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

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Color(int.parse('0xFF${widget.character.color}'))
                      .withOpacity(0.3),
                  width: 2),
            ),
            child: ClipOval(
              child: _characterAvatarPath != null
                  ? Image.file(File(_characterAvatarPath!), fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Color(int.parse('0xFF${widget.character.color}')),
                          Color(int.parse('0xFF${widget.character.color}'))
                              .withOpacity(0.7),
                        ]),
                      ),
                      child: Center(
                        child: Text(widget.character.avatar,
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
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
                    offset: const Offset(0, 2))
              ],
            ),
            child: AnimatedBuilder(
              animation: _typingAnimationController,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
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

  Widget _buildMessageBubble(
      Message message, bool isUser, Color color, int index) {
    bool shouldShowTime = false;
    if (index == 0) {
      shouldShowTime = true;
    } else {
      final previousMessage = _messages[index - 1];
      final timeDifference =
          message.timestamp.difference(previousMessage.timestamp);
      shouldShowTime = timeDifference.inMinutes >= 5;
    }

    return Column(
      children: [
        if (shouldShowTime)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _formatMessageTime(message.timestamp),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color.fromARGB(255, 49, 49, 49)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.3), width: 2),
                  ),
                  child: ClipOval(
                    child: _characterAvatarPath != null
                        ? Image.file(File(_characterAvatarPath!),
                            fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [color, color.withOpacity(0.7)]),
                            ),
                            child: Center(
                              child: Text(widget.character.avatar,
                                  style: const TextStyle(fontSize: 18)),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        MESSAGE_MAX_WIDTH_RATIO,
                  ),
                  child: GestureDetector(
                    onSecondaryTapUp: (details) {
                      _showMessageContextMenu(
                          context, details.globalPosition, index, message);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MESSAGE_BUBBLE_HORIZONTAL_PADDING,
                        vertical: MESSAGE_BUBBLE_VERTICAL_PADDING,
                      ),
                      decoration: BoxDecoration(
                        gradient: isUser
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.character.aiBubbleGradient,
                              ),
                        color: isUser ? color.withOpacity(0.6) : null,
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
                        border: !isUser
                            ? Border.all(
                                color: widget.character.aiBubbleBorderColor,
                                width: 1.5)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2)),
                          if (!isUser)
                            BoxShadow(
                              color: widget.character.aiBubbleGlowColor
                                  .withOpacity(AI_BUBBLE_GLOW_OPACITY),
                              blurRadius: AI_BUBBLE_GLOW_BLUR,
                              spreadRadius: -2,
                              offset: const Offset(0, 0),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isUser && message.imagePath != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(message.imagePath!),
                                  width: 180,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 180,
                                    height: 80,
                                    color: Colors.white24,
                                    child: const Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54),
                                  ),
                                ),
                              ),
                            ),
                          if (!(isUser && message.content == '[图片]'))
                            if (!isUser && message.content.contains('\n\n中文：'))
                              ..._buildTranslatedMessage(message.content)
                            else
                              Text(
                                isUser && message.content.startsWith('[图片] ')
                                    ? message.content.substring(5)
                                    : message.content,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isUser
                                      ? Colors.white
                                      : const Color(0xFF2D3142),
                                  height: 1.5,
                                ),
                              ),
                          if (!isUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => _togglePlayAudio(message),
                                    child: _buildPlayButton(message),
                                  ),
                                  const SizedBox(width: 8),
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
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.3), width: 2),
                  ),
                  child: ClipOval(
                    child: USER_AVATAR_PATH.isNotEmpty &&
                            File(USER_AVATAR_PATH).existsSync()
                        ? Image.file(File(USER_AVATAR_PATH), fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [color, color.withOpacity(0.7)]),
                            ),
                            child: const Center(
                              child: Icon(Icons.person,
                                  size: 20, color: Colors.white),
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

  Widget _buildPlayButton(Message message) {
    final isPlaying = _currentPlayingMessage == message && _isPlaying;

    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
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
          Icon(Icons.volume_down,
              size: 18, color: widget.character.aiBubbleBorderColor),
        ],
      ),
    );
  }

  Widget _buildRegenerateButton(Message message) {
    final isRegenerating = _regeneratingAudio[message] == true;

    if (isRegenerating) {
      return RotationTransition(
        turns: _typingAnimationController,
        child: Icon(Icons.refresh, size: 18, color: Colors.blue[600]),
      );
    } else {
      return Icon(Icons.refresh, size: 18, color: Colors.grey[600]);
    }
  }
}

class SoundWavePainter extends CustomPainter {
  final double animationValue;
  final Color color;

  SoundWavePainter({required this.animationValue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    final waveCount = _calculateWaveCount(animationValue);

    for (int i = 0; i < waveCount; i++) {
      final radius = size.width * (0.4 + i * 0.18);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, -0.6, 1.2, false, paint);
    }
  }

  int _calculateWaveCount(double value) {
    if (value < 0.5) {
      return (value * 2 * 3).floor().clamp(0, 3);
    } else {
      return (3 - (value - 0.5) * 2 * 3).floor().clamp(0, 3);
    }
  }

  @override
  bool shouldRepaint(SoundWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
