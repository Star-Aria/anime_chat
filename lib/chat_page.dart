import 'dart:ui';
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

// AI消息气泡渐变色（可自定义颜色列表）
const List<Color> AI_BUBBLE_GRADIENT = [
  Color.fromARGB(255, 212, 249, 215),
  Color.fromARGB(255, 243, 195, 212),
  Color.fromARGB(255, 223, 189, 248),
  Color.fromARGB(255, 255, 255, 255),
];

// AI消息气泡边框颜色
const Color AI_BUBBLE_BORDER_COLOR = Color.fromARGB(255, 203, 147, 249);

// AI消息气泡发光颜色和强度
const Color AI_BUBBLE_GLOW_COLOR = Color.fromARGB(255, 200, 117, 255); // 发光颜色
const double AI_BUBBLE_GLOW_BLUR = 30.0; // 发光范围（越大越扩散）
const double AI_BUBBLE_GLOW_OPACITY = 0.8; // 发光强度（0.0-1.0）

// 对话框圆角大小
const double MESSAGE_BUBBLE_RADIUS = 18.0; // 主圆角
const double MESSAGE_BUBBLE_CORNER_RADIUS = 4.0; // 靠近发送者的小圆角

// 对话框内边距
const double MESSAGE_BUBBLE_HORIZONTAL_PADDING = 16.0; // 左右内边距
const double MESSAGE_BUBBLE_VERTICAL_PADDING = 12.0; // 上下内边距

// 背景图片路径（留空则不使用背景图）
const String BACKGROUND_IMAGE_PATH = ''; // 例如: 'assets/images/bg.jpg'
// 注意：需要在 pubspec.yaml 中添加 assets 配置

// 背景图片模糊度
const double BACKGROUND_BLUR_SIGMA = 3.0; // 模糊强度（0-20）

