import 'package:flutter/material.dart';

import 'config.dart';
import 'services/backend.dart';
import 'services/memory_backend.dart';
import 'services/share_link.dart';
import 'services/supabase_backend.dart';
import 'state/app_state.dart';
import 'ui/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/worker_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 工人扫码进来: 计划都在网址里, 不需要登入也不需要连后端
  final payload = workerPayloadFrom(Uri.base);
  final plan = payload == null ? null : decodeWorkerPayload(payload);
  if (plan != null) {
    runApp(WorkerLinkApp(plan: plan));
    return;
  }

  Backend backend;
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    backend = await SupabaseBackend.init(supabaseUrl, supabaseAnonKey);
  } else {
    backend = MemoryBackend(); // 没设置 Supabase: 演示模式
  }
  runApp(ContainerCalcApp(state: AppState(backend)..boot()));
}

class WorkerLinkApp extends StatelessWidget {
  const WorkerLinkApp({super.key, required this.plan});
  final WorkerPlan plan;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '装柜 Loading',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // 网址的 # 部分会被当成初始路由名称, 所以任何路由都回传装柜画面
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => WorkerScreen(container: plan.container, unit: plan.unit, totalUnits: plan.totalUnits)),
      );
}

class ContainerCalcApp extends StatefulWidget {
  const ContainerCalcApp({super.key, required this.state});
  final AppState state;

  @override
  State<ContainerCalcApp> createState() => _ContainerCalcAppState();
}

class _ContainerCalcAppState extends State<ContainerCalcApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.state.onToast = (m, isError) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m), backgroundColor: isError ? redErr : navy, duration: const Duration(seconds: 4)));
    };
    // 登出/被强制登出时, 关掉个人资料、管理后台等已开启的页面
    widget.state.addListener(() {
      if (widget.state.user == null) _nav.currentState?.popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '集装箱装载计算器 Container Loading Calculator',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scaffoldMessengerKey: _messenger,
        navigatorKey: _nav,
        home: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final s = widget.state;
            if (s.booting) return const Scaffold(backgroundColor: navy, body: Center(child: CircularProgressIndicator(color: orange)));
            // key 随 formGeneration 变化: 换帐号时丢弃所有表单状态
            if (s.user == null) return AuthScreen(key: ValueKey('auth${s.formGeneration}'), state: s);
            return HomeScreen(state: s);
          },
        ),
      );
}
