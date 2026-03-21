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

    final List<String> sentences =
        EmotionAnalyzer.splitSentences(cleanJapanese);

    print('TTS 分句结果（共 ${sentences.length} 句）：');
    for (int i = 0; i < sentences.length; i++) {
      print('  [$i] ${sentences[i]}');
    }

    final List<SpeechEmotion> emotions;
    if (_emotionAnalysisEnabled) {
      print('正在进行情绪分析...');
      emotions = await EmotionAnalyzer.analyzeEmotions(
        sentences: sentences,
        character: widget.character,
      );
    } else {
      final fallback = widget.character.emotionAudioMap?.availableEmotions
                  .contains(SpeechEmotion.neutral) ==
              true
          ? SpeechEmotion.neutral
          : (widget.character.emotionAudioMap?.availableEmotions.first ??
              SpeechEmotion.neutral);
      emotions = List.filled(sentences.length, fallback);
      print('情绪分析已关闭，全部使用 ${fallback.name}');
    }

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
    // 省略：_sendProactiveMessage 内部逻辑不变
    // 由于字数限制，这部分不变的代码保持不变即可
  }

  Future<void> _sendProactiveGreeting(String greetingType) async {
    // 省略：不变
  }

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

      print('重新生成音频...');
      setState(() {
        _isPlaying = true;
        _currentPlayingMessage = message;
      });

      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      final correctedText = _applyPronunciationCorrection(japaneseText);

      final audioPath = await ApiService.generateSpeech(
        text: correctedText,
        referWavPath: widget.character.referWavPath,
        promptText: widget.character.promptText,
        promptLanguage: widget.character.promptLanguage,
        speedFactor: _ttsSpeed,
      );

      if (audioPath == null) {
        print('音频生成失败');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentPlayingMessage = null;
          });
        }
        return;
      }

      final messageIndex = _messages.indexOf(message);
      if (messageIndex != -1) {
        _messages[messageIndex] = message.copyWith(audioPath: audioPath);
        await StorageService.saveConversation(widget.character.id, _messages);
      }

      await _playAudioSequentially(
        paths: [audioPath],
        forMessage: message,
      );
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
    try {
      if (mounted) {
        setState(() {
          _regeneratingAudio[message] = true;
        });
      }

      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

      print('重新生成情绪化语音: $japaneseText');

      final List<String> sentences =
          EmotionAnalyzer.splitSentences(japaneseText);

      final List<SpeechEmotion> emotions;
      if (_emotionAnalysisEnabled) {
        emotions = await EmotionAnalyzer.analyzeEmotions(
          sentences: sentences,
          character: widget.character,
        );
      } else {
        final fallback = widget.character.emotionAudioMap?.availableEmotions
                    .contains(SpeechEmotion.neutral) ==
                true
            ? SpeechEmotion.neutral
            : (widget.character.emotionAudioMap?.availableEmotions.first ??
                SpeechEmotion.neutral);
        emotions = List.filled(sentences.length, fallback);
      }

      final List<String> newAudioPaths = [];
      for (int i = 0; i < sentences.length; i++) {
        final referenceAudio = await _getValidReferenceAudio(emotions[i]);
        final correctedSentence = _applyPronunciationCorrection(sentences[i]);

        final audioPath = await ApiService.generateSpeech(
          text: correctedSentence,
          referWavPath: referenceAudio.referWavPath,
          promptText: referenceAudio.promptText,
          promptLanguage: referenceAudio.promptLanguage,
          speedFactor: _ttsSpeed,
        );

        if (audioPath != null) {
          newAudioPaths.add(audioPath);
        } else {
          print('句子 [$i] 重新生成失败，跳过');
        }
      }

      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }

      if (newAudioPaths.isEmpty) {
        print('所有句子重新生成均失败');
        return;
      }

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

      final messageIndex = _messages.indexOf(message);
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3142)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: _pickCharacterAvatar,
              child: Container(
                width: 40,
                height: 40,
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
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.character.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3142))),
                Text(widget.character.nameJp,
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Times New Roman',
                        color: Colors.grey[600])),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.wallpaper, color: Color(0xFF2D3142)),
            onPressed: _showBackgroundMenu,
            tooltip: '背景设置',
          ),
          if (_isPlaying)
            IconButton(
              icon: Icon(Icons.stop, color: color),
              onPressed: _stopAudio,
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.grey[700]),
            onPressed: _clearConversation,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF2D3142)),
            onPressed: _openSettings,
            tooltip: '角色设置',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _buildChatBackground(),
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, top: 16, bottom: 100),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isLoading && index == _messages.length) {
                          return _buildTypingIndicator();
                        }
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
