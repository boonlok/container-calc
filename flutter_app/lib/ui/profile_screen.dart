/// 我的资料: 公司名称/地址/Logo、修改密码
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/backend.dart';
import '../services/download.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// 把图片缩到不超过 maxDim, 并确保 data URL 不超过 limit 字元 (太大就继续缩小), 保留透明
Future<String> resizeLogo(Uint8List bytes, {int maxDim = 300, int limit = 45000}) async {
  var dim = maxDim;
  while (true) {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    final w = first.width, h = first.height;
    first.dispose();
    final scale = (w > h ? dim / w : dim / h).clamp(0.0, 1.0);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: (w * scale).round().clamp(1, 4096), targetHeight: (h * scale).round().clamp(1, 4096));
    final img = (await codec.getNextFrame()).image;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    final url = 'data:image/png;base64,${base64Encode(png!.buffer.asUint8List())}';
    if (url.length <= limit || dim <= 48) return url;
    dim = (dim * 0.75).round();
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController company, address;
  final oldPw = TextEditingController(), newPw = TextEditingController();
  late String logo;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final u = widget.state.user!;
    company = TextEditingController(text: u.companyName);
    address = TextEditingController(text: u.companyAddress);
    logo = u.logoDataUrl;
  }

  @override
  void dispose() {
    for (final c in [company, address, oldPw, newPw]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final bytes = await pickImageBytes();
    if (bytes == null) return;
    try {
      final url = await resizeLogo(bytes);
      if (mounted) setState(() => logo = url);
    } catch (_) {
      widget.state.toast('图片读取失败 Failed to read image', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final u = await widget.state.backend.updateProfile(companyName: company.text, companyAddress: address.text, logoDataUrl: logo);
      widget.state.updateUser(u);
      widget.state.toast('资料已保存 Profile saved ✓');
    } catch (e) {
      widget.state.handleError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _changePw() async {
    if (oldPw.text.isEmpty || newPw.text.isEmpty) {
      widget.state.toast('请填写目前密码与新密码 Please fill in both password fields', error: true);
      return;
    }
    setState(() => busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.state.backend.changePassword(oldPw.text, newPw.text);
      nav.popUntil((r) => r.isFirst);
      await widget.state.logout(message: '密码已修改，请重新登入 Password changed, please log in again');
      return;
    } catch (e) {
      if (e is AppError) {
        widget.state.handleError(e);
      } else {
        widget.state.toast('修改密码失败 Failed to change password: $e', error: true);
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.state.user;
    return Scaffold(
      appBar: AppBar(backgroundColor: navy, foregroundColor: Colors.white, title: const Text('我的资料 My Profile', style: TextStyle(fontSize: 16))),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                SectionCard(
                  title: '公司资料 Company',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(enabled: false, controller: TextEditingController(text: u?.email ?? ''), decoration: const InputDecoration(labelText: '邮箱 Email')),
                    const SizedBox(height: 12),
                    TextField(controller: company, decoration: const InputDecoration(labelText: '公司名称 Company Name')),
                    const SizedBox(height: 12),
                    TextField(controller: address, decoration: const InputDecoration(labelText: '公司地址 Company Address')),
                    const SizedBox(height: 12),
                    const Text('公司标志 Company Logo (会显示在 PDF 表头，建议透明底 PNG — shown in PDF header)', style: TextStyle(fontSize: 12, color: textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      OutlinedButton(onPressed: _pickLogo, child: const Text('选择图片 Choose Image')),
                      if (logo.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(5)),
                          child: Image.memory(base64Decode(logo.split(',').last), height: 60, errorBuilder: (_, _, _) => const Text('?')),
                        ),
                        IconButton(tooltip: '移除 Remove', icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => logo = '')),
                      ],
                    ]),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: busy ? null : _save, child: const Text('保存 Save')),
                  ]),
                ),
                SectionCard(
                  title: '修改密码 Change Password',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: oldPw, obscureText: true, decoration: const InputDecoration(labelText: '目前密码 Current Password')),
                    const SizedBox(height: 12),
                    TextField(controller: newPw, obscureText: true, decoration: const InputDecoration(labelText: '新密码 New Password')),
                    const SizedBox(height: 14),
                    OutlinedButton(onPressed: busy ? null : _changePw, child: const Text('修改密码 Change Password')),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
