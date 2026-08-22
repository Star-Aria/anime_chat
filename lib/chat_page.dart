import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'character_config.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'web_context_service.dart';
import 'music_service.dart';
import 'proactive_message_service.dart';
import 'emotion_analyzer.dart';
import 'character_settings_page.dart';
import 'path_service.dart';
import 'name_pronunciation.dart';

// ========================================
// 自定义配置区域
// ========================================

const double messageMaxWidthRatio = 0.80;

const double aiBubbleGlowBlur = 30.0;
const double aiBubbleGlowOpacity = 0.8;

const double messageBubbleRadius = 18.0;
const double messageBubbleCornerRadius = 4.0;

const double messageBubbleHorizontalPadding = 16.0;
const double messageBubbleVerticalPadding = 12.0;

const String backgroundImagePath = '';

const List<Color> chatBackgroundGradient = [
  Color(0xFFF5F7FA),
  Color(0xFFE8EDF2),
  Color(0xFFDDE3E9),
];

// 字体配置 - AI消息原文（日文）
const String aiOriginalFontFamily = 'Yu Mincho';
const double aiOriginalFontSize = 13.0;
const FontWeight aiOriginalFontWeight = FontWeight.w500;

// 字体配置 - AI消息翻译（中文）
const String aiTranslationFontFamily = 'FangSong';
const double aiTranslationFontSize = 13.0;
const FontWeight aiTranslationFontWeight = FontWeight.normal;

const String userAvatarPath = r'assets\我的头像.jpg';

const bool enablePronunciationCorrection = true;
const String pronunciationMode = 'replace';

Map<String, String> _expandedPronunciationMap(
  Map<String, String> source, {
  required bool allowSplitParts,
}) {
  final expanded = <String, String>{};
  for (final entry in source.entries) {
    if (!_isPronunciationKeySafe(entry.key)) continue;
    expanded[entry.key] = entry.value;

    final compactKey = entry.key.replaceAll(RegExp(r'[\s　]+'), '');
    if (compactKey != entry.key && _isPronunciationKeySafe(compactKey)) {
      expanded[compactKey] = entry.value.replaceAll(RegExp(r'[\s　]+'), '');
    }

    if (allowSplitParts) {
      final wordParts = _splitNameLikeText(entry.key);
      final pronunciationParts = _splitByNameSeparators(entry.value);
      if (wordParts.length == pronunciationParts.length &&
          wordParts.length > 1) {
        for (int i = 0; i < wordParts.length; i++) {
          if (!_isPronunciationPartKeySafe(wordParts[i])) continue;
          expanded.putIfAbsent(wordParts[i], () => pronunciationParts[i]);
        }
      }
    }
  }
  return expanded;
}

bool _isPronunciationKeySafe(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(trimmed);
}

bool _isPronunciationPartKeySafe(String key) {
  final trimmed = key.trim();
  if (!_isPronunciationKeySafe(trimmed)) return false;

  // Avoid global replacements for punctuation fragments and tiny Latin pieces
  // produced by mixed-language song titles such as "Symbol II : Air".
  if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(trimmed) && trimmed.length < 3) {
    return false;
  }
  return true;
}

