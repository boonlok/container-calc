// 测试 api-supabase.js (google.script.run 兼容层): 用内存版的假 Supabase 客户端验证
// 函式名称、参数、回传格式、错误讯息与 Code.gs 一致。行级权限本身由 rls.test.mjs 验证。
import fs from 'fs';
import vm from 'vm';
import path from 'path';
import { fileURLToPath } from 'url';

const dir = path.dirname(fileURLToPath(import.meta.url));
let failed = 0;
const t = (name, ok, extra) => { if (!ok) failed++; console.log(ok ? 'PASS' : 'FAIL', name, extra || ''); };

function makeFake() {
  const tables = { profiles: [], container_presets: [{ id: 1, owner: null, name: 'Shared', length_cm: 589, width_cm: 235, height_cm: 239, max_payload_kg: 28180, active: true }], calculation_history: [] };
  const users = []; let session = null; let seq = 100; const mails = [];
  const uuid = () => 'id-' + (++seq);
  function builder(table) {
    let op = 'select', payload = null, filters = [], ordering = null, mode = null, returning = false;
    const run = () => {
      const rows = tables[table];
      const match = rows.filter(r => filters.every(([c, v]) => String(r[c]) === String(v)));
      if (op === 'insert') { const r = Object.assign({ id: table === 'calculation_history' ? uuid() : ++seq, created_at: new Date().toISOString() }, payload); rows.push(r); return { data: returning ? [r] : null, error: null }; }
      if (op === 'update') { match.forEach(r => Object.assign(r, payload)); return { data: returning ? match : null, error: null }; }
      if (op === 'delete') { match.forEach(r => rows.splice(rows.indexOf(r), 1)); return { data: returning ? match : null, error: null }; }
      let out = match.slice();
      if (ordering) out.sort((a, b) => (a[ordering.c] > b[ordering.c] ? 1 : -1) * (ordering.asc ? 1 : -1));
      if (mode === 'single') return out.length === 1 ? { data: out[0], error: null } : { data: null, error: { message: 'row not found' } };
      if (mode === 'maybe') return { data: out[0] || null, error: null };
      return { data: out, error: null };
    };
    const b = {
      select() { if (op !== 'select') returning = true; return b; },
      insert(p) { op = 'insert'; payload = p; return b; }, update(p) { op = 'update'; payload = p; return b; }, delete() { op = 'delete'; return b; },
      eq(c, v) { filters.push([c, v]); return b; }, order(c, o) { ordering = { c, asc: !o || o.ascending !== false }; return b; },
      single() { mode = 'single'; return b; }, maybeSingle() { mode = 'maybe'; return b; },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
    };
    return b;
  }
  const fake = {
    tables, mails, users,
    from: builder,
    auth: {
      async getSession() { return { data: { session } }; },
      async signUp({ email, password, options }) {
        if (users.some(u => u.email === email)) return { data: {}, error: { message: 'User already registered' } };
        const u = { id: uuid(), email, password }; users.push(u);
        const first = tables.profiles.length === 0;
        tables.profiles.push({ id: u.id, email, role: first ? 'admin' : 'user', status: first ? 'active' : 'inactive', company_name: (options.data || {}).company_name || '', company_address: '', logo_data_url: '', created_at: new Date().toISOString() });
        session = { access_token: 'tok-' + u.id, user: { id: u.id, email } };
        return { data: { user: { id: u.id, identities: [{}] }, session }, error: null };
      },
      async signInWithPassword({ email, password }) {
        const u = users.find(x => x.email === email && x.password === password);
        if (!u) return { data: {}, error: { message: 'Invalid login credentials' } };
        session = { access_token: 'tok-' + u.id, user: { id: u.id, email } };
        return { data: { session, user: session.user }, error: null };
      },
      async signOut() { session = null; return { error: null }; },
      async resetPasswordForEmail(email) { if (users.some(u => u.email === email)) mails.push({ email, code: '123456' }); return { error: null }; },
      async verifyOtp({ email, token }) {
        if (!mails.some(m => m.email === email && m.code === token)) return { data: {}, error: { message: 'bad otp' } };
        const u = users.find(x => x.email === email); session = { access_token: 'rec', user: { id: u.id, email } };
        return { data: { session }, error: null };
      },
      async updateUser({ password }) { const u = users.find(x => x.id === session.user.id); u.password = password; return { data: {}, error: null }; },
    },
    functions: { async invoke(name, { body }) { fake.invoked = { name, body }; return { data: { success: true }, error: null }; } },
  };
  return fake;
}

