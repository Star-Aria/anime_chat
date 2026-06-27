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
  // 以后加新角色, 在这里加映射
  'sakiko': 'BanG Dream',
  'andy': '未分类',
};

// ========================================
// 番剧展示顺序 + 占位番剧
// ========================================
// 这个列表决定 Tab 从左到右的显示顺序。
// 列表里的番剧即使没有任何角色也会被显示为空 Tab (占位)。
// 不在这个列表但 kCharacterSeriesMap 里出现过的番剧会自动追加到末尾。
const List<String> kSeriesOrder = [
  '鬼灭之刃',
  'BanG Dream',
  '未分类',
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
// 当前方案: 顶部头图 + 白色波浪容器 + 蓝粉渐变文件夹
// 视觉语言:
//   - 顶部用一张实景图片做"头图 banner", 给画面提供天然的色彩锚点
//   - 中间白色波浪容器贴齐屏幕左右下三边, 作为色彩中的呼吸留白
//   - 文件夹用蓝→粉渐变, 取自头图天空蓝 + 樱花粉, 和头图色彩呼应
//   - 文件夹边缘有蓝→紫→粉的发光描边, 强调"玻璃感"
//
// 想换头图配色: 改 kFolderGradStart / kFolderGradEnd / kEdgeGlow* 这几组,
// 让文件夹和发光描边的色彩匹配新头图。

// ----------------------------------------
// 头图相关
// ----------------------------------------
// 头图本地路径 (用户可以替换成自己的图片)
// Windows 路径需要原样写入, Flutter 会用 File 读取
const String kHeroImagePath = r'C:\anime_chat\头图.jpg';

// ----------------------------------------
// 头图高度: 渲染高度 vs 可见高度 (解耦)
// ----------------------------------------
// 之前 kHeroImageHeight 同时控制 "头图渲染多高" 和 "波浪容器从哪开始",
// 想让头图变高就会压缩下方内容。现在拆成两个独立变量:
//
//   kHeroImageHeight:    头图渲染时占据多高 (越大头图本身越大, 能展示更多原图内容)
//   kHeroVisibleHeight:  头图实际可见到的底部 (= 波浪容器顶部位置)
//
// 头图区域 = 屏幕 0 ~ kHeroImageHeight, 但 kHeroVisibleHeight 以下会被
// 波浪容器遮挡, 所以用户实际看到的头图 = 0 ~ kHeroVisibleHeight (再加波浪起伏)。
//
// 调整方式:
//   - 想让头图区域更大 (展示更多原图): 增大 kHeroImageHeight, 不影响下方布局
//   - 想让波浪容器从更高位置开始: 减小 kHeroVisibleHeight (但会压缩下方)
//   - 想让波浪容器从更低位置开始: 增大 kHeroVisibleHeight
const double kHeroImageHeight = 230.0; // 头图渲染高度 (越大越能展现更多原图)
const double kHeroVisibleHeight = 145.0; // 波浪容器顶部位置 (= 头图实际可见底部)

// ----------------------------------------
// 头图显示位置 (BoxFit.cover 模式下, 图片比头图区域大时显示哪一部分)
// ----------------------------------------
// 头图区域是宽屏 800x180 (近 4.4:1), 而你的头图原图通常是竖向的,
// 所以图片会被裁剪。alignment 决定保留哪部分:
//   - Alignment.topCenter      显示图片顶部 (适合天空主题, 保留蓝天云朵)
//   - Alignment.center         显示图片中部 (默认, 适合主体居中的图)
//   - Alignment.bottomCenter   显示图片底部 (适合花树/前景主题)
//   - Alignment(0, 0.3)        手动指定 y 偏移 (-1=最顶, 0=居中, 1=最底)
// 想看不同区域: 改这个常量然后热重载即可
const Alignment kHeroImageAlignment = Alignment(0, 0.2);

// 头图上方覆盖一层白色蒙版, 让 logo / 标题文字浮在上面更清晰
// 数值 = (顶部 alpha, 底部 alpha), 顶部更透 (露出更多原图), 底部更白 (柔化波浪衔接)
const double kHeroOverlayTopAlpha = 0.05;
const double kHeroOverlayBottomAlpha = 0.20;

// 波浪容器向上重叠头图的距离 (= 头图渲染高度 - 头图可见高度)
// 这是个派生值, 不再独立调整 — 想改头图可见区或渲染区, 改上面的两个常量。
// 保留这个常量是为了让旧代码 (注释 / painter 内部计算) 仍能直接引用,
// 不必到处替换成减法表达式。
const double kWaveOverlap = kHeroImageHeight - kHeroVisibleHeight;

// ----------------------------------------
// 文件夹 + 选中 Tab 的渐变色
// ----------------------------------------
// 蓝 → 粉 双色渐变 (左上 -> 右下), 跨度大、色相对比明显
// kFolderGradStart 同时作为选中 Tab 的填充色 (实色), 三处 (文件夹左上 + Tab 主体
// + Tab 凹弧) 永远同色, 视觉上 "Tab 是从文件夹拉出的一角"
const Color kFolderGradStart = Color(0xFF5BA8DC); // 头图天空蓝
const Color kFolderGradEnd = Color(0xFFFFD4E5); // 樱花粉

// 兼容老代码: kFolderColor = 渐变起点, 单色场景使用 (Tab 主体 / Tab 凹弧)
const Color kFolderColor = kFolderGradStart;

// 文件夹标签未选中时的文字颜色 (淡蓝灰, 在浅色头图下方区域不抢戏)
const Color kFolderTabDim = Color(0xFF7AA0BD);

// 文件夹标签选中时的文字颜色 + 箭头颜色
// 选中 Tab 是蓝色实色, 文字用白色更醒目
const Color kFolderAccent = Color(0xFFFFFFFF);

// ----------------------------------------
// 文件夹边缘发光描边 (蓝 -> 紫 -> 粉 横向三段渐变)
// ----------------------------------------
// 用于文件夹四周的发光边, 类似 macOS / Vision Pro 那种玻璃外光
const Color kEdgeGlowStart = Color(0xFF5BA8DC); // 蓝 (= 文件夹起点)
const Color kEdgeGlowMid = Color(0xFFC8B5E5); // 中段紫
const Color kEdgeGlowEnd = Color(0xFFFFB8D0); // 粉 (≈ 文件夹终点)

// ----------------------------------------
// 角色卡片
// ----------------------------------------
// 卡片本身保持纯白玻璃质感, 渐变常量备用 (当前未使用 BackdropFilter 内已自带)
const Color kCardGradientStart = Color(0xFFFFFFFF);
const Color kCardGradientEnd = Color(0xFFFAFBFC);

// 角色卡片阴影色调 (冷调海蓝, 配合彩色文件夹底)
// 阴影实际使用时 alpha 较低 (0.05~0.10)
const Color kCardShadowTint = Color(0xFF5688C9);

// 注: 旧的点击流光颜色常量 kCardSweepColor 已被删除。
//     新动效用 _DiagonalShimmerPainter (倾斜白光带) +
//     边缘发光波纹 (用角色色 character.color), 不再需要单独的流光色。
//     如果以后想恢复整片色块扫光, 可在这里加回类似的常量。

// ----------------------------------------
// 波浪容器主体投影色 (冷调海蓝)
// 在 _WaveContainerPainter 里实际用 withAlpha 做半透明
// ----------------------------------------
const Color kWaveShadowTint = Color(0xFF5688C9);

// ----------------------------------------
// Logo 渐变色 (蓝 -> 粉, 呼应头图主色 + 文件夹渐变)
// ----------------------------------------
const Color kLogoGradientStart = Color(0xFF5688C9);
const Color kLogoGradientEnd = Color(0xFFE8A0C0);

// 标题文字颜色: 白色 + 深蓝阴影 (在头图上保证可读性)
// 实际渲染时, 文字本体是 kTitleColor, 投影是 kTitleShadowColor
const Color kTitleColor = Color(0xFFFFFFFF);
const Color kTitleShadowColor = Color(0xFF1A4870);

// 旧的标题渐变色保留兼容, 当前未使用
const Color kTitleGradientStart = Color(0xFFFFFFFF);
const Color kTitleGradientEnd = Color(0xFFFFFFFF);

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
          // 第一层: 屏幕底色 + 顶部头图 banner
          // ============================================
          Container(color: const Color(0xFFF5F7FA)),

          _buildHeroImage(),

          // ============================================
          // 主要内容: Logo / 标题 浮在头图上, 下方是波浪容器
          // ============================================
          Column(
            children: [
              SizedBox(height: kHeroImageHeight - kWaveOverlap),
              Expanded(
                child: _buildWaveContainer(),
              ),
            ],
          ),

          // ============================================
          // 磨砂玻璃带 + 顶部独立波浪线 (在外层 Stack, 排在波浪容器之上)
          // ============================================
          // 关键: 必须放在波浪容器之 *后* 渲染 (在 Stack children 列表里靠后),
          // 才能让 BackdropFilter 真正模糊它后方的内容 (头图 + 容器顶白)。
          //
          // 位置数学:
          //   - 波浪容器顶部 (Column 中起点) y = kHeroImageHeight - kWaveOverlap
          //   - painter 内主波浪中线 = waveBaseY = 14
          //   - 主波浪在屏幕坐标 y = kHeroImageHeight - kWaveOverlap + 14
          //
          //   - _FrostedGlassBand 高 _kBandHeight = 50
          //   - 玻璃带下波浪中线在 widget 内部 _kBandBottomY = 34
          //   - 让玻璃带下波浪 = 屏幕主波浪 (无缝衔接到容器顶白描边):
          //       Positioned.top + 34 = kHeroImageHeight - kWaveOverlap + 14
          //       Positioned.top = kHeroImageHeight - kWaveOverlap - 20
          //
          // 所以以下两个 Positioned 都用同样的 top + 高度, 只是渲染内容不同:
          //   1. 磨砂玻璃带 (上波浪 ~ 下波浪 之间的彩色磨砂内容, 厚 16px)
          //   2. 顶部独立装饰波浪线 (在上波浪上方 ~6px 处的白色细线)
          Positioned(
            top: kHeroImageHeight - kWaveOverlap - 20,
            left: 0,
            right: 0,
            height: 50, // = _kBandHeight
            child: const _FrostedGlassBand(),
          ),
          Positioned(
            top: kHeroImageHeight - kWaveOverlap - 20,
            left: 0,
            right: 0,
            height: 50, // = _kBandHeight
            child: const IgnorePointer(
              child: CustomPaint(
                painter: _TopGlassLinePainter(),
              ),
            ),
          ),

          // Logo + 标题
          // 基于头图 *可见区域* (0 ~ kHeroVisibleHeight) 定位, 而不是头图渲染高度
          // 这样头图变高 (kHeroImageHeight 变大) 时, Logo + 标题位置不会跟着下移
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kHeroVisibleHeight,
            child: Align(
              alignment: const Alignment(0, -0.35),
              child: _buildTopHeader(),
            ),
          ),

          // ============================================
          // 收取消息提示胶囊 (Stack 最上层浮层)
          // ============================================
          // 关键: 必须放在 Stack children 的最后, 才能在视觉层级上盖在
          // 磨砂玻璃带 / 装饰波浪线 / Logo / 标题之上, 避免被它们遮挡。
          //
          // 用 Positioned 绝对定位 (而不是 Column 中的占位 widget):
          //   - Column 中放它会推动下方波浪容器往下移, 而磨砂带是按
          //     kHeroImageHeight 计算位置的 (不会跟着移), 导致磨砂带和
          //     波浪容器错位 — 视觉上 "磨砂玻璃带被推上面被截一截, 胶囊
          //     夹在中间" 的 bug
          //   - 改成 Positioned 浮层, fetching bar 只是浮在头图底部 + 波浪
          //     容器顶部的交界处, 不影响下方任何 widget 的位置
          //
          // 位置: top = 头图底部之上 ~30px (= 波浪容器顶之上 ~10px)
          // 想调位置: 改 top 表达式
          if (_isFetchingMessages)
            Positioned(
              // 基于可见头图区域定位 (头图底部 = 波浪容器顶 = kHeroVisibleHeight)
              // 想让胶囊位置上移: 把 30 改大 (40-60); 想下移: 改小 (20)
              top: kHeroVisibleHeight - 30,
              left: 0,
              right: 0,
              child: _buildFetchingBar(),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------
  // 顶部头图 banner
  // ----------------------------------------
  // 加载本地图片作为头图, 顶部覆盖一层白色蒙版让 logo / 标题文字浮在上面更清晰。
  // 文件加载失败时回退到一个柔和的蓝色渐变, 保证布局不崩。
  // 想换图片: 改 main.dart 顶部的 kHeroImagePath 常量。
  // 想调高度: 改 kHeroImageHeight 常量。
  // 想调蒙版浓度: 改 kHeroOverlayTopAlpha / kHeroOverlayBottomAlpha 常量。
  Widget _buildHeroImage() {
    final file = File(kHeroImagePath);
    final imageExists = file.existsSync();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: kHeroImageHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 图片本体 (或回退渐变)
          if (imageExists)
            Image.file(
              file,
              fit: BoxFit.cover, // cover: 保持比例填满, 多余部分按 alignment 裁掉
              alignment: kHeroImageAlignment, // 控制显示图片哪一部分
            )
          else
            // 回退方案: 头图文件不存在时, 用一个蓝色渐变占位, 保证布局不崩
            // 这样即使忘了放头图, 程序也能正常运行, 不会黑屏或报错
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5BA8DC),
                    Color(0xFFA4D5EC),
                    Color(0xFFD9EBF2),
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  '头图未找到\n请确认 $kHeroImagePath 存在',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ),
            ),

          // 白色蒙版 (上淡下浓的渐变), 让头图柔化, 文字浮上去更清晰
          // 顶部更透 (能看清更多原图), 底部更白 (和波浪容器无缝衔接)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(kHeroOverlayTopAlpha),
                  Colors.white.withOpacity(kHeroOverlayBottomAlpha),
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
  // 顶部 Header: logo + 标题 (浮在头图上)
  // ----------------------------------------
  // Logo: 仿早期无头图版本的简洁实现 — 不加任何光晕层, 只用彩色阴影做立体感
  //        这样 Logo 看起来干净, 不会因为多层光晕重叠而显灰。
  Widget _buildTopHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ========================================
        // Logo: 52x52 圆角方块, 蓝粉渐变, 微倾斜
        // ========================================
        // 简洁实现: 直接 Transform.rotate + Container(渐变 + 双层彩色 boxShadow)
        // 不再叠加白光晕 / 黑阴影, 避免颜色重叠变灰
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
              // ----------------------------------------
              // 彩色阴影: 双层不同色 + 不同模糊半径, 形成立体感
              // ----------------------------------------
              // 用 Logo 主色调 (蓝/粉) 的彩色阴影 (不用黑色, 避免在头图上变灰),
              // 偏向底部 (offset.dy > 0), Logo 看起来像 "悬浮" 在头图上方
              // 想要更明显悬浮: 增大 blurRadius 或 offset.dy
              // 想要更内敛: 减小 alpha
              boxShadow: [
                BoxShadow(
                  color: kLogoGradientStart.withOpacity(0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: kLogoGradientEnd.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
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
        // Logo 和标题之间的间距 - 可调, 2 让标题非常贴近 Logo
        const SizedBox(height: 15),

        // ========================================
        // 标题 "Anime Chat": Georgia 字体 + 多层阴影 + 强发光
        // ========================================
        // 字体: Georgia (Windows / macOS 自带衬线, 比 Times New Roman 笔画更粗,
        //       适合做展示型标题, 在彩色头图上读起来更稳重)
        // 想换字体: 改 fontFamily, 备选 'serif' / 'Cambria' / 'Constantia'
        Text(
          'Anime Chat',
          style: TextStyle(
            fontSize: 24, // 标题大小 - 可调
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            fontFamily: 'Georgia',
            color: kTitleColor, // 白色文字
            shadows: [
              // 大白色光晕 (最外发光)
              Shadow(
                color: Colors.white.withOpacity(0.7),
                offset: const Offset(0, 0),
                blurRadius: 18,
              ),
              // 中白色光晕 (强化发光)
              Shadow(
                color: Colors.white.withOpacity(0.85),
                offset: const Offset(0, 0),
                blurRadius: 8,
              ),
              // 深蓝阴影 (定义形状)
              Shadow(
                color: kTitleShadowColor.withOpacity(0.6),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
              // 深蓝硬阴影 (强化字形)
              Shadow(
                color: kTitleShadowColor.withOpacity(0.4),
                offset: const Offset(0, 1),
                blurRadius: 1,
              ),
            ],
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
  // 这个容器现在直接贴齐屏幕左右下三边 (外层 Column 没有水平 padding),
  // 顶部是波浪线和头图无缝衔接 (波浪绘制时会向上扩展, 覆盖头图底部一小段)。
  // 容器内部给 Tab 和文件夹留水平 padding。
  //
  // 注: 磨砂玻璃带 _FrostedGlassBand 和顶部独立波浪线 _TopGlassLinePainter
  //     是放在外层 build() 的 Stack 里 (波浪容器之上的层), 这样它们能用
  //     BackdropFilter 真正模糊后方的头图。
  Widget _buildWaveContainer() {
    return CustomPaint(
      painter: _WaveContainerPainter(),
      child: Padding(
        // 外层 padding:
        //   left/right 25: 给 Tab 和文件夹两侧留出空间
        //   top 40:        给顶部波浪线 + Tab 留出视觉空间
        //   bottom 28:     文件夹底部和屏幕底之间留缝隙
        padding: const EdgeInsets.fromLTRB(25, 40, 25, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFolderTabs(),
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
      // Tab 栏总高度 = 选中 Tab 高度 (40, 含向下重叠文件夹的 2px) - 可调
      // 必须 >= _FolderTab 里 active 时的 height, 否则 Tab 会被裁
      height: 40,
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
        // ----------------------------------------
        // 文件夹本体: 蓝 -> 粉 双色渐变 (左上 -> 右下)
        // ----------------------------------------
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kFolderGradStart, // 左上 蓝 (实色, 让卡片背后色彩鲜亮)
            kFolderGradEnd, // 右下 粉 (实色)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        // ----------------------------------------
        // 文件夹整圈彩色描边 (1.5px)
        // ----------------------------------------
        // 仿聊天气泡的边线: 一条明显的彩色线 + 极浅的同色发光
        // 用蓝色 (kEdgeGlowStart) 是因为文件夹左上端是蓝色, 整圈的 border 用单色,
        // 单色描边比渐变描边更"实在"(像气泡边)。
        //
        // 关键决策: 描边整圈都画, 但 Tab 选中态的底部会向下重叠文件夹顶部 2px,
        //          实现 "Tab 和文件夹之间无分界线" 的视觉。
        //          (具体重叠机制看 _FolderTab 的 height + bottom margin)
        border: Border.all(
          color: kEdgeGlowStart,
          width: 1.5,
        ),
        // ----------------------------------------
        // 文件夹同色微弱发光 (blur 6, alpha 0.4)
        // ----------------------------------------
        // 仿聊天气泡的"线 + 微发光": stroke 是清晰的实色线,
        // 外面有一圈很弱的同色光晕, 发光不会散得很大, 紧贴边线
        boxShadow: [
          BoxShadow(
            color: kEdgeGlowStart.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
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
            // 用半透明白, 在彩色文件夹底上柔和但可见
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 8),
          Text(
            '$series 暂无角色',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
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
    // 现在波浪容器贴齐屏幕左右下三边, 底部不需要圆角 (圆角会让屏幕底部出现
    // 留白小缝, 视觉上不连贯)。改为 0 = 直角。
    // 想让左右下保留圆角: 改回 22
    const double bottomRadius = 0;

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

    // ========================================
    // 第 0 层 - 远投影 (大半径柔光, 营造"漂浮感")
    // ========================================
    // 想让投影更深: 增大 alpha (90-130)
    // 想让投影更散: 增大 sigma (24-32)
    final bigShadowPaint = Paint()
      ..color = kWaveShadowTint.withAlpha(90)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.save();
    canvas.translate(0, 16);
    canvas.drawPath(path, bigShadowPaint);
    canvas.restore();

    // ========================================
    // 第 0.5 层 - 近投影 (贴近波浪边缘, 加强轮廓)
    // ========================================
    final closeShadowPaint = Paint()
      ..color = kWaveShadowTint.withAlpha(70)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.save();
    canvas.translate(0, 6);
    canvas.drawPath(path, closeShadowPaint);
    canvas.restore();

    // ========================================
    // 第 1 层 - 容器主体 (顶部 alpha 渐变 + 下方纯白)
    // ========================================
    // 容器主体的 fill 用 ui.Gradient.linear 做垂直 alpha 渐变:
    //   - 顶部 (y = waveBaseY - waveAmp*1.5 ≈ -7, 波浪起伏最高点): alpha 0 (完全透明)
    //   - y = 30 (= 屏幕 y=175 = 头图下方略远处): alpha 0.96 (完全实白)
    //   - y > 30 以下: 保持 alpha 0.96
    //
    // 这样波浪容器顶部能透出后方的内容 (头图 + 磨砂玻璃带), 视觉上头图色彩
    // 慢慢过渡到实白容器, 不再是 "突兀的白色硬边"。
    //
    // 想让透明区域更大 (容器顶部更透): 增大 fadeBottomY (默认 30, 范围 25~50)
    // 想让顶部完全透明区扩展更下: 把 alpha 0 的 stop 从 0.0 改成 0.1~0.2
    // 想让容器整体更透 (即使下方也不太实): 减小 0.96 → 0.85~0.92
    const double fadeBottomY = 50; // 渐变结束 y 位置
    const double fadeTopY = -7; // 渐变起始 y 位置 (波浪起伏最高点)
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, fadeTopY),
        Offset(w / 2, fadeBottomY),
        [
          Colors.white.withOpacity(0.45), // 顶部透明
          Colors.white.withOpacity(0.96), // 底部实白
        ],
        [0.0, 1.0],
      );
    canvas.drawPath(path, fillPaint);

    // ========================================
    // 第 3 层 - 容器顶部白色高光描边 (= 主波浪线本身)
    // ========================================
    // 沿主波浪顶边画一条白色描边, alpha 高一点 (0.95) 让线条清晰可见,
    // 这条线就是"容器顶部的白色高光", 紧贴第 4 层突出玻璃的底部。
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
    final topStrokePaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(topWavePath, topStrokePaint);

    // 注: 之前 painter 里实现的"第 4 层 突出磨砂玻璃带"和"第 5 层 顶部独立波浪线"
    // 已经被移出 painter, 改在 _buildWaveContainer 的 Stack 里用
    // ClipPath + BackdropFilter 实现真正的磨砂玻璃效果 (高斯模糊背景),
    // 而不是这里 painter 能做到的"半透明纯白填充"。
    // 见 _FrostedGlassBand 和 _TopGlassLinePainter 类的实现。
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ========================================
// 真磨砂玻璃带 widget (用 ClipPath + BackdropFilter 实现高斯模糊)
// ========================================
// 不同于 painter 里画的"半透明白色填充", 这个组件用 BackdropFilter 真的对
// 它后方的内容(头图)进行高斯模糊, 然后叠加一层半透明白色蒙层,
// 实现真正的毛玻璃效果。
//
// 关键尺寸约定 (widget 内部坐标系, y=0 是 widget 顶部):
//   - widget 总高 _kBandHeight = 50 (足够容纳上下波浪起伏 + 16px 玻璃区)
//   - 上波浪线中线 _kBandTopY = 18 (上下起伏 ±14, 范围 4~32)
//   - 下波浪线中线 _kBandBottomY = 34 (上下起伏 ±14, 范围 20~48)
//   - 磨砂玻璃区 = 上波浪 (~y18) 到下波浪 (~y34), 厚度只有 16px
//
// 关键改动 (vs 之前): 玻璃带从 40px 厚减到 16px 薄, 这样它视觉上只是
// "头图和实白容器之间的薄过渡层", 不会被误认为是另一个独立的容器层。
//
// 屏幕坐标对齐:
//   - widget 的 Positioned.top 让 "下波浪线 (y=34)" 落在屏幕的
//     "波浪容器主波浪线" 位置 (= kHeroImageHeight - kWaveOverlap + 14)
//   - 即 Positioned.top = kHeroImageHeight - kWaveOverlap + 14 - 34
//                       = kHeroImageHeight - kWaveOverlap - 20
const double _kBandHeight = 50;
const double _kBandTopY = 18; // 上波浪中线
const double _kBandBottomY = 34; // 下波浪中线 (= 屏幕主波浪线位置)
const double _kBandWaveAmp = 14; // 波浪起伏幅度

class _FrostedGlassBand extends StatelessWidget {
  const _FrostedGlassBand();

  @override
  Widget build(BuildContext context) {
    // 简化版: 普通半透明白色条带 (不再用 BackdropFilter 高斯模糊背景)
    //
    // 之前用 ClipPath + BackdropFilter 实现 "真磨砂玻璃" 效果, 但渲染开销大,
    // 视觉上和直接画一层半透明白色差别不明显, 性价比低。改回用 ClipPath +
    // 半透明白 Container 的简单方案 — 形状不变, 只是不再做高斯模糊。
    //
    // alpha 控制条带白浊度:
    //   - 0.20-0.30: 中等半透明, 能透出后方头图色彩 (推荐 0.25)
    //   - 0.40-0.55: 偏白实, 接近实白容器
    //   - 0.10-0.15: 极透, 几乎看不到条带
    return ClipPath(
      clipper: _FrostedGlassClipper(),
      child: Container(
        color: Colors.white.withOpacity(0.25),
      ),
    );
  }
}

// 磨砂玻璃带的形状裁剪器: 上下两条波浪线之间的"带状"区域
class _FrostedGlassClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final path = Path();

    // 上波浪 (玻璃带的顶边)
    path.moveTo(0, _kBandTopY);
    path.cubicTo(
      w * 0.1,
      _kBandTopY - _kBandWaveAmp,
      w * 0.2,
      _kBandTopY + _kBandWaveAmp,
      w * 0.33,
      _kBandTopY,
    );
    path.cubicTo(
      w * 0.45,
      _kBandTopY - _kBandWaveAmp,
      w * 0.55,
      _kBandTopY + _kBandWaveAmp,
      w * 0.67,
      _kBandTopY - _kBandWaveAmp * 0.5,
    );
    path.cubicTo(
      w * 0.8,
      _kBandTopY - _kBandWaveAmp * 1.5,
      w * 0.9,
      _kBandTopY + _kBandWaveAmp * 0.8,
      w,
      _kBandTopY - _kBandWaveAmp * 0.5,
    );

    // 下波浪 (玻璃带的底边, 从右向左反向画闭合)
    // 这条线在屏幕坐标系上 = 主波浪线 (容器顶白描边位置)
    path.lineTo(w, _kBandBottomY - _kBandWaveAmp * 0.5);
    path.cubicTo(
      w * 0.9,
      _kBandBottomY + _kBandWaveAmp * 0.8,
      w * 0.8,
      _kBandBottomY - _kBandWaveAmp * 1.5,
      w * 0.67,
      _kBandBottomY - _kBandWaveAmp * 0.5,
    );
    path.cubicTo(
      w * 0.55,
      _kBandBottomY + _kBandWaveAmp,
      w * 0.45,
      _kBandBottomY - _kBandWaveAmp,
      w * 0.33,
      _kBandBottomY,
    );
    path.cubicTo(
      w * 0.2,
      _kBandBottomY + _kBandWaveAmp,
      w * 0.1,
      _kBandBottomY - _kBandWaveAmp,
      0,
      _kBandBottomY,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ========================================
// 玻璃带上方的独立装饰波浪线 painter
// ========================================
// 在磨砂玻璃带顶部上方画一条更细的白色波浪描边, 模拟"两层叠加的磨砂玻璃"
// 效果。
//
// 这个 painter 的 widget 大小 = _FrostedGlassBand 大小 (50px), 但只在
// 上波浪上方 ~4px 处画线, 其他位置透明
class _TopGlassLinePainter extends CustomPainter {
  const _TopGlassLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // 这条线在 widget 内部 y = 上波浪中线 - 4 (上波浪上方 4px)
    // 改小这个 4 让独立线更靠近上波浪 (但要 >= _kBandWaveAmp 才不会被 widget 顶部裁掉)
    // 改大让独立线更远离上波浪 (太大会被裁)
    const double lineY = _kBandTopY - 6;

    final path = Path()..moveTo(0, lineY);
    path.cubicTo(
      w * 0.1,
      lineY - _kBandWaveAmp,
      w * 0.2,
      lineY + _kBandWaveAmp,
      w * 0.33,
      lineY,
    );
    path.cubicTo(
      w * 0.45,
      lineY - _kBandWaveAmp,
      w * 0.55,
      lineY + _kBandWaveAmp,
      w * 0.67,
      lineY - _kBandWaveAmp * 0.5,
    );
    path.cubicTo(
      w * 0.8,
      lineY - _kBandWaveAmp * 1.5,
      w * 0.9,
      lineY + _kBandWaveAmp * 0.8,
      w,
      lineY - _kBandWaveAmp * 0.5,
    );

    // 想让独立线更明显: 增大 alpha (默认 0.9, 范围 0.6~1.0)
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ========================================
// 文件夹 Tab 组件
// ========================================
// 一个 Tab 分三层:
// 1. 主体: 蓝色实色 (= kFolderColor = kFolderGradStart) 圆角矩形
//    (上半圆角, 底边和 folder-body 渐变左上端无缝衔接,
//    实现"Tab 是从文件夹拉出的一角"的视觉)
// 2. 左侧向内凹陷圆弧 (伪元素, 用 CustomPainter 画, 同色)
// 3. 右侧向内凹陷圆弧 (同色)
// Tab 未选中时用更低的透明度 + 更矮的高度, 选中时变高变清晰
// 选中态文字用白色 (kFolderAccent), 未选中用雾蓝灰 (kFolderTabDim)
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
    // 未选中的 Tab 高度更矮, 底色更透 (但文字保持清晰)
    // 选中态额外多 2px (向下重叠文件夹顶部, 隐藏分界线)
    // ----------------------------------------
    // 关键: 选中态高度从 38 加到 40 (+2 是用来向下"压住"文件夹顶部 2px,
    //       让 Tab 底边和文件夹顶边的描边互相覆盖, 看不到 "两条描边并排"
    //       的分界线, 实现 "Tab 和文件夹是一体" 的视觉。
    // 未选中态保持 32 不变 (没必要重叠, 它本来就不强调"和文件夹一体")。
    final double height = active ? 40 : 32;
    // ----------------------------------------
    // Tab 底色 (半透明白控制透明度, 文字本身保持清晰)
    // ----------------------------------------
    final Color tabFillColor =
        active ? kFolderColor : kFolderColor.withOpacity(0.55);
    // 文字色: 选中用白色 (= kFolderAccent), 未选中用深色保证可读性
    final Color textColor = active ? kFolderAccent : const Color(0xFF3F6A99);
    final FontWeight fontWeight = active ? FontWeight.w600 : FontWeight.w500;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // 不再用 Opacity 包裹! 直接画 Stack, 通过 tabFillColor 控制底色透明度
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ----------------------------------------
          // 同色微弱发光 (选中态才画, 仿聊天气泡的"线 + 微发光")
          // ----------------------------------------
          // 在 Tab 主体下方放一个发光底层, 让 Tab 边缘有同色光晕,
          // 视觉上和文件夹的边线发光是同一个连贯的光环
          if (active)
            Positioned(
              left: -2,
              right: -2,
              bottom: -2,
              top: -2,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kEdgeGlowStart.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 0,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Tab 主体
          Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: tabFillColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              // ----------------------------------------
              // Tab 描边: 选中态画蓝色实在描边 (顶+左+右, 底不画)
              // ----------------------------------------
              // 关键: 用 Border 分别指定四边, 底边 BorderSide.none 让 Tab 底
              //      和文件夹顶边视觉无缝衔接 (因为同色填充会自然连贯, 中间
              //      没有线把它们隔开)。
              // 未选中态不画描边, 只是个半透明色块, 视觉低调。
              border: active
                  ? const Border(
                      top: BorderSide(
                        color: kEdgeGlowStart,
                        width: 1.5,
                      ),
                      left: BorderSide(
                        color: kEdgeGlowStart,
                        width: 1.5,
                      ),
                      right: BorderSide(
                        color: kEdgeGlowStart,
                        width: 1.5,
                      ),
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Padding(
              // 选中态加 2px 底部 padding 抵消 height +2 的视觉偏移,
              // 让文字仍然在 Tab 视觉中心
              padding: EdgeInsets.only(bottom: active ? 2 : 0),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13, // Tab 文字大小 - 可调
                  fontWeight: fontWeight,
                  color: textColor,
                ),
              ),
            ),
          ),
          // 左侧凹弧: 定位在 Tab 左外侧, 用 CustomPainter 画一段"向内凹陷的圆弧"
          // 颜色用 tabFillColor (跟 Tab 主体同色同透明度), 保证未选中时凹弧也透
          Positioned(
            left: -14,
            bottom: 0,
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _TabCornerPainter(isLeft: true, color: tabFillColor),
            ),
          ),
          // 右侧凹弧
          Positioned(
            right: -14,
            bottom: 0,
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _TabCornerPainter(isLeft: false, color: tabFillColor),
            ),
          ),
        ],
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
// 角色卡片组件 (玻璃质感 + 三段式点击动效)
// ========================================
// 视觉要点:
// 1. 玻璃质感: BackdropFilter 模糊背景 + 半透明白 + 白色细描边
// 2. 外阴影: 极淡, 保持轻盈
// 3. 点击动效 (三段同时触发, 1500ms 总时长):
//    a. 缩放 (C): 立即缩到 0.97 然后弹回 (松手时)
//    b. 边缘发光波纹 (F): 角色色光环从卡片边缘扩散 (1100ms)
//       + 卡片白描边短暂变亮配合
//    c. 倾斜扫光 (A): 一束渐变白光带从左下扫到右上 (1500ms)
// 4. 跳转策略: 点击立即跳转聊天页, 动画在后台播放
//    (用户从聊天页返回时, 看到的是已经播完的卡片, 体感更顺畅)
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
  // ----------------------------------------
  // 单一 AnimationController 驱动三段动画
  // ----------------------------------------
  // 用 Interval 把不同子动画切到不同时间段, 这样只需要一个 controller,
  // 不需要管理多个 controller 的同步。
  // 总时长 1500ms, 想加快/减慢整体动效就改这一个常量。
  late final AnimationController _activateController;

  // 边缘发光波纹: 0% ~ 73% 完成 (1100ms / 1500ms), 后段渐隐
  late final Animation<double> _glowAnimation;
  // 倾斜扫光: 0% ~ 100% 完成 (1500ms 全程)
  late final Animation<double> _shimmerAnimation;
  // 卡片白描边变亮: 跟边缘发光同步 (0% ~ 73%)
  late final Animation<double> _borderFlashAnimation;

  // hover 状态 (鼠标悬停时卡片轻微上浮)
  bool _hovering = false;
  // 按下状态 (轻微缩放反馈)
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _activateController = AnimationController(
      vsync: this,
      // 总动画时长 - 想整体加快/减慢就改这里
      // - 1500ms: 当前值, 三段动效都看得清
      // - 1200ms: 节奏更快一点
      // - 1800ms: 更舒缓
      duration: const Duration(milliseconds: 1500),
    );

    // 边缘发光: 在 0~73% 时段内走完一个 0->1 的曲线 (实际持续 1100ms)
    _glowAnimation = CurvedAnimation(
      parent: _activateController,
      curve: const Interval(0.0, 0.73, curve: Curves.easeOutCubic),
    );

    // 扫光: 全程 0~100% (在 1500ms 内走完)
    // 用 easeInOutCubic 让光带在中段 (卡片可见区) 速度更慢, 更显眼
    _shimmerAnimation = CurvedAnimation(
      parent: _activateController,
      curve: Curves.easeInOutCubic,
    );

    // 描边变亮: 跟发光波纹同步, 但用更柔和的曲线
    _borderFlashAnimation = CurvedAnimation(
      parent: _activateController,
      curve: const Interval(0.0, 0.73, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _activateController.dispose();
    super.dispose();
  }

  void _handleTap() {
    // ----------------------------------------
    // 跳转策略: 让动画播 ~800ms 用户充分看到扫光走过卡片再跳转
    // ----------------------------------------
    // Flutter 的 Navigator.push 会立刻把当前页面推到后台, 后台 widget 不再
    // layout/paint, 用户看不到动画。所以必须先延迟一段, 让动画在前台播放。
    //
    // 时间设计 (总时长 1500ms):
    //   - 800ms 时扫光进度 ≈ 53%, 光带正在卡片中心位置, 视觉效果最强
    //   - 边缘发光波纹 1100ms (整体 0~73%), 800ms 时已过中段 (= 73%),
    //     光环达到最大扩散半径
    //
    // 跳转时强制 stop + reset controller, 防止后台 tick 导致返回时残留帧
    //
    // 想让用户看到更长动效再跳转: 增大 800 (但不要超过 1300, 否则跳转太慢)
    // 想点击立即跳转 (不要前置动画): 改成 0
    _activateController.forward(from: 0.0);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      // 跳转前停 controller 并复位, 防止后台 tick 导致返回主页时有残帧
      _activateController.stop();
      _activateController.value = 0.0;
      widget.onTap();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 角色色: 用于边缘发光波纹的颜色
    final characterColor = Color(int.parse('0xFF${widget.character.color}'));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _activateController,
          builder: (context, child) {
            return AnimatedScale(
              // ========================================
              // 第 C 段: 按下缩放反馈
              // ========================================
              // _pressed 时立即缩到 0.97, 释放回 1.0
              // duration 短一点 (120ms) 让"按下感"即时
              scale: _pressed ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                // hover 时向上浮 2px
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(
                  0,
                  _hovering ? -2 : 0,
                  0,
                ),
                child: _buildCardWithGlow(characterColor),
              ),
            );
          },
        ),
      ),
    );
  }

  // ----------------------------------------
  // 卡片本体 + 边缘发光波纹层 (Stack 不裁剪, 让发光能溢出边缘)
  // ----------------------------------------
  Widget _buildCardWithGlow(Color characterColor) {
    return Stack(
      // clipBehavior: Clip.none 让边缘发光波纹能溢出卡片边界
      // 这是 F 效果的关键 - 没有这个就看不到光晕扩散
      clipBehavior: Clip.none,
      children: [
        // ----------------------------------------
        // 卡片本体 (DecoratedBox 提供阴影 + ClipRRect 裁剪 BackdropFilter)
        // ----------------------------------------
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // 极淡外阴影: hover 时略加深
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
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AnimatedBuilder(
                animation: _borderFlashAnimation,
                builder: (context, child) {
                  // ========================================
                  // 描边变亮 (跟边缘发光同步)
                  // ========================================
                  // 用 _borderFlashAnimation 进度计算 alpha:
                  //   t=0   (开始): alpha 0.55 (基础)
                  //   t=0.27 (峰值): alpha 0.95 (最亮)
                  //   t=0.82 (中段): alpha 0.75
                  //   t=1.0  (结束): alpha 0.55 (回到基础)
                  final t = _borderFlashAnimation.value;
                  final double borderAlpha;
                  if (t < 0.27) {
                    // 0 -> 峰值: 0.55 -> 0.95
                    borderAlpha = 0.55 + (t / 0.27) * 0.40;
                  } else if (t < 0.82) {
                    // 峰值 -> 中段: 0.95 -> 0.75
                    final p = (t - 0.27) / (0.82 - 0.27);
                    borderAlpha = 0.95 - p * 0.20;
                  } else {
                    // 中段 -> 收尾: 0.75 -> 0.55
                    final p = (t - 0.82) / (1.0 - 0.82);
                    borderAlpha = 0.75 - p * 0.20;
                  }

                  return Container(
                    decoration: BoxDecoration(
                      // 半透明白: alpha 0.28 让玻璃通透
                      color: Colors.white.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(18),
                      // 描边 alpha 由动画驱动, 静态时是基础 0.55
                      border: Border.all(
                        color: Colors.white.withOpacity(borderAlpha),
                        width: 1.5,
                      ),
                    ),
                    child: child,
                  );
                },
                // child 不依赖动画, 抽出来避免每帧重建
                child: Stack(
                  children: [
                    // 卡片主体内容 (头像 + 文字 + 箭头)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: _buildCardContent(),
                    ),

                    // ----------------------------------------
                    // 第 A 段: 倾斜扫光层
                    // ----------------------------------------
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shimmerAnimation,
                          builder: (context, _) {
                            final t = _shimmerAnimation.value;
                            if (t == 0.0) return const SizedBox.shrink();
                            return CustomPaint(
                              painter: _DiagonalShimmerPainter(progress: t),
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

        // ----------------------------------------
        // 第 F 段: 边缘发光波纹层 (放在卡片之上, 用 CustomPainter 只画外圈描边)
        // ----------------------------------------
        // 之前用 BoxShadow + spreadRadius 模拟"光环扩散", 但 BoxShadow 的 blur
        // 会让发光区域辐射到卡片内部 (尤其当 blur 较大时), 加上卡片半透明,
        // 视觉上"卡片整张被发光填充"。
        //
        // 现在改用 CustomPaint, 在 painter 里:
        //   - 画一个比卡片更大的圆角矩形 stroke (不是 fill!)
        //   - 用 MaskFilter.blur 让描边变成柔光环
        //   - stroke 是空心的, 内部完全透明, 不会盖住卡片本体
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                final t = _glowAnimation.value; // 0.0 ~ 1.0
                if (t == 0.0) return const SizedBox.shrink();

                // 光环参数随 t 变化:
                //   t=0.27 (= 20% 整体进度): 峰值 - alpha 1.0, ringExpand 4
                //   t=0.82 (= 60% 整体进度): 中段 - alpha 0.7, ringExpand 12
                //   t=1.00 (= 73% 整体进度): 末段 - alpha 0, ringExpand 18
                final double opacity;
                final double ringExpand; // 发光环离卡片边缘的距离
                final double blur; // 发光环的模糊半径
                if (t < 0.27) {
                  final p = t / 0.27;
                  opacity = p;
                  ringExpand = 4 * p;
                  blur = 14 * p;
                } else if (t < 0.82) {
                  final p = (t - 0.27) / (0.82 - 0.27);
                  opacity = 1.0 - p * 0.3;
                  ringExpand = 4 + p * 8;
                  blur = 14 + p * 12;
                } else {
                  final p = (t - 0.82) / (1.0 - 0.82);
                  opacity = 0.7 * (1 - p);
                  ringExpand = 12 + p * 6;
                  blur = 26 + p * 10;
                }

                return CustomPaint(
                  painter: _GlowRingPainter(
                    color: characterColor.withOpacity(0.7 * opacity),
                    ringExpand: ringExpand,
                    blur: blur,
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
            // 颜色用冷调蓝灰, 配合玻璃卡片透出的蓝粉底色
            Text(
              preview.japaneseText ?? '',
              style: TextStyle(
                fontSize: 12,
                color: showBilingual
                    ? const Color(0xFF1A2942) // 深蓝灰 (主信息, 醒目)
                    : const Color(0xFF555E6E), // 中蓝灰 (单语时偏柔)
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 中文翻译 (仅 AI 消息且有翻译时显示)
            // 颜色比日文稍淡, 视觉层级清晰
            if (showBilingual) ...[
              const SizedBox(height: 1),
              Text(
                preview.chineseText!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5A6C8A), // 中蓝灰
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
  // 用 mainAxisSize.min 让 Column 自适应内容高度, 不强占父级 38px,
  // 避免在卡片高度变化时抛 RenderFlex overflow 异常
  Widget _buildRightColumn(_ChatPreview? preview) {
    final timeText = _formatTime(preview?.lastTime);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (timeText.isNotEmpty) ...[
          Text(
            timeText,
            style: const TextStyle(
              fontSize: 10,
              // 时间字色用冷调蓝灰, 和首页主色调一致
              color: Color(0xFF8A9FB5),
            ),
          ),
          const SizedBox(height: 4), // 时间和箭头间距 - 从 6 减到 4 防溢出
        ],
        // 右侧箭头
        // 颜色用海蓝深色 kAccentDeepBlue (= #3F6A99 ≈ 标题阴影色),
        // 不能用 kFolderAccent (现在是白色, 在白卡片上看不见!)
        const Icon(
          Icons.chevron_right,
          size: 18, // 箭头大小 - 可调, 从 20 减到 18 防溢出
          color: Color(0xFF3F6A99),
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
  // 圆点颜色 - 可调; 用海蓝 (= 文件夹起点 / Tab 选中色), 和首页主色统一
  static const Color kDotColor = Color(0xFF5BA8DC);
  static const Duration kDotPulseDuration =
      Duration(milliseconds: 1100); // 圆点一次脉动的时长 - 可调

  // 文字参数
  static const String kCapsuleText = '消息收取中'; // 文字内容 - 可调
  static const double kCapsuleTextSize = 12; // 文字字号 - 可调
  // 文字颜色 - 可调; 用比圆点更深的海蓝, 在浅色胶囊背景上保证可读性
  static const Color kCapsuleTextColor = Color(0xFF1F4F70);

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
// 倾斜扫光 painter (A 段动效)
// ========================================
// 画一束 -20° 倾斜的渐变光带, 从卡片左外侧扫到右外侧。
// 用 SkewX 倾斜变换 + 横向 LinearGradient 实现。
//
// progress: 0.0 ~ 1.0
//   0.0 时光带在卡片左外侧 (left 约 -100%)
//   1.0 时光带已扫到右外侧 (left 约 +200%, 完全离开卡片)

// ========================================
// 边缘发光环 painter (F 段动效)
// ========================================
// 用 stroke (描边) + MaskFilter.blur 画一个柔光环, 只在卡片轮廓外侧,
// 不会填充内部 (这是 CustomPainter 比 BoxShadow 更可控的地方)
//
// 参数:
//   color:      发光颜色 (含 alpha)
//   ringExpand: 发光环离卡片边缘的距离 (像素), 越大光环离卡片越远
//   blur:       高斯模糊半径, 越大光环越柔
class _GlowRingPainter extends CustomPainter {
  final Color color;
  final double ringExpand;
  final double blur;

  _GlowRingPainter({
    required this.color,
    required this.ringExpand,
    required this.blur,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 卡片本身的圆角矩形 (size 就是卡片大小)
    // 发光环的位置: 比卡片向外扩 ringExpand 像素, 圆角也加上扩展
    // 这样光环包裹住卡片
    final ringRect = Rect.fromLTWH(
      -ringExpand,
      -ringExpand,
      size.width + ringExpand * 2,
      size.height + ringExpand * 2,
    );
    final ringRRect = RRect.fromRectAndRadius(
      ringRect,
      Radius.circular(18 + ringExpand),
    );

    // stroke + MaskFilter.blur 实现"只在描边一圈发光"
    // strokeWidth 控制环的厚度, blur 让描边边缘虚化成光晕
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, blur * 0.5) // 环厚度跟模糊半径成正比
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

    canvas.drawRRect(ringRRect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.ringExpand != ringExpand ||
      oldDelegate.blur != blur;
}

class _DiagonalShimmerPainter extends CustomPainter {
  final double progress;

  _DiagonalShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // 光带宽度 = 卡片宽度的 70% (跟 demo 一致)
    final shimmerWidth = size.width * 0.7;
    // 光带左端在 progress=0 时在屏幕外左侧 (-shimmerWidth),
    // 在 progress=1 时移到右侧 (+size.width), 总移动距离 = size.width + shimmerWidth
    final shimmerLeft = -shimmerWidth + progress * (size.width + shimmerWidth);

    // 入场/出场淡入淡出: 光带在前 10% / 后 10% alpha 渐变, 中间 80% 完全可见
    double envelopeAlpha;
    if (progress < 0.1) {
      envelopeAlpha = progress / 0.1;
    } else if (progress > 0.9) {
      envelopeAlpha = (1.0 - progress) / 0.1;
    } else {
      envelopeAlpha = 1.0;
    }

    // 光带本身的渐变 (横向): 透明 -> 中段亮白 -> 透明
    // 三段渐变让中间高亮区集中, 两侧柔和淡出
    final gradient = ui.Gradient.linear(
      Offset(shimmerLeft, 0),
      Offset(shimmerLeft + shimmerWidth, 0),
      [
        Colors.white.withOpacity(0.0),
        Colors.white.withOpacity(0.25 * envelopeAlpha),
        Colors.white.withOpacity(0.85 * envelopeAlpha),
        Colors.white.withOpacity(0.25 * envelopeAlpha),
        Colors.white.withOpacity(0.0),
      ],
      [0.0, 0.30, 0.50, 0.70, 1.0],
    );

    // 倾斜变换 (-20°): 用 transform 让矩形 skew, 整个光带就斜过来了
    // skew 弧度 = -20 * pi / 180 ≈ -0.349
    canvas.save();
    final skewMatrix = Matrix4.identity()..setEntry(0, 1, math.tan(-0.349));
    // 以卡片中心为变换原点, 这样 skew 后光带不会偏移到屏幕外
    canvas.translate(size.width / 2, size.height / 2);
    canvas.transform(skewMatrix.storage);
    canvas.translate(-size.width / 2, -size.height / 2);

    // 画一个比卡片更大的矩形 (上下各延伸一倍), 让 skew 后光带覆盖整个卡片高度
    final paint = Paint()..shader = gradient;
    canvas.drawRect(
      Rect.fromLTWH(
        shimmerLeft,
        -size.height,
        shimmerWidth,
        size.height * 3,
      ),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalShimmerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
