import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
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
        const Text('主动消息调试面板',
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
                                    d['serviceRunning'] ? '运行中' : '未初始化'),
                                _debugRow('下次检查', d['nextFire'] ?? '—'),
                                _debugRow('上次发送', d['lastProactive']),
                                _debugRow('冷却状态',
                                    '${d['hoursSince']}  ${d['cooldownOk'] ? "可触发" : "冷却中"}'),
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
                                              '已触发 ${d['name']} 的主动消息';
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
// 弥散渐变背景 -- 单个色块数据模型
// ========================================
// 每个色块用一个径向渐变圆绘制，通过叠加多个不同位置/大小/颜色的圆
// 形成繁复的弥散渐变效果。
class _GradientBlob {
  final double cx; // 色块中心 X 归一化坐标 (0.0=最左, 1.0=最右)
  final double cy; // 色块中心 Y 归一化坐标 (0.0=最上, 1.0=最下)
  final double radius; // 色块扩散半径，值越大越弥散（建议 0.2~1.0）
  final Color color; // 色块颜色（建议低透明度 0.06~0.20）
  final double driftX; // 水平漂移方向系数
  final double driftY; // 垂直漂移方向系数

  const _GradientBlob({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.color,
    this.driftX = 1.0,
    this.driftY = 1.0,
  });
}

// ========================================
// 背景色块配置
// ========================================
// 背景整体偏淡偏暖灰，颜色透明度低，这样卡片的彩色投影才能清晰呈现。
// 同种颜色分布在不同位置形成呼应关系。
const List<_GradientBlob> _backgroundBlobs = [
  // ---------- 紫色系（蝴蝶忍，左上和右下呼应） ----------
  _GradientBlob(
      cx: 0.1,
      cy: 0.15,
      radius: 0.55,
      color: Color.fromRGBO(170, 120, 230, 0.12),
      driftX: 0.8,
      driftY: -0.6),
  _GradientBlob(
      cx: 0.75,
      cy: 0.8,
      radius: 0.4,
      color: Color.fromRGBO(160, 100, 220, 0.08),
      driftX: -0.5,
      driftY: 0.7),
  _GradientBlob(
      cx: 0.5,
      cy: 0.35,
      radius: 0.3,
      color: Color.fromRGBO(190, 150, 255, 0.06),
      driftX: 0.3,
      driftY: 0.9),

  // ---------- 青绿色系（时透无一郎，右上和左下） ----------
  _GradientBlob(
      cx: 0.85,
      cy: 0.12,
      radius: 0.5,
      color: Color.fromRGBO(0, 200, 210, 0.10),
      driftX: -0.7,
      driftY: -0.4),
  _GradientBlob(
      cx: 0.2,
      cy: 0.75,
      radius: 0.35,
      color: Color.fromRGBO(80, 220, 200, 0.07),
      driftX: 0.6,
      driftY: 0.5),

  // ---------- 蓝色系（富冈义勇） ----------
  _GradientBlob(
      cx: 0.3,
      cy: 0.5,
      radius: 0.45,
      color: Color.fromRGBO(80, 140, 230, 0.08),
      driftX: 0.5,
      driftY: -0.3),
  _GradientBlob(
      cx: 0.9,
      cy: 0.45,
      radius: 0.35,
      color: Color.fromRGBO(100, 170, 250, 0.06),
      driftX: -0.6,
      driftY: 0.4),

  // ---------- 粉色系（暖色平衡） ----------
  _GradientBlob(
      cx: 0.4,
      cy: 0.08,
      radius: 0.4,
      color: Color.fromRGBO(240, 140, 190, 0.08),
      driftX: -0.3,
      driftY: 0.7),
  _GradientBlob(
      cx: 0.15,
      cy: 0.55,
      radius: 0.3,
      color: Color.fromRGBO(255, 170, 200, 0.05),
      driftX: 0.9,
      driftY: -0.2),

  // ---------- 暖黄 ----------
  _GradientBlob(
      cx: 0.65,
      cy: 0.25,
      radius: 0.3,
      color: Color.fromRGBO(255, 200, 120, 0.06),
      driftX: -0.4,
      driftY: 0.6),
];

// ========================================
// 角色选择页面（首页）
// ========================================
class CharacterSelectionPage extends StatefulWidget {
  const CharacterSelectionPage({Key? key}) : super(key: key);

  @override
  State<CharacterSelectionPage> createState() => _CharacterSelectionPageState();
}

