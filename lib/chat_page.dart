import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'character_config.dart';
import 'storage_service.dart';
import 'api_service.dart';

class ChatPage extends StatefulWidget {
  final Character character;

  const ChatPage({Key? key, required this.character}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AudioPlayer _audioPlayer;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _modelSwitched = false;
  String? _characterAvatarPath;

  late AnimationController _typingAnimationController;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _loadConversation();
    _switchModel();
    _loadCharacterAvatar();

    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    // audioplayers 包的 Windows 版本可能不需要特殊配置
    // 如果需要配置，使用以下方式：
    _audioPlayer.setReleaseMode(ReleaseMode.release);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
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

      if (!success) {
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
    if (text.isEmpty || _isLoading) return;

    final userMessage = Message(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _textController.clear();
    _scrollToBottom();

    await StorageService.saveConversation(widget.character.id, _messages);

    final recentMessages = StorageService.getRecentMessages(_messages);
    final responseMap = await ApiService.generateResponse(
      characterPersonality: widget.character.personality,
      conversationHistory: recentMessages,
      userMessage: text,
    );

    final japaneseText = responseMap['japanese'] ?? '';
    final chineseText = responseMap['chinese'] ?? '';
    final displayContent = '$japaneseText\n\n中文：$chineseText';

    print('🎤 生成音频中...');
    final audioPath = await ApiService.generateSpeech(
      text: japaneseText,
      referWavPath: widget.character.referWavPath,
      promptText: widget.character.promptText,
      promptLanguage: widget.character.promptLanguage,
    );

    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPath,
    );

    if (mounted) {
      setState(() {
        _messages.add(assistantMessage);
        _isLoading = false;
      });
    }

    _scrollToBottom();
    await StorageService.saveConversation(widget.character.id, _messages);

    if (audioPath != null) {
      _playAudioFromPath(audioPath);
    }
  }

  Future<void> _playAudioFromPath(String audioPath) async {
    try {
      await _audioPlayer.stop();

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });

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

      await _audioPlayer.setSource(DeviceFileSource(audioPath));
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.resume();

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

  Future<void> _playAudio(Message message) async {
    try {
      await _audioPlayer.stop();

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });

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

      print('🔄 重新生成音频...');

      String japaneseText = message.content;
      if (message.content.contains('\n\n中文：')) {
        japaneseText = message.content.split('\n\n中文：')[0];
      }

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

      final messageIndex = _messages.indexOf(message);
      if (messageIndex != -1) {
        _messages[messageIndex] = message.copyWith(audioPath: audioPath);
        await StorageService.saveConversation(widget.character.id, _messages);
      }

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
      Text(
        parts[0],
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF2D3142),
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          parts[1],
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            height: 1.4,
          ),
        ),
      ),
    ];
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

    if (confirm == true) {
      await StorageService.clearConversation(widget.character.id);
      setState(() {
        _messages.clear();
      });
      _loadConversation();
    }
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
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
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
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.grey[700]),
            onPressed: _clearConversation,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 主聊天区域
          Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFF5F7FA),
                        const Color(0xFFE8EDF2),
                        const Color(0xFFDDE3E9),
                      ],
                    ),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 100,
                    ),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == _messages.length) {
                        return _buildTypingIndicator();
                      }

                      final message = _messages[index];
                      final isUser = message.role == 'user';

                      return _buildMessageBubble(message, isUser, color);
                    },
                  ),
                ),
              ),
            ],
          ),

          // 毛玻璃输入框 - 使用你的成功模式！
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
                    Colors.white.withOpacity(0.25), // 半透明渐变
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
                      color: Colors.transparent, // 完全透明，让渐变显示
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
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
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
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

  // 闪烁的省略号指示器
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
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

  // 消息气泡
  Widget _buildMessageBubble(Message message, bool isUser, Color color) {
    return Padding(
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
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                // AI消息：主题色渐变 + 发光效果
                gradient: isUser
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withOpacity(0.15),
                          color.withOpacity(0.08),
                        ],
                      ),
                // 用户消息：主题色纯色
                color: isUser ? color.withOpacity(0.85) : null,
                borderRadius: isUser
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(4),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                // AI消息边框：主题色
                border: !isUser
                    ? Border.all(
                        color: color.withOpacity(0.3),
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
                      color: color.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: -2,
                      offset: const Offset(0, 0),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && message.content.contains('\n\n中文：'))
                    ..._buildTranslatedMessage(message.content)
                  else
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: isUser ? Colors.white : const Color(0xFF2D3142),
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
                            onTap: () => _playAudio(message),
                            child: Icon(
                              Icons.volume_up,
                              size: 18,
                              color: color,
                            ),
                          ),
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
          if (isUser) const SizedBox(width: 10),
        ],
      ),
    );
  }
}
