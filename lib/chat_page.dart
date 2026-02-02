import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
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
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 加载历史对话
  Future<void> _loadConversation() async {
    final messages = await StorageService.loadConversation(widget.character.id);
    setState(() {
      _messages = messages;
    });

    _scrollToBottom();
  }

  // 发送消息
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    // 添加用户消息
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

    // 保存对话
    await StorageService.saveConversation(widget.character.id, _messages);

    // 获取AI回复（日文+中文翻译）
    final recentMessages = StorageService.getRecentMessages(_messages);
    final responseMap = await ApiService.generateResponse(
      characterPersonality: widget.character.personality,
      conversationHistory: recentMessages,
      userMessage: text,
    );

    // 组合日文和中文显示
    final japaneseText = responseMap['japanese'] ?? '';
    final chineseText = responseMap['chinese'] ?? '';
    final displayContent = '$japaneseText\n\n中文：$chineseText';

    // 添加AI回复
    final assistantMessage = Message(
      role: 'assistant',
      content: displayContent,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(assistantMessage);
      _isLoading = false;
    });

    _scrollToBottom();

    // 保存对话
    await StorageService.saveConversation(widget.character.id, _messages);

    // 自动播放语音（只播放日文部分）
    _playAudio(japaneseText);
  }

  // 播放音频 - 支持长文本分段播放（使用 GPT-SoVITS）
  Future<void> _playAudio(String text) async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    setState(() {
      _isPlaying = true;
    });

    try {
      // 如果文本包含中文翻译，只提取日文部分
      String japaneseText = text;
      if (text.contains('\n\n中文：')) {
        japaneseText = text.split('\n\n中文：')[0];
      }

      // 使用 GPT-SoVITS 分段生成语音
      final audioPaths = await ApiService.generateSpeechSegments(
        text: japaneseText,
        referWavPath: widget.character.referWavPath,
        promptText: widget.character.promptText,
        promptLanguage: widget.character.promptLanguage,
      );

      if (audioPaths.isEmpty) {
        setState(() {
          _isPlaying = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('语音生成失败，请检查 GPT-SoVITS 服务是否运行')),
          );
        }
        return;
      }

      // 依次播放所有音频片段
      for (int i = 0; i < audioPaths.length; i++) {
        if (!_isPlaying) break;

        print('开始播放片段 ${i + 1}/${audioPaths.length}');

        // 设置播放源
        await _audioPlayer.setSource(DeviceFileSource(audioPaths[i]));

        // 开始播放
        await _audioPlayer.resume();

        // 等待播放完成
        await for (final state in _audioPlayer.onPlayerStateChanged) {
          if (state == PlayerState.completed) {
            print('片段 ${i + 1} 播放完成');
            break;
          }
        }

        // 如果还有下一段，等待一小段时间再播放（自然停顿）
        if (i < audioPaths.length - 1 && _isPlaying) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      print('所有片段播放完成');
    } catch (e) {
      print('播放失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  // 滚动到底部
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

  // 构建包含翻译的消息显示
  List<Widget> _buildTranslatedMessage(String content) {
    final parts = content.split('\n\n中文：');
    final japaneseText = parts[0];
    final chineseText = parts.length > 1 ? parts[1] : '';

    return [
      // 日文部分
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
        // 分隔线
        Container(
          height: 1,
          color: Colors.grey.withOpacity(0.3),
        ),
        const SizedBox(height: 8),
        // 中文翻译部分
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

  // 清空对话
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
          if (_isPlaying)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () async {
                await _audioPlayer.stop();
                setState(() {
                  _isPlaying = false;
                });
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
          // 对话列表
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
                        // 显示消息内容，如果是AI回复且包含翻译，则分开显示
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
                            child: GestureDetector(
                              onTap: () => _playAudio(message.content),
                              child: Icon(
                                Icons.volume_up,
                                size: 18,
                                color: Colors.blue[300],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 加载指示器
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

          // 输入框
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
