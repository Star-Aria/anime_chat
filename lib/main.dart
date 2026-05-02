import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui; // 用于 ImageFilter.blur, 给背景光斑做真正的高斯模糊
import 'character_config.dart';
import 'chat_page.dart';
import 'proactive_message_service.dart';
import 'storage_service.dart';

// ========================================
// 窗口大小配置
// ========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 设置窗口初始参数
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600), // 窗口初始大小 (宽, 高) - 保持 4:3 比例
    minimumSize: Size(600, 450), // 窗口最小大小（不能缩小到比这更小）- 同样 4:3
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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Chat',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        fontFamily: 'FangSong', // 默认字体
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00D4AA),
          surface: Colors.white,
        ),
      ),
      home: const CharacterSelectionPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ========================================
// 番剧分组映射表
// ========================================
// 把角色 id 映射到番剧名, 首页用这个表把角色分到不同的文件夹 Tab 下。
// 新增角色时在这里补一行即可; 如果角色不在映射表里, 默认归入 "未分类"。
// key 是 Character.id (见 character_config.dart), value 是显示的番剧名。
const Map<String, String> kCharacterSeriesMap = {
  'shinobu': '鬼灭之刃',
  'muichirou': '鬼灭之刃',
  'giyu': '鬼灭之刃',
  // 以后加新角色, 在这里加映射, 比如:
  // 'maruyama_aya': 'BanG Dream',
};

// ========================================
// 番剧展示顺序 + 占位番剧
// ========================================
// 这个列表决定 Tab 从左到右的显示顺序。
// 列表里的番剧即使没有任何角色也会被显示为空 Tab (占位)。
// 不在这个列表但 kCharacterSeriesMap 里出现过的番剧会自动追加到末尾。
const List<String> kSeriesOrder = [
  '鬼灭之刃',
  'BanG Dream', // 占位 Tab, 目前没有角色, 以后加角色时自动填充
];

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
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
      });
    }
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
// 首页配色常量 (集中管理, 要调色改这里就够了)
// ========================================
// 第一层: 弥散渐变背景的三个断点颜色
const Color kBgGradientStart = Color(0xFFFFF5F8); // 左上: 淡粉
const Color kBgGradientMid = Color(0xFFF0F4FF); // 中间: 淡蓝
const Color kBgGradientEnd = Color(0xFFF5F0FF); // 右下: 淡紫

// 第一层: 渐变背景上方叠加的模糊光斑的颜色 (7 个)
// 数量多 + 每个淡一点 = 玻璃透过来能看到的色彩更丰富, 但整体基调仍然柔和
const Color kBgBlobColor1 = Color(0xFFFFB6C1); // 右上 粉
const Color kBgBlobColor2 = Color(0xFFB6E5FF); // 左下 蓝
const Color kBgBlobColor3 = Color(0xFFD4B6FF); // 中右 紫
const Color kBgBlobColor4 = Color(0xFFFFDCC0); // 右下 暖橙
const Color kBgBlobColor5 = Color(0xFFC0E5D8); // 左中 淡青
const Color kBgBlobColor6 = Color(0xFFFFD4E8); // 右下 淡粉
const Color kBgBlobColor7 = Color(0xFFD4E0FF); // 左上 淡蓝紫

// 第三层: 文件夹的底色 (淡粉)
const Color kFolderColor = Color(0xFFFDF4F4);
// 文件夹标签未选中时的文字颜色
const Color kFolderTabDim = Color(0xFFA88888);
// 文件夹标签选中时的文字颜色 + 箭头颜色
const Color kFolderAccent = Color(0xFFB85573);

// 第四层: 角色卡片的渐变色 (从左上的白到右下的极淡米)
const Color kCardGradientStart = Color(0xFFFFFFFF);
const Color kCardGradientEnd = Color(0xFFFDFBF6);

// 角色卡片阴影的色调 (暖米色, 配合淡粉底不冲突)
// 阴影用 rgba 形式, 这里定义为 Color 方便后续生成不同 alpha 的版本
const Color kCardShadowTint = Color.fromARGB(255, 190, 160, 130);

// 点击流光动效的颜色 (米色, 和卡片整体配色统一)
const Color kCardSweepColor = Color.fromARGB(140, 245, 228, 195);

// Logo 渐变色 (粉 -> 蓝紫)
const Color kLogoGradientStart = Color(0xFFFF9AAF);
const Color kLogoGradientEnd = Color(0xFF9AAFFF);

// 标题渐变色 (粉 -> 蓝)
const Color kTitleGradientStart = Color(0xFFFF6B9D);
const Color kTitleGradientEnd = Color(0xFF6B9DFF);

// ========================================
// 角色选择页面 (首页)
// ========================================
class CharacterSelectionPage extends StatefulWidget {
  const CharacterSelectionPage({super.key});

  @override
  State<CharacterSelectionPage> createState() => _CharacterSelectionPageState();
}

class _CharacterSelectionPageState extends State<CharacterSelectionPage> {
  // 是否正在收取离线主动消息（启动时 ProactiveMessageService 补发检查期间为 true）
  bool _isFetchingMessages = false;

  // 按番剧分组后的角色列表
  // key: 番剧名, value: 按最近聊天时间排序后的角色列表 (新的在前)
  Map<String, List<Character>> _groupedCharacters = {};

  // Tab 顺序 (合并 kSeriesOrder + kCharacterSeriesMap 里出现但不在 order 里的)
  List<String> _orderedSeries = [];

  // 当前选中的 Tab 索引
  int _currentTabIndex = 0;

  // 角色 id -> 最近一条聊天预览信息的缓存
  // 用一个 map 避免每次重建都重新读 SharedPreferences
  Map<String, _ChatPreview> _previewCache = {};

