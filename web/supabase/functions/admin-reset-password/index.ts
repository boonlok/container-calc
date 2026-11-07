// Edge Function: 管理员重设别人的密码 (需要 service role, 所以不能放在浏览器里做)
// 部署: supabase functions deploy admin-reset-password
// 呼叫者必须带有效的登入 JWT, 且在 profiles 表里是已启用的 admin。
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const authHeader = req.headers.get('Authorization') ?? '';

    // 1) 以呼叫者身份确认是 admin (走 RLS, 不信任前端传来的任何身份资料)
    const asCaller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
    const { data: u, error: uErr } = await asCaller.auth.getUser();
    if (uErr || !u.user) return json({ error: '登入已过期，请重新登入 Session expired, please log in again' }, 401);
    const { data: me } = await asCaller.from('profiles').select('role,status').eq('id', u.user.id).single();
    if (!me || me.role !== 'admin' || me.status !== 'active') return json({ error: '此操作需要管理员权限 This action requires admin access' }, 403);

    // 2) 参数检查
    const { email, newPassword } = await req.json();
    if (typeof email !== 'string' || typeof newPassword !== 'string' || newPassword.length < 6 || newPassword.length > 200) {
      return json({ error: '参数不正确 Invalid parameters' }, 400);
    }

    // 3) 用 service role 改密码并让对方所有登入失效
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: target } = await admin.from('profiles').select('id').eq('email', email.trim().toLowerCase()).maybeSingle();
    if (!target) return json({ error: '找不到此帐号 Account not found' }, 404);
    const { error: pwErr } = await admin.auth.admin.updateUserById(target.id, { password: newPassword });
    if (pwErr) return json({ error: pwErr.message }, 400);
    await admin.rpc('revoke_sessions', { uid: target.id });
    return json({ success: true });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
