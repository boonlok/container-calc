/// 演示/测试用的内存后端: 行为与 Supabase 版 (schema.sql 的规则) 一致 ——
/// 第一个账号自动成为已启用的 admin, 其余待审核; 账号隔离; 共用柜型只有 admin 可改。
library;

import 'dart:convert';

import '../core/models.dart';
import 'backend.dart';

class _User {
  _User(this.email, this.password, this.role, this.status, this.companyName, this.companyAddress);
  String email, password, role, status, companyName, companyAddress, logo = '';
}

class _Hist {
  _Hist(this.id, this.owner, this.name, this.summary, this.data, this.date);
  final String id, owner, name, date;
  final Map<String, Object?> summary;
  final Map<String, Object?> data;
}

class MemoryBackend implements Backend {
  MemoryBackend() {
    for (final p in [
      ('20GP (20呎标准柜)', 589.0, 235.0, 239.0, 28180.0),
      ('40GP (40呎标准柜)', 1203.0, 235.0, 239.0, 26580.0),
      ('40HC (40呎高柜)', 1203.0, 235.0, 269.0, 28600.0),
      ('45HC (45呎高柜)', 1355.0, 235.0, 269.0, 27600.0),
    ]) {
      _presets.add(_P(_nextPresetId++, '', p.$1, p.$2, p.$3, p.$4, p.$5));
    }
  }

  @override
  bool get isDemo => true;

  final _users = <_User>[];
  final _presets = <_P>[];
  final _history = <_Hist>[];
  int _nextPresetId = 1, _nextHist = 1;
  String? _session; // 目前登入的 email
  final _resetCodes = <String, String>{};

  /// 测试用: 取得最近寄出的验证码
  String? lastResetCodeFor(String email) => _resetCodes[email.toLowerCase()];

  UserProfile _toProfile(_User u) => UserProfile(
      email: u.email, role: u.role, status: u.status, companyName: u.companyName, companyAddress: u.companyAddress, logoDataUrl: u.logo);

  _User _me() {
    final e = _session;
    final u = e == null ? null : _users.where((x) => x.email == e).firstOrNull;
    if (u == null) throw SessionExpired(msgExpired);
    if (u.status != 'active') throw SessionExpired(msgInactive);
    return u;
  }

  _User _admin() {
    final u = _me();
    if (u.role != 'admin') throw AppError(msgAdmin);
    return u;
  }

  @override
  Future<UserProfile?> restoreSession() async {
    final e = _session;
    final u = e == null ? null : _users.where((x) => x.email == e).firstOrNull;
    return (u != null && u.status == 'active') ? _toProfile(u) : null;
  }

  @override
  Future<LoginResult> login(String email, String password) async {
    email = email.trim().toLowerCase();
    final u = _users.where((x) => x.email == email && x.password == password).firstOrNull;
    if (u == null) return LoginResult.fail(msgBadLogin);
    if (u.status != 'active') return LoginResult.fail(msgNotActive);
    _session = u.email;
    return LoginResult.ok(_toProfile(u));
  }