List<String> _splitNameLikeText(String text) {
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

List<String> _splitByNameSeparators(String text) {
  return text
      .split(RegExp(r'[\s　・･·]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

_NameCharKind _nameCharKind(int rune) {
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

enum _NameCharKind { cjk, kana, latin, other }

class ChatPage extends StatefulWidget {
  final Character character;

  const ChatPage({super.key, required this.character});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Offset? _lastInputPointerPosition;

  final AudioPlayer _audioPlayerPrimary = AudioPlayer();
  final AudioPlayer _audioPlayerSecondary = AudioPlayer();
  final SoLoud _musicEngine = SoLoud.instance;
  Future<void>? _musicEngineInitialization;
  AudioSource? _musicSource;
  SoundHandle? _musicHandle;
  Timer? _musicPositionTimer;
  final Map<String, Future<_MusicLyrics?>> _musicLyricsCache = {};
  bool _primaryIsActive = true;
  AudioPlayer get _activePlayer =>
      _primaryIsActive ? _audioPlayerPrimary : _audioPlayerSecondary;

  List<Message> _messages = [];
  List<ChatSession> _chatSessions = [];
  String? _activeSessionId;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isMusicPlaying = false;
  String? _currentPlayingMusicId;
  Duration _musicPosition = Duration.zero;
  Duration _musicDuration = Duration.zero;
  String? _characterAvatarPath;
  String? _backgroundImagePath;

  String? get _effectiveCharacterAvatarPath {
    final customPath = _characterAvatarPath;
    if (customPath != null && File(AppPaths.resolve(customPath)).existsSync()) {
      return AppPaths.resolve(customPath);
    }

    final defaultPath = widget.character.defaultAvatarPath;
    if (defaultPath.isNotEmpty &&
        File(AppPaths.resolve(defaultPath)).existsSync()) {
      return AppPaths.resolve(defaultPath);
    }

    return null;
  }

  String? get _effectiveBackgroundImagePath {
    final customPath = _backgroundImagePath;
    if (customPath != null && File(AppPaths.resolve(customPath)).existsSync()) {
      return AppPaths.resolve(customPath);
    }

    final defaultPath = widget.character.defaultBackgroundPath;
    if (defaultPath.isNotEmpty &&
        File(AppPaths.resolve(defaultPath)).existsSync()) {
      return AppPaths.resolve(defaultPath);
    }

    return null;
  }

  final List<Map<String, dynamic>> _userMessageQueue = [];
  bool _isProcessingQueue = false;

  // 当前这轮对话中 AI 已经追加了几条连续消息
  // 每次用户发消息时重置为 0，每次 AI 成功追加一条就 +1，
  // 达到 _maxConsecutiveFollowUps 后不再追加
  int _consecutiveCount = 0;

  // 当前用户消息触发的联网资料。
  //
  // 普通回复会先根据用户消息搜索天气/原作/现实信息；如果随后 AI 又连续补充一条，
  // 那条连续消息仍然是在延续同一话题，也应该继续看到这一轮联网资料。
  // 每次用户发新消息时会清空，避免把上一轮话题的资料串到新问题里。
  String? _currentTurnWebContext;
  List<String> _currentTurnKnownSongTitles = const [];

  final Map<Message, bool> _regeneratingAudio = {};
  Message? _currentPlayingMessage;
  Completer<void>? _segmentCompleter;

  List<String> _pendingImagePaths = [];

  late AnimationController _typingAnimationController;
  late AnimationController _soundWaveController;
  late AnimationController _musicVisualController;

  // 设置变量缓存
  String? _personalityOverride;
  String? _userNameOverride;
  String? _userNameTranslationOverride;
  String? _userNamePronunciation; // 缓存用户的称呼读音

  bool _showOriginal = true; // 是否显示日文原文
  bool _showTranslation = true;

  bool _emotionAnalysisEnabled = true;
  double _ttsSpeed = 1.0;

  String? get _sessionId => _activeSessionId;

  String get _effectivePersonality {
    String base =
        (_personalityOverride != null && _personalityOverride!.isNotEmpty)
            ? _personalityOverride!
            : widget.character.personality;

    if (_userNameOverride != null && _userNameOverride!.isNotEmpty) {
      base += '\n\n[用户称呼设置]\n'
          '用户设置的唯一称呼是"$_userNameOverride"。\n'
          '称呼用户时必须逐字原样使用"$_userNameOverride"，禁止私自添加、删除或替换任何前后缀。\n'
          '如果用户希望带后缀，会直接在设置页写成完整称呼，例如"凛野さん"；否则禁止自行添加さん、ちゃん、くん、君、様、先生、小姐等称呼后缀。\n'
          '忽略以上提示词中的其他称呼设定。';
      if (_userNameTranslationOverride != null &&
          _userNameTranslationOverride!.isNotEmpty) {
        base += '\n中文翻译中显示用户称呼时，必须使用"$_userNameTranslationOverride"。';
      }
    } else {
      base += '\n\n[用户称呼设置] 对方未设置称呼，请不要使用任何固定名字称呼用户，或直接不称呼。';
    }

    return base;
  }

  @override
  void initState() {
    super.initState();
    _musicVisualController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _initAudioPlayer();
    unawaited(_ensureMusicEngine().catchError((Object error) {
      debugPrint('音乐引擎初始化失败：$error');
    }));
    _initializeChatSession();
    _switchModel();
    _loadCharacterAvatar();
    _loadBackgroundImage();

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
    final sessionId = _sessionId;
    final canUseLegacySettings = sessionId == null || sessionId == 'default';
    String key(String baseKey) =>
        StorageService.scopedSettingKey(baseKey, id, sessionId);

    final personalityOverride = prefs.getString(key('personality_override')) ??
        (canUseLegacySettings
            ? prefs.getString('personality_override_$id')
            : null);
    final userNameOverride = prefs.getString(key('user_name')) ??
        (canUseLegacySettings ? prefs.getString('user_name_$id') : null);
    final userNameTranslationOverride =
        prefs.getString(key('user_name_translation')) ??
            (canUseLegacySettings
                ? prefs.getString('user_name_translation_$id')
                : null);
    final userNamePronunciation =
        prefs.getString(key('user_name_pronunciation')) ??
            (canUseLegacySettings
                ? prefs.getString('user_name_pronunciation_$id')
                : null);

    final showOriginal = prefs.getBool(key('show_original')) ??
        (canUseLegacySettings ? prefs.getBool('show_original_$id') : null) ??
        true;
    final showTranslation = prefs.getBool(key('show_translation')) ??
        (canUseLegacySettings ? prefs.getBool('show_translation_$id') : null) ??
        true;

    final emotionAnalysisEnabled =
        prefs.getBool(key('emotion_analysis_enabled')) ??
            (canUseLegacySettings
                ? prefs.getBool('emotion_analysis_enabled_$id')
                : null) ??
            true;
    final ttsSpeed = prefs.getDouble(key('tts_speed')) ??
        (canUseLegacySettings ? prefs.getDouble('tts_speed_$id') : null) ??
        1.0;

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
        _userNameTranslationOverride = (userNameTranslationOverride != null &&
                userNameTranslationOverride.isNotEmpty)
            ? userNameTranslationOverride
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

    debugPrint('已加载角色设置：'
        'userName=$_userNameOverride, '
        'translationName=$_userNameTranslationOverride, '
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
    _musicPositionTimer?.cancel();
    unawaited(_disposeMusicBackend());
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    _soundWaveController.dispose();
    _musicVisualController.dispose();
    super.dispose();
  }

  Future<void> _switchModel() async {
    debugPrint('正在切换到 ${widget.character.name} 的模型...');
    final success = await ApiService.switchCharacterModel(
      gptModelPath: widget.character.gptModelPath,
      sovitsModelPath: widget.character.sovitsModelPath,
    );
    if (mounted) {
      if (success) {
        debugPrint('${widget.character.name} 的模型切换成功');
      } else {
        debugPrint('模型切换失败，可能使用默认模型');
      }
    }
  }

  Future<void> _initializeChatSession() async {
    final sessions = await StorageService.loadChatSessions(widget.character.id);
    final activeSessionId =
        await StorageService.getActiveSessionId(widget.character.id);
    if (!mounted) return;
    setState(() {
      _chatSessions = sessions;
      _activeSessionId = activeSessionId;
    });
    await _loadCharacterSettings();
    await _loadConversation();
  }

  Future<void> _loadConversation() async {
    final sessionId = _sessionId ??
        await StorageService.getActiveSessionId(widget.character.id);
    final messages = await StorageService.loadConversation(
      widget.character.id,
      sessionId: sessionId,
    );
    if (mounted) {
      setState(() {
        _activeSessionId = sessionId;
        _messages = messages;
      });
    }
    _scrollToBottom(animated: false, settlePasses: 5);
  }

  Future<void> _refreshChatSessions() async {
    final sessions = await StorageService.loadChatSessions(widget.character.id);
    if (mounted) {
      setState(() {
        _chatSessions = sessions;
      });
    }
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
        builder: (context) => CharacterSettingsPage(
          character: widget.character,
          sessionId: _sessionId,
        ),
      ),
    );
    await _loadCharacterSettings();
  }

  Future<void> _createNewChatSession() async {
    final session = await StorageService.createChatSession(widget.character.id);
    final sessions = await StorageService.loadChatSessions(widget.character.id);
    if (!mounted) return;
    setState(() {
      _chatSessions = sessions;
      _activeSessionId = session.id;
      _messages = [];
      _userMessageQueue.clear();
      _pendingImagePaths = [];
      _isLoading = false;
      _isProcessingQueue = false;
    });
    await _loadCharacterSettings();
    _scrollToBottom(animated: false, settlePasses: 5);
  }

  Future<void> _switchChatSession(String sessionId) async {
    if (sessionId == _activeSessionId) return;
    if (_isPlaying) {
      await _stopAudio();
    }
    await StorageService.switchActiveChatSession(
        widget.character.id, sessionId);
    final sessions = await StorageService.loadChatSessions(widget.character.id);
    final messages = await StorageService.loadConversation(
      widget.character.id,
      sessionId: sessionId,
    );
    if (!mounted) return;
    setState(() {
      _chatSessions = sessions;
      _activeSessionId = sessionId;
      _messages = messages;
      _userMessageQueue.clear();
      _pendingImagePaths = [];
      _isLoading = false;
      _isProcessingQueue = false;
    });
    await _loadCharacterSettings();
    _scrollToBottom(animated: false, settlePasses: 5);
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
    final imagePaths = List<String>.from(_pendingImagePaths);
    if (text.isEmpty && imagePaths.isEmpty) return;

    _consecutiveCount = 0;
    _currentTurnWebContext = null;
    _currentTurnKnownSongTitles = const [];

    final imgLabel = imagePaths.length > 1
        ? '[图片×${imagePaths.length}]'
        : imagePaths.isNotEmpty
            ? '[图片]'
            : '';
    final displayContent = imagePaths.isNotEmpty
        ? (text.isEmpty ? imgLabel : '$imgLabel $text')
        : text;

    final userMessage = Message(
      role: 'user',
      content: displayContent,
      timestamp: DateTime.now(),
      imagePath: imagePaths.isNotEmpty ? imagePaths.first : null,
      imagePaths: imagePaths.isNotEmpty ? imagePaths : null,
    );

    _textController.clear();
    setState(() {
      _messages.add(userMessage);
      _userMessageQueue.add({'text': text, 'imagePaths': imagePaths});
      _pendingImagePaths = [];
    });

    _scrollToBottom();
    await StorageService.saveConversation(
      widget.character.id,
      _messages,
      sessionId: _sessionId,
    );
    await _refreshChatSessions();

    if (!_isProcessingQueue) {
      _processMessageQueue();
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (images.isNotEmpty && mounted) {
      setState(() {
        _pendingImagePaths.addAll(images.map((e) => e.path));
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
    final userMessage = (item['text'] as String?) ?? '';
    final imagePaths = List<String>.from(item['imagePaths'] as List? ?? []);

    // 1. 先生成本地时间上下文：
    //    这里不联网，只告诉 AI 当前年月日、星期、早中晚、距离上次聊天多久等。
    final timeContext = _generateTimeContext();

    // _messages 里已经包含了刚刚发送的用户消息。
    // ApiService.generateResponse() 下面还会把 userMessage 作为“本轮最后一句”单独加入一次，
    // 所以传历史时要去掉最后这条用户消息，避免同一句话在 prompt 里重复两遍。
    //
    // 这份历史也会交给 WebContextService，用来判断“这个是什么意思”
    // 这类追问是否还在延续上一轮原作/角色资料话题。
    final historyMessages =
        _messages.isNotEmpty && _messages.last.role == 'user'
            ? _messages.sublist(0, _messages.length - 1)
            : _messages;
    final recentMessages = StorageService.getRecentMessages(historyMessages);

    final musicAttachment = await MusicService.pickAttachmentForRequest(
      userText: userMessage,
      character: widget.character,
      conversationHistory: historyMessages,
    );

    // 2. 再生成“现实/联网信息上下文”：
    //    WebContextService 会根据当前角色 id 决定能查什么。
    //    例如：
    //    - 鬼灭角色：日本天气、日本节日、《鬼灭之刃》原作资料
    //    - 祥子：东京天气、日本/国际节日、流行语、BanG Dream 资料
    //    - 安迪：上海天气、中国/国际节日、经济、新闻、书影音等
    //    如果用户这句话不需要联网，它会返回空字符串，不影响正常聊天。
    final musicContext = musicAttachment == null
        ? await MusicService.buildDiscussionContext(
            userText: userMessage,
            character: widget.character,
          )
        : MusicService.buildPromptContext(musicAttachment);
    final localOnlyMusicDiscussion = musicAttachment == null &&
        await MusicService.shouldUseLocalOnlyForDiscussion(
          userText: userMessage,
          character: widget.character,
        );

    //    分享本地曲库歌曲，以及聊已覆盖的 MyGO / Ave Mujica 歌曲时，
    //    description、歌词和结构化标签已经足够，因此不触发联网搜索。
    //    其他未被本地曲库覆盖的音乐问题仍走普通联网链路。
    final webContext = musicAttachment != null || localOnlyMusicDiscussion
        ? ''
        : await WebContextService.buildContext(
            userMessage: userMessage,
            characterId: widget.character.id,
            characterName: widget.character.name,
            conversationHistory: recentMessages,
          );
    final responseContext = [
      if (webContext.isNotEmpty) webContext,
      if (musicContext.isNotEmpty) musicContext,
    ].join('\n\n');
    final lyricsTranslationReference =
        await MusicService.buildTranslationLyricsReference(
      userText: userMessage,
      character: widget.character,
      selectedAttachment: musicAttachment,
    );
    final knownSongTitles = musicContext.isEmpty
        ? const <String>[]
        : (await MusicService.loadCatalog())
            .map((song) => song.title)
            .toList(growable: false);
    _currentTurnKnownSongTitles = knownSongTitles;

    if (responseContext.isNotEmpty) {
      debugPrint('本轮额外上下文:\n$responseContext');
      _currentTurnWebContext = responseContext;
    } else {
      _currentTurnWebContext = null;
    }

    try {
      final responseMap = await ApiService.generateResponse(
        characterPersonality: _effectivePersonality,
        conversationHistory: recentMessages,
        userMessage: userMessage,
        timeContext: timeContext,
        // 把联网查到的内容塞进 system prompt，让角色用这些真实信息回答。
        // 注意：最终说话的还是 DeepSeek 角色，不是搜索服务直接回复用户。
        webContext: responseContext,
        imagePaths: imagePaths.isNotEmpty ? imagePaths : null,
        characterId: widget.character.id,
        characterLanguage: widget.character.language,
        lyricsTranslationReference: lyricsTranslationReference,
        knownSongTitles: knownSongTitles,
      );

      final japaneseText = responseMap['japanese'] ?? '';
      final chineseText = responseMap['chinese'] ?? '';

      final imageDescription = responseMap['imageDescription'] ?? '';
      if (imageDescription.isNotEmpty && _messages.isNotEmpty) {
        final idx = _messages.lastIndexWhere((m) =>
            m.role == 'user' &&
            (m.imagePaths?.isNotEmpty == true || m.imagePath != null));
        if (idx != -1) {
          setState(() {
            _messages[idx] =
                _messages[idx].copyWith(imageDescription: imageDescription);
          });
          await StorageService.saveConversation(
            widget.character.id,
            _messages,
            sessionId: _sessionId,
          );
        }
      }

      await _sendAIMessage(
        japaneseText,
        chineseText,
        musicAttachment: musicAttachment,
      );

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
      debugPrint('生成回复时出错: $e');
    }

    setState(() {
      _isLoading = false;
    });

    await _processMessageQueue();
  }

  Future<void> _sendAIMessage(
    String japanese,
    String chinese, {
    MusicAttachment? musicAttachment,
  }) async {
    final isChineseChar = widget.character.language == 'zh';

    // 中文角色：中文是主内容（TTS 读中文）；日语角色：日语是主内容
    final primaryText = isChineseChar ? chinese : japanese;
    if (primaryText.isEmpty) return;

    final cleanPrimary = primaryText.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    final cleanChinese =
        isChineseChar ? '' : chinese.replaceAll(RegExp(r'\n{2,}'), '\n').trim();

    // 日语角色保留"日文\n\n中文：中文翻译"格式以便开关显示；
    // 中文角色直接存储中文文本，无需翻译分隔符
    final displayContent = isChineseChar
        ? cleanPrimary
        : (cleanChinese.isNotEmpty
            ? '$cleanPrimary\n\n中文：$cleanChinese'
            : cleanPrimary);

    // 使用统一的情绪分析 + 逐句 TTS 方法生成音频（传入主内容）
    final List<String> audioPaths = await _generateEmotionAudio(cleanPrimary);

    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPaths.isNotEmpty ? audioPaths.first : null,
      audioPaths: audioPaths.isNotEmpty ? audioPaths : null,
      musicAttachment: musicAttachment,
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
    await StorageService.saveConversation(
      widget.character.id,
      _messages,
      sessionId: _sessionId,
    );
    await _refreshChatSessions();

    if (audioPaths.isNotEmpty && mounted) {
      debugPrint('开始顺序播放 ${audioPaths.length} 段情绪化语音...');
      await _playAudioSequentially(
        paths: audioPaths,
        forMessage: assistantMessage,
      );
      debugPrint('所有音频段播放完毕');
    } else {
      debugPrint('没有成功生成的音频段');
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
    // 触发概率优先读取设置页中的 proactive_follow_up_chance，
    // 未设置时回退到角色配置中的 proactiveTopicChance。
    //
    // 连续发送上限由 _maxConsecutiveFollowUps 控制，防止无限连发。
    if (!mounted || _isLoading) return;

    // 概率判定：不满足则跳过，不追加消息
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;
    final sessionId = _sessionId;
    final canUseLegacySettings = sessionId == null || sessionId == 'default';
    final scopedKey = StorageService.scopedSettingKey(
      'proactive_follow_up_chance',
      id,
      sessionId,
    );
    final double chance = prefs.getDouble(scopedKey) ??
        (canUseLegacySettings
            ? prefs.getDouble('proactive_follow_up_chance_$id')
            : null) ??
        widget.character.proactiveTopicChance;
    if (Random().nextDouble() >= chance) {
      debugPrint('连续消息概率未命中（${(chance * 100).toStringAsFixed(0)}%），不追加');
      return;
    }

    debugPrint('连续消息概率命中，AI 将追加一条消息');

    setState(() {
      _isLoading = true;
    });

    try {
      final timeContext = _generateTimeContext();
      final recentMessages = StorageService.getRecentMessages(_messages);
      final webContext = _currentTurnWebContext;
      if (webContext != null && webContext.isNotEmpty) {
        debugPrint('连续消息复用本轮联网上下文');
      }

      // 追加消息使用正常的对话上下文（包含完整历史），
      // 因为这是同一轮对话中的连续发言，不是隔了很久的主动消息，
      // AI 接着之前的话题说是合理的。
      // 如果本轮用户消息刚刚触发过联网搜索，这里会复用同一段 webContext，
      // 避免连续补充消息退回模型记忆、把原作细节说偏。
      //
      // proactiveInstruction 传入追加消息的指令，
      // userMessage 传空字符串表示这不是用户发起的对话。
      final responseMap = await ApiService.generateResponse(
          characterPersonality: _effectivePersonality,
          conversationHistory: recentMessages,
          userMessage: '',
          timeContext: timeContext,
          webContext: webContext,
          characterId: widget.character.id,
          characterLanguage: widget.character.language,
          knownSongTitles: _currentTurnKnownSongTitles,
          proactiveInstruction: '你刚刚回复了对方的消息，现在你想再补充一句。\n'
              '可以是对刚才话题的延伸、突然想到的相关事情、'
              '或者一个轻松的追加评论。\n'
              '说话方式和语气保持你的角色风格，自然地接上去，不要重复刚才说过的内容。\n');

      final japaneseText = responseMap['japanese'] ?? '';
      final chineseText = responseMap['chinese'] ?? '';

      if (japaneseText.isNotEmpty) {
        // 追加消息和主回复之间加一个短暂延迟，模拟"打字中..."的自然感
        // _followUpDelayMs 控制延迟时长（毫秒），可根据需要调整
        await Future.delayed(const Duration(milliseconds: _followUpDelayMs));
        await _sendAIMessage(japaneseText, chineseText);
      }
    } catch (e) {
      debugPrint('生成连续消息时出错: $e');
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

    for (int i = 0; i < paths.length; i++) {
      if (!_isPlaying || !mounted) {
        debugPrint('用户停止播放，中断后续音频段（已播 $i/${paths.length} 段）');
        break;
      }

      debugPrint('顺序播放第 ${i + 1}/${paths.length} 段：${paths[i]}');

      _segmentCompleter = Completer<void>();
      await _resumeActivePlayer(paths[i]);
      await _segmentCompleter!.future;

      debugPrint('第 ${i + 1}/${paths.length} 段播放完毕');
      _primaryIsActive = !_primaryIsActive;
    }

    _segmentCompleter = null;

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
        debugPrint('播放：文件不存在，跳过（$audioPath）');
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
      debugPrint('播放失败（$audioPath）: $e');
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

  Future<void> _ensureMusicEngine() async {
    if (_musicEngine.isInitialized) return;

    final pendingInitialization = _musicEngineInitialization;
    if (pendingInitialization != null) {
      await pendingInitialization;
      return;
    }

    final initialization = () async {
      await _musicEngine.init(bufferSize: 512);
    }();
    _musicEngineInitialization = initialization;
    try {
      await initialization;
    } finally {
      if (!_musicEngine.isInitialized) {
        _musicEngineInitialization = null;
      }
    }
  }

  void _startMusicPositionUpdates() {
    _musicPositionTimer?.cancel();
    _musicPositionTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _updateMusicPosition(),
    );
  }

  void _updateMusicPosition() {
    final handle = _musicHandle;
    if (!_musicEngine.isInitialized || handle == null) return;

    try {
      if (!_musicEngine.getIsValidVoiceHandle(handle)) {
        _finishMusicPlayback();
        return;
      }
      final position = _musicEngine.getPosition(handle);
      if (!mounted || position == _musicPosition) return;
      setState(() => _musicPosition = position);
    } catch (error) {
      debugPrint('读取音乐播放进度失败：$error');
    }
  }

  void _finishMusicPlayback() {
    _musicPositionTimer?.cancel();
    _musicPositionTimer = null;
    _musicHandle = null;
    _musicVisualController
      ..stop()
      ..reset();
    if (!mounted) return;
    setState(() {
      _isMusicPlaying = false;
      _currentPlayingMusicId = null;
      _musicPosition = Duration.zero;
      _musicDuration = Duration.zero;
    });
  }

  Future<void> _disposeCurrentMusicSource() async {
    _musicPositionTimer?.cancel();
    _musicPositionTimer = null;
    final handle = _musicHandle;
    final source = _musicSource;
    _musicHandle = null;
    _musicSource = null;
    if (!_musicEngine.isInitialized) return;
    if (handle != null && _musicEngine.getIsValidVoiceHandle(handle)) {
      await _musicEngine.stop(handle);
    }
    if (source != null) {
      await _musicEngine.disposeSource(source);
    }
  }

  Future<void> _disposeMusicBackend() async {
    try {
      await _disposeCurrentMusicSource();
    } catch (error) {
      debugPrint('释放音乐播放资源失败：$error');
    }
  }

  Future<void> _toggleMusicAttachment(MusicAttachment attachment) async {
    if (_currentPlayingMusicId == attachment.id) {
      final handle = _musicHandle;
      if (handle == null || !_musicEngine.isInitialized) return;
      final shouldPause = _isMusicPlaying;
      _musicEngine.setPause(handle, shouldPause);
      if (shouldPause) {
        _musicVisualController.stop();
      } else {
        _musicVisualController.repeat();
      }
      if (!mounted) return;
      setState(() => _isMusicPlaying = !shouldPause);
      return;
    }

    await _stopAudio();
    await _disposeCurrentMusicSource();
    _musicVisualController.stop();
    _musicVisualController.reset();
    if (mounted) {
      setState(() {
        _isMusicPlaying = false;
        _currentPlayingMusicId = null;
        _musicPosition = Duration.zero;
        _musicDuration = Duration.zero;
      });
    }

    final localPath = attachment.localAudioPath?.trim();
    final previewUrl = attachment.previewUrl?.trim();

    try {
      await _ensureMusicEngine();
      AudioSource? source;
      if (localPath != null && localPath.isNotEmpty) {
        final resolvedPath = AppPaths.resolve(localPath);
        if (await File(resolvedPath).exists()) {
          source = await _musicEngine.loadFile(
            resolvedPath,
            mode: LoadMode.memory,
          );
        } else {
          debugPrint('音乐文件不存在，尝试预览链接：$resolvedPath');
        }
      }
      if (source == null && previewUrl != null && previewUrl.isNotEmpty) {
        source = await _musicEngine.loadUrl(
          previewUrl,
          mode: LoadMode.memory,
        );
      }
      if (source == null) {
        debugPrint('音乐附件没有可播放来源：${attachment.title}');
        return;
      }
      if (!mounted) {
        await _musicEngine.disposeSource(source);
        return;
      }

      _musicSource = source;
      _musicHandle = _musicEngine.play(source, volume: 1);
      final duration = _musicEngine.getLength(source);
      setState(() {
        _currentPlayingMusicId = attachment.id;
        _isMusicPlaying = true;
        _musicPosition = Duration.zero;
        _musicDuration = duration;
      });
      _musicVisualController.repeat();
      _startMusicPositionUpdates();
    } catch (e) {
      debugPrint('音乐播放失败：$e');
      await _disposeMusicBackend();
      _musicVisualController.stop();
      _musicVisualController.reset();
      if (!mounted) return;
      setState(() {
        _isMusicPlaying = false;
        _currentPlayingMusicId = null;
        _musicPosition = Duration.zero;
        _musicDuration = Duration.zero;
      });
    }
  }

  Future<void> _seekMusic(
    MusicAttachment attachment,
    double milliseconds,
  ) async {
    if (_currentPlayingMusicId != attachment.id ||
        _musicDuration <= Duration.zero) {
      return;
    }
    final target = Duration(
      milliseconds:
          milliseconds.round().clamp(0, _musicDuration.inMilliseconds),
    );
    final handle = _musicHandle;
    if (handle == null || !_musicEngine.isInitialized) return;
    _musicEngine.seek(handle, target);
    if (!mounted) return;
    setState(() => _musicPosition = target);
  }

  Future<void> _stopMusic() async {
    await _disposeCurrentMusicSource();
    _musicVisualController.stop();
    _musicVisualController.reset();
    if (!mounted) return;
    setState(() {
      _isMusicPlaying = false;
      _currentPlayingMusicId = null;
      _musicPosition = Duration.zero;
      _musicDuration = Duration.zero;
    });
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
      debugPrint('停止播放');
    } catch (e) {
      debugPrint('停止播放失败: $e');
    }
  }

  Future<void> _playAudio(Message message) async {
    try {
      await _stopMusic();
      await _audioPlayerPrimary.stop();
      await _audioPlayerSecondary.stop();

      if (!mounted) return;

      if (message.audioPaths != null && message.audioPaths!.isNotEmpty) {
        final existingPaths = <String>[];
        for (final p in message.audioPaths!) {
          if (await File(p).exists()) {
            existingPaths.add(p);
          } else {
            debugPrint('音频文件不存在，跳过：$p');
          }
        }

        if (existingPaths.isNotEmpty) {
          debugPrint('使用缓存的多段音频，共 ${existingPaths.length} 段');
          await _playAudioSequentially(
            paths: existingPaths,
            forMessage: message,
          );
          return;
        }
        debugPrint('多段音频缓存均已失效，重新生成');
      }

      if (message.audioPath != null) {
        final file = File(message.audioPath!);
        if (await file.exists()) {
          debugPrint('使用旧版单段缓存音频：${message.audioPath}');
          await _playAudioSequentially(
            paths: [message.audioPath!],
            forMessage: message,
          );
          return;
        }
        debugPrint('旧版单段缓存已失效，重新生成');
      }

      // ========================================
      // 缓存音频不存在时的重新生成逻辑
      // ========================================
      // 使用统一的 _generateEmotionAudio 方法，和发送消息、重新生成按钮走完全相同的流程
      debugPrint('缓存音频不存在，重新生成...');
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
        debugPrint('所有句子音频生成均失败');
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
        await StorageService.saveConversation(
          widget.character.id,
          _messages,
          sessionId: _sessionId,
        );

        debugPrint('开始顺序播放 ${newAudioPaths.length} 段情绪化语音...');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: updatedMessage,
        );
      } else {
        // 即使找不到原消息（极端情况），也尝试播放已生成的音频
        debugPrint('未在消息列表中找到原消息，仍尝试播放');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: message,
        );
      }
    } catch (e) {
      debugPrint('播放错误: $e');
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

      debugPrint('重新生成情绪化语音...');

      // 调用统一方法：分句 -> 情绪分析 -> 逐句 TTS
      final List<String> newAudioPaths =
          await _generateEmotionAudio(japaneseText);

      if (mounted) {
        setState(() {
          _regeneratingAudio.remove(message);
        });
      }

      if (newAudioPaths.isEmpty) {
        debugPrint('所有句子重新生成均失败');
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
            debugPrint('删除旧音频失败: $e');
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
        await StorageService.saveConversation(
          widget.character.id,
          _messages,
          sessionId: _sessionId,
        );

        if (!mounted) return;

        try {
          await _audioPlayerPrimary.stop();
          await _audioPlayerSecondary.stop();
        } catch (e) {
          debugPrint('停止播放器失败（忽略）: $e');
        }

        if (_segmentCompleter != null && !_segmentCompleter!.isCompleted) {
          _segmentCompleter!.complete();
        }
        _segmentCompleter = null;
        _primaryIsActive = true;

        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentPlayingMessage = null;
          });
        }

        debugPrint('重新生成完成，开始顺序播放 ${newAudioPaths.length} 段...');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: updatedMessage,
        );
      } else {
        // 找不到原消息时的兜底：仍然播放已生成的音频，但无法更新缓存
        debugPrint('未在消息列表中找到原消息（index=-1），仍尝试播放');
        await _playAudioSequentially(
          paths: newAudioPaths,
          forMessage: message,
        );
      }
    } catch (e) {
      debugPrint('重新生成语音错误: $e');
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
    // 中文角色的消息不含 '\n\n中文：' 分隔符，走这个分支直接显示中文文本
    if (parts.length != 2) {
      if (_showOriginal) {
        final isChineseChar = widget.character.language == 'zh';
        if (isChineseChar) {
          // 中文角色：文字放在磨砂玻璃面板里，和日语角色的翻译框视觉一致
          widgets.add(
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    content,
                    style: const TextStyle(
                      fontFamily: aiTranslationFontFamily,
                      fontSize: aiTranslationFontSize,
                      fontWeight: aiTranslationFontWeight,
                      color: Color(0xFF2D3142),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          widgets.add(Text(
            content,
            style: const TextStyle(
              fontFamily: aiOriginalFontFamily,
              fontSize: aiOriginalFontSize,
              fontWeight: aiOriginalFontWeight,
              color: Color(0xFF2D3142),
              height: 1.5,
            ),
          ));
        }
      } else {
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
            fontFamily: aiOriginalFontFamily,
            fontSize: aiOriginalFontSize,
            fontWeight: aiOriginalFontWeight,
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
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Text(
                parts[1],
                style: const TextStyle(
                  fontFamily: aiTranslationFontFamily,
                  fontSize: aiTranslationFontSize,
                  fontWeight: aiTranslationFontWeight,
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
  Future<List<String>> _generateEmotionAudio(String text) async {
    final String lang = widget.character.language;

    // --- 第一步：分句（按角色语言选择合适的标点）---
    final List<String> sentences =
        EmotionAnalyzer.splitSentences(text, language: lang);

    debugPrint('TTS 分句结果（共 ${sentences.length} 句）：');
    for (int i = 0; i < sentences.length; i++) {
      debugPrint('  [$i] ${sentences[i]}');
    }

    // --- 第二步：情绪分析 ---
    // 根据 _emotionAnalysisEnabled 开关决定是调用 DeepSeek 分析还是直接用默认情绪
    final List<SpeechEmotion> emotions;
    if (_emotionAnalysisEnabled) {
      debugPrint('正在进行情绪分析...');
      emotions = await EmotionAnalyzer.analyzeEmotions(
        sentences: sentences,
        character: widget.character,
        language: lang,
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
      debugPrint('情绪分析已关闭，全部使用 ${fallback.name}');
    }

    // --- 第三步：逐句生成 TTS 音频 ---
    debugPrint('开始逐句生成情绪化语音...');
    final List<String> audioPaths = [];

    for (int i = 0; i < sentences.length; i++) {
      final String sentence = sentences[i];
      final SpeechEmotion emotion = emotions[i];
      final referenceAudio = await _getValidReferenceAudio(emotion);

      debugPrint(
          '句子 [$i] 情绪：${emotion.name}，参考音频：${referenceAudio.referWavPath}');

      // 发音替换：日语角色应用注音词典，中文角色只做用户名替换
      final correctedSentence = _applyPronunciationCorrection(sentence);

      final List<String> generatedPaths =
          await ApiService.generateSpeechSegments(
        text: correctedSentence,
        referWavPath: referenceAudio.referWavPath,
        promptText: referenceAudio.promptText,
        promptLanguage: referenceAudio.promptLanguage,
        speedFactor: _ttsSpeed,
        textLanguage: lang,
      );

      if (generatedPaths.isNotEmpty) {
        audioPaths.addAll(generatedPaths);
        debugPrint('句子 [$i] 音频生成成功：${generatedPaths.join(', ')}');
      } else {
        debugPrint('句子 [$i] 音频生成失败，跳过该段');
      }
    }

    return audioPaths;
  }

  Future<EmotionReferenceAudio> _getValidReferenceAudio(
      SpeechEmotion emotion) async {
    final audio = widget.character.getReferenceAudio(emotion);
    if (await File(AppPaths.resolve(audio.referWavPath)).exists()) {
      return audio;
    }
    debugPrint('情绪音频文件不存在（${emotion.name}）：${audio.referWavPath}，回退到默认参考音频');
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

    // 2. 日语专有名词注音纠正（仅对日语角色生效，中文角色跳过）
    if (enablePronunciationCorrection && widget.character.language != 'zh') {
      final expandedPronunciations = <String, String>{
        ..._expandedPronunciationMap(
          characterPronunciationDictionary,
          allowSplitParts: true,
        ),
        ..._expandedPronunciationMap(
          termPronunciationDictionary,
          allowSplitParts: false,
        ),
        ..._expandedPronunciationMap(
          widget.character.pronunciationOverrides ?? const <String, String>{},
          allowSplitParts: false,
        ),
      };
      final pronunciationEntries = expandedPronunciations.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));

      for (final entry in pronunciationEntries) {
        final word = entry.key;
        final pronunciation = entry.value;
        if (correctedText.contains(word)) {
          if (pronunciationMode == 'bracket') {
            correctedText =
                correctedText.replaceAll(word, '$word[$pronunciation]');
          } else {
            correctedText = correctedText.replaceAll(word, pronunciation);
          }
        }
      }
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
            lastChatInfo = '距离上次对话：约$months个月前';
            isLongAbsence = true;
          } else {
            final years = (difference.inDays / 365).floor();
            lastChatInfo = '距离上次对话：约$years年前';
            isLongAbsence = true;
          }
          break;
        }
      }
    }

    String context = '''【当前时间信息】
现在的时间是：$year年$month$day日（$weekday）$timeOfDay $hour:$minute
当前季节：$season''';

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
在回复用户这条消息时，你可以用自己的说话方式自然地加入"好久没聊了"的感觉，也可以不提。
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

  void _scrollToBottom({
    bool animated = true,
    int settlePasses = 1,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        if (settlePasses > 0) {
          _scrollToBottom(animated: animated, settlePasses: settlePasses - 1);
        }
        return;
      }

      final target = position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }

      if (settlePasses > 0) {
        Future.delayed(const Duration(milliseconds: 50), () {
          _scrollToBottom(animated: false, settlePasses: settlePasses - 1);
        });
      }
    });
  }

  Future<void> _clearConversation() async {
    final color = Color(int.parse('0xFF${widget.character.color}'));
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7FA).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.82),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 70,
                        offset: const Offset(0, 34),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '清空聊天记录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '确定要清空当前对话的所有聊天记录吗？',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                            ),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: color,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('清空'),
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
    );

    if (confirm == true) {
      await StorageService.clearConversation(
        widget.character.id,
        sessionId: _sessionId,
      );
      setState(() {
        _messages.clear();
      });
      await _refreshChatSessions();
      _loadConversation();
    }
  }

  Future<void> _deleteMessage(int index) async {
    if (index < 0 || index >= _messages.length) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
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
          debugPrint('已删除音频缓存: $p');
        } catch (e) {
          debugPrint('删除音频缓存失败: $e');
        }
      }
    }

    setState(() {
      _messages.removeAt(index);
    });

    await StorageService.saveConversation(
      widget.character.id,
      _messages,
      sessionId: _sessionId,
    );
    await _refreshChatSessions();
    debugPrint('消息已删除（下标: $index）');
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 12,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 42,
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 10),
              const Text('复制消息', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 42,
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

    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.content));
    } else if (selected == 'delete') {
      await _deleteMessage(index);
    }
  }

  void _showBackgroundMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      builder: (context) {
        final color = Color(int.parse('0xFF${widget.character.color}'));
        final screenWidth = MediaQuery.of(context).size.width;
        final panelWidth = min(screenWidth - 56, 520.0);

        Widget buildAction({
          required IconData icon,
          required String title,
          required VoidCallback onTap,
          Color? foregroundColor,
        }) {
          final fg = foregroundColor ?? const Color(0xFF2D3142);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Icon(icon, size: 19, color: fg),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: panelWidth,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F7FA).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.82),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.24),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 76,
                          offset: const Offset(0, 34),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 2, 4),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '背景设置',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2D3142),
                                  ),
                                ),
                              ),
                              Icon(Icons.wallpaper,
                                  color: color.withValues(alpha: 0.72),
                                  size: 19),
                            ],
                          ),
                        ),
                        buildAction(
                          icon: Icons.image_outlined,
                          title: '选择背景图片',
                          onTap: () {
                            Navigator.pop(context);
                            _pickBackgroundImage();
                          },
                        ),
                        if (_backgroundImagePath != null)
                          buildAction(
                            icon: Icons.delete_outline,
                            title: '清除背景图片',
                            foregroundColor: const Color(0xFFE85D75),
                            onTap: () {
                              Navigator.pop(context);
                              _clearBackgroundImage();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatSessionTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    if (day == today) return '$hour:$minute';
    if (day == today.subtract(const Duration(days: 1))) {
      return '昨天 $hour:$minute';
    }
    return '${time.month}月${time.day}日 $hour:$minute';
  }

  Future<void> _renameChatSession(ChatSession session) async {
    final color = Color(int.parse('0xFF${widget.character.color}'));
    final controller = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7FA).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.82),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 70,
                        offset: const Offset(0, 34),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '重命名对话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        maxLength: 30,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF2D3142),
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '输入对话名称',
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.72),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 11,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: color, width: 1.2),
                          ),
                        ),
                        onSubmitted: (value) => Navigator.pop(context, value),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                            ),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(context, controller.text),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: color,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('保存'),
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
    );
    controller.dispose();

    if (newTitle == null || newTitle.trim().isEmpty) return;
    await StorageService.renameChatSession(
      widget.character.id,
      session.id,
      newTitle,
    );
    await _refreshChatSessions();
  }

  Future<void> _deleteChatSession(ChatSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7FA).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.82),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 70,
                        offset: const Offset(0, 34),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '删除对话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '确定要删除“${session.title}”吗？',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '聊天记录和这段对话的独立设置都会删除。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                            ),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0xFFE85D75),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('删除'),
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
    );
    if (confirm != true) return;

    if (_isPlaying) {
      await _stopAudio();
    }

    final nextActiveId = await StorageService.deleteChatSession(
      widget.character.id,
      session.id,
    );
    final sessions = await StorageService.loadChatSessions(widget.character.id);
    final messages = await StorageService.loadConversation(
      widget.character.id,
      sessionId: nextActiveId,
    );
    if (!mounted) return;
    setState(() {
      _chatSessions = sessions;
      _activeSessionId = nextActiveId;
      _messages = messages;
      _userMessageQueue.clear();
      _pendingImagePaths = [];
      _isLoading = false;
      _isProcessingQueue = false;
    });
    await _loadCharacterSettings();
    _scrollToBottom();
  }

  Future<void> _showChatSessionContextMenu(
    ChatSession session,
    Offset globalPosition,
    BuildContext sheetContext,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 12,
      items: [
        PopupMenuItem<String>(
          value: 'rename',
          height: 42,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline,
                  size: 18, color: Colors.grey[700]),
              const SizedBox(width: 10),
              const Text('重命名'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 42,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
              const SizedBox(width: 10),
              Text('删除', style: TextStyle(color: Colors.red[400])),
            ],
          ),
        ),
      ],
    );

    if (selected == 'rename') {
      if (!mounted || !sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      await _renameChatSession(session);
    } else if (selected == 'delete') {
      if (!mounted || !sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      await _deleteChatSession(session);
    }
  }

  void _showChatSessionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      builder: (context) {
        final color = Color(int.parse('0xFF${widget.character.color}'));
        final screenWidth = MediaQuery.of(context).size.width;
        final panelWidth = min(screenWidth - 56, 620.0);

        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: panelWidth,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.54,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F7FA).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.82),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.24),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 76,
                          offset: const Offset(0, 34),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 14, 10),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '对话',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2D3142),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: '新建对话',
                                child: Material(
                                  color: color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await _createNewChatSession();
                                    },
                                    child: SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: Icon(Icons.add_comment_outlined,
                                          color: color, size: 18),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            itemCount: _chatSessions.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 12,
                              endIndent: 12,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                            itemBuilder: (context, index) {
                              final session = _chatSessions[index];
                              final selected = session.id == _activeSessionId;
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTapDown: (details) =>
                                    _showChatSessionContextMenu(
                                  session,
                                  details.globalPosition,
                                  context,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await _switchChatSession(session.id);
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 140),
                                      curve: Curves.easeOut,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? color.withValues(alpha: 0.10)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onDoubleTap: () async {
                                                Navigator.pop(context);
                                                await _renameChatSession(
                                                    session);
                                              },
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    session.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: const Color(
                                                          0xFF2D3142),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    _formatSessionTime(
                                                        session.updatedAt),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[500],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          AnimatedOpacity(
                                            duration: const Duration(
                                                milliseconds: 140),
                                            opacity: selected ? 1 : 0,
                                            child: Icon(Icons.check,
                                                color: color, size: 20),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextFieldContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    Color color,
  ) {
    final buttonItems = editableTextState.contextMenuButtonItems;
    final buttons = buttonItems.isEmpty
        ? [
            _buildContextMenuButton(
              label: '粘贴',
              onPressed: _pasteClipboardText,
              foregroundColor: const Color.fromARGB(255, 24, 26, 35),
            ),
          ]
        : buttonItems
            .map((item) => _buildContextMenuButton(
                  label: _contextMenuLabel(item),
                  onPressed: item.onPressed,
                  foregroundColor: const Color.fromARGB(255, 95, 99, 113),
                ))
            .toList();

    return CustomSingleChildLayout(
      delegate: _InputContextMenuLayoutDelegate(
        anchor: _lastInputPointerPosition ??
            editableTextState.contextMenuAnchors.primaryAnchor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: buttons,
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenuButton({
    required String label,
    required VoidCallback? onPressed,
    required Color foregroundColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF2D3142).withValues(alpha: 0.10);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFF2D3142).withValues(alpha: 0.06);
          }
          if (states.contains(WidgetState.focused)) {
            return const Color(0xFF2D3142).withValues(alpha: 0.08);
          }
          return null;
        }),
        child: SizedBox(
          width: 90,
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_contextMenuIconByLabel(label),
                  size: 18, color: foregroundColor),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(fontSize: 14, color: foregroundColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _contextMenuIconByLabel(String label) {
    if (label == '粘贴') return Icons.content_paste;
    if (label == '复制') return Icons.copy_outlined;
    if (label == '剪切') return Icons.content_cut;
    if (label == '全选') return Icons.select_all;
    return Icons.more_horiz;
  }

  Future<void> _pasteClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final value = _textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final nextOffset = start + text.length;

    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    ContextMenuController.removeAny();
  }

  String _contextMenuLabel(ContextMenuButtonItem item) {
    if (item.type == ContextMenuButtonType.paste) return '粘贴';
    if (item.type == ContextMenuButtonType.copy) return '复制';
    if (item.type == ContextMenuButtonType.cut) return '剪切';
    if (item.type == ContextMenuButtonType.selectAll) return '全选';
    return item.label ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('0xFF${widget.character.color}'));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Theme(
        data: Theme.of(context).copyWith(
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: Stack(
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
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.25),
                          Colors.white.withValues(alpha: 0.15),
                        ],
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_pendingImagePaths.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  height: 64,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _pendingImagePaths.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 6),
                                    itemBuilder: (_, i) => Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.file(
                                            File(_pendingImagePaths[i]),
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: -4,
                                          right: -4,
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _pendingImagePaths.removeAt(i)),
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle),
                                              child: const Icon(Icons.close,
                                                  size: 11,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    onTap: _isLoading ? null : _pickImage,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.10),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(
                                              sigmaX: 18, sigmaY: 18),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white
                                                      .withValues(alpha: 0.66),
                                                  Colors.white
                                                      .withValues(alpha: 0.34),
                                                ],
                                              ),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.72),
                                                width: 1.4,
                                              ),
                                            ),
                                            child: Icon(Icons.image_outlined,
                                                size: 22,
                                                color: color.withValues(
                                                    alpha: 0.78)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.10),
                                          blurRadius: 18,
                                          offset: const Offset(0, 7),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(30),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 18, sigmaY: 18),
                                        child: Container(
                                          constraints: const BoxConstraints(
                                              minHeight: 56),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Colors.white
                                                    .withValues(alpha: 0.68),
                                                Colors.white
                                                    .withValues(alpha: 0.42),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(30),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.74),
                                                width: 1.4),
                                          ),
                                          child: Listener(
                                            onPointerDown: (event) {
                                              _lastInputPointerPosition =
                                                  event.position;
                                            },
                                            child: TextField(
                                              controller: _textController,
                                              style: const TextStyle(
                                                  color: Color(0xFF2D3142),
                                                  fontSize: 14),
                                              decoration: InputDecoration(
                                                hintText: _pendingImagePaths
                                                        .isNotEmpty
                                                    ? '给图片配上文字（可选）...'
                                                    : '输入消息...',
                                                hintStyle: const TextStyle(
                                                    color: Color.fromARGB(
                                                        255, 128, 128, 128),
                                                    fontSize: 14),
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 22,
                                                        vertical: 15),
                                              ),
                                              contextMenuBuilder: (context,
                                                      editableTextState) =>
                                                  _buildTextFieldContextMenu(
                                                context,
                                                editableTextState,
                                                color,
                                              ),
                                              maxLines: null,
                                              textInputAction:
                                                  TextInputAction.send,
                                              onSubmitted: (_) =>
                                                  _sendMessage(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: color.withValues(alpha: 0.28),
                                          blurRadius: 18,
                                          offset: const Offset(0, 7))
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 18, sigmaY: 18),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color.lerp(color, Colors.white,
                                                      0.22)!
                                                  .withValues(alpha: 0.92),
                                              color.withValues(alpha: 0.78),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.50),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.send,
                                              color: Colors.white, size: 22),
                                          onPressed:
                                              _isLoading ? null : _sendMessage,
                                        ),
                                      ),
                                    ),
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
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                    // 第二层更柔和的远距离阴影，增加空间层次感
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
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
                  child: Container(
                    decoration: BoxDecoration(
                      // --- 陶瓷底色渐变：从上到下由浅白到微灰白，模拟真实陶瓷的柔和光泽 ---
                      // 这里不用 BackdropFilter，避免鼠标移入顶栏/底栏时背景图被重新滤镜采样导致颜色闪变。
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.94),
                          Colors.white.withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
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
                                        color: color.withValues(alpha: 0.3),
                                        width: 2),
                                  ),
                                  child: ClipOval(
                                    child: _effectiveCharacterAvatarPath != null
                                        ? Image.file(
                                            File(
                                                _effectiveCharacterAvatarPath!),
                                            fit: BoxFit.cover)
                                        : Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(colors: [
                                                color,
                                                color.withValues(alpha: 0.7)
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
                                      const Text('对方正在输入...',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color.fromARGB(
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
                                icon: const Icon(Icons.forum_outlined,
                                    color: Color(0xFF2D3142)),
                                onPressed: _showChatSessionMenu,
                                tooltip: '对话列表',
                              ),
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
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFF2D3142)),
                                onPressed: _clearConversation,
                                tooltip: '清空聊天记录',
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
          ],
        ),
      ),
    );
  }

  Widget _buildChatBackground() {
    final backgroundPath = _effectiveBackgroundImagePath;
    if (backgroundPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: widget.character.backgroundBlurSigma,
              sigmaY: widget.character.backgroundBlurSigma,
            ),
            child: Image.file(File(backgroundPath), fit: BoxFit.cover),
          ),
          Container(
            color: Colors.white
                .withValues(alpha: 1.0 - widget.character.backgroundOpacity),
          ),
        ],
      );
    }

    if (backgroundImagePath.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: widget.character.backgroundBlurSigma,
              sigmaY: widget.character.backgroundBlurSigma,
            ),
            child: Image.asset(backgroundImagePath, fit: BoxFit.cover),
          ),
          Container(
            color: Colors.white
                .withValues(alpha: 1.0 - widget.character.backgroundOpacity),
          ),
        ],
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: chatBackgroundGradient,
        ),
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
                    border: Border.all(
                        color: color.withValues(alpha: 0.3), width: 2),
                  ),
                  child: ClipOval(
                    child: _effectiveCharacterAvatarPath != null
                        ? Image.file(File(_effectiveCharacterAvatarPath!),
                            fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                color,
                                color.withValues(alpha: 0.7)
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
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        messageMaxWidthRatio,
                  ),
                  child: GestureDetector(
                    onSecondaryTapUp: (details) {
                      _showMessageContextMenu(
                          context, details.globalPosition, index, message);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: messageBubbleHorizontalPadding,
                        vertical: messageBubbleVerticalPadding,
                      ),
                      decoration: BoxDecoration(
                        gradient: isUser
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.character.aiBubbleGradient,
                              ),
                        color: isUser ? color.withValues(alpha: 0.6) : null,
                        borderRadius: isUser
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(messageBubbleRadius),
                                topRight:
                                    Radius.circular(messageBubbleCornerRadius),
                                bottomLeft:
                                    Radius.circular(messageBubbleRadius),
                                bottomRight:
                                    Radius.circular(messageBubbleRadius),
                              )
                            : const BorderRadius.only(
                                topLeft:
                                    Radius.circular(messageBubbleCornerRadius),
                                topRight: Radius.circular(messageBubbleRadius),
                                bottomLeft:
                                    Radius.circular(messageBubbleRadius),
                                bottomRight:
                                    Radius.circular(messageBubbleRadius),
                              ),
                        border: !isUser
                            ? Border.all(
                                color: widget.character.aiBubbleBorderColor,
                                width: 1.5)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2)),
                          if (!isUser)
                            BoxShadow(
                              color: widget.character.aiBubbleGlowColor
                                  .withValues(alpha: aiBubbleGlowOpacity),
                              blurRadius: aiBubbleGlowBlur,
                              spreadRadius: -2,
                              offset: const Offset(0, 0),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isUser &&
                              (message.imagePaths?.isNotEmpty == true ||
                                  message.imagePath != null))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: (message.imagePaths ??
                                        (message.imagePath != null
                                            ? [message.imagePath!]
                                            : <String>[]))
                                    .map((path) {
                                  final isMulti =
                                      (message.imagePaths?.length ?? 1) > 1;
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(path),
                                      width: isMulti ? 86 : 180,
                                      height: isMulti ? 86 : null,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: isMulti ? 86 : 180,
                                        height: isMulti ? 86 : 80,
                                        color: Colors.white24,
                                        child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.white54),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          if (!(isUser &&
                              !message.content.contains(' ') &&
                              message.content.startsWith('[图片')))
                            if (!isUser &&
                                (message.content.contains('\n\n中文：') ||
                                    widget.character.language == 'zh'))
                              ..._buildTranslatedMessage(message.content)
                            else
                              Text(
                                isUser && message.content.startsWith('[图片')
                                    ? message.content.replaceFirst(
                                        RegExp(r'^\[图片[^\]]*\] ?'), '')
                                    : message.content,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isUser
                                      ? Colors.white
                                      : const Color(0xFF2D3142),
                                  height: 1.5,
                                ),
                              ),
                          if (message.musicAttachment != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _buildMusicAttachmentCard(
                                message.musicAttachment!,
                                isUser,
                                color,
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
                    border: Border.all(
                        color: color.withValues(alpha: 0.3), width: 2),
                  ),
                  child: ClipOval(
                    child: userAvatarPath.isNotEmpty &&
                            File(AppPaths.resolve(userAvatarPath)).existsSync()
                        ? Image.file(File(AppPaths.resolve(userAvatarPath)),
                            fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                color,
                                color.withValues(alpha: 0.7)
                              ]),
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

  Widget _buildMusicAttachmentCard(
    MusicAttachment attachment,
    bool isUser,
    Color accentColor,
  ) {
    final canPlay = _hasPlayableMusicSource(attachment);
    final isSelected = _currentPlayingMusicId == attachment.id;
    final isPlaying = isSelected && _isMusicPlaying;
    final subtitleParts = [
      if (attachment.artist.trim().isNotEmpty) attachment.artist.trim(),
      if (attachment.band.trim().isNotEmpty &&
          attachment.band.trim() != attachment.artist.trim())
        attachment.band.trim(),
    ];
    final subtitle = subtitleParts.join(' · ');
    final fallbackDuration = attachment.durationMs == null
        ? Duration.zero
        : Duration(milliseconds: attachment.durationMs!);
    final duration = isSelected ? _musicDuration : fallbackDuration;
    final position = isSelected ? _musicPosition : Duration.zero;
    final hasDuration = duration > Duration.zero;
    final maxMilliseconds =
        hasDuration ? duration.inMilliseconds.toDouble() : 1.0;
    final currentMilliseconds = position.inMilliseconds
        .clamp(0, hasDuration ? duration.inMilliseconds : 0)
        .toDouble();
    final lyricsFuture = _loadMusicLyrics(attachment);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            width: 440,
            height: 166,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isUser ? 0.24 : 0.34),
                  accentColor.withValues(alpha: isSelected ? 0.14 : 0.07),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.48),
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(
                    alpha: isSelected ? 0.14 : 0.06,
                  ),
                  blurRadius: isSelected ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildMusicVinyl(
                  attachment: attachment,
                  canPlay: canPlay,
                  isPlaying: isPlaying,
                  accentColor: accentColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF182033),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              isPlaying
                                  ? Icons.graphic_eq_rounded
                                  : Icons.album_outlined,
                              key: ValueKey(isPlaying),
                              size: 13,
                              color: isPlaying
                                  ? accentColor
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              canPlay ? subtitle : '音频不可用',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: canPlay
                                    ? const Color(0xFF526078)
                                    : const Color(0xFF94A3B8),
                                fontSize: 11,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      FutureBuilder<_MusicLyrics?>(
                        future: lyricsFuture,
                        builder: (context, snapshot) {
                          final lyrics = snapshot.data;
                          if (lyrics == null || lyrics.entries.isEmpty) {
                            return const SizedBox(height: 48);
                          }
                          return _buildMusicLyricsViewport(
                            lyrics: lyrics,
                            position: position,
                            duration: duration,
                            accentColor: accentColor,
                            active: isSelected,
                          );
                        },
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 16,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            activeTrackColor: accentColor,
                            inactiveTrackColor:
                                Colors.white.withValues(alpha: 0.66),
                            disabledActiveTrackColor:
                                accentColor.withValues(alpha: 0.32),
                            disabledInactiveTrackColor:
                                Colors.white.withValues(alpha: 0.48),
                            thumbColor: accentColor,
                            overlayColor: accentColor.withValues(alpha: 0.10),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4.5,
                              disabledThumbRadius: 3.5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            value: currentMilliseconds,
                            max: maxMilliseconds,
                            onChanged: isSelected && hasDuration
                                ? (value) => _seekMusic(attachment, value)
                                : null,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _formatMusicDuration(position),
                            style: const TextStyle(
                              color: Color(0xFF5B6880),
                              fontSize: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            hasDuration
                                ? _formatMusicDuration(duration)
                                : '--:--',
                            style: const TextStyle(
                              color: Color(0xFF5B6880),
                              fontSize: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 9),
                          Tooltip(
                            message: isPlaying ? '暂停' : '播放',
                            child: Material(
                              color: accentColor.withValues(alpha: 0.88),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: canPlay
                                    ? () => _toggleMusicAttachment(attachment)
                                    : null,
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMusicVinyl({
    required MusicAttachment attachment,
    required bool canPlay,
    required bool isPlaying,
    required Color accentColor,
  }) {
    final disc = SizedBox(
      width: 80,
      height: 80,
      child: CustomPaint(
        painter: _VinylDiscPainter(accentColor: accentColor),
        child: Center(
          child: Container(
            width: 57,
            height: 57,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.74),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipOval(
              child: FutureBuilder<Uint8List?>(
                future: MusicService.loadCoverBytes(attachment),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes != null && bytes.isNotEmpty) {
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) =>
                          _buildMusicCoverPlaceholder(accentColor),
                    );
                  }
                  return _buildMusicCoverPlaceholder(accentColor);
                },
              ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: 112,
      height: 112,
      child: Tooltip(
        message: isPlaying ? '暂停' : '播放',
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            radius: 56,
            onTap: canPlay ? () => _toggleMusicAttachment(attachment) : null,
            child: AnimatedBuilder(
              animation: _musicVisualController,
              child: disc,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 98,
                      height: 98,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accentColor.withValues(
                            alpha: isPlaying ? 0.34 : 0.18,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(
                              alpha: isPlaying ? 0.14 : 0.06,
                            ),
                            blurRadius: isPlaying ? 18 : 10,
                          ),
                        ],
                      ),
                    ),
                    Transform.rotate(
                      angle: _musicVisualController.value * 2 * pi,
                      child: child,
                    ),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEAF0F8),
                        border: Border.all(
                          color: const Color(0xFF20283A),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<_MusicLyrics?> _loadMusicLyrics(MusicAttachment attachment) {
    final timedLyricsPath = _effectiveTimedLyricsPath(attachment);
    if (timedLyricsPath != null && timedLyricsPath.isNotEmpty) {
      final resolvedPath = AppPaths.resolve(timedLyricsPath);
      return _musicLyricsCache.putIfAbsent('timed:$resolvedPath', () async {
        try {
          final file = File(resolvedPath);
          if (await file.exists()) {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is Map<String, dynamic>) {
              final timedLyrics = _MusicLyrics.fromNeteaseJson(decoded);
              if (timedLyrics.entries.isNotEmpty) return timedLyrics;
            }
          }
        } catch (error) {
          debugPrint('读取网易云时间戳歌词失败：$error');
        }
        return _loadFallbackMusicLyrics(attachment);
      });
    }

    return _loadFallbackMusicLyrics(attachment);
  }

  String? _effectiveTimedLyricsPath(MusicAttachment attachment) {
    final configuredPath = attachment.timedLyricsPath?.trim();
    if (configuredPath != null && configuredPath.isNotEmpty) {
      return configuredPath;
    }

    // 旧聊天记录是在 timedLyricsPath 字段加入前保存的。它们仍保留
    // lyricsPath，因此用同目录、同文件名的 JSON 自动升级显示链路。
    final legacyLyricsPath = attachment.lyricsPath?.trim();
    if (legacyLyricsPath == null || legacyLyricsPath.isEmpty) return null;
    final extensionIndex = legacyLyricsPath.lastIndexOf('.');
    if (extensionIndex <= legacyLyricsPath.lastIndexOf(RegExp(r'[\\/]'))) {
      return null;
    }
    final candidatePath =
        '${legacyLyricsPath.substring(0, extensionIndex)}.json';
    return File(AppPaths.resolve(candidatePath)).existsSync()
        ? candidatePath
        : null;
  }

  Future<_MusicLyrics?> _loadFallbackMusicLyrics(
    MusicAttachment attachment,
  ) {
    if (attachment.lyrics.isNotEmpty) {
      final first = attachment.lyrics.first.hashCode;
      final last = attachment.lyrics.last.hashCode;
      final cacheKey =
          'inline:${attachment.id}:${attachment.lyrics.length}:$first:$last';
      return _musicLyricsCache.putIfAbsent(
        cacheKey,
        () async => _MusicLyrics.fromLines(attachment.lyrics),
      );
    }

    final lyricsPath = attachment.lyricsPath?.trim();
    if (lyricsPath == null || lyricsPath.isEmpty) {
      return Future.value(null);
    }
    final resolvedPath = AppPaths.resolve(lyricsPath);
    return _musicLyricsCache.putIfAbsent('path:$resolvedPath', () async {
      final file = File(resolvedPath);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return _MusicLyrics.fromText(text);
    });
  }

  Widget _buildMusicLyricsViewport({
    required _MusicLyrics lyrics,
    required Duration position,
    required Duration duration,
    required Color accentColor,
    required bool active,
  }) {
    final activeIndex = lyrics.activeIndex(position, duration);
    final previous = lyrics.entryAt(activeIndex - 1);
    final current = lyrics.entryAt(activeIndex);
    final next = lyrics.entryAt(activeIndex + 1);
    final isPrelude = lyrics.timed && activeIndex < 0;
    final currentLineProgress =
        lyrics.entryProgress(activeIndex, position, duration);

    return ClipRect(
      child: SizedBox(
        height: 48,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.18),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: SizedBox(
            key: ValueKey(activeIndex),
            width: double.infinity,
            child: isPrelude
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      active ? '♪  前奏' : '♪  准备播放',
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.58),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMusicLyricTextLine(
                        previous?.primary ?? '',
                        color: const Color(0xFF6B7890).withValues(alpha: 0.54),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      const SizedBox(height: 2),
                      _buildMusicLyricTextLine(
                        current?.primary ?? '',
                        color: active
                            ? const Color(0xFF172033)
                            : const Color(0xFF334155),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        scrollProgress: active ? currentLineProgress : null,
                      ),
                      if ((current?.secondary ?? '').isNotEmpty) ...[
                        const SizedBox(height: 1),
                        _buildMusicLyricTextLine(
                          current!.secondary,
                          color: accentColor.withValues(
                            alpha: active ? 0.86 : 0.62,
                          ),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          scrollProgress: active ? currentLineProgress : null,
                        ),
                      ] else ...[
                        const SizedBox(height: 2),
                        _buildMusicLyricTextLine(
                          next?.primary ?? '',
                          color:
                              const Color(0xFF6B7890).withValues(alpha: 0.54),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMusicLyricTextLine(
    String text, {
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
    double? scrollProgress,
  }) {
    final style = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.1,
    );

    return SizedBox(
      height: fontSize + 4,
      width: double.infinity,
      child: scrollProgress == null
          ? Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: style,
            )
          : _MusicLyricMarquee(
              text: text,
              style: style,
              // 每句开头和结尾各停留一小段时间，中间随播放
              // 进度扫过 ScrollView 的真实可滚动范围。
              progress: ((scrollProgress - 0.16) / 0.68).clamp(0.0, 1.0),
            ),
    );
  }

  Widget _buildMusicCoverPlaceholder(Color accentColor) {
    return ColoredBox(
      color: const Color(0xFFDCE6F1),
      child: Icon(
        Icons.album_rounded,
        color: accentColor.withValues(alpha: 0.76),
        size: 28,
      ),
    );
  }

  String _formatMusicDuration(Duration duration) {
    final totalSeconds = max(0, duration.inSeconds);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool _hasPlayableMusicSource(MusicAttachment attachment) {
    final previewUrl = attachment.previewUrl?.trim();
    if (previewUrl != null && previewUrl.isNotEmpty) return true;

    final localPath = attachment.localAudioPath?.trim();
    if (localPath == null || localPath.isEmpty) return false;
    return File(AppPaths.resolve(localPath)).existsSync();
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

class _MusicLyricMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double progress;

  const _MusicLyricMarquee({
    required this.text,
    required this.style,
    required this.progress,
  });

  @override
  State<_MusicLyricMarquee> createState() => _MusicLyricMarqueeState();
}

class _MusicLyricMarqueeState extends State<_MusicLyricMarquee> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _schedulePositionUpdate(jump: true);
  }

  @override
  void didUpdateWidget(_MusicLyricMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePositionUpdate(jump: oldWidget.text != widget.text);
  }

  void _schedulePositionUpdate({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target = _controller.position.maxScrollExtent *
          widget.progress.clamp(0.0, 1.0);
      if (jump) {
        _controller.jumpTo(target);
        return;
      }
      if ((_controller.offset - target).abs() < 0.25) return;
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.linear,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.hardEdge,
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      ),
    );
  }
}

class _InputContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset anchor;

  _InputContextMenuLayoutDelegate({required this.anchor});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxDx = max(8.0, size.width - childSize.width - 8);
    final dx = (anchor.dx + 10).clamp(8.0, maxDx).toDouble();
    final preferredDy = anchor.dy + 14;
    final maxDy = max(8.0, size.height - childSize.height - 8);
    final dy = preferredDy <= maxDy ? preferredDy : maxDy;
    return Offset(dx, dy.clamp(8.0, maxDy).toDouble());
  }

  @override
  bool shouldRelayout(_InputContextMenuLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor;
  }
}

class _VinylDiscPainter extends CustomPainter {
  final Color accentColor;

  const _VinylDiscPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.48),
          const Color(0xFF20283A),
          const Color(0xFF0D1320),
        ],
        stops: const [0, 0.56, 1],
      ).createShader(bounds);
    canvas.drawCircle(center, radius, basePaint);

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (var index = 0; index < 9; index++) {
      final grooveRadius = radius * (0.42 + index * 0.065);
      groovePaint.color = Colors.white.withValues(
        alpha: index.isEven ? 0.13 : 0.07,
      );
      canvas.drawCircle(center, grooveRadius, groovePaint);
    }

    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.09);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.78),
      -1.32,
      0.76,
      false,
      sheenPaint,
    );
  }

  @override
  bool shouldRepaint(_VinylDiscPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

class _MusicLyricEntry {
  final String primary;
  final String secondary;
  final Duration? timestamp;
  final Duration? endTimestamp;

  const _MusicLyricEntry({
    required this.primary,
    this.secondary = '',
    this.timestamp,
    this.endTimestamp,
  });
}

class _MusicLyrics {
  final List<_MusicLyricEntry> entries;
  final bool timed;

  const _MusicLyrics({
    required this.entries,
    required this.timed,
  });

  factory _MusicLyrics.fromText(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .toList(growable: false);
    return _MusicLyrics.fromLines(lines);
  }

  factory _MusicLyrics.fromLines(List<String> lines) {
    final timedEntries = _parseTimedLines(lines);
    if (timedEntries.isNotEmpty) {
      return _MusicLyrics(entries: timedEntries, timed: true);
    }

    final sectionedEntries = _parseSectionedLyrics(lines);
    if (sectionedEntries.isNotEmpty) {
      return _MusicLyrics(entries: sectionedEntries, timed: false);
    }

    final plainEntries = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !_isLyricHeading(line))
        .map((line) => _MusicLyricEntry(primary: line))
        .toList(growable: false);
    return _MusicLyrics(entries: plainEntries, timed: false);
  }

  factory _MusicLyrics.fromNeteaseJson(Map<String, dynamic> json) {
    final primaryLyrics = _neteaseLyricText(json['lrc']);
    final translatedLyrics = _neteaseLyricText(json['tlyric']);
    if (primaryLyrics.isEmpty) {
      return const _MusicLyrics(entries: [], timed: true);
    }

    final primaryEntries = _parseTimedLines(
      _normalizedLines(primaryLyrics),
      skipCredits: true,
    );
    final translationsByTimestamp = <int, String>{};
    for (final entry in _parseTimedLines(_normalizedLines(translatedLyrics))) {
      final timestamp = entry.timestamp;
      if (timestamp != null && entry.primary.isNotEmpty) {
        translationsByTimestamp[timestamp.inMilliseconds] = entry.primary;
      }
    }

    final entries = primaryEntries
        .map(
          (entry) => _MusicLyricEntry(
            primary: entry.primary,
            secondary:
                translationsByTimestamp[entry.timestamp!.inMilliseconds] ?? '',
            timestamp: entry.timestamp,
            endTimestamp: entry.endTimestamp,
          ),
        )
        .toList(growable: false);
    return _MusicLyrics(entries: entries, timed: true);
  }

  static String _neteaseLyricText(dynamic section) {
    if (section is! Map) return '';
    final lyric = section['lyric'];
    return lyric is String ? lyric : '';
  }

  static List<String> _normalizedLines(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trimRight())
      .toList(growable: false);

  int activeIndex(Duration position, Duration duration) {
    if (entries.isEmpty) return 0;
    if (timed) {
      var index = -1;
      for (var i = 0; i < entries.length; i++) {
        final timestamp = entries[i].timestamp;
        if (timestamp == null || timestamp > position) break;
        index = i;
      }
      return index.clamp(-1, entries.length - 1).toInt();
    }

    if (duration <= Duration.zero) return 0;
    final ratio =
        position.inMilliseconds / max(1, duration.inMilliseconds).toDouble();
    return (ratio * entries.length)
        .floor()
        .clamp(0, entries.length - 1)
        .toInt();
  }

  double entryProgress(
    int index,
    Duration position,
    Duration duration,
  ) {
    if (index < 0 || index >= entries.length) return 0;

    int startMilliseconds;
    int endMilliseconds;
    if (timed) {
      startMilliseconds = entries[index].timestamp?.inMilliseconds ?? 0;
      final explicitEnd = entries[index].endTimestamp?.inMilliseconds;
      final fallbackEnd = index + 1 < entries.length
          ? entries[index + 1].timestamp?.inMilliseconds ??
              duration.inMilliseconds
          : duration.inMilliseconds;
      if (explicitEnd != null) {
        endMilliseconds = explicitEnd;
      } else {
        final repeatedLineDuration = _previousMatchingLineDuration(index);
        endMilliseconds = repeatedLineDuration == null
            ? fallbackEnd
            : min(fallbackEnd, startMilliseconds + repeatedLineDuration);
      }
    } else {
      final totalMilliseconds = max(1, duration.inMilliseconds);
      startMilliseconds = (totalMilliseconds * index / entries.length).round();
      endMilliseconds =
          (totalMilliseconds * (index + 1) / entries.length).round();
    }

    final lineDuration = max(1, endMilliseconds - startMilliseconds);
    return ((position.inMilliseconds - startMilliseconds) / lineDuration)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  int? _previousMatchingLineDuration(int index) {
    final current = entries[index];
    for (var previousIndex = index - 1; previousIndex >= 0; previousIndex--) {
      final previous = entries[previousIndex];
      if (previous.primary != current.primary) continue;
      final start = previous.timestamp?.inMilliseconds;
      final end = previous.endTimestamp?.inMilliseconds;
      if (start != null && end != null && end > start) {
        return end - start;
      }
    }
    return null;
  }

  _MusicLyricEntry? entryAt(int index) {
    if (index < 0 || index >= entries.length) return null;
    return entries[index];
  }

  static List<_MusicLyricEntry> _parseTimedLines(
    List<String> lines, {
    bool skipCredits = false,
  }) {
    final entries = <_MusicLyricEntry>[];
    final timelineBoundaries = <Duration>[];
    final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final rawLine in lines) {
      final matches = timestampPattern.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final timestamps = matches.map(_durationFromTimestampMatch).toList();
      timelineBoundaries.addAll(timestamps);
      final text = rawLine.replaceAll(timestampPattern, '').trim();
      if (text.isEmpty || _isLyricHeading(text)) continue;
      if (skipCredits && _isSongCredit(text)) continue;
      for (final timestamp in timestamps) {
        entries.add(
          _MusicLyricEntry(
            primary: text,
            timestamp: timestamp,
          ),
        );
      }
    }
    entries.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    timelineBoundaries.sort();
    return entries
        .map(
          (entry) => _MusicLyricEntry(
            primary: entry.primary,
            secondary: entry.secondary,
            timestamp: entry.timestamp,
            endTimestamp: timelineBoundaries.cast<Duration?>().firstWhere(
                  (boundary) => boundary! > entry.timestamp!,
                  orElse: () => null,
                ),
          ),
        )
        .toList(growable: false);
  }

  static Duration _durationFromTimestampMatch(RegExpMatch match) {
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final fractionText = match.group(3) ?? '0';
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: _fractionToMilliseconds(fractionText),
    );
  }

  static bool _isSongCredit(String text) => RegExp(
        r'^(作词|作詞|作曲|编曲|編曲|词|詞|曲)\s*[:：]',
        caseSensitive: false,
      ).hasMatch(text);

  static int _fractionToMilliseconds(String text) {
    if (text.isEmpty) return 0;
    final normalized =
        text.length >= 3 ? text.substring(0, 3) : text.padRight(3, '0');
    return int.tryParse(normalized) ?? 0;
  }

  static List<_MusicLyricEntry> _parseSectionedLyrics(List<String> lines) {
    final primaryLines = <String>[];
    final secondaryLines = <String>[];
    var currentSection = _LyricSection.none;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_isJapaneseHeading(line)) {
        currentSection = _LyricSection.primary;
        continue;
      }
      if (_isTranslationHeading(line)) {
        currentSection = _LyricSection.secondary;
        continue;
      }
      if (_isLyricHeading(line)) continue;

      switch (currentSection) {
        case _LyricSection.primary:
          primaryLines.add(line);
          break;
        case _LyricSection.secondary:
          secondaryLines.add(line);
          break;
        case _LyricSection.none:
          break;
      }
    }

    if (primaryLines.isEmpty && secondaryLines.isEmpty) return const [];
    final count = max(primaryLines.length, secondaryLines.length);
    final entries = <_MusicLyricEntry>[];
    for (var index = 0; index < count; index++) {
      final primary = index < primaryLines.length ? primaryLines[index] : '';
      final secondary =
          index < secondaryLines.length ? secondaryLines[index] : '';
      final displayPrimary = primary.isNotEmpty ? primary : secondary;
      if (displayPrimary.isEmpty) continue;
      entries.add(
        _MusicLyricEntry(
          primary: displayPrimary,
          secondary: primary.isNotEmpty ? secondary : '',
        ),
      );
    }
    return entries;
  }

  static bool _isJapaneseHeading(String line) =>
      RegExp(r'^【\s*(日文原词|日文歌词|原词|歌词)\s*】$').hasMatch(line);

  static bool _isTranslationHeading(String line) =>
      RegExp(r'^【\s*(中文翻译|中文译文|翻译|译文)\s*】$').hasMatch(line);

  static bool _isLyricHeading(String line) =>
      RegExp(r'^【[^】]+】$').hasMatch(line);
}

enum _LyricSection { none, primary, secondary }

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