const sb = makeFake();
const storage = {};
const win = { APP_CONFIG: {}, __TEST_SB: sb, localStorage: { getItem: k => storage[k] ?? null, setItem: (k, v) => { storage[k] = v; }, removeItem: k => { delete storage[k]; } } };
win.window = win;
const ctx = vm.createContext(Object.assign(win, { Object, Promise, Proxy, console, Date, Number, String, Array, Error, JSON, Math, isNaN, Function }));
// localStorage.keys: Object.keys(localStorage) 需要能列出键
Object.defineProperty(win, 'localStorage', { value: new Proxy({ getItem: k => storage[k] ?? null, setItem: (k, v) => { storage[k] = v; }, removeItem: k => { delete storage[k]; } }, { ownKeys: () => Object.keys(storage), getOwnPropertyDescriptor: (o, k) => (k in storage ? { enumerable: true, configurable: true, value: storage[k] } : Object.getOwnPropertyDescriptor(o, k)) }) });
vm.runInContext(fs.readFileSync(path.join(dir, '..', 'api-supabase.js'), 'utf8'), ctx);

const h = win.__apiHandlers;
const thr = async (f) => { try { await f(); return null; } catch (e) { return e.message; } };

// ---- 注册 / 登录 ----
const r1 = await h.registerUser('Admin@X.com', 'secret1', 'A Co', '');
t('first register -> isFirstUser, stays logged in', r1.success && r1.isFirstUser && !!(await sb.auth.getSession()).data.session);
await sb.auth.signOut();
const r2 = await h.registerUser('u1@x.com', 'secret1', 'B Co', '');
t('second register -> pending, signed out', r2.success && !r2.isFirstUser && !(await sb.auth.getSession()).data.session);
t('duplicate email rejected', /已被注册/.test(await thr(() => h.registerUser('u1@x.com', 'secret1', '', '')) || ''));
t('short password rejected', /至少需要 6/.test(await thr(() => h.registerUser('z@x.com', '123', '', '')) || ''));
t('bad email rejected', /格式不正确/.test(await thr(() => h.registerUser('nope', 'secret1', '', '')) || ''));
const li = await h.loginUser('u1@x.com', 'secret1');
t('inactive login blocked with message', li.success === false && /尚未启用/.test(li.message) && !(await sb.auth.getSession()).data.session);
t('wrong password -> generic message', (await h.loginUser('u1@x.com', 'wrong')).message.indexOf('邮箱或密码错误') === 0);
const la = await h.loginUser('admin@x.com', 'secret1');
t('admin login returns token + Code.gs-shaped user', la.success && !!la.token && la.user.Email === 'admin@x.com' && la.user.Role === 'admin' && la.user.CompanyName === 'A Co');
t('getMyProfile ok', (await h.getMyProfile()).Email === 'admin@x.com');
await sb.auth.signOut();
const noSess = await thr(() => h.getMyProfile());
t('no session -> expired message matches forced-logout regex', /过期/.test(noSess || ''), noSess);

// ---- 管理员 ----
await h.loginUser('admin@x.com', 'secret1');
t('getAllUsers returns 2', (await h.getAllUsers()).length === 2);
t('invalid role rejected', /角色值不正确/.test(await thr(() => h.adminUpdateUser('', 'u1@x.com', { role: '<img>' })) || ''));
const upd = await h.adminUpdateUser('', 'u1@x.com', { status: 'active', companyName: 'B2' });
t('adminUpdateUser activates + returns user list', upd.find(u => u.Email === 'u1@x.com').Status === 'active' && upd.find(u => u.Email === 'u1@x.com').CompanyName === 'B2');
t('unknown account', /找不到/.test(await thr(() => h.adminUpdateUser('', 'ghost@x.com', {})) || ''));
t('adminResetPassword calls edge function', (await h.adminResetPassword('', 'u1@x.com', 'newpass1')).success && sb.invoked.name === 'admin-reset-password' && sb.invoked.body.email === 'u1@x.com');
await sb.auth.signOut();
await h.loginUser('u1@x.com', 'secret1');
t('non-admin cannot list users', /管理员权限/.test(await thr(() => h.getAllUsers()) || ''));

