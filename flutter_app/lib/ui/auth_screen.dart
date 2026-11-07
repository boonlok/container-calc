/// 登入 / 注册 / 忘记密码
library;

import 'package:flutter/material.dart';

import '../core/algorithm.dart';
import '../core/models.dart';
import '../render/iso.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import 'draw_view.dart';
import 'theme.dart';

enum _Mode { login, register, forgot }

/// 登录页的装饰图: 用真实算法算出一个混装柜
final _heroArt = () {
  Item it(int id, double n, double l, double w, double h, int color) => Item(id: id, name: '', totalPcs: n, pcsPerBox: 1, boxL: l, boxW: w, boxH: h, color: color);
  final c = packContainers(
    [it(1, 240, 60, 40, 40, 0xFFE8631C), it(2, 420, 30, 30, 25, 0xFF3B9BD9), it(3, 60, 100, 50, 50, 0xFF2EBF8A), it(4, 90, 48, 40, 30, 0xFFF2B705)],
    [Preset(name: '40HC', length: 1203, width: 235, height: 269, maxPayload: 28600)],
  ).containers.first;
  return renderIso(c, IsoCamera(const Vec3(-0.62, 0.42, 0.66)), w: 560, h: 280, labels: false);
}();

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode mode = _Mode.login;
  String error = '', info = '';
  bool busy = false;

  final email = TextEditingController();
  final password = TextEditingController();
  final company = TextEditingController();
  final address = TextEditingController();
  final code = TextEditingController();
  final newPw = TextEditingController();

  @override
  void initState() {
    super.initState();
    info = widget.state.flash;
  }

  @override
  void dispose() {
    for (final c in [email, password, company, address, code, newPw]) {
      c.dispose();
    }
    super.dispose();
  }

  void _switch(_Mode m) => setState(() {
        mode = m;
        error = '';
        info = '';
      });

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = '';
      info = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = e is AppError ? e.message : '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _login() => _run(() async {
        if (email.text.trim().isEmpty || password.text.isEmpty) {
          throw AppError('请输入邮箱与密码 Please enter email and password');
        }
        final r = await widget.state.login(email.text, password.text);
        if (!r.success && mounted) setState(() => error = r.message);
      });

  Future<void> _register() => _run(() async {
        final r = await widget.state.backend.register(email.text, password.text, company.text, address.text);
        if (r.isFirstUser) {
          // 第一个帐号 (admin) 已启用 → 直接登入
          final l = await widget.state.login(email.text, password.text);
          if (!l.success && mounted) setState(() => error = l.message);
        } else if (mounted) {
          setState(() {
            mode = _Mode.login;
            info = r.message;
          });
        }
      });

  Future<void> _sendCode() => _run(() async {
        if (email.text.trim().isEmpty) throw AppError('请输入邮箱 Please enter your email');
        final m = await widget.state.backend.requestPasswordReset(email.text);
        if (mounted) setState(() => info = m);
      });

  Future<void> _reset() => _run(() async {
        final m = await widget.state.backend.resetPasswordWithCode(email.text, code.text, newPw.text);
        if (mounted) {
          setState(() {
            mode = _Mode.login;
            info = m;
            code.clear();
            newPw.clear();
          });
        }
      });

  Widget _field(String label, TextEditingController c, {bool obscure = false, VoidCallback? onSubmit, TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: kb,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _primary(String text, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: orange, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          onPressed: busy ? null : onTap,
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _link(String text, VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(foregroundColor: orange, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _formCard() => Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))]),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: orange, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.view_in_ar, color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(height: 10),
          const Text('集装箱装载计算器', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
          const Text('CONTAINER LOADING CALCULATOR', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: textSecondary, letterSpacing: 0.4)),
          const SizedBox(height: 18),
          if (widget.state.backend.isDemo) _banner('演示模式：尚未设置 Supabase，资料只在此页面内，重新整理就会消失 Demo mode: not connected to Supabase, data is not saved', const Color(0xFFFFF7E0), const Color(0xFF8A6D00)),
          if (error.isNotEmpty) _banner(error, const Color(0xFFFBEAE8), redErr),
          if (info.isNotEmpty) _banner(info, const Color(0xFFE7F3EE), greenOk),
          ..._form(),
        ]),
      );

  Widget _hero() => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('算得准，装得快', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)),
          const SizedBox(height: 4),
          const Text('Plan it right. Load it fast.', style: TextStyle(fontSize: 16, color: Color(0xFFB9C7D8))),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 560, height: 280, child: CustomPaint(painter: DrawListPainter(_heroArt))),
          ),
          const SizedBox(height: 22),
          _point(Icons.bolt, '几秒算出最省的柜型组合', 'The cheapest container mix in seconds'),
          _point(Icons.phone_iphone, '工人手机扫码，一列一列照着装', 'Workers scan and follow column by column'),
          _point(Icons.picture_as_pdf_outlined, '一键导出 A3 装柜方案 PDF', 'One-click A3 loading plan PDF'),
        ]),
      );

  Widget _point(IconData icon, String zh, String en) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: const Color(0xFFFFB27F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(zh, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
              Text(en, style: const TextStyle(color: Color(0xFF9FB0C3), fontSize: 11.5)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [navy, navyLight])),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 1040;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: wide
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [_hero(), const SizedBox(width: 56), _formCard()])
                    : _formCard(),
              ),
            );
          }),
        ),
      );

  Widget _banner(String t, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 12.5)),
      );

  List<Widget> _form() {
    switch (mode) {
      case _Mode.login:
        return [
          _field('邮箱 Email', email, kb: TextInputType.emailAddress),
          _field('密码 Password', password, obscure: true, onSubmit: _login),
          _primary(busy ? '登入中... Logging in...' : '登入 Log In', _login),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _link('注册新帐号 Register', () => _switch(_Mode.register)),
            _link('忘记密码 Forgot password?', () => _switch(_Mode.forgot)),
          ]),
        ];
      case _Mode.register:
        return [
          _field('邮箱 Email', email, kb: TextInputType.emailAddress),
          _field('密码 Password (至少6个字元 min 6 chars)', password, obscure: true),
          _field('公司名称 Company Name (选填 optional)', company),
          _field('公司地址 Company Address (选填 optional)', address),
          _primary(busy ? '注册中... Registering...' : '注册 Register', _register),
          const SizedBox(height: 10),
          Center(child: _link('返回登入 Back to Log In', () => _switch(_Mode.login))),
        ];
      case _Mode.forgot:
        return [
          _field('邮箱 Email', email, kb: TextInputType.emailAddress),
          OutlinedButton(onPressed: busy ? null : _sendCode, child: const Text('寄送验证码 Send Code')),
          const SizedBox(height: 12),
          _field('验证码 Code', code, kb: TextInputType.number),
          _field('新密码 New Password (至少6个字元 min 6 chars)', newPw, obscure: true),
          _primary('重设密码 Reset Password', _reset),
          const SizedBox(height: 10),
          Center(child: _link('返回登入 Back to Log In', () => _switch(_Mode.login))),
        ];
    }
  }
}