  @override
  void initState() {
    super.initState();
    _buildGroupingAndOrder();
    _loadAllPreviews();

    // 注册全局的离线消息收取状态回调
    // 使用一个特殊的 key '__global__' 来表示首页级别的监听，
    // 与聊天页按 characterId 注册的回调互不冲突
    ProactiveMessageService().registerFetchingCallback(
      '__global__',
      (isFetching) {
        if (mounted) {
          setState(() {
            _isFetchingMessages = isFetching;
          });
        }
        // 收取完毕后重新加载预览, 保证首页的"最近一条消息"是最新的
        if (!isFetching) {
          _loadAllPreviews();
        }
      },
    );
  }

  @override
  void dispose() {
    ProactiveMessageService().unregisterFetchingCallback('__global__');
    super.dispose();
  }

  // ----------------------------------------
  // 构建分组和 Tab 顺序
  // ----------------------------------------
  void _buildGroupingAndOrder() {
    final Map<String, List<Character>> grouped = {};

    // 先把 kSeriesOrder 里的番剧都作为空组初始化一遍
    // 这样即使某个番剧没有角色 (比如 BanG Dream 占位 Tab), 也会显示一个空 Tab
    for (final series in kSeriesOrder) {
      grouped[series] = [];
    }

    // 遍历所有角色, 根据映射表分配到对应番剧组
    for (final c in CharacterConfig.characters) {
      final series = kCharacterSeriesMap[c.id] ?? '未分类';
      grouped.putIfAbsent(series, () => []);
      grouped[series]!.add(c);
    }

    // 生成最终 Tab 顺序: kSeriesOrder 在前, 其他的按字母追加
    final List<String> order = List.from(kSeriesOrder);
    for (final series in grouped.keys) {
      if (!order.contains(series)) {
        order.add(series);
      }
    }

    _groupedCharacters = grouped;
    _orderedSeries = order;
  }

