import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
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

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AudioPlayer _audioPlayer;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _modelSwitched = false;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _loadConversation();
    _switchModel();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: [],
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
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
          const SnackBar(
            content: Text('模型切换失败，可能使用默认模型'),
            duration: Duration(seconds: 2),
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

    // ⭐ 先生成音频，获取路径
    print('🎤 生成音频中...');
    final audioPath = await ApiService.generateSpeech(
      text: japaneseText,
      referWavPath: widget.character.referWavPath,
      promptText: widget.character.promptText,
      promptLanguage: widget.character.promptLanguage,
    );

    // ⭐ 创建消息时保存音频路径
    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
      audioPath: audioPath, // ⭐ 保存音频路径到消息
    );

    if (mounted) {
      setState(() {
        _messages.add(assistantMessage);
        _isLoading = false;
      });
    }

    _scrollToBottom();
    await StorageService.saveConversation(widget.character.id, _messages);

    // ⭐ 自动播放（使用已生成的音频）
    if (audioPath != null) {
      _playAudioFromPath(audioPath);
    }
  }

  // ⭐ 新方法：直接播放指定路径的音频
  Future<void> _playAudioFromPath(String audioPath) async {
    try {
      await _audioPlayer.stop();

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });

      // 验证文件存在
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
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  // ⭐ 修改后的播放方法：支持缓存
  Future<void> _playAudio(Message message) async {
    try {
      await _audioPlayer.stop();

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });

      // ⭐ 检查是否有缓存的音频
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

      // ⭐ 没有缓存，重新生成
      print('🔄 重新生成音频...');

      // 提取日文部分
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
            const SnackBar(content: Text('语音生成失败')),
          );
        }
        return;
      }

      // ⭐ 更新消息的音频路径并保存
      final index = _messages.indexOf(message);
      if (index != -1) {
        _messages[index] = message.copyWith(audioPath: audioPath);
        await StorageService.saveConversation(widget.character.id, _messages);
      }

      // 播放新生成的音频
      await _playAudioFromPath(audioPath);
    } catch (e) {
      print('❌ 播放失败: $e');
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Widget> _buildTranslatedMessage(String content) {
    final parts = content.split('\n\n中文：');
    final japaneseText = parts[0];
    final chineseText = parts.length > 1 ? parts[1] : '';

    return [
      Text(
        japaneseText,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      if (chineseText.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: Colors.grey.withOpacity(0.3),
        ),
        const SizedBox(height: 8),
        Text(
          chineseText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[400],
            height: 1.4,
          ),
        ),
      ],
    ];
  }

  Future<void> _clearConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有对话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
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
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        title: Row(
          children: [
            Text(
              widget.character.avatar,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.character.name,
                  style: const TextStyle(fontSize: 18),
                ),
                Text(
                  widget.character.nameJp,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
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
                  color: Colors.green[400],
                  size: 20,
                ),
              ),
            ),
          if (_isPlaying)
            IconButton(
              icon: const Icon(Icons.stop),
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
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.role == 'user';

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? color.withOpacity(0.8)
                          : const Color(0xFF1E2442),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUser
                            ? color.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser && message.content.contains('\n\n中文：'))
                          ..._buildTranslatedMessage(message.content)
                        else
                          Text(
                            message.content,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                        if (!isUser)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      _playAudio(message), // ⭐ 传入整个 message
                                  child: Icon(
                                    Icons.volume_up,
                                    size: 18,
                                    color: Colors.blue[300],
                                  ),
                                ),
                                // ⭐ 显示缓存状态
                                if (message.audioPath != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: Colors.green[300],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${widget.character.name}正在思考...',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1F3A),
              border: Border(
                top: BorderSide(
                  color: Color(0xFF2A2F4A),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF0A0E27),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
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
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.7)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
