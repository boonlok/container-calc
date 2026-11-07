/// 管理后台: 审核账号 (启用/停用)、角色、公司资料、重设密码
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<UserProfile>? users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await widget.state.backend.listUsers();
      if (mounted) setState(() => users = u);
    } catch (e) {
      widget.state.handleError(e);
    }
  }

  Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 10.5, color: fg, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final me = widget.state.user?.email;
    final list = users;
    return Scaffold(
      appBar: AppBar(backgroundColor: navy, foregroundColor: Colors.white, title: const Text('管理后台 Admin Dashboard', style: TextStyle(fontSize: 16))),
      body: list == null
          ? const Center(child: Text('载入中... Loading...'))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text('共 ${list.length} 个帐号 — 可编辑任何人的资料、权限与启用状态 ${list.length} accounts', style: const TextStyle(fontSize: 11.5, color: textSecondary)),
              const SizedBox(height: 10),
              for (final u in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
                  child: Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${u.email}${u.email == me ? ' (you)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: navy)),
                    Text(u.companyName.isEmpty ? '未设定 not set' : u.companyName, style: const TextStyle(fontSize: 12, color: textSecondary)),
                    _badge(u.role.toUpperCase(), u.isAdmin ? const Color(0xFFFDE8D0) : const Color(0xFFE2E6EC), u.isAdmin ? const Color(0xFFC24F14) : textSecondary),
                    _badge(u.status.toUpperCase(), u.isActive ? const Color(0xFFE7F3EE) : const Color(0xFFFBEAE8), u.isActive ? greenOk : redErr),
                    OutlinedButton(onPressed: () => _edit(u), child: const Text('编辑 Edit', style: TextStyle(fontSize: 11.5))),
                  ]),
                ),
            ]),
    );
  }

  Future<void> _edit(UserProfile u) async {
    final company = TextEditingController(text: u.companyName);
    final address = TextEditingController(text: u.companyAddress);
    final pw = TextEditingController();
    var role = u.role, status = u.status;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('编辑帐号 Edit Account', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(alignment: Alignment.centerLeft, child: Text(u.email, style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(height: 12),
              TextField(controller: company, decoration: const InputDecoration(labelText: '公司名称 Company Name')),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: '公司地址 Company Address')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: '角色 Role'),
                items: const [DropdownMenuItem(value: 'user', child: Text('User')), DropdownMenuItem(value: 'admin', child: Text('Admin'))],
                onChanged: (v) => setD(() => role = v ?? role),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: '状态 Status'),
                items: const [DropdownMenuItem(value: 'active', child: Text('Active')), DropdownMenuItem(value: 'inactive', child: Text('Inactive'))],
                onChanged: (v) => setD(() => status = v ?? status),
              ),
              const SizedBox(height: 10),
              TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: '重设密码 Reset Password (留空则不变更 leave blank to keep)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消 Cancel')),
            FilledButton(
              onPressed: () async {
                final s = widget.state;
                try {
                  if (pw.text.isNotEmpty && pw.text.length < 6) {
                    s.toast('新密码至少需要 6 个字元 New password must be at least 6 characters', error: true);
                    return;
                  }
                  final next = await s.backend.adminUpdateUser(u.email, role: role, status: status, companyName: company.text, companyAddress: address.text);
                  if (pw.text.isNotEmpty) await s.backend.adminResetPassword(u.email, pw.text);
                  if (mounted) setState(() => users = next);
                  s.toast('帐号已更新 Account updated ✓');
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  s.handleError(e);
                }
              },
              child: const Text('保存 Save'),
            ),
          ],
        ),
      ),
    );
  }
}