  // ----------------------------------------
  // 加载所有角色的最近一条聊天预览 + 未读数 + 最后聊天时间
  // ----------------------------------------
  // 这个方法会并发读取 StorageService 和 SharedPreferences,
  // 读完之后按 "最后一条消息时间" 对每个番剧组内的角色倒序排序 (新的在前)
  Future<void> _loadAllPreviews() async {
    final Map<String, _ChatPreview> newCache = {};
    final prefs = await SharedPreferences.getInstance();

    for (final c in CharacterConfig.characters) {
      final messages = await StorageService.loadConversation(c.id);
      final unread = prefs.getInt('unread_${c.id}') ?? 0;
      final avatarPath = prefs.getString('avatar_${c.id}');

      if (messages.isEmpty) {
        newCache[c.id] = _ChatPreview(
          lastTime: null,
          lastMessage: null,
          isFromUser: false,
          japaneseText: null,
          chineseText: null,
          unread: unread,
          avatarPath: avatarPath,
        );
      } else {
        // 取最后一条消息
        final last = messages.last;
        final isFromUser = last.role == 'user';

        String? jp;
        String? cn;
        if (isFromUser) {
          // 用户消息: 直接显示 content (没有双语)
          jp = last.content;
          cn = null;
        } else {
          // AI 消息: 格式是 "日文\n\n中文：中文翻译"
          // 按 api_service.dart line 90-91 的规则拆分
          final content = last.content;
          if (content.contains('\n\n中文：')) {
            final parts = content.split('\n\n中文：');
            jp = parts[0].trim();
            cn = parts.length > 1 ? parts[1].trim() : null;
          } else {
            // 没有中文翻译标记, 整段当日文显示
            jp = content;
            cn = null;
          }
        }

        newCache[c.id] = _ChatPreview(
          lastTime: last.timestamp,
          lastMessage: last.content,
          isFromUser: isFromUser,
          japaneseText: jp,
          chineseText: cn,
          unread: unread,
          avatarPath: avatarPath,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _previewCache = newCache;
      _sortGroupedCharactersByTime();
    });
  }

  // ----------------------------------------
  // 把每个番剧组内的角色按最近聊天时间倒序排序
  // ----------------------------------------
  // 没有聊天记录的角色放到组的末尾
  void _sortGroupedCharactersByTime() {
    _groupedCharacters.forEach((series, chars) {
      chars.sort((a, b) {
        final ta = _previewCache[a.id]?.lastTime;
        final tb = _previewCache[b.id]?.lastTime;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1; // 没聊天记录的放后面
        if (tb == null) return -1;
        return tb.compareTo(ta); // 时间新的在前
      });
    });
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
          // ============================================
          // 第一层: 弥散渐变背景
          // ============================================
          // 覆盖整个窗口, 提供柔和的粉蓝紫渐变基底
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kBgGradientStart, kBgGradientMid, kBgGradientEnd],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ============================================
          // 第一层附加: 七个模糊光斑 (blob)
          // ============================================
          // 数量多 + 每个淡, 让玻璃卡片透过后能看到丰富的色彩变化
          // 位置用像素值, 可以根据窗口大小调整
          _buildBgBlob(
            color: kBgBlobColor1,
            size: const Size(260, 340),
            top: -70,
            right: -50,
          ),
          _buildBgBlob(
            color: kBgBlobColor2,
            size: const Size(280, 360),
            bottom: 40,
            left: -70,
          ),
          _buildBgBlob(
            color: kBgBlobColor3,
            size: const Size(220, 280),
            top: 160,
            right: 140,
          ),
          _buildBgBlob(
            color: kBgBlobColor4,
            size: const Size(220, 280),
            bottom: 150,
            right: 30,
          ),
          _buildBgBlob(
            color: kBgBlobColor5,
            size: const Size(200, 260),
            top: 220,
            left: 60,
          ),
          _buildBgBlob(
            color: kBgBlobColor6,
            size: const Size(180, 230),
            bottom: 60,
            right: 200,
          ),
          _buildBgBlob(
            color: kBgBlobColor7,
            size: const Size(170, 220),
            top: 40,
            left: 180,
          ),

          // ============================================
          // 主要内容 (SafeArea 内)
          // ============================================
          SafeArea(
            child: Padding(
              // 左右 16 的外边距, 顶部 18 给 logo 留空间, 底部 16 和左右一致
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: [
                  // ========================================
                  // 顶部: logo + 标题 (居中, 紧凑)
                  // ========================================
                  _buildTopHeader(),

                  const SizedBox(height: 12),

                  // ========================================
                  // 消息收取中提示条
                  // ========================================
                  // 启动时 ProactiveMessageService 会检查并补发离线期间的主动消息，
                  // 期间在角色列表上方显示提示条，收取完毕后自动消失。
                  // 样式参考微信"消息收取中"的横条提示。
                  if (_isFetchingMessages) _buildFetchingBar(),

                  // ========================================
                  // 第二层: 波浪顶边的白色容器
                  // ========================================
                  // 用 CustomPainter 绘制顶部是波浪的白色背景
                  // 容器内部放置 Tab + 文件夹 + 角色卡片列表
                  Expanded(
                    child: _buildWaveContainer(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------
  // 构建背景模糊光斑
  // ----------------------------------------
  // 用 ImageFiltered + ImageFilter.blur 对圆形本身做真正的高斯模糊,
  // 效果相当于 CSS 的 filter: blur(60px), 得到边界完全柔和的光晕,
  // 而不是硬边圆 + 外阴影的组合。
  Widget _buildBgBlob({
    required Color color,
    required Size size,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: ImageFiltered(
          // sigmaX/sigmaY 是高斯模糊的标准差, 值越大越柔
          // 60 相当于 CSS 的 filter: blur(60px)
          // 想让光晕更发散可以增大, 想让光斑边界更清晰可以减小
          imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // opacity 稍微高一点, 因为模糊后整体会变淡
              // 可调: 0.5-0.7 之间
              color: color.withOpacity(0.55),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------
  // 顶部 Header: logo + 渐变标题
  // ----------------------------------------
  Widget _buildTopHeader() {
    return Column(
      children: [
        // Logo: 52x52 的圆角方块, 粉蓝渐变, 微倾斜
        Transform.rotate(
          angle: -5 * math.pi / 180, // 逆时针倾斜 5 度
          child: Container(
            width: 52, // Logo 大小 - 可调
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kLogoGradientStart, kLogoGradientEnd],
              ),
              boxShadow: [
                BoxShadow(
                  color: kLogoGradientStart.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 26, // Logo 图标大小 - 可调
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 标题: 用 ShaderMask 实现渐变文字
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [kTitleGradientStart, kTitleGradientEnd],
          ).createShader(bounds),
          child: const Text(
            'Anime Chat',
            style: TextStyle(
              fontSize: 22, // 标题大小 - 可调
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
              fontFamily: 'Times New Roman',
              color: Colors.white, // 这里颜色会被 ShaderMask 覆盖, 只是占位
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------
  // 消息收取中提示条（精致玻璃胶囊样式）
  // ----------------------------------------
  // 走和角色卡片一致的玻璃材质：ClipRRect + BackdropFilter + 半透明白 + 白描边，
  // 视觉上不再是一条醒目的黄色横幅，而是融入首页整体氛围的一枚小胶囊。
  // 自动水平居中、宽度自适应内容，高度固定 30px，给下方的 Expanded 波浪容器
  // 留足空间，避免角色卡片被挤压出现溢出。
  // ----------------------------------------
  // 参数总览（都在 _FetchingCapsule 里，想改样式直接改那里）：
  //   - 胶囊高度、圆角、横向内边距
  //   - 脉动圆点的颜色、直径、动画周期
  //   - 文字内容、字号、字色
  Widget _buildFetchingBar() {
    return Container(
      // 容器本身只负责上下留一点外边距，让胶囊和 logo、波浪容器之间有呼吸空间
      // 数值可调：top 控制离 logo 的距离，bottom 控制离波浪容器顶部的距离
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      alignment: Alignment.center,
      child: const _FetchingCapsule(),
    );
  }

  // ----------------------------------------
  // 第二层波浪容器 + 内部的 Tab 和文件夹
  // ----------------------------------------
  Widget _buildWaveContainer() {
    return CustomPaint(
      // 用 CustomPainter 绘制"顶部波浪 + 下方矩形"的白色背景 + 柔和投影
      painter: _WaveContainerPainter(),
      child: Padding(
        // padding-top 50: 给顶部波浪 + Tab 留出视觉空间
        //                 Tab 底部距波浪最低点约 30-38px
        // 数值越大文件夹整体越往下压, 文件夹内部高度越小
        // 要让 3 张卡片刚好塞满, 建议保持在 48-54 之间
        padding: const EdgeInsets.fromLTRB(18, 50, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ========================================
            // 第三层: 文件夹 Tab 栏
            // ========================================
            _buildFolderTabs(),

            // ========================================
            // 第三层: 文件夹本体 + 第四层: 角色卡片列表
            // ========================================
            Expanded(
              child: _buildFolderBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------
  // 文件夹 Tab 栏
  // ----------------------------------------
  // 用 Row + Stack 实现每个 Tab 两侧的向内凹陷圆弧 + 未选中和选中的高度差
  Widget _buildFolderTabs() {
    return SizedBox(
      height: 38, // Tab 栏总高度 (选中态高度) - 可调
      child: Padding(
        // 左侧 padding 28: 让最左边 Tab 的左侧凹弧有足够空间, 不超出容器
        padding: const EdgeInsets.only(left: 28, right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_orderedSeries.length, (index) {
            final series = _orderedSeries[index];
            final isActive = index == _currentTabIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 8), // Tab 间距 - 可调
              child: _FolderTab(
                label: series,
                active: isActive,
                onTap: () {
                  setState(() {
                    _currentTabIndex = index;
                  });
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  // ----------------------------------------
  // 文件夹本体 + 角色卡片列表
  // ----------------------------------------
  // 文件夹本体是淡粉色圆角矩形, 内部放角色卡片列表
  // 注意: 这里不能用 ClipRRect 或 overflow hidden, 否则卡片的外阴影会被裁成矩形
  // 解决方案: 外层用 Container 画背景, ListView 的 padding 留缓冲
  //
  // 卡片高度策略:
  // - 角色数 <= kVisibleCardCount (默认 3): 卡片均分可见区域高度, 不滚动
  // - 角色数 > kVisibleCardCount: 每张卡片固定高度 (按 3 张时的高度), 可滚动
  Widget _buildFolderBody() {
    final currentSeries =
        _orderedSeries.isEmpty ? null : _orderedSeries[_currentTabIndex];
    final chars = currentSeries == null
        ? <Character>[]
        : _groupedCharacters[currentSeries] ?? [];

    return Container(
      decoration: BoxDecoration(
        // folder-body 改成半透明的淡粉, 让第一层的背景光斑能透过来
        // 卡片玻璃折射的就是这个透过来的色彩
        // 如果这里用实色, 卡片背后就只有纯色, 玻璃效果再强也看不出来
        // alpha 可调范围 0.4~0.7, 越小越透 (背景越显眼), 越大越实 (玻璃效果越弱)
        color: kFolderColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      // 不要 clipBehavior! 否则阴影会被裁成大矩形
      child: chars.isEmpty
          ? _buildEmptyState(currentSeries ?? '')
          : LayoutBuilder(
              builder: (context, constraints) {
                // folder-body 的可用内部区域
                final totalHeight = constraints.maxHeight;

                // 列表内边距: 上下 14 + 左右 12 留出缓冲避免阴影被裁
                const double listPadTop = 14;
                const double listPadBottom = 14;
                const double listPadLeft = 12;
                const double listPadRight = 12;

                // 卡片之间的间距
                const double cardGap = 14;

                // 固定容纳卡片数: 高度按这个值算出来, 之后不再随实际角色数变化
                // 可调: 改成 4 就让卡片更矮, 文件夹能显示更多卡片
                const int kVisibleCardCount = 3;

                // 卡片的目标高度 = (总高 - 上下 padding - (固定容纳数 - 1) * 间距) / 固定容纳数
                // 不论当前实际有几张卡片, 高度都按 kVisibleCardCount 张时的计算结果固定
                // 所以: 角色少 -> 文件夹底部留白; 角色多 -> 可以滚动, 每张仍是这个高度
                final double cardHeight = (totalHeight -
                        listPadTop -
                        listPadBottom -
                        (kVisibleCardCount - 1) * cardGap) /
                    kVisibleCardCount;

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    listPadLeft,
                    listPadTop,
                    listPadRight,
                    listPadBottom,
                  ),
                  itemCount: chars.length,
                  // ----------------------------------------
                  // 滚动策略
                  // ----------------------------------------
                  // 统一使用 BouncingScrollPhysics，任何情况下都允许滚动：
                  // - 正常情况（空间充足）：cardHeight 已经把列表高度填满，
                  //   此时 ListView 内容高度 == 可见高度，用户怎么滑都不会动，视觉上和"禁止滚动"一致
                  // - 收取提示出现时：可用高度减少，卡片底部可能被裁一点，
                  //   这时列表自然进入"可滚动"状态，用户向下滑就能把被裁的部分拉上来
                  // - 角色数超过 kVisibleCardCount：本来就需要滚动，和原逻辑一致
                  // 这样无论高度怎么变，都不会再抛 RenderFlex 溢出异常
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final character = chars[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        // 最后一张卡片去掉下边距, 其他卡片之间间隔 cardGap
                        bottom: index == chars.length - 1 ? 0 : cardGap,
                      ),
                      child: SizedBox(
                        height: cardHeight,
                        child: _CharacterCard(
                          character: character,
                          preview: _previewCache[character.id],
                          onTap: () async {
                            // 点击卡片 -> 进入聊天页面
                            // 卡片内部会播放流光动效, 动效结束后再 push 新页面
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChatPage(character: character),
                              ),
                            );
                            // 从聊天页返回后刷新预览 (最近消息/未读数都可能变了)
                            _loadAllPreviews();
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  // ----------------------------------------
  // 空状态 (文件夹里没有角色)
  // ----------------------------------------
  Widget _buildEmptyState(String series) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 48,
            color: kFolderAccent.withOpacity(0.3),
          ),
          const SizedBox(height: 8),
          Text(
            '$series 暂无角色',
            style: TextStyle(
              fontSize: 13,
              color: kFolderAccent.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================================
// 聊天预览数据结构
// ========================================
// 用来缓存每个角色的"最近一条消息" + "未读数" + "自定义头像路径"
class _ChatPreview {
  final DateTime? lastTime; // 最后一条消息的时间, 没聊过就是 null
  final String? lastMessage; // 消息原文 (可能是带 "\n\n中文：" 的完整字符串)
  final bool isFromUser; // 最后一条是否是用户发的
  final String? japaneseText; // 提取出的日文部分 (用户消息放这里, AI 消息的日文部分也放这里)
  final String? chineseText; // 中文翻译 (仅 AI 消息有)
  final int unread; // 未读数
  final String? avatarPath; // 用户自定义头像的本地路径

  _ChatPreview({
    required this.lastTime,
    required this.lastMessage,
    required this.isFromUser,
    required this.japaneseText,
    required this.chineseText,
    required this.unread,
    required this.avatarPath,
  });
}

// ========================================
// CustomPainter: 绘制第二层容器 (顶部波浪 + 下方白色矩形 + 柔和投影)
// ========================================
// 波浪的起伏通过三次贝塞尔曲线控制, y 值越小越靠上
// 想调整波浪形状, 修改 cubicTo 里的控制点 y 值即可
class _WaveContainerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 构造容器形状路径: 顶部是波浪, 下方是直角矩形, 左右和底边圆角
    final path = Path();

    // 波浪高度基准 (y=0 是容器顶部)
    // waveBaseY 越小, 波浪整体越靠上; 越大, 波浪整体越往下压
    // 可调: 12-20 之间效果自然
    const double waveBaseY = 14;

    // 波浪的起伏幅度 (控制点上下偏移量)
    // 可调: 8-16 之间, 越大波浪越明显
    const double waveAmp = 14;

    // 左右底部的圆角半径
    const double bottomRadius = 22;

    // 起点: 左上 (x=0, y=waveBaseY)
    path.moveTo(0, waveBaseY);

    // 三段三次贝塞尔曲线, 每段覆盖宽度的 1/3
    // 每段控制点的 y 值在 waveBaseY ± waveAmp 之间交替, 形成山峰-山谷-山峰的起伏
    final w = size.width;
    path.cubicTo(
      w * 0.1, waveBaseY - waveAmp, // 控制点 1
      w * 0.2, waveBaseY + waveAmp, // 控制点 2
      w * 0.33, waveBaseY, // 终点
    );
    path.cubicTo(
      w * 0.45,
      waveBaseY - waveAmp,
      w * 0.55,
      waveBaseY + waveAmp,
      w * 0.67,
      waveBaseY - waveAmp * 0.5,
    );
    path.cubicTo(
      w * 0.8,
      waveBaseY - waveAmp * 1.5,
      w * 0.9,
      waveBaseY + waveAmp * 0.8,
      w,
      waveBaseY - waveAmp * 0.5,
    );

    // 右侧垂直线下来到底部圆角起点
    path.lineTo(w, size.height - bottomRadius);
    // 右下圆角
    path.quadraticBezierTo(w, size.height, w - bottomRadius, size.height);
    // 底边
    path.lineTo(bottomRadius, size.height);
    // 左下圆角
    path.quadraticBezierTo(0, size.height, 0, size.height - bottomRadius);
    // 左侧垂直线回到起点
    path.lineTo(0, waveBaseY);
    path.close();

    // 先画两层柔和的投影, 营造波浪上方的层次感
    // 第一层: 大而散的深投影 (远距离, 柔光)
    // 第二层: 近距离细投影 (贴近波浪边缘, 定义形状)
    // 这两层叠加, 让波浪"浮在"渐变背景之上

    // 大柔影: sigma 20 是 blur 半径, alpha 80 让阴影颜色明显更深
    final bigShadowPaint = Paint()
      ..color = const Color.fromARGB(80, 150, 110, 180)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    // 向下偏移 14, 远阴影离波浪主体更远, 营造"飘起来"的感觉
    canvas.save();
    canvas.translate(0, 14);
    canvas.drawPath(path, bigShadowPaint);
    canvas.restore();

    // 小近影: sigma 8, 贴紧波浪边缘, 加强轮廓
    final closeShadowPaint = Paint()
      ..color = const Color.fromARGB(60, 150, 110, 180)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.save();
    canvas.translate(0, 4);
    canvas.drawPath(path, closeShadowPaint);
    canvas.restore();

    // 再画白色主体 (半透明, 让背景光斑透过来)
    // alpha 0.7: 比实色白淡, 让光斑透出来形成色彩变化, 又不会完全看不清容器形状
    // 可调范围 0.55~0.85, 越小容器越透 (玻璃卡片折射的色彩越丰富)
    final fillPaint = Paint()..color = Colors.white.withOpacity(0.7);
    canvas.drawPath(path, fillPaint);

    // 最后在波浪顶边画一条淡淡的高光描边, 让波浪更立体
    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // 只描绘顶部波浪那段, 不描绘底部圆角矩形
    final topWavePath = Path()..moveTo(0, waveBaseY);
    topWavePath.cubicTo(
      w * 0.1,
      waveBaseY - waveAmp,
      w * 0.2,
      waveBaseY + waveAmp,
      w * 0.33,
      waveBaseY,
    );
    topWavePath.cubicTo(
      w * 0.45,
      waveBaseY - waveAmp,
      w * 0.55,
      waveBaseY + waveAmp,
      w * 0.67,
      waveBaseY - waveAmp * 0.5,
    );
    topWavePath.cubicTo(
      w * 0.8,
      waveBaseY - waveAmp * 1.5,
      w * 0.9,
      waveBaseY + waveAmp * 0.8,
      w,
      waveBaseY - waveAmp * 0.5,
    );
    canvas.drawPath(topWavePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ========================================
// 文件夹 Tab 组件
// ========================================
// 一个 Tab 分三层:
// 1. 主体: 淡粉色圆角矩形 (上半圆角, 底边和 folder-body 无缝衔接)
// 2. 左侧向内凹陷圆弧 (伪元素, 用 CustomPainter 画)
// 3. 右侧向内凹陷圆弧
// Tab 未选中时用更低的透明度 + 更矮的高度, 选中时变高变清晰
class _FolderTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FolderTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 未选中的 Tab 高度更矮, 透明度更低
    final double height = active ? 38 : 32;
    final double opacity = active ? 1.0 : 0.55;
    final Color textColor = active ? kFolderAccent : kFolderTabDim;
    final FontWeight fontWeight = active ? FontWeight.w600 : FontWeight.w500;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: opacity,
        // 用 Stack 把 Tab 主体 + 两侧凹弧叠起来
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Tab 主体
            Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: const BoxDecoration(
                color: kFolderColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13, // Tab 文字大小 - 可调
                  fontWeight: fontWeight,
                  color: textColor,
                ),
              ),
            ),
            // 左侧凹弧: 定位在 Tab 左外侧, 用 CustomPainter 画一段"向内凹陷的圆弧"
            Positioned(
              left: -14,
              bottom: 0,
              child: CustomPaint(
                size: const Size(14, 14),
                painter: _TabCornerPainter(isLeft: true, color: kFolderColor),
              ),
            ),
            // 右侧凹弧
            Positioned(
              right: -14,
              bottom: 0,
              child: CustomPaint(
                size: const Size(14, 14),
                painter: _TabCornerPainter(isLeft: false, color: kFolderColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// Tab 凹弧 CustomPainter
// ========================================
// 在一个 14x14 的方块里画"向内凹陷的圆弧"
// 原理: 方块整体填淡粉色, 然后在方块的外侧角上挖掉一个 14px 的圆
// isLeft = true 时挖左上角, 得到 Tab 左侧那段向内凹陷的弧
// isLeft = false 时挖右上角, 得到 Tab 右侧那段
class _TabCornerPainter extends CustomPainter {
  final bool isLeft;
  final Color color;

  _TabCornerPainter({required this.isLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    // 画方块, 然后用 Path.combine 的 difference 模式挖掉外角的圆
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rectPath = Path()..addRect(rect);

    // 圆的圆心在方块的"外上角":
    //   - 左凹弧: 圆心在方块左上 (0, 0)
    //   - 右凹弧: 圆心在方块右上 (width, 0)
    final Offset circleCenter =
        isLeft ? const Offset(0, 0) : Offset(size.width, 0);
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: size.width));

    // 方块减去圆, 剩下的就是"向内凹的圆弧形状"
    final resultPath =
        Path.combine(PathOperation.difference, rectPath, circlePath);
    canvas.drawPath(resultPath, paint);
  }

  @override
  bool shouldRepaint(covariant _TabCornerPainter oldDelegate) {
    return oldDelegate.isLeft != isLeft || oldDelegate.color != color;
  }
}

// ========================================
// 角色卡片组件 (磨砂陶瓷浮雕效果 + 点击流光动效)
// ========================================
// 视觉要点:
// 1. 背景: 从左上白到右下淡米的 135° 线性渐变
// 2. 外阴影: 两层柔和投影 (悬浮感)
// 3. 内光: 顶部细高光线 + 底部暗影 (厚度感)
// 4. 点击动效: 一束米色流光从左到右扫过 (AnimationController 驱动)
// 5. 按下时卡片微微下沉, 释放后弹起
class _CharacterCard extends StatefulWidget {
  final Character character;
  final _ChatPreview? preview;
  final VoidCallback onTap;

  const _CharacterCard({
    required this.character,
    required this.preview,
    required this.onTap,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard>
    with SingleTickerProviderStateMixin {
  // 流光动画: 0.0 时光在卡片左侧外, 1.0 时光扫到右侧外
  late final AnimationController _sweepController;
  late final Animation<double> _sweepAnimation;

  // hover 状态 (鼠标悬停时卡片上浮)
  bool _hovering = false;

  // 按下状态 (轻微下沉反馈)
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      // 流光动画时长 - 可调, 和 ease-out 曲线配合效果最佳
    );
    _sweepAnimation = CurvedAnimation(
      parent: _sweepController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  void _handleTap() async {
    // 先完整播放流光动效, 动效结束后再 push 新页面
    // 这样用户看到的体验是"点击 -> 流光完整扫过 -> 进入聊天页"
    // 不再用固定延迟 + forward, 而是直接 await forward(), 等动画走完
    await _sweepController.forward(from: 0.0);
    if (!mounted) return;
    widget.onTap();
    // 从聊天页返回后, 重置流光动画到初始状态
    _sweepController.value = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          // hover 时向上浮 2px, 按下时向下沉 1px (只位移, 不改阴影)
          transform: Matrix4.translationValues(
            0,
            _pressed ? 1 : (_hovering ? -2 : 0),
            0,
          ),
          // ========================================
          // 玻璃卡片核心: ClipRRect + BackdropFilter + 半透明白
          // ========================================
          // 这个结构对标 character_settings_page.dart 里的 _buildCard 写法:
          //   ClipRRect -> BackdropFilter -> Container(半透明白 + 白描边 + 淡阴影)
          // 没有 BackdropFilter 就没有真正的"模糊背景"效果, 只是一张半透明的贴纸。
          //
          // 这里额外包了一层 DecoratedBox 提供极淡的外阴影 (保持轻盈),
          // 内部 ClipRRect 负责裁剪圆角, BackdropFilter 对卡片背后的内容做高斯模糊,
          // 最内层的 Container 用半透明白 + 白描边画出玻璃本体。
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // 极淡外阴影: 和设置页一致 (black alpha 0.05, blur 10, offset 4)
              // 这里 hover 时略微加深一点点, 不是陶瓷那种大阴影
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_hovering ? 0.08 : 0.05),
                  blurRadius: _hovering ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                // 高斯模糊背后的内容 - 这才是"玻璃"的关键
                // sigmaX/sigmaY = 20 和设置页的 GLASS_BLUR_SIGMA 一致
                // 想让玻璃更模糊就加大, 想看得更清楚就减小
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    // 半透明白: alpha 0.38 和设置页 GLASS_BG_OPACITY 一致
                    // 数值越小越透 (背景颜色越鲜明), 越大越白实
                    // 可调范围 0.25~0.55
                    color: Colors.white.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(18),
                    // 玻璃细描边: 白色 alpha 0.5, 宽 1.5px
                    // 这是玻璃"有边缘"的关键, 去掉就像纯雾一样没形状
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // 卡片主体内容 (头像 + 文字 + 箭头)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: _buildCardContent(),
                      ),
                      // 流光层: 用 AnimatedBuilder 驱动 clipPath 从左到右展开
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _sweepAnimation,
                            builder: (context, child) {
                              // 只在动画进行时画流光, 省点性能
                              if (_sweepController.value == 0) {
                                return const SizedBox.shrink();
                              }
                              return ClipRect(
                                clipper: _SweepClipper(
                                    progress: _sweepAnimation.value),
                                // 纯米色填充, 不用渐变
                                // 之前用 transparent -> 米色 -> transparent 的线性渐变,
                                // 但 Colors.transparent 在 Flutter 里是 alpha=0 的黑色,
                                // 插值过程会经过半透明黑, 导致流光两侧出现灰边。
                                // 现在直接用 kCardSweepColor 实填充, 视觉干净
                                child: Container(
                                  color: kCardSweepColor,
                                ),
                              );
                            },
                          ),
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
    );
  }

  // ----------------------------------------
  // 卡片内容: 左头像 + 中文字 + 右时间/箭头
  // ----------------------------------------
  Widget _buildCardContent() {
    final character = widget.character;
    final preview = widget.preview;
    final characterColor = Color(int.parse('0xFF${character.color}'));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 头像 + 未读红点 (未读数显示在头像右上角)
        _buildAvatar(character, characterColor, preview),
        const SizedBox(width: 13),
        // 中间: 角色名 + 最近一条消息 (双语)
        Expanded(
          child: _buildInfoColumn(preview),
        ),
        const SizedBox(width: 8),
        // 右侧: 时间 + 箭头
        _buildRightColumn(preview),
      ],
    );
  }

  // ----------------------------------------
  // 头像区域
  // ----------------------------------------
  Widget _buildAvatar(Character character, Color color, _ChatPreview? preview) {
    final avatarPath = preview?.avatarPath;
    final unread = preview?.unread ?? 0;

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 头像主体 (46x46, 居中)
          Container(
            width: 46, // 头像大小 - 可调
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: avatarPath == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, color.withOpacity(0.7)],
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: kCardShadowTint.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: avatarPath != null
                  ? Image.file(
                      File(avatarPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarFallback(
                        character,
                        color,
                      ),
                    )
                  : _buildAvatarFallback(character, color),
            ),
          ),
          // 未读红点 (仅未读数 > 0 时显示)
          if (unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF6B88), Color(0xFFE85970)],
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE85970).withOpacity(0.45),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 头像兜底: 没有自定义头像时显示角色 emoji/字符 (character.avatar 字段)
  Widget _buildAvatarFallback(Character character, Color color) {
    return Center(
      child: Text(
        character.avatar,
        style: const TextStyle(fontSize: 22),
      ),
    );
  }

  // ----------------------------------------
  // 中间信息列: 角色名 + 最近聊天内容
  // ----------------------------------------
  // 说明：外层用 ClipRect 包裹，保证即使卡片整体被挤压到比内容更矮，
  // 超出的底部文字也会被优雅地裁掉，而不是抛出 "RenderFlex overflowed" 异常。
  // 内部 Column 使用 mainAxisSize.min，让列表自身不强制占满可用高度，
  // 配合外层 Center 做垂直居中，视觉上保持和原来一致。
  Widget _buildInfoColumn(_ChatPreview? preview) {
    // 没有聊天记录时的提示
    if (preview == null || preview.lastTime == null) {
      return ClipRect(
        child: OverflowBox(
          // alignment 控制内容在可用空间不足时被裁掉的方向
          // Alignment.center: 上下对称裁剪（中间信息保留，上下各裁一点）
          // Alignment.topCenter: 只裁底部（底部文字会先被裁掉，适合从上往下阅读）
          alignment: Alignment.topCenter,
          // 允许 child 在垂直方向使用任意高度，超出部分交给外层 ClipRect 裁剪
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.character.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2D3142),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                widget.character.nameJp,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFAAAAAA),
                  fontFamily: 'Times New Roman',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    // 判断是否是 AI 发的 + 有中文翻译 -> 显示双语 (日文 + 中文小字)
    // 用户发的或 AI 只有日文 -> 单行
    final bool showBilingual = !preview.isFromUser &&
        preview.chineseText != null &&
        preview.chineseText!.isNotEmpty;

    return ClipRect(
      child: OverflowBox(
        // 同上: 裁剪时保留顶部（角色名），溢出时从底部裁
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 角色名
            Text(
              widget.character.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2D3142),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // 日文一行 (如果是用户消息, 这里显示的是用户的 content)
            Text(
              preview.japaneseText ?? '',
              style: TextStyle(
                fontSize: 12,
                color: showBilingual
                    ? const Color(0xFF6A5F85)
                    : const Color(0xFF888888),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 中文翻译 (仅 AI 消息且有翻译时显示)
            if (showBilingual) ...[
              const SizedBox(height: 1),
              Text(
                preview.chineseText!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA098B0),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------
  // 右侧列: 时间 + 箭头
  // ----------------------------------------
  Widget _buildRightColumn(_ChatPreview? preview) {
    final timeText = _formatTime(preview?.lastTime);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (timeText.isNotEmpty) ...[
          Text(
            timeText,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFFA098B0),
            ),
          ),
          const SizedBox(height: 6),
        ],
        // 右侧箭头 (SVG chevron 效果, Flutter 用 Icons.chevron_right)
        const Icon(
          Icons.chevron_right,
          size: 20, // 箭头大小 - 可调
          color: kFolderAccent,
        ),
      ],
    );
  }

  // ----------------------------------------
  // 时间格式化
  // ----------------------------------------
  // 根据时间和现在的差距, 显示不同粒度的文字:
  // - 1 分钟内: "刚刚"
  // - 1 小时内: "N 分钟前"
  // - 今天: "HH:mm"
  // - 昨天: "昨天"
  // - 一周内: "星期X"
  // - 更久: "MM-DD"
  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';

    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(time.year, time.month, time.day);
    final daysDiff = today.difference(msgDay).inDays;

    if (daysDiff == 0) {
      // 今天: HH:mm
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (daysDiff == 1) return '昨天';
    if (daysDiff < 7) {
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      return '星期${weekdays[time.weekday - 1]}';
    }
    // 更早: MM-DD
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}

// ========================================
// 消息收取中 - 胶囊组件
// ========================================
// 和角色卡片使用同一套玻璃材质语言（ClipRRect + BackdropFilter + 半透明白 + 白描边），
// 在左侧加一个柔和脉动的小圆点代替传统的旋转 spinner，视觉上更克制也更有品质感。
// 组件为自适应宽度：宽度由文字内容决定，整条胶囊会在父容器中居中显示。
//
// 可调参数一览（想改观感都在这里）：
// - kCapsuleHeight      胶囊高度
// - kCapsuleRadius      胶囊圆角（设成高度一半就是纯胶囊形）
// - kCapsulePaddingH    胶囊内部左右 padding
// - kDotSize            左侧脉动圆点直径
// - kDotColor           圆点颜色（默认柔和粉紫，和 logo 呼应）
// - kDotPulseDuration   圆点一次脉动的时长
// - kCapsuleText        文字内容
// - kCapsuleTextSize    文字字号
// - kCapsuleTextColor   文字颜色
// - kCapsuleBlurSigma   玻璃高斯模糊强度（和角色卡片保持一致）
// - kCapsuleBgOpacity   半透明白的透明度（越小越透）
class _FetchingCapsule extends StatefulWidget {
  const _FetchingCapsule();

  @override
  State<_FetchingCapsule> createState() => _FetchingCapsuleState();
}

class _FetchingCapsuleState extends State<_FetchingCapsule>
    with SingleTickerProviderStateMixin {
  // 整条胶囊的几何参数
  static const double kCapsuleHeight = 30; // 胶囊高度 - 可调
  static const double kCapsuleRadius = 15; // 圆角半径（= 高度一半 = 纯胶囊形）
  static const double kCapsulePaddingH = 16; // 胶囊内部左右 padding - 可调

  // 左侧脉动圆点参数
  static const double kDotSize = 7; // 圆点直径 - 可调
  static const Color kDotColor =
      Color(0xFFB85573); // 圆点颜色 - 可调（默认和 folder accent 呼应）
  static const Duration kDotPulseDuration =
      Duration(milliseconds: 1100); // 圆点一次脉动的时长 - 可调

  // 文字参数
  static const String kCapsuleText = '消息收取中'; // 文字内容 - 可调
  static const double kCapsuleTextSize = 12; // 文字字号 - 可调
  static const Color kCapsuleTextColor = Color(0xFF6A5F85); // 文字颜色 - 可调

  // 玻璃材质参数
  static const double kCapsuleBlurSigma = 20; // 高斯模糊强度 - 可调，和角色卡片保持一致
  static const double kCapsuleBgOpacity = 0.55; // 半透明白透明度 - 可调（越小越透）

  // 脉动动画控制器（循环播放，呼吸感由曲线决定）
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: kDotPulseDuration,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCapsuleRadius),
      child: BackdropFilter(
        // 对胶囊背后的渐变 + 光斑做高斯模糊，形成玻璃感
        filter: ui.ImageFilter.blur(
          sigmaX: kCapsuleBlurSigma,
          sigmaY: kCapsuleBlurSigma,
        ),
        child: Container(
          height: kCapsuleHeight,
          padding: const EdgeInsets.symmetric(horizontal: kCapsulePaddingH),
          decoration: BoxDecoration(
            // 半透明白胶囊底色
            color: Colors.white.withOpacity(kCapsuleBgOpacity),
            borderRadius: BorderRadius.circular(kCapsuleRadius),
            // 白描边: 和角色卡片描边保持一致，让玻璃感更统一
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1,
            ),
            // 极淡外阴影: 让胶囊"浮在"背景上，不要让它和背景糊在一起
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min, // 宽度自适应内容，不占满父容器
            children: [
              // 左侧脉动圆点: 替代传统 spinner，更精致
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  // 脉动: 圆点透明度在 0.35 ~ 1.0 之间来回变化
                  // 想更明显就把下限调低, 想更温和就把下限调高
                  final double opacity = 0.35 + 0.65 * _pulseController.value;
                  return Container(
                    width: kDotSize,
                    height: kDotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kDotColor.withOpacity(opacity),
                      // 圆点外发出一圈淡光晕, 和它的透明度联动
                      boxShadow: [
                        BoxShadow(
                          color: kDotColor.withOpacity(opacity * 0.5),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // 文字: 去掉了省略号, 脉动圆点已经传达了"进行中"的含义
              const Text(
                kCapsuleText,
                style: TextStyle(
                  fontSize: kCapsuleTextSize,
                  color: kCapsuleTextColor,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
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
// 流光动效裁剪器
// ========================================
// 根据 progress (0.0 -> 1.0) 从左到右逐渐露出卡片区域
// progress = 0: 完全隐藏 (裁剪掉整个区域)
// progress = 1: 完全露出 (裁剪矩形和原矩形一样大)
class _SweepClipper extends CustomClipper<Rect> {
  final double progress;

  _SweepClipper({required this.progress});

  @override
  Rect getClip(Size size) {
    // 让流光宽度比实际 progress 稍宽一点, 末尾能看到完整的淡出
    // progress = 0 时, clipRect 宽度为 0, 完全看不到流光
    // progress = 1 时, clipRect 宽度为 size.width, 完全显示
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(covariant _SweepClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