// ---- 资料 / 密码 ----
const prof = await h.updateMyProfile('', { companyName: 'New Co', logoDataUrl: 'data:image/png;base64,AAAA' });
t('updateMyProfile returns updated user', prof.CompanyName === 'New Co' && prof.LogoDataUrl.length > 0);
t('bad logo rejected', /Logo/.test(await thr(() => h.updateMyProfile('', { logoDataUrl: 'javascript:alert(1)' })) || ''));
t('wrong current password rejected', /目前密码不正确/.test(await thr(() => h.changeMyPassword('', 'bad', 'another1')) || ''));
const cp = await h.changeMyPassword('', 'secret1', 'another1');
t('changeMyPassword requires relogin', cp.success && cp.requiresRelogin && !(await sb.auth.getSession()).data.session);
t('login with new password', (await h.loginUser('u1@x.com', 'another1')).success);
await sb.auth.signOut();

// ---- 忘记密码 ----
const g1 = await h.requestPasswordReset('u1@x.com'), g2 = await h.requestPasswordReset('nobody@x.com');
t('reset request: same message either way', g1.message === g2.message && sb.mails.length === 1);
t('wrong code rejected', /不正确|过期/.test(await thr(() => h.resetPasswordWithCode('u1@x.com', '000000', 'brandnew1')) || ''));
const rr = await h.resetPasswordWithCode('u1@x.com', '123456', 'brandnew1');
t('reset with code ok, then login works', rr.success && (await h.loginUser('u1@x.com', 'brandnew1')).success);

// ---- 柜型 ----
let presets = await h.getAllContainerPresets();
t('presets mapped to sheet-style keys', presets[0]._row === 1 && presets[0]['Container Name'] === 'Shared' && presets[0]['Length (cm)'] === 589 && presets[0]['Owner'] === '');
presets = await h.saveContainerPreset('', { 'Container Name': 'MyBox', 'Length (cm)': 500, 'Width (cm)': 200, 'Height (cm)': 200, 'Max Payload (kg)': 1000 });
const mine = presets.find(p => p['Container Name'] === 'MyBox');
t('new preset saved with owner = me', !!mine && mine['Owner'] !== '' && presets.length === 2);
t('invalid preset rejected', !!(await thr(() => h.saveContainerPreset('', { 'Container Name': '', 'Length (cm)': 0 }))));
const edited = await h.saveContainerPreset('', { _row: mine._row, 'Container Name': 'MyBox2', 'Length (cm)': 510, 'Width (cm)': 200, 'Height (cm)': 200, 'Max Payload (kg)': 1000 });
t('edit preset by _row', edited.find(p => p._row === mine._row)['Container Name'] === 'MyBox2');
t('edit missing/foreign row -> no permission', /没有权限/.test(await thr(() => h.saveContainerPreset('', { _row: 9999, 'Container Name': 'x', 'Length (cm)': 1, 'Width (cm)': 1, 'Height (cm)': 1, 'Max Payload (kg)': 1 })) || ''));

// ---- 历史 ----
await h.saveCalculationHistory('', 'calc1', { totalItems: 2, totalContainers: 1, summaryText: '20GP' }, { v: 2, z: 'abc' });
let hl = await h.getCalculationHistory();
t('history list shape (id/row/date/name/owner), no data column', hl.length === 1 && !!hl[0].id && hl[0].id === hl[0].row && hl[0].name === 'calc1' && hl[0].owner === 'u1@x.com' && hl[0].totalItems === 2 && /^\d{4}-\d\d-\d\d \d\d:\d\d$/.test(hl[0].date) && !('data' in hl[0]));
t('load by id returns stored data', (await h.loadCalculation('', hl[0].id)).z === 'abc');
t('unknown id rejected', /不存在/.test(await thr(() => h.loadCalculation('', 'nope')) || ''));
t('delete returns fresh list', (await h.deleteCalculationHistory('', hl[0].id)).length === 0);
t('non-object history rejected', !!(await thr(() => h.saveCalculationHistory('', 'x', {}, 'str'))));

// ---- google.script.run 兼容层 ----
const viaRun = (fn, ...args) => new Promise(res => win.google.script.run.withSuccessHandler(v => res({ ok: v })).withFailureHandler(e => res({ err: e })).__proto__ && win.google.script.run.withSuccessHandler(v => res({ ok: v })).withFailureHandler(e => res({ err: e }))[fn](...args));
t('run: success handler gets result', (await viaRun('getMyProfile', 'tok')).ok.Email === 'u1@x.com');
t('run: failure handler gets {message}', /Unknown server function/.test((await viaRun('doesNotExist')).err.message));
await sb.auth.signOut();
t('run: failure on expired session', /过期/.test((await viaRun('getAllContainerPresets', 'tok')).err.message));

console.log(failed ? `\n${failed} FAILED` : '\nall PASS');
process.exit(failed ? 1 : 0);
