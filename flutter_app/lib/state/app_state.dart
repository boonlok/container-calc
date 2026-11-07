/// 全局状态 App state: 登入者、物品清单、柜型、计算结果、货运信息
library;

import 'package:flutter/foundation.dart';

import '../core/algorithm.dart';
import '../core/models.dart';
import '../services/backend.dart';
import '../services/history_codec.dart';

const colorPalette = <int>[
  0xFFE74C3C, 0xFF3498DB, 0xFF2ECC71, 0xFFF39C12, 0xFF9B59B6, 0xFF1ABC9C,
  0xFFE67E22, 0xFF34495E, 0xFFF1C40F, 0xFFE84393, 0xFF00B894, 0xFF0984E3,
];
const defaultAccessories = ['Cable Clip', 'Screw', 'Sticker', 'Manual Book', 'Instruction Sheet', 'Warning Label'];

class AppState extends ChangeNotifier {
  AppState(this.backend);
  final Backend backend;

  /// 提示讯息 (由 main.dart 接到 ScaffoldMessenger)
  void Function(String message, bool isError)? onToast;
  void toast(String m, {bool error = false}) => onToast?.call(m, error);

  bool booting = true;
  UserProfile? user;
  String flash = ''; // 回到登录页时显示的讯息

  List<Item> items = [];
  List<Preset> presets = [];
  Set<int> activePresetIds = {};
  bool presetsLoading = false;
  PackResult? result;
  int selectedIndex = 0;
  ShipmentInfo shipment = ShipmentInfo();

  /// 内容被整批替换 (载入历史/登出) 时递增: 表单元件用它当 key 重建, 丢掉旧的输入框内容
  int formGeneration = 0;

  int _nextItemId = 1, _colorCursor = 0;

  Future<void> boot() async {
    try {
      user = await backend.restoreSession();
      if (user != null) await _afterLogin();
    } catch (_) {
      user = null;
    }
    booting = false;
    notifyListeners();
  }

  // 清掉所有资料: 下一个登入的帐号绝不能看到上一个帐号的物品/结果/柜型/货运信息
  void _resetData() {
    items = [];
    presets = [];
    activePresetIds = {};
    result = null;
    selectedIndex = 0;
    shipment = ShipmentInfo();
    _nextItemId = 1;
    _colorCursor = 0;
    formGeneration++;
  }

  Future<void> _afterLogin() async {
    _resetData();
    addItem();
    addItem();
    shipment.accessories = [for (final n in defaultAccessories) Accessory(name: n)];
    await loadPresets();
  }

  Future<void> loadPresets() async {
    presetsLoading = true;
    notifyListeners();
    try {
      presets = await backend.listPresets();
      activePresetIds = {for (final p in presets) if (p.active && p.id != null) p.id!};
    } catch (e) {
      handleError(e);
    }
    presetsLoading = false;
    notifyListeners();
  }

  Future<LoginResult> login(String email, String password) async {
    final r = await backend.login(email, password);
    if (r.success) {
      user = r.user;
      flash = '';
      await _afterLogin();
      notifyListeners();
    }
    return r;
  }

  Future<void> logout({String message = ''}) async {
    try {
      await backend.logout();
    } catch (_) {/* 本地状态照样清除 */}
    user = null;
    flash = message;
    _resetData();
    notifyListeners();
  }

  void updateUser(UserProfile u) {
    user = u;
    notifyListeners();
  }

  /// 统一错误处理: 会话失效就回登录页, 其余显示提示
  void handleError(Object e) {
    if (e is SessionExpired) {
      logout(message: e.message);
    } else {
      toast(e is AppError ? e.message : '服务器错误 Server error: $e', error: true);
    }
  }

  // ---------- 物品 ----------
  void addItem() {
    items.add(Item(id: _nextItemId++, color: colorPalette[_colorCursor++ % colorPalette.length]));
    notifyListeners();
  }

  void removeItem(int id) {
    items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  /// 载入一组示例物品, 第一次使用时不用自己想数字
  void loadSample() {
    items = [
      Item(id: _nextItemId++, name: '钢管 Steel Pipe', totalPcs: 3600, pcsPerBox: 12, boxL: 60, boxW: 40, boxH: 40, boxWeight: 18, color: colorPalette[0]),
      Item(id: _nextItemId++, name: '配件盒 Parts Box', totalPcs: 8400, pcsPerBox: 20, boxL: 30, boxW: 30, boxH: 25, boxWeight: 6, color: colorPalette[1]),
      Item(id: _nextItemId++, name: '机柜 Cabinet', totalPcs: 60, pcsPerBox: 1, boxL: 100, boxW: 50, boxH: 50, boxWeight: 35, color: colorPalette[2]),
    ];
    _colorCursor = 3;
    formGeneration++;
    notifyListeners();
  }

  // ---------- 配件 ----------
  void addAccessory() {
    shipment.accessories.add(Accessory());
    notifyListeners();
  }

  void removeAccessory(Accessory a) {
    shipment.accessories.remove(a);
    notifyListeners();
  }

  // ---------- 柜型 ----------
  void togglePreset(int id, bool on) {
    on ? activePresetIds.add(id) : activePresetIds.remove(id);
    notifyListeners();
  }

  Future<bool> savePreset(Preset p) async {
    try {
      final before = {for (final x in presets) x.id};
      presets = await backend.savePreset(p);
      if (p.id == null) {
        for (final x in presets) {
          if (x.id != null && !before.contains(x.id)) activePresetIds.add(x.id!);
        }
      }
      notifyListeners();
      return true;
    } catch (e) {
      handleError(e);
      return false;
    }
  }

  // ---------- 计算 ----------
  /// 回传错误讯息 (null = 成功)
  String? calculate() {
    final errors = validateItems(items);
    final selected = presets.where((p) => p.id != null && activePresetIds.contains(p.id)).toList();
    if (selected.isEmpty) errors.add('请至少启用一种集装箱尺寸 Please enable at least one container size');
    if (errors.isNotEmpty) return errors.first;
    result = packContainers(items, selected).pushedToFarWall();
    selectedIndex = 0;
    notifyListeners();
    return null;
  }

  void selectContainer(int i) {
    selectedIndex = i;
    notifyListeners();
  }

  // ---------- 历史 ----------
  Future<void> saveHistory(String name) async {
    final r = result;
    if (r == null) return;
    await backend.saveHistory(
      name,
      {'totalItems': items.length, 'totalContainers': r.containers.length, 'summaryText': r.containers.map((c) => c.containerType).join(', ')},
      packHistory(items, r, shipment),
    );
  }

  /// 载入历史记录 (内容已清洗); 结果不可信或缺失时用物品清单重新计算
  Future<void> applyHistory(String id) async {
    final raw = await backend.loadHistory(id);
    final h = unpackHistory(raw);
    items = h.items;
    _nextItemId = items.fold(0, (m, i) => i.id > m ? i.id : m) + 1;
    if (h.shipment != null) shipment = h.shipment!;
    formGeneration++;
    if (h.result != null) {
      result = h.result;
      selectedIndex = 0;
      toast('已载入 Loaded ✓');
    } else {
      toast('已载入物品，正在重新计算... Items loaded, recalculating...');
      final err = calculate();
      if (err != null) toast(err, error: true);
    }
    notifyListeners();
  }
}