class _CharacterSelectionPageState extends State<CharacterSelectionPage>
    with SingleTickerProviderStateMixin {
  // 背景光晕的缓慢漂移动画控制器
  // duration 控制一个完整循环的时长，值越大漂移越慢（建议 20~60 秒）
  late AnimationController _bgAnimCtrl;

  @override
  void initState() {
    super.initState();
    _bgAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25), // 背景漂移动画周期
    )..repeat();
  }

  @override
  void dispose() {
    _bgAnimCtrl.dispose();
    super.dispose();
  }

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
      body: Stack(
        children: [
          // ========================================
          // 层 1：弥散渐变背景（多色块叠加 + 缓慢漂移动画）
          // ========================================
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BgPainter(
                    blobs: _backgroundBlobs,
                    t: _bgAnimCtrl.value,
                    drift: 22.0, // 漂移幅度（像素），值越大移动范围越大
                    // 基底色 -- 浅暖灰白，要比卡片淡很多
                    baseColor: const Color(0xFFF6F3F0),
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),

          // ========================================
          // 层 2：页面主体内容
          // ========================================
          SafeArea(
            child: Column(
              children: [
                // 页面标题区域
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
                  child: Column(
                    children: [
                      // Logo
                      _GlassLogo(),
                      const SizedBox(height: 18),
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
                      const SizedBox(height: 6),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                    itemCount: CharacterConfig.characters.length,
                    itemBuilder: (context, index) {
                      final character = CharacterConfig.characters[index];
                      return _LiquidGlassCard(
                        character: character,
                        entranceDelay: Duration(milliseconds: 150 * index),
                      );
                    },
                  ),
                ),

                // 底部提示文字
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '点击角色卡片开始对话',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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

// ========================================
// 弥散渐变背景绘制器
// ========================================
class _BgPainter extends CustomPainter {
  final List<_GradientBlob> blobs;
  final double t; // 0~1 动画进度
  final double drift; // 漂移幅度
  final Color baseColor;

  _BgPainter({
    required this.blobs,
    required this.t,
    this.drift = 22.0,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 铺满基底色
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    for (int i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      // 每个色块用独立相位漂移，黄金角错开（约 137.5 度）
      final phase = i * 2.399;
      final dx = drift * b.driftX * sin(t * 2 * pi + phase);
      final dy = drift * b.driftY * cos(t * 2 * pi + phase * 0.7);

      final cx = size.width * b.cx + dx;
      final cy = size.height * b.cy + dy;
      final r = max(size.width, size.height) * b.radius;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..shader = RadialGradient(
            colors: [b.color, b.color.withOpacity(0)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => old.t != t;
}

// ========================================
// 液态玻璃风格 Logo
// ========================================
class _GlassLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          // 紫色投影
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.3),
            blurRadius: 28,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
          // 青色投影
          BoxShadow(
            color: const Color(0xFF00D4AA).withOpacity(0.2),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(-4, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.75),
                  Color.fromRGBO(255, 255, 255, 0.45),
                  Color.fromRGBO(220, 210, 240, 0.3),
                ],
                stops: [0.0, 0.4, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 1.5,
              ),
            ),
            child: Center(
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF00D4AA)],
                  ).createShader(bounds);
                },
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================
// 液态玻璃角色卡片
// ========================================
// 设计要点（参考 Liquid Glass Kit）：
//   1. 立体感：多层彩色投影（colored drop shadow）模拟厚度与悬浮
//   2. 圆润感：大圆角 + 内部 padding 充裕
//   3. 光影模拟：顶亮底暗的渐变 + 上边缘白色高光带 + 底部暗色描边
//   4. 彩色边缘：边框使用渐变色（上亮下深）的角色主题色
//   5. hover 交互：上浮 + 投影增强 + 发光增强
class _LiquidGlassCard extends StatefulWidget {
  final Character character;
  final Duration entranceDelay;

  const _LiquidGlassCard({
    Key? key,
    required this.character,
    this.entranceDelay = Duration.zero,
  }) : super(key: key);

  @override
  State<_LiquidGlassCard> createState() => _LiquidGlassCardState();
}

class _LiquidGlassCardState extends State<_LiquidGlassCard>
    with TickerProviderStateMixin {
  String? _characterAvatarPath; // 角色自定义头像路径
  int _unreadCount = 0; // 未读消息数
  bool _isHovered = false;

  late AnimationController _hoverCtrl;
  late Animation<double> _hoverT; // 0.0(默认) ~ 1.0(hover)

  late AnimationController _entranceCtrl;
  late Animation<double> _entranceOpacity;
  late Animation<Offset> _entranceSlide;

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

    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _hoverT = CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOutCubic);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _entranceOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
    );

    Future.delayed(widget.entranceDelay, () {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    ProactiveMessageService().unregisterUnreadCallback(widget.character.id);
    _hoverCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // 加载用户自定义的角色头像（与聊天界面保持一致）
  Future<void> _loadCharacterAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_${widget.character.id}');
    if (avatarPath != null && mounted) {
      setState(() => _characterAvatarPath = avatarPath);
    }
  }

  // 加载未读消息数
  Future<void> _loadUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('unread_${widget.character.id}') ?? 0;
    if (mounted) setState(() => _unreadCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Color(int.parse('0xFF${widget.character.color}'));

    return SlideTransition(
      position: _entranceSlide,
      child: FadeTransition(
        opacity: _entranceOpacity,
        child: AnimatedBuilder(
          animation: _hoverT,
          builder: (context, _) {
            final ht = _hoverT.value;

            // ========================================
            // hover 动态参数（可在此处调整 hover 效果强度）
            // ========================================
            final translateY = -6.0 * ht; // 上浮距离，最大 6px
            final shadowBlur = 18.0 + 18.0 * ht; // 主投影模糊半径
            final shadowOffY = 8.0 + 8.0 * ht; // 主投影垂直偏移
            final shadowAlpha = 0.28 + 0.17 * ht; // 主投影透明度
            final borderAlpha = 0.32 + 0.28 * ht; // 彩色边框透明度
            final glassAlpha = 0.62 + 0.1 * ht; // 玻璃白底透明度

            return Transform.translate(
              offset: Offset(0, translateY),
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() => _isHovered = true);
                    _hoverCtrl.forward();
                  },
                  onExit: (_) {
                    setState(() => _isHovered = false);
                    _hoverCtrl.reverse();
                  },
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    // 点击卡片进入聊天页面
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(character: widget.character),
                        ),
                      );
                      // 从聊天页返回后刷新未读数（ChatPage 会在 initState 里清零）
                      _loadUnreadCount();
                    },
                    child: _buildCard(
                      themeColor,
                      shadowBlur: shadowBlur,
                      shadowOffY: shadowOffY,
                      shadowAlpha: shadowAlpha,
                      borderAlpha: borderAlpha,
                      glassAlpha: glassAlpha,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ----------------------------------------
  // 液态玻璃卡片主体
  // ----------------------------------------
  Widget _buildCard(
    Color themeColor, {
    required double shadowBlur,
    required double shadowOffY,
    required double shadowAlpha,
    required double borderAlpha,
    required double glassAlpha,
  }) {
    // 卡片圆角半径（建议 22~28）
    const double R = 24.0;

    // 用于上边缘高光的亮色版主题色
    final lightTheme = Color.lerp(themeColor, Colors.white, 0.5)!;

    return Container(
      // ========================================
      // 外层容器：负责所有投影
      // ========================================
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R),
        boxShadow: [
          // 第 1 层：主色调彩色投影 -- 核心立体感来源
          // 颜色跟角色主题色一致，模拟"有色玻璃透光打在桌面上"
          BoxShadow(
            color: themeColor.withOpacity(shadowAlpha),
            blurRadius: shadowBlur,
            spreadRadius: -3,
            offset: Offset(0, shadowOffY),
          ),
          // 第 2 层：更深更远的投影 -- 增加投影层次和深度感
          BoxShadow(
            color: themeColor.withOpacity(shadowAlpha * 0.35),
            blurRadius: shadowBlur * 1.6,
            spreadRadius: -6,
            offset: Offset(0, shadowOffY * 1.6),
          ),
          // 第 3 层：环境光散射 -- 卡片周围极淡的主题色光晕
          BoxShadow(
            color: themeColor.withOpacity(0.07),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R),
        child: BackdropFilter(
          // 毛玻璃模糊度（建议 8~14）
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: CustomPaint(
            // ========================================
            // 玻璃体绘制 -- 光影、渐变、高光、边框
            // ========================================
            painter: _CardGlassPainter(
              themeColor: themeColor,
              lightTheme: lightTheme,
              borderAlpha: borderAlpha,
              glassAlpha: glassAlpha,
              R: R,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  _buildAvatar(themeColor),
                  const SizedBox(width: 16),
                  Expanded(child: _buildInfo(themeColor)),
                  _buildArrow(themeColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------
  // 头像区域
  // ----------------------------------------
  Widget _buildAvatar(Color themeColor) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              // 头像的彩色投影
              BoxShadow(
                color: themeColor.withOpacity(0.35),
                blurRadius: 14,
                spreadRadius: -3,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.75),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _characterAvatarPath != null
                ? Image.file(File(_characterAvatarPath!), fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          themeColor.withOpacity(0.45),
                          themeColor.withOpacity(0.2),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(widget.character.avatar,
                          style: const TextStyle(fontSize: 26)),
                    ),
                  ),
          ),
        ),
        // 未读消息红点（有未读时才显示）
        if (_unreadCount > 0)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF1744).withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: -1,
                    offset: const Offset(0, 2),
                  ),
                ],
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
    );
  }

  // ----------------------------------------
  // 角色信息区域
  // ----------------------------------------
  Widget _buildInfo(Color themeColor) {
    return Column(
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: themeColor.withOpacity(0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: themeColor.withOpacity(0.12),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            '鬼灭之刃',
            style: TextStyle(
              fontSize: 11,
              color: themeColor.withOpacity(0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------
  // 右侧箭头
  // ----------------------------------------
  Widget _buildArrow(Color themeColor) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: themeColor.withOpacity(_isHovered ? 0.12 : 0.06),
        border: Border.all(
          color: themeColor.withOpacity(_isHovered ? 0.4 : 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.arrow_forward_ios,
        color: themeColor.withOpacity(_isHovered ? 0.8 : 0.5),
        size: 14,
      ),
    );
  }
}

// ========================================
// 玻璃卡片绘制器
// ========================================
// 绘制卡片内部的光影效果：
//   1. 上亮下暗的渐变底色 -- 模拟光照方向
//   2. 上边缘高光带 -- 模拟玻璃顶部折射反光（立体感核心）
//   3. 渐变色彩边框 -- 上方亮色、下方主题色，有色玻璃边缘质感
//   4. 最上方白色高光描边 -- 模拟直射光在上边缘的反射
class _CardGlassPainter extends CustomPainter {
  final Color themeColor;
  final Color lightTheme;
  final double borderAlpha;
  final double glassAlpha;
  final double R;

  _CardGlassPainter({
    required this.themeColor,
    required this.lightTheme,
    required this.borderAlpha,
    required this.glassAlpha,
    required this.R,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(R));

    // ---- 1. 渐变底色（上亮下暗） ----
    // 顶部接近白色，底部微带主题色调
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(255, 255, 255, glassAlpha), // 顶部亮白
            Color.fromRGBO(255, 255, 255, glassAlpha * 0.82), // 中上
            Color.lerp(Colors.white, themeColor, 0.05)! // 底部微带色
                .withOpacity(glassAlpha * 0.7),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // ---- 2. 上边缘高光带 ----
    // 在卡片上部 30% 的区域叠加一层从白到透明的渐变
    // 这使得卡片顶部看起来更亮，模拟光线直射在玻璃圆弧顶部的效果
    // 是"圆润有厚度"的关键
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.32),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.5), // 高光最亮处
            Colors.white.withOpacity(0.0), // 向下淡出
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.32)),
    );
    canvas.restore();

    // ---- 3. 彩色渐变边框 ----
    // 上方用亮色版主题色（接近白），下方用正常主题色
    // 整体呈现出"有色玻璃边缘"的质感
    // strokeWidth 控制边框粗细（建议 1.2~2.0）
    canvas.drawRRect(
      rrect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lightTheme.withOpacity(borderAlpha * 1.1), // 左上：亮色
            themeColor.withOpacity(borderAlpha * 0.5), // 中间
            themeColor.withOpacity(borderAlpha * 0.7), // 右下：深色
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // ---- 4. 上边缘白色高光描边 ----
    // 在彩色边框之上，上半弧再叠一层白色描边
    // 模拟最强的直射反光
    canvas.drawRRect(
      rrect.deflate(0.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withOpacity(0.75), // 上方最亮
            Colors.white.withOpacity(0.0), // 中部消失
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CardGlassPainter old) {
    return old.borderAlpha != borderAlpha || old.glassAlpha != glassAlpha;
  }
}