// 背景图片不透明度
const double BACKGROUND_OPACITY = 0.7; // 透明度（0.0-1.0）

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

  late AnimationController _typingAnimationController; // "AI正在输入"动画控制器

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
  }

  // 初始化音频播放器
  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer.setReleaseMode(ReleaseMode.release);
  }

  // 页面销毁时释放资源
  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
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

      if (!success) {
        // 模型切换失败，显示警告
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('模型切换失败，可能使用默认模型'),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        print('✅ ${widget.character.name} 的模型切换成功');
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

  // 加载用户自定义的聊天背景图
  Future<void> _loadBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    final bgPath = prefs.getString('background_image');
    if (bgPath != null && mounted) {
      setState(() {
        _backgroundImagePath = bgPath;
      });
    }
  }

  // ========================================
  // 图片和背景设置相关方法
  // ========================================

  // 选择聊天背景图片（从相册）
  Future<void> _pickBackgroundImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // 保存图片路径到本地存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_image', image.path);

      if (mounted) {
        setState(() {
          _backgroundImagePath = image.path;
        });
      }
    }
  }

  // 清除自定义背景图片（恢复默认渐变背景）
  Future<void> _clearBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('background_image');

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

  // 发送用户消息并获取AI回复
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    // 创建用户消息对象
    final userMessage = Message(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    // 将用户消息添加到消息列表并更新UI
    setState(() {
      _messages.add(userMessage);
      _isLoading = true; // 显示"AI正在输入"指示器
    });

    _textController.clear(); // 清空输入框
    _scrollToBottom(); // 滚动到底部

    // 保存对话记录到本地存储
    // 保存对话记录到本地存储
    await StorageService.saveConversation(widget.character.id, _messages);

    // 调用DeepSeek API生成AI回复（包含日文原文和中文翻译）
    final recentMessages = StorageService.getRecentMessages(_messages);
    final responseMap = await ApiService.generateResponse(
      characterPersonality: widget.character.personality,
      conversationHistory: recentMessages,
      userMessage: text,
    );

    // 提取日文原文和中文翻译
    final japaneseText = responseMap['japanese'] ?? '';
    final chineseText = responseMap['chinese'] ?? '';
    final displayContent = '$japaneseText\n\n中文：$chineseText';

    // 调用GPT-SoVITS API生成日文语音
    print('🎤 生成音频中...');
    final audioPath = await ApiService.generateSpeech(
      text: japaneseText,
      referWavPath: widget.character.referWavPath,
      promptText: widget.character.promptText,
      promptLanguage: widget.character.promptLanguage,
    );

    // 创建AI消息对象（包含文本和音频路径）
    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPath,
    );

    // 将AI消息添加到消息列表并更新UI
    if (mounted) {
      setState(() {
        _messages.add(assistantMessage);
        _isLoading = false; // 隐藏"AI正在输入"指示器
      });
    }

    _scrollToBottom(); // 滚动到底部
    await StorageService.saveConversation(widget.character.id, _messages);

    // 自动播放生成的语音
    if (audioPath != null) {
      _playAudioFromPath(audioPath);
    }
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

      // 检查音频文件是否存在
      final file = File(audioPath);
      if (!await file.exists()) {
        print('❌ 音频文件不存在: $audioPath');
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
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
        // 显示错误提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // 播放指定消息的音频（点击音量图标时调用）
  Future<void> _playAudio(Message message) async {
    try {
      await _audioPlayer.stop(); // 先停止当前播放

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
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

      // 调用GPT-SoVITS API生成语音
      final audioPath = await ApiService.generateSpeech(
        text: japaneseText,
        referWavPath: widget.character.referWavPath,
        promptText: widget.character.promptText,
        promptLanguage: widget.character.promptLanguage,
      );

      if (audioPath == null) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          // 显示生成失败提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('音频生成失败'),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
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
      // 翻译部分（中文）- 使用翻译字体配置，带灰色背景
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          parts[1],
          style: const TextStyle(
            fontFamily: AI_TRANSLATION_FONT_FAMILY,
            fontSize: AI_TRANSLATION_FONT_SIZE,
            fontWeight: AI_TRANSLATION_FONT_WEIGHT,
            color: Color.fromARGB(255, 32, 32, 32),
            height: 1.4,
          ),
        ),
      ),
    ];
  }

  // ========================================
  // 辅助工具方法
  // ========================================

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
          // 模型切换成功指示器
          if (_modelSwitched)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: 20,
                ),
              ),
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

                        return _buildMessageBubble(message, isUser, color);
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
    // 情况1：使用用户从相册选择的背景图片
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
          // 模糊和半透明遮罩（让文字更清晰）
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: BACKGROUND_BLUR_SIGMA, // 在顶部配置区修改
                sigmaY: BACKGROUND_BLUR_SIGMA,
              ),
              child: Container(
                color: Colors.white.withOpacity(
                  1.0 - BACKGROUND_OPACITY, // 在顶部配置区修改
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 情况2：使用代码中配置的背景图路径（从assets）
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
                sigmaX: BACKGROUND_BLUR_SIGMA,
                sigmaY: BACKGROUND_BLUR_SIGMA,
              ),
              child: Container(
                color: Colors.white.withOpacity(1.0 - BACKGROUND_OPACITY),
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
          colors: CHAT_BACKGROUND_GRADIENT, // 在顶部配置区修改
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
  Widget _buildMessageBubble(Message message, bool isUser, Color color) {
    return Padding(
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
                maxWidth:
                    MediaQuery.of(context).size.width * MESSAGE_MAX_WIDTH_RATIO,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MESSAGE_BUBBLE_HORIZONTAL_PADDING, // 在顶部配置区修改
                  vertical: MESSAGE_BUBBLE_VERTICAL_PADDING, // 在顶部配置区修改
                ),
                decoration: BoxDecoration(
                  // AI消息：自定义渐变色 + 发光效果
                  gradient: isUser
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AI_BUBBLE_GRADIENT, // 在顶部配置区修改
                        ),
                  // 用户消息：主题色纯色背景
                  color: isUser ? color.withOpacity(0.6) : null,
                  // 圆角设置（靠近发送者一侧用小圆角）
                  borderRadius: isUser
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                          topRight:
                              Radius.circular(MESSAGE_BUBBLE_CORNER_RADIUS),
                          bottomLeft: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                          bottomRight: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                        )
                      : const BorderRadius.only(
                          topLeft:
                              Radius.circular(MESSAGE_BUBBLE_CORNER_RADIUS),
                          topRight: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                          bottomLeft: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                          bottomRight: Radius.circular(MESSAGE_BUBBLE_RADIUS),
                        ),
                  // AI消息边框
                  border: !isUser
                      ? Border.all(
                          color: AI_BUBBLE_BORDER_COLOR, // 在顶部配置区修改
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
                        color: AI_BUBBLE_GLOW_COLOR
                            .withOpacity(AI_BUBBLE_GLOW_OPACITY), // 在顶部配置区修改
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
                          color:
                              isUser ? Colors.white : const Color(0xFF2D3142),
                          height: 1.5,
                        ),
                      ),
                    // AI消息底部的播放按钮
                    if (!isUser)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 语音播放图标（点击播放音频）
                            GestureDetector(
                              onTap: () => _playAudio(message),
                              child: Icon(
                                Icons.volume_up,
                                size: 18,
                                color: AI_BUBBLE_BORDER_COLOR,
                              ),
                            ),
                            // 音频已缓存指示器
                            if (message.audioPath != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 12,
                                  color: Colors.green[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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
    );
  }
}
