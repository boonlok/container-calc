// 端到端界面测试 (演示模式后端): 注册第一个账号 → 输入物品 → 计算 → 看到混装柜特写 → 保存/载入历史 → 登出后资料清空
import 'dart:io';

import 'package:container_calc/core/models.dart';
import 'package:container_calc/main.dart';
import 'package:container_calc/services/memory_backend.dart';
import 'package:container_calc/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont() async {
  final bytes = File('assets/fonts/NotoSansSC-subset.ttf').readAsBytesSync();
  final loader = FontLoader('NotoSansSC')..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();
}

void main() {
  // 草稿保存用到本机储存: 测试里换成内存版, 否则会一直等平台回应
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('register → calculate → close-ups → history → logout clears data', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(MemoryBackend());
    await state.boot();
    await tester.pumpWidget(ContainerCalcApp(state: state));
    await tester.pumpAndSettle();

    // 登录页 → 注册第一个账号 (自动成为管理员并登入)
    expect(find.text('登入 Log In'), findsOneWidget);
    expect(find.textContaining('演示模式'), findsWidgets);
    await tester.tap(find.text('注册新帐号 Register'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'boss@x.com');
    await tester.enterText(fields.at(1), 'secret1');
    await tester.tap(find.text('注册 Register'));
    await tester.pumpAndSettle();
    expect(state.user?.isAdmin, isTrue);
    expect(find.textContaining('物品清单 Item List'), findsOneWidget);
    expect(state.presets.length, 4);

    // 未填资料: 显示双语错误, 不会产生结果
    await tester.ensureVisible(find.byKey(const ValueKey('calcBtn')));
    await tester.tap(find.byKey(const ValueKey('calcBtn')));
    await tester.pump();
    expect(find.textContaining('缺少物品名称'), findsOneWidget);
    expect(state.result, isNull);

    // 直接填入模型 (表格输入框另外测), 计算两种物品 → 混装
    state.items[0]
      ..name = '钢管 Steel'
      ..totalPcs = 300
      ..pcsPerBox = 1
      ..boxL = 60
      ..boxW = 40
      ..boxH = 40;
    state.items[1]
      ..name = '配件盒 Parts'
      ..totalPcs = 420
      ..pcsPerBox = 1
      ..boxL = 30
      ..boxW = 30
      ..boxH = 25;
    await tester.tap(find.byKey(const ValueKey('calcBtn')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.result, isNotNull);
    expect(find.textContaining('总集装箱数'), findsOneWidget);
    expect(state.result!.containers.first.allocations.length, 2);

    // 混装柜: 每个区块有特写和工人注意事项
    expect(find.byKey(const ValueKey('section1')), findsOneWidget);
    expect(find.byKey(const ValueKey('section2')), findsOneWidget);
    expect(find.textContaining('各物品区块特写'), findsOneWidget);
    expect(find.textContaining('最靠柜门'), findsOneWidget);

    // 保存 + 改动 + 载入历史
    await state.saveHistory('calc1');
    final rows = await state.backend.listHistory();
    expect(rows.single.name, 'calc1');
    state.items[0].name = 'changed';
    await state.applyHistory(rows.single.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.items[0].name, '钢管 Steel');
    expect(state.result!.containers.length, greaterThan(0));

    // 登出: 资料全部清空 (下一个账号看不到)
    await state.logout(message: '已登出 Logged out');
    await tester.pumpAndSettle();
    expect(state.items, isEmpty);
    expect(state.result, isNull);
    expect(state.presets, isEmpty);
    expect(find.text('登入 Log In'), findsOneWidget);
    expect(find.text('已登出 Logged out'), findsOneWidget);
  });

  testWidgets('item table input updates the model and box count', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = MemoryBackend();
    await b.register('a@x.com', 'secret1', '', '');
    final state = AppState(b);
    await state.boot();
    await state.login('a@x.com', 'secret1');
    await tester.pumpWidget(ContainerCalcApp(state: state));
    await tester.pump(const Duration(milliseconds: 100));

    final first = state.items.first;
    final hint = find.widgetWithText(TextField, '例如: 钢管 Steel Pipe').first;
    await tester.enterText(hint, 'Box A');
    expect(first.name, 'Box A');
    final numberFields = find.descendant(of: find.byType(Row), matching: find.widgetWithText(TextField, 'L'));
    await tester.enterText(numberFields.first, '50');
    expect(first.boxL, 50);
    expect(colorToHex(first.color), '#e74c3c');
  });


  testWidgets('planner screens fit a phone: sample → calculate → results without overflow', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = MemoryBackend();
    await b.register('a@x.com', 'secret1', '', '');
    final state = AppState(b);
    await state.boot();
    await state.login('a@x.com', 'secret1');
    await tester.pumpWidget(ContainerCalcApp(state: state));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: 'home fits a phone');
    expect(find.widgetWithText(TextFormField, '总数量 PCS'), findsWidgets, reason: 'phone uses item cards');

    await tester.ensureVisible(find.byKey(const ValueKey('loadSample')));
    await tester.tap(find.byKey(const ValueKey('loadSample')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.items.length, 3);
    await tester.ensureVisible(find.byKey(const ValueKey('calcBtn')));
    await tester.tap(find.byKey(const ValueKey('calcBtn')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.result, isNotNull);
    expect(tester.takeException(), isNull, reason: 'results fit a phone');
    expect(find.byKey(const ValueKey('startLoading')), findsOneWidget);
  });
}