  @override
  Future<RegisterResult> register(String email, String password, String companyName, String companyAddress) async {
    email = email.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) throw AppError('请填写邮箱与密码 Email and password are required');
    if (!isValidEmail(email)) throw AppError('邮箱格式不正确 Invalid email format');
    if (password.length < 6) throw AppError(msgPw6);
    if (_users.any((u) => u.email == email)) throw AppError('此邮箱已被注册 This email is already registered');
    final first = _users.isEmpty;
    _users.add(_User(email, password, first ? 'admin' : 'user', first ? 'active' : 'inactive', companyName.trim(), companyAddress.trim()));
    return RegisterResult(
        isFirstUser: first,
        message: first
            ? '注册成功，已自动设为管理员，可直接登入 Registered as the first admin account, you can log in now'
            : '注册成功，请等待管理员启用此帐号后才能登入 Registered — please wait for an admin to activate your account before logging in');
  }

  @override
  Future<void> logout() async => _session = null;

  @override
  Future<String> requestPasswordReset(String email) async {
    email = email.trim().toLowerCase();
    if (_users.any((u) => u.email == email)) _resetCodes[email] = '123456';
    return '如果此邮箱已注册，验证码已寄出。If this email is registered, a code has been sent.';
  }

  @override
  Future<String> resetPasswordWithCode(String email, String code, String newPassword) async {
    email = email.trim().toLowerCase();
    if (newPassword.length < 6) throw AppError(msgPw6);
    if (_resetCodes[email] != code.trim()) throw AppError('验证码不正确或已过期 Code incorrect or expired');
    _users.firstWhere((u) => u.email == email).password = newPassword;
    _resetCodes.remove(email);
    if (_session == email) _session = null;
    return '密码已重设，请用新密码登入 Password reset — please log in';
  }

  @override
  Future<UserProfile> updateProfile({String? companyName, String? companyAddress, String? logoDataUrl}) async {
    final u = _me();
    if (logoDataUrl != null && !isValidLogo(logoDataUrl)) throw AppError('Logo 图片格式不正确或太大 Invalid or too large logo image');
    if (companyName != null) u.companyName = companyName.trim();
    if (companyAddress != null) u.companyAddress = companyAddress.trim();
    if (logoDataUrl != null) u.logo = logoDataUrl;
    return _toProfile(u);
  }

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final u = _me();
    if (newPassword.length < 6) throw AppError('新密码至少需要 6 个字元 New password must be at least 6 characters');
    if (u.password != oldPassword) throw AppError('目前密码不正确 Current password is incorrect');
    u.password = newPassword;
    _session = null;
  }

  @override
  Future<List<UserProfile>> listUsers() async {
    _admin();
    return _users.map(_toProfile).toList();
  }

  @override
  Future<List<UserProfile>> adminUpdateUser(String email, {String? role, String? status, String? companyName, String? companyAddress}) async {
    final me = _admin();
    if (role != null && !['admin', 'user'].contains(role)) throw AppError('角色值不正确 Invalid role');
    if (status != null && !['active', 'inactive'].contains(status)) throw AppError('状态值不正确 Invalid status');
    final t = _users.where((u) => u.email == email.toLowerCase()).firstOrNull;
    if (t == null) throw AppError('找不到此帐号 Account not found');
    final self = t.email == me.email;
    if (role != null && role != t.role && self) throw AppError('不能修改自己的角色或状态 Cannot change your own role/status');
    if (status != null && status != t.status && self) throw AppError('不能修改自己的角色或状态 Cannot change your own role/status');
    if (role != null) t.role = role;
    if (status != null) t.status = status;
    if (companyName != null) t.companyName = companyName.trim();
    if (companyAddress != null) t.companyAddress = companyAddress.trim();
    return _users.map(_toProfile).toList();
  }

  @override
  Future<void> adminResetPassword(String email, String newPassword) async {
    _admin();
    if (newPassword.length < 6) throw AppError('新密码至少需要 6 个字元 New password must be at least 6 characters');
    final t = _users.where((u) => u.email == email.toLowerCase()).firstOrNull;
    if (t == null) throw AppError('找不到此帐号 Account not found');
    t.password = newPassword;
  }

  @override
  Future<List<Preset>> listPresets() async {
    final me = _me();
    return _presets.where((p) => p.owner.isEmpty || p.owner == me.email || me.role == 'admin').map((p) => p.toPreset()).toList();
  }

  @override
  Future<List<Preset>> savePreset(Preset p) async {
    final me = _me();
    final name = p.name.trim();
    if (name.isEmpty || !(p.length > 0) || !(p.width > 0) || !(p.height > 0) || !(p.maxPayload > 0)) {
      throw AppError('柜型名称与尺寸/载重必须填写且大于 0 Name, dimensions and payload are required');
    }
    if (p.id != null) {
      final ex = _presets.where((x) => x.id == p.id).firstOrNull;
      final can = ex != null && (me.role == 'admin' || (ex.owner.isNotEmpty && ex.owner == me.email));
      if (!can) throw AppError('没有权限修改这笔资料 No permission to modify this record');
      ex.name = name;
      ex.l = p.length;
      ex.w = p.width;
      ex.h = p.height;
      ex.payload = p.maxPayload;
      ex.active = p.active;
    } else {
      _presets.add(_P(_nextPresetId++, me.email, name, p.length, p.width, p.height, p.maxPayload));
    }
    return listPresets();
  }

  List<HistoryRow> _rows(_User me) => _history
      .where((h) => me.role == 'admin' || h.owner == me.email)
      .map((h) => HistoryRow(
          id: h.id, name: h.name, date: h.date, totalItems: (h.summary['totalItems'] as num?)?.toInt() ?? 0,
          totalContainers: (h.summary['totalContainers'] as num?)?.toInt() ?? 0, summary: '${h.summary['summaryText'] ?? ''}', owner: h.owner))
      .toList()
      .reversed
      .toList();

  @override
  Future<List<HistoryRow>> listHistory() async => _rows(_me());

  @override
  Future<void> saveHistory(String name, Map<String, Object?> summary, Map<String, Object?> data) async {
    final me = _me();
    if (jsonEncode(data).length > 2000000) throw AppError('记录内容过大，无法保存 Record too large to save');
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    _history.add(_Hist('h${_nextHist++}', me.email, name.length > 200 ? name.substring(0, 200) : name, summary,
        jsonDecode(jsonEncode(data)) as Map<String, Object?>, '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}'));
  }

  @override
  Future<Map<String, Object?>> loadHistory(String id) async {
    final me = _me();
    final h = _history.where((x) => x.id == id && (me.role == 'admin' || x.owner == me.email)).firstOrNull;
    if (h == null) throw AppError('记录不存在 Record not found');
    return h.data;
  }

  @override
  Future<List<HistoryRow>> deleteHistory(String id) async {
    final me = _me();
    final before = _history.length;
    _history.removeWhere((x) => x.id == id && (me.role == 'admin' || x.owner == me.email));
    if (_history.length == before) throw AppError('记录不存在或没有权限 Record not found or no permission');
    return _rows(me);
  }
}

class _P {
  _P(this.id, this.owner, this.name, this.l, this.w, this.h, this.payload);
  final int id;
  final String owner;
  String name;
  double l, w, h, payload;
  bool active = true;
  Preset toPreset() => Preset(id: id, name: name, length: l, width: w, height: h, maxPayload: payload, active: active, owner: owner);
}
