/* ============================================================
   Supabase 后端适配层 (取代 Apps Script 的 google.script.run)
   ============================================================
   前端 (Auth / JavaScript / Render ...) 原本都是这样呼叫后端:
       google.script.run.withSuccessHandler(ok).withFailureHandler(fail).someFunction(token, ...)
   这里提供同样接口的 window.google.script.run, 函式名称、参数与回传格式都与 Code.gs 一致,
   实际改成呼叫 Supabase (登录用 Supabase Auth, 资料用带行级权限 RLS 的 Postgres 表),
   所以前端代码几乎不用改。第一个参数 token 会被忽略 —— 身份一律以 Supabase 的 session 为准。
   ============================================================ */
(function () {
  'use strict';
  const cfg = window.APP_CONFIG || {};
  const sb = window.__TEST_SB || window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  });
  window.sb = sb;

  // 同步清掉 Supabase 存在 localStorage 的登录资料 (登出后马上重新载入页面时不能等异步完成)
  window.__clearAuthStorage = function () {
    try {
      Object.keys(localStorage).filter(function (k) { return k.indexOf('sb-') === 0; })
        .forEach(function (k) { localStorage.removeItem(k); });
    } catch (e) { /* 忽略 */ }
  };

  const MSG = {
    expired: '登入已过期，请重新登入 Session expired, please log in again',
    inactive: '此帐号已被停用，请联系管理员 Account is inactive, please contact admin',
    notActive: '此帐号尚未启用，请联系管理员 This account is not yet active, please contact admin',
    badLogin: '邮箱或密码错误 Incorrect email or password',
    admin: '此操作需要管理员权限 This action requires admin access',
    noPerm: '没有权限执行此操作 No permission',
    pw6: '密码至少需要 6 个字元 Password must be at least 6 characters',
  };

  function fail(msg) { throw new Error(msg); }
  function dbError(error) {
    if (!error) return;
    const m = String(error.message || error);
    if (error.code === '42501' || /row-level security/i.test(m)) fail(MSG.noPerm);
    if (/JWT|not authenticated/i.test(m)) fail(MSG.expired);
    fail(m.replace(/^.*?exception:\s*/i, ''));
  }

  async function needSession() {
    const r = await sb.auth.getSession();
    const session = r && r.data && r.data.session;
    if (!session) fail(MSG.expired);
    return session;
  }

  function toUser(p) {
    return {
      Email: p.email, Role: p.role, Status: p.status,
      CompanyName: p.company_name || '', CompanyAddress: p.company_address || '',
      LogoDataUrl: p.logo_data_url || '',
      CreatedDate: p.created_at || '', LastLogin: p.last_login || '',
    };
  }

  async function ownProfile(session) {
    const r = await sb.from('profiles').select('*').eq('id', session.user.id).single();
    dbError(r.error);
    return r.data;
  }

  async function activeProfile() {
    const session = await needSession();
    const p = await ownProfile(session);
    if (p.status !== 'active') fail(MSG.inactive);
    return { session: session, profile: p };
  }

  async function adminOnly() {
    const a = await activeProfile();
    if (a.profile.role !== 'admin') fail(MSG.admin);
    return a;
  }

  const isEmail = function (s) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 254; };
  const logoOk = function (s) { return s === '' || (/^data:image\/(png|jpeg);base64,[A-Za-z0-9+\/=]+$/.test(s) && s.length <= 200000); };
  function fmtDate(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return String(iso || '');
    const p = function (n) { return String(n).padStart(2, '0'); };
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }

  // ---------------- 帐号 ----------------
  const handlers = {
    async loginUser(email, password) {
      email = String(email || '').trim().toLowerCase();
      if (!email || !password) return { success: false, message: '请输入邮箱与密码 Please enter email and password' };
      const r = await sb.auth.signInWithPassword({ email: email, password: String(password) });
      if (r.error || !r.data || !r.data.session) return { success: false, message: MSG.badLogin };
      const p = await ownProfile(r.data.session);
      if (p.status !== 'active') {
        await sb.auth.signOut({ scope: 'local' });
        return { success: false, message: MSG.notActive };
      }
      await sb.from('profiles').update({ last_login: new Date().toISOString() }).eq('id', p.id);
      return { success: true, token: r.data.session.access_token, user: toUser(p) };
    },

    async registerUser(email, password, companyName, companyAddress) {
      email = String(email || '').trim().toLowerCase();
      if (!email || !password) fail('请填写邮箱与密码 Email and password are required');
      if (!isEmail(email)) fail('邮箱格式不正确 Invalid email format');
      password = String(password);
      if (password.length < 6) fail(MSG.pw6);
      if (password.length > 200) fail('密码过长 Password too long');
      const r = await sb.auth.signUp({
        email: email, password: password,
        options: { data: { company_name: String(companyName || '').trim().slice(0, 100), company_address: String(companyAddress || '').trim().slice(0, 300) } },
      });
      if (r.error) {
        if (/already|registered|exists/i.test(r.error.message)) fail('此邮箱已被注册 This email is already registered');
        fail(r.error.message);
      }
      // 开启「邮箱确认」时, 已存在的邮箱会回传 identities 为空的假用户
      if (!r.data || !r.data.user || (r.data.user.identities && r.data.user.identities.length === 0)) fail('此邮箱已被注册 This email is already registered');
      if (!r.data.session) {
        return { success: true, isFirstUser: false, message: '注册成功，请先点击邮箱里的确认链接，再等待管理员启用 Registered — please confirm your email, then wait for admin approval' };
      }
      const p = await ownProfile(r.data.session);
      const isFirst = p.role === 'admin' && p.status === 'active';
      if (!isFirst) await sb.auth.signOut({ scope: 'local' }); // 待审核帐号不能保持登入
      return {
        success: true, isFirstUser: isFirst,
        message: isFirst
          ? '注册成功，已自动设为管理员，可直接登入 Registered as the first admin account, you can log in now'
          : '注册成功，请等待管理员启用此帐号后才能登入 Registered — please wait for an admin to activate your account before logging in',
      };
    },

    // 验证码由 Supabase 寄出 (需在 Auth → Email Templates → Reset Password 模板里放入 {{ .Token }})
    async requestPasswordReset(email) {
      email = String(email || '').trim().toLowerCase();
      if (isEmail(email)) { try { await sb.auth.resetPasswordForEmail(email); } catch (e) { /* 不泄露细节 */ } }
      return { success: true, message: '如果此邮箱已注册，验证码已寄出 (有效期以邮件为准)。If this email is registered, a code has been sent.' };
    },

    async resetPasswordWithCode(email, code, newPassword) {
      email = String(email || '').trim().toLowerCase();
      if (!email || !code || !newPassword) fail('请填写邮箱、验证码与新密码 Email, code and new password are required');
      if (String(newPassword).length < 6) fail(MSG.pw6);
      const v = await sb.auth.verifyOtp({ email: email, token: String(code).trim(), type: 'recovery' });
      if (v.error) fail('验证码不正确或已过期 Code incorrect or expired');
      const u = await sb.auth.updateUser({ password: String(newPassword) });
      if (u.error) fail(u.error.message);
      await sb.auth.signOut({ scope: 'global' }); // 旧登录全部失效
      window.__clearAuthStorage();
      return { success: true, message: '密码已重设，请用新密码登入 Password reset — please log in' };
    },

    async getMyProfile() {
      const a = await activeProfile();
      return toUser(a.profile);
    },

    async updateMyProfile(token, data) {
      const a = await activeProfile();
      data = data || {};
      const upd = {};
      if (data.companyName !== undefined) upd.company_name = String(data.companyName).trim().slice(0, 100);
      if (data.companyAddress !== undefined) upd.company_address = String(data.companyAddress).trim().slice(0, 300);
      if (data.logoDataUrl !== undefined) {
        if (!logoOk(String(data.logoDataUrl))) fail('Logo 图片格式不正确或太大 Invalid or too large logo image');
        upd.logo_data_url = String(data.logoDataUrl);
      }
      if (Object.keys(upd).length) {
        const r = await sb.from('profiles').update(upd).eq('id', a.profile.id);
        dbError(r.error);
      }
      return toUser(await ownProfile(a.session));
    },

    async changeMyPassword(token, oldPassword, newPassword) {
      const a = await activeProfile();
      if (!newPassword || String(newPassword).length < 6) fail('新密码至少需要 6 个字元 New password must be at least 6 characters');
      const chk = await sb.auth.signInWithPassword({ email: a.profile.email, password: String(oldPassword || '') });
      if (chk.error) fail('目前密码不正确 Current password is incorrect');
      const u = await sb.auth.updateUser({ password: String(newPassword) });
      if (u.error) fail(u.error.message);
      await sb.auth.signOut({ scope: 'global' });
      window.__clearAuthStorage();
      return { success: true, requiresRelogin: true };
    },

    // ---------------- 管理员 ----------------
    async getAllUsers() {
      await adminOnly();
      const r = await sb.from('profiles').select('*').order('created_at', { ascending: true });
      dbError(r.error);
      return r.data.map(toUser);
    },

    async adminUpdateUser(token, targetEmail, data) {
      await adminOnly();
      data = data || {};
      if (data.role !== undefined && ['admin', 'user'].indexOf(data.role) === -1) fail('角色值不正确 Invalid role');
      if (data.status !== undefined && ['active', 'inactive'].indexOf(data.status) === -1) fail('状态值不正确 Invalid status');
      const t = await sb.from('profiles').select('id').eq('email', String(targetEmail || '').toLowerCase()).maybeSingle();
      dbError(t.error);
      if (!t.data) fail('找不到此帐号 Account not found');
      const upd = {};
      if (data.role !== undefined) upd.role = data.role;
      if (data.status !== undefined) upd.status = data.status;
      if (data.companyName !== undefined) upd.company_name = String(data.companyName).trim().slice(0, 100);
      if (data.companyAddress !== undefined) upd.company_address = String(data.companyAddress).trim().slice(0, 300);
      if (data.logoDataUrl !== undefined) {
        if (!logoOk(String(data.logoDataUrl))) fail('Logo 图片格式不正确或太大 Invalid or too large logo image');
        upd.logo_data_url = String(data.logoDataUrl);
      }
      // 数据库触发器会挡下「改自己的角色/状态」; 没有实际变更的栏位原样写回不会触发错误
      const r = await sb.from('profiles').update(upd).eq('id', t.data.id);
      dbError(r.error);
      return handlers.getAllUsers();
    },

    // 需要 service role, 由 Edge Function admin-reset-password 代为执行 (函式内会再次确认呼叫者是 admin)
    async adminResetPassword(token, targetEmail, newPassword) {
      await adminOnly();
      if (!newPassword || String(newPassword).length < 6) fail('新密码至少需要 6 个字元 New password must be at least 6 characters');
      const r = await sb.functions.invoke('admin-reset-password', { body: { email: String(targetEmail || ''), newPassword: String(newPassword) } });
      if (r.error) fail('重设密码失败 Failed to reset password: ' + (r.error.message || r.error));
      if (r.data && r.data.error) fail(r.data.error);
      return { success: true };
    },

    // ---------------- 柜型预设 ----------------
    async getAllContainerPresets() {
      await activeProfile();
      const r = await sb.from('container_presets').select('*').order('id', { ascending: true });
      dbError(r.error);
      return r.data.map(function (c) {
        return {
          _row: c.id, 'Container Name': c.name, 'Length (cm)': Number(c.length_cm), 'Width (cm)': Number(c.width_cm),
          'Height (cm)': Number(c.height_cm), 'Max Payload (kg)': Number(c.max_payload_kg), 'Active': c.active, 'Owner': c.owner || '',
        };
      });
    },

    async saveContainerPreset(token, data) {
      const a = await activeProfile();
      const L = Number(data['Length (cm)']), W = Number(data['Width (cm)']), H = Number(data['Height (cm)']), P = Number(data['Max Payload (kg)']);
      const name = String(data['Container Name'] || '').trim().slice(0, 100);
      if (!name || !(L > 0) || !(W > 0) || !(H > 0) || !(P > 0)) fail('柜型名称与尺寸/载重必须填写且大于 0 Name, dimensions and payload are required');
      const row = { name: name, length_cm: L, width_cm: W, height_cm: H, max_payload_kg: P };
      if (data._row) {
        row.active = data['Active'] !== false;
        const r = await sb.from('container_presets').update(row).eq('id', Number(data._row)).select('id');
        dbError(r.error);
        if (!r.data || r.data.length === 0) fail('没有权限修改这笔资料 No permission to modify this record');
      } else {
        row.owner = a.session.user.id;
        const r = await sb.from('container_presets').insert(row);
        dbError(r.error);
      }
      return handlers.getAllContainerPresets();
    },

    async toggleContainerActive(token, row, active) {
      await activeProfile();
      const r = await sb.from('container_presets').update({ active: !!active }).eq('id', Number(row)).select('id');
      dbError(r.error);
      if (!r.data || r.data.length === 0) fail('没有权限修改这笔资料 No permission to modify this record');
      return handlers.getAllContainerPresets();
    },

    async deleteContainerPreset(token, row) {
      await activeProfile();
      const r = await sb.from('container_presets').delete().eq('id', Number(row)).select('id');
      dbError(r.error);
      if (!r.data || r.data.length === 0) fail('记录不存在或没有权限 Record not found or no permission');
      return handlers.getAllContainerPresets();
    },

    // ---------------- 计算记录 ----------------
    async saveCalculationHistory(token, name, summary, data) {
      const a = await activeProfile();
      if (!data || typeof data !== 'object') fail('记录内容格式不正确 Invalid record');
      summary = summary || {};
      const r = await sb.from('calculation_history').insert({
        owner: a.session.user.id, owner_email: a.profile.email,
        name: String(name || ('Untitled ' + new Date().toLocaleString())).slice(0, 200),
        total_items: Number(summary.totalItems) || 0, total_containers: Number(summary.totalContainers) || 0,
        summary: String(summary.summaryText || '').slice(0, 500), data: data,
      });
      dbError(r.error);
      return true;
    },

    // 列表不含 data 栏位 (可能很大), 载入时才单独取
    async getCalculationHistory() {
      await activeProfile();
      const r = await sb.from('calculation_history')
        .select('id, name, total_items, total_containers, summary, owner_email, created_at')
        .order('created_at', { ascending: false });
      dbError(r.error);
      return r.data.map(function (h) {
        return {
          id: h.id, row: h.id, date: fmtDate(h.created_at), name: h.name,
          totalItems: h.total_items, totalContainers: h.total_containers, summary: h.summary, owner: String(h.owner_email || '').toLowerCase(),
        };
      });
    },

    async loadCalculation(token, id) {
      await activeProfile();
      const r = await sb.from('calculation_history').select('data').eq('id', String(id)).maybeSingle();
      dbError(r.error);
      if (!r.data) fail('记录不存在 Record not found');
      return r.data.data;
    },

    async deleteCalculationHistory(token, id) {
      await activeProfile();
      const r = await sb.from('calculation_history').delete().eq('id', String(id)).select('id');
      dbError(r.error);
      if (!r.data || r.data.length === 0) fail('记录不存在或没有权限 Record not found or no permission');
      return handlers.getCalculationHistory();
    },
  };

  // ---------------- google.script.run 兼容层 ----------------
  function makeRunner() {
    let ok = function () {}, ko = function (e) { console.error(e); };
    const runner = new Proxy({}, {
      get: function (t, name) {
        if (name === 'withSuccessHandler') return function (f) { ok = f; return runner; };
        if (name === 'withFailureHandler') return function (f) { ko = f; return runner; };
        return function () {
          const args = Array.prototype.slice.call(arguments);
          Promise.resolve().then(function () {
            if (typeof handlers[name] !== 'function') throw new Error('Unknown server function: ' + String(name));
            return handlers[name].apply(null, args);
          }).then(function (res) { ok(res); }, function (e) { ko({ message: (e && e.message) || String(e) }); });
        };
      },
    });
    return runner;
  }
  window.google = { script: { get run() { return makeRunner(); } } };
  window.__apiHandlers = handlers; // 测试用
})();
