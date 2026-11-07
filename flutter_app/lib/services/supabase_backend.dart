/// Supabase 后端: 对应 web/supabase/schema.sql (账号隔离由数据库的行级权限 RLS 强制执行)
library;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/models.dart';
import 'backend.dart';

class SupabaseBackend implements Backend {
  SupabaseBackend(this.client);
  final sb.SupabaseClient client;

  static Future<SupabaseBackend> init(String url, String anonKey) async {
    await sb.Supabase.initialize(url: url, publishableKey: anonKey);
    return SupabaseBackend(sb.Supabase.instance.client);
  }

  @override
  bool get isDemo => false;

  sb.GoTrueClient get _auth => client.auth;

  AppError _err(Object e) {
    if (e is AppError) return e;
    if (e is sb.PostgrestException) {
      final m = e.message;
      if (e.code == '42501' || RegExp('row-level security', caseSensitive: false).hasMatch(m)) {
        return AppError('没有权限执行此操作 No permission');
      }
      if (RegExp('JWT', caseSensitive: false).hasMatch(m)) return SessionExpired(msgExpired);
      return AppError(m.replaceFirst(RegExp(r'^.*?exception:\s*', caseSensitive: false), ''));
    }
    if (e is sb.AuthException) return AppError(e.message);
    return AppError('$e');
  }

  UserProfile _toUser(Map<String, dynamic> p) => UserProfile(
        email: '${p['email']}', role: '${p['role']}', status: '${p['status']}',
        companyName: '${p['company_name'] ?? ''}', companyAddress: '${p['company_address'] ?? ''}',
        logoDataUrl: '${p['logo_data_url'] ?? ''}',
      );

  Future<Map<String, dynamic>> _ownProfile() async {
    final u = _auth.currentUser;
    if (u == null) throw SessionExpired(msgExpired);
    try {
      return await client.from('profiles').select().eq('id', u.id).single();
    } catch (e) {
      if (e is sb.PostgrestException && e.code == 'PGRST116') throw SessionExpired(msgExpired); // 找不到 = 已被删除
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> _active() async {
    final p = await _ownProfile();
    if (p['status'] != 'active') throw SessionExpired(msgInactive);
    return p;
  }

  Future<Map<String, dynamic>> _adminOnly() async {
    final p = await _active();
    if (p['role'] != 'admin') throw AppError(msgAdmin);
    return p;
  }

  @override
  Future<UserProfile?> restoreSession() async {
    if (_auth.currentSession == null) return null;
    try {
      final p = await _ownProfile();
      if (p['status'] != 'active') {
        await _auth.signOut(scope: sb.SignOutScope.local);
        return null;
      }
      return _toUser(p);
    } catch (_) {
      await _auth.signOut(scope: sb.SignOutScope.local);
      return null;
    }
  }

  @override
  Future<LoginResult> login(String email, String password) async {
    email = email.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) return LoginResult.fail('请输入邮箱与密码 Please enter email and password');
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } catch (_) {
      return LoginResult.fail(msgBadLogin);
    }
    final p = await _ownProfile();
    if (p['status'] != 'active') {
      await _auth.signOut(scope: sb.SignOutScope.local);
      return LoginResult.fail(msgNotActive);
    }
    try {
      await client.from('profiles').update({'last_login': DateTime.now().toUtc().toIso8601String()}).eq('id', p['id']);
    } catch (_) {/* 不影响登入 */}
    return LoginResult.ok(_toUser(p));
  }

