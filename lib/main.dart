import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'character_config.dart';
import 'chat_page.dart';
import 'proactive_message_service.dart';

// ========================================
// 窗口大小配置
// ========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 设置窗口初始参数
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600), // 窗口初始大小 (宽, 高)
    minimumSize: Size(600, 450), // 窗口最小大小（不能缩小到比这更小）
    center: true, // 窗口是否居中显示
    backgroundColor: Colors.transparent,
    skipTaskbar: false, // 是否在任务栏显示
    titleBarStyle: TitleBarStyle.normal, // 标题栏样式
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  ProactiveMessageService().initialize(CharacterConfig.characters);

  runApp(const MyApp());
}

// ========================================
// 应用主组件
// ========================================
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Chat',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        fontFamily: 'FangSong', // 默认字体
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF6C63FF),
          secondary: const Color(0xFF00D4AA),
          background: const Color(0xFFF5F7FA),
          surface: Colors.white,
        ),
      ),
      home: const CharacterSelectionPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 调试面板：显示所有角色的主动消息计时状态
Future<void> _showDebugPanel(BuildContext context) async {
  showDialog(
    context: context,
    builder: (ctx) => _DebugPanelDialog(),
  );
}

class _DebugPanelDialog extends StatefulWidget {
  @override
  State<_DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<_DebugPanelDialog> {
  List<Map<String, dynamic>> _info = [];
  bool _loading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });
    final info = await ProactiveMessageService()
        .getDebugInfo(CharacterConfig.characters);
    if (mounted)
      setState(() {
        _info = info;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Text('🔧 主动消息调试面板',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: '刷新',
          onPressed: _refresh,
        ),
      ]),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_statusMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_statusMessage!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green)),
                      ),
                    ..._info.map((d) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text('${d['name']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const Spacer(),
                                  if ((d['unread'] as int) > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text('未读 ${d['unread']}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11)),
                                    ),
                                ]),
                                const SizedBox(height: 6),
                                _debugRow('服务状态',
                                    d['serviceRunning'] ? '✅ 运行中' : '❌ 未初始化'),
                                _debugRow('下次检查', d['nextFire'] ?? '—'),
                                _debugRow('上次发送', d['lastProactive']),
                                _debugRow('冷却状态',
                                    '${d['hoursSince']}  ${d['cooldownOk'] ? "✅ 可触发" : "⏳ 冷却中"}'),
                                _debugRow('触发概率', d['idleChance']),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.send, size: 14),
                                    label: const Text('强制触发（跳过冷却和概率）',
                                        style: TextStyle(fontSize: 12)),
                                    onPressed: () async {
                                      setState(() {
                                        _statusMessage = null;
                                      });
                                      final character = CharacterConfig
                                          .characters
                                          .firstWhere((c) => c.id == d['id']);
                                      await ProactiveMessageService()
                                          .debugForceProactive(character);
                                      await _refresh();
                                      if (mounted) {
                                        setState(() {
                                          _statusMessage =
                                              '✅ 已触发 ${d['name']} 的主动消息';
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}

Widget _debugRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

// ========================================
// 角色选择页面
// ========================================
class CharacterSelectionPage extends StatelessWidget {
  const CharacterSelectionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 调试按钮（仅 debug 模式下显示，release 构建后自动消失）
      floatingActionButton: () {
        bool isDebug = false;
        assert(() {
          isDebug = true;
          return true;
        }());
        if (!isDebug) return null;
        return FloatingActionButton.small(
          backgroundColor: Colors.black54,
          tooltip: '主动消息调试面板',
          child: const Icon(Icons.bug_report, color: Colors.white, size: 18),
          onPressed: () => _showDebugPanel(context),
        );
      }(),
      body: Container(
        // 渐变背景
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF5F7FA),
              Color(0xFFE8ECEF),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 页面标题区域
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Logo图标
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF00D4AA)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 35,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 应用标题
                    const Text(
                      'Anime Chat',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Times New Roman',
                        color: Color(0xFF2D3142),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 副标题
                    Text(
                      '选择你想对话的角色',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // 角色卡片列表
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: CharacterConfig.characters.length,
                  itemBuilder: (context, index) {
                    final character = CharacterConfig.characters[index];
                    return _CharacterCard(character: character);
                  },
                ),
              ),

              // 底部提示文字
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '点击角色卡片开始对话',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================
// 角色卡片组件
// ========================================
class _CharacterCard extends StatefulWidget {
  final Character character;

  const _CharacterCard({Key? key, required this.character}) : super(key: key);

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  String? _characterAvatarPath; // 角色自定义头像路径
  int _unreadCount = 0; // 未读消息数

  @override
  void initState() {
    super.initState();
    _loadCharacterAvatar();
    _loadUnreadCount();
    // 注册未读数变化回调，离线消息到达时立即刷新红点，不需要等用户手动刷新
    ProactiveMessageService().registerUnreadCallback(
      widget.character.id,
      (count) {
        if (mounted) setState(() => _unreadCount = count);
      },
    );
  }

  @override
  void dispose() {
    ProactiveMessageService().unregisterUnreadCallback(widget.character.id);
    super.dispose();
  }

  // 加载用户自定义的角色头像（与聊天界面保持一致）
  Future<void> _loadCharacterAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_${widget.character.id}');
    if (avatarPath != null && mounted) {
      setState(() {
        _characterAvatarPath = avatarPath;
      });
    }
  }

  // 加载未读消息数
  Future<void> _loadUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('unread_${widget.character.id}') ?? 0;
    if (mounted) {
      setState(() {
        _unreadCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('0xFF${widget.character.color}'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 点击卡片进入聊天页面
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatPage(character: widget.character),
              ),
            );
            // 从聊天页返回后刷新未读数（ChatPage 会在 initState 里清零）
            _loadUnreadCount();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 角色头像（优先显示自定义头像）+ 未读消息红点
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: color.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
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
                                    style: const TextStyle(fontSize: 30),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // 未读消息红点（有未读时才显示）
                    if (_unreadCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.all(Radius.circular(9)),
                          ),
                          child: Center(
                            child: Text(
                              _unreadCount > 99 ? '99+' : '$_unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // 角色信息区域
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 角色中文名
                      Text(
                        widget.character.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 角色日文名
                      Text(
                        widget.character.nameJp,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Times New Roman',
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 作品标签
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '鬼灭之刃',
                          style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧箭头图标
                Icon(
                  Icons.arrow_forward_ios,
                  color: color.withOpacity(0.6),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
