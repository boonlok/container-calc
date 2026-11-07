/// 后端接口 Backend interface
///
/// 两种实现: SupabaseBackend (正式) 与 MemoryBackend (未设置 Supabase 时的演示模式, 也用于测试)。
/// 所有错误都以 AppError 抛出, 讯息是中英双语, 界面直接显示。
library;

import '../core/models.dart';

class AppError implements Exception {
  AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 会话失效 (过期/被停用/被撤销): 界面应回到登录页
class SessionExpired extends AppError {
  SessionExpired(super.message);
}

class LoginResult {
  LoginResult.ok(this.user) : message = '';
  LoginResult.fail(this.message) : user = null;
  final UserProfile? user;
  final String message;
  bool get success => user != null;
}

class RegisterResult {
  RegisterResult({required this.isFirstUser, required this.message});
  final bool isFirstUser;
  final String message;
}

abstract class Backend {
  /// 演示模式: 资料只存在内存里, 重新整理页面就消失
  bool get isDemo;

  Future<UserProfile?> restoreSession();
  Future<LoginResult> login(String email, String password);
  Future<RegisterResult> register(String email, String password, String companyName, String companyAddress);
  Future<void> logout();
  Future<String> requestPasswordReset(String email);
  Future<String> resetPasswordWithCode(String email, String code, String newPassword);

  Future<UserProfile> updateProfile({String? companyName, String? companyAddress, String? logoDataUrl});
  Future<void> changePassword(String oldPassword, String newPassword);

  // 管理员
  Future<List<UserProfile>> listUsers();
  Future<List<UserProfile>> adminUpdateUser(String email, {String? role, String? status, String? companyName, String? companyAddress});
  Future<void> adminResetPassword(String email, String newPassword);

  // 柜型
  Future<List<Preset>> listPresets();
  Future<List<Preset>> savePreset(Preset p);

  // 历史记录
  Future<List<HistoryRow>> listHistory();
  Future<void> saveHistory(String name, Map<String, Object?> summary, Map<String, Object?> data);
  Future<Map<String, Object?>> loadHistory(String id);
  Future<List<HistoryRow>> deleteHistory(String id);
}

bool isValidEmail(String s) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s) && s.length <= 254;
bool isValidLogo(String s) =>
    s.isEmpty || (RegExp(r'^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$').hasMatch(s) && s.length <= 200000);

const msgExpired = '登入已过期，请重新登入 Session expired, please log in again';
const msgInactive = '此帐号已被停用，请联系管理员 Account is inactive, please contact admin';
const msgNotActive = '此帐号尚未启用，请联系管理员 This account is not yet active, please contact admin';
const msgBadLogin = '邮箱或密码错误 Incorrect email or password';
const msgAdmin = '此操作需要管理员权限 This action requires admin access';
const msgPw6 = '密码至少需要 6 个字元 Password must be at least 6 characters';