  @override
  Future<RegisterResult> register(String email, String password, String companyName, String companyAddress) async {
    email = email.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) throw AppError('请填写邮箱与密码 Email and password are required');
    if (!isValidEmail(email)) throw AppError('邮箱格式不正确 Invalid email format');
    if (password.length < 6) throw AppError(msgPw6);
    if (password.length > 200) throw AppError('密码过长 Password too long');
    final cn = companyName.trim(), ca = companyAddress.trim();
    sb.AuthResponse r;
    try {
      r = await _auth.signUp(email: email, password: password, data: {
        'company_name': cn.length > 100 ? cn.substring(0, 100) : cn,
        'company_address': ca.length > 300 ? ca.substring(0, 300) : ca,
      });
    } on sb.AuthException catch (e) {
      if (RegExp('already|registered|exists', caseSensitive: false).hasMatch(e.message)) {
        throw AppError('此邮箱已被注册 This email is already registered');
      }
      throw AppError(e.message);
    }
    // 开启「邮箱确认」时, 已存在的邮箱会回传 identities 为空的假用户
    final u = r.user;
    if (u == null || (u.identities != null && u.identities!.isEmpty)) throw AppError('此邮箱已被注册 This email is already registered');
    if (r.session == null) {
      return RegisterResult(
          isFirstUser: false,
          message: '注册成功，请先点击邮箱里的确认链接，再等待管理员启用 Registered — please confirm your email, then wait for admin approval');
    }
    final p = await _ownProfile();
    final first = p['role'] == 'admin' && p['status'] == 'active';
    if (!first) await _auth.signOut(scope: sb.SignOutScope.local); // 待审核帐号不能保持登入
    return RegisterResult(
        isFirstUser: first,
        message: first
            ? '注册成功，已自动设为管理员，可直接登入 Registered as the first admin account, you can log in now'
            : '注册成功，请等待管理员启用此帐号后才能登入 Registered — please wait for an admin to activate your account before logging in');
  }

  @override
  Future<void> logout() => _auth.signOut(scope: sb.SignOutScope.local);

  @override
  Future<String> requestPasswordReset(String email) async {
    email = email.trim().toLowerCase();
    if (isValidEmail(email)) {
      try {
        await _auth.resetPasswordForEmail(email);
      } catch (_) {/* 不泄露细节 */}
    }
    return '如果此邮箱已注册，验证码已寄出 (有效期以邮件为准)。If this email is registered, a code has been sent.';
  }

  @override
  Future<String> resetPasswordWithCode(String email, String code, String newPassword) async {
    email = email.trim().toLowerCase();
    if (email.isEmpty || code.isEmpty || newPassword.isEmpty) throw AppError('请填写邮箱、验证码与新密码 Email, code and new password are required');
    if (newPassword.length < 6) throw AppError(msgPw6);
    try {
      await _auth.verifyOTP(email: email, token: code.trim(), type: sb.OtpType.recovery);
    } catch (_) {
      throw AppError('验证码不正确或已过期 Code incorrect or expired');
    }
    try {
      await _auth.updateUser(sb.UserAttributes(password: newPassword));
      await _auth.signOut(scope: sb.SignOutScope.global); // 旧登录全部失效
    } catch (e) {
      throw _err(e);
    }
    return '密码已重设，请用新密码登入 Password reset — please log in';
  }

  @override
  Future<UserProfile> updateProfile({String? companyName, String? companyAddress, String? logoDataUrl}) async {
    final me = await _active();
    final upd = <String, Object?>{};
    if (companyName != null) upd['company_name'] = companyName.trim().length > 100 ? companyName.trim().substring(0, 100) : companyName.trim();
    if (companyAddress != null) {
      upd['company_address'] = companyAddress.trim().length > 300 ? companyAddress.trim().substring(0, 300) : companyAddress.trim();
    }
    if (logoDataUrl != null) {
      if (!isValidLogo(logoDataUrl)) throw AppError('Logo 图片格式不正确或太大 Invalid or too large logo image');
      upd['logo_data_url'] = logoDataUrl;
    }
    try {
      if (upd.isNotEmpty) await client.from('profiles').update(upd).eq('id', me['id']);
      return _toUser(await _ownProfile());
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final me = await _active();
    if (newPassword.length < 6) throw AppError('新密码至少需要 6 个字元 New password must be at least 6 characters');
    try {
      await _auth.signInWithPassword(email: '${me['email']}', password: oldPassword);
    } catch (_) {
      throw AppError('目前密码不正确 Current password is incorrect');
    }
    try {
      await _auth.updateUser(sb.UserAttributes(password: newPassword));
      await _auth.signOut(scope: sb.SignOutScope.global);
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<UserProfile>> listUsers() async {
    await _adminOnly();
    try {
      final rows = await client.from('profiles').select().order('created_at', ascending: true);
      return rows.map<UserProfile>((r) => _toUser(r)).toList();
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<UserProfile>> adminUpdateUser(String email, {String? role, String? status, String? companyName, String? companyAddress}) async {
    await _adminOnly();
    if (role != null && !['admin', 'user'].contains(role)) throw AppError('角色值不正确 Invalid role');
    if (status != null && !['active', 'inactive'].contains(status)) throw AppError('状态值不正确 Invalid status');
    try {
      final t = await client.from('profiles').select('id').eq('email', email.toLowerCase()).maybeSingle();
      if (t == null) throw AppError('找不到此帐号 Account not found');
      final upd = <String, Object?>{
        'role': ?role,
        'status': ?status,
        if (companyName != null) 'company_name': companyName.trim(),
        if (companyAddress != null) 'company_address': companyAddress.trim(),
      };
      // 数据库触发器会挡下「改自己的角色/状态」; 原样写回没有变更的值不会触发错误
      if (upd.isNotEmpty) await client.from('profiles').update(upd).eq('id', t['id']);
    } catch (e) {
      throw _err(e);
    }
    return listUsers();
  }

  @override
  Future<void> adminResetPassword(String email, String newPassword) async {
    await _adminOnly();
    if (newPassword.length < 6) throw AppError('新密码至少需要 6 个字元 New password must be at least 6 characters');
    try {
      final r = await client.functions.invoke('admin-reset-password', body: {'email': email, 'newPassword': newPassword});
      final data = r.data;
      if (data is Map && data['error'] != null) throw AppError('${data['error']}');
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError('重设密码失败 Failed to reset password: ${e is sb.FunctionException ? (e.details ?? e.reasonPhrase ?? e) : e}');
    }
  }

  Preset _toPreset(Map<String, dynamic> c) => Preset(
        id: (c['id'] as num).toInt(), name: '${c['name']}', length: (c['length_cm'] as num).toDouble(),
        width: (c['width_cm'] as num).toDouble(), height: (c['height_cm'] as num).toDouble(),
        maxPayload: (c['max_payload_kg'] as num).toDouble(), active: c['active'] != false, owner: '${c['owner'] ?? ''}',
      );

  @override
  Future<List<Preset>> listPresets() async {
    await _active();
    try {
      final rows = await client.from('container_presets').select().order('id', ascending: true);
      return rows.map<Preset>(_toPreset).toList();
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<Preset>> savePreset(Preset p) async {
    final me = await _active();
    final name = p.name.trim();
    if (name.isEmpty || !(p.length > 0) || !(p.width > 0) || !(p.height > 0) || !(p.maxPayload > 0)) {
      throw AppError('柜型名称与尺寸/载重必须填写且大于 0 Name, dimensions and payload are required');
    }
    final row = <String, Object?>{
      'name': name.length > 100 ? name.substring(0, 100) : name,
      'length_cm': p.length, 'width_cm': p.width, 'height_cm': p.height, 'max_payload_kg': p.maxPayload,
    };
    try {
      if (p.id != null) {
        row['active'] = p.active;
        final r = await client.from('container_presets').update(row).eq('id', p.id!).select('id');
        if (r.isEmpty) throw AppError('没有权限修改这笔资料 No permission to modify this record');
      } else {
        row['owner'] = me['id'];
        await client.from('container_presets').insert(row);
      }
    } catch (e) {
      throw _err(e);
    }
    return listPresets();
  }

  HistoryRow _toRow(Map<String, dynamic> h) {
    final d = DateTime.tryParse('${h['created_at']}')?.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return HistoryRow(
      id: '${h['id']}', name: '${h['name']}',
      date: d == null ? '${h['created_at']}' : '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}',
      totalItems: (h['total_items'] as num?)?.toInt() ?? 0, totalContainers: (h['total_containers'] as num?)?.toInt() ?? 0,
      summary: '${h['summary'] ?? ''}', owner: '${h['owner_email'] ?? ''}'.toLowerCase(),
    );
  }

  @override
  Future<List<HistoryRow>> listHistory() async {
    await _active();
    try {
      // 列表不含 data 栏位 (可能很大), 载入时才单独取
      final rows = await client
          .from('calculation_history')
          .select('id, name, total_items, total_containers, summary, owner_email, created_at')
          .order('created_at', ascending: false);
      return rows.map<HistoryRow>(_toRow).toList();
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<void> saveHistory(String name, Map<String, Object?> summary, Map<String, Object?> data) async {
    final me = await _active();
    final nm = name.isEmpty ? 'Untitled ${DateTime.now()}' : name;
    final st = '${summary['summaryText'] ?? ''}';
    try {
      await client.from('calculation_history').insert({
        'owner': me['id'], 'owner_email': me['email'], 'name': nm.length > 200 ? nm.substring(0, 200) : nm,
        'total_items': (summary['totalItems'] as num?)?.toInt() ?? 0, 'total_containers': (summary['totalContainers'] as num?)?.toInt() ?? 0,
        'summary': st.length > 500 ? st.substring(0, 500) : st, 'data': data,
      });
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<Map<String, Object?>> loadHistory(String id) async {
    await _active();
    try {
      final r = await client.from('calculation_history').select('data').eq('id', id).maybeSingle();
      if (r == null) throw AppError('记录不存在 Record not found');
      return (r['data'] as Map).cast<String, Object?>();
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<HistoryRow>> deleteHistory(String id) async {
    await _active();
    try {
      final r = await client.from('calculation_history').delete().eq('id', id).select('id');
      if (r.isEmpty) throw AppError('记录不存在或没有权限 Record not found or no permission');
    } catch (e) {
      throw _err(e);
    }
    return listHistory();
  }
}
