// 用 PGlite (WASM 版 Postgres) 在本机验证 schema.sql 的行级权限 (RLS)、触发器与约束。
// 以 Supabase 的做法模拟: 角色 anon/authenticated/service_role, auth.uid() 读取 request.jwt.claim.sub
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const db = new PGlite();
let failed = 0;
const t = (name, ok, extra) => { if (!ok) failed++; console.log(ok ? 'PASS' : 'FAIL', name, extra || ''); };

await db.exec(`
  create schema auth;
  create table auth.users(id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}');
  create table auth.sessions(id uuid default gen_random_uuid(), user_id uuid);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create role anon nologin; create role authenticated nologin; create role service_role nologin;
  grant usage on schema public, auth to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
`);
await db.exec(fs.readFileSync(path.join(dir, '..', 'supabase', 'schema.sql'), 'utf8'));
await db.exec(fs.readFileSync(path.join(dir, '..', 'supabase', 'schema.sql'), 'utf8')); // 可重复执行
t('schema.sql runs twice without error (idempotent)', true);

async function signup(email, meta) {
  const r = await db.query(`insert into auth.users(email, raw_user_meta_data) values ($1, $2::jsonb) returning id`, [email, JSON.stringify(meta || {})]);
  return r.rows[0].id;
}
async function as(uid, fn) {
  await db.exec(`set role ${uid ? 'authenticated' : 'anon'}`);
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid || '']);
  try { return await fn(); } finally { await db.exec('reset role'); await db.query(`select set_config('request.jwt.claim.sub', '', false)`); }
}
const q = (sql, p) => db.query(sql, p).then(r => r.rows);
const err = async (fn) => { try { await fn(); return null; } catch (e) { return e.message; } };

const A = await signup('Admin@X.com', { company_name: 'A Co', company_address: 'addr' });
const U1 = await signup('u1@x.com');
const U2 = await signup('u2@x.com');
const profs = await q('select email, role, status, company_name from public.profiles order by created_at, email');
t('first signup = active admin, email lowercased', profs[0].email === 'admin@x.com' && profs[0].role === 'admin' && profs[0].status === 'active' && profs[0].company_name === 'A Co');
t('later signups = inactive user', profs.filter(p => p.role === 'user' && p.status === 'inactive').length === 2);

// 未启用账号: 看不到任何柜型
t('inactive user sees no presets', (await as(U1, () => q('select * from public.container_presets'))).length === 0);
t('inactive user cannot insert history', !!(await as(U1, () => err(() => q(`insert into public.calculation_history(name,data) values ('x','{}')`)))));
t('anon sees nothing', (await as(null, () => q('select * from public.profiles'))).length === 0);

// admin 启用 U1 / U2
await as(A, () => q(`update public.profiles set status='active' where email in ('u1@x.com','u2@x.com')`));
t('admin can activate users', (await q(`select count(*)::int c from public.profiles where status='active'`))[0].c === 3);
t('active user sees 4 shared presets', (await as(U1, () => q('select * from public.container_presets'))).length === 4);

// profile 保护
t('user cannot change own role', /没有权限/.test(await as(U1, () => err(() => q(`update public.profiles set role='admin' where id=$1`, [U1]))) || ''));
t('user cannot change own status', !!(await as(U1, () => err(() => q(`update public.profiles set status='inactive' where id=$1`, [U1])))));
t('user can change own company', (await as(U1, () => q(`update public.profiles set company_name='B Co' where id=$1 returning id`, [U1]))).length === 1);
t('user cannot edit others profile', (await as(U1, () => q(`update public.profiles set company_name='hacked' where id=$1 returning id`, [U2]))).length === 0);
t('user sees only own profile', (await as(U1, () => q('select * from public.profiles'))).length === 1);
t('admin sees all profiles', (await as(A, () => q('select * from public.profiles'))).length === 3);
t('admin cannot demote self', /不能修改自己/.test(await as(A, () => err(() => q(`update public.profiles set role='user' where id=$1`, [A]))) || ''));
t('admin cannot deactivate self', !!(await as(A, () => err(() => q(`update public.profiles set status='inactive' where id=$1`, [A])))));
t('email is immutable', !!(await as(A, () => err(() => q(`update public.profiles set email='z@x.com' where id=$1`, [U1])))));
t('invalid role rejected', !!(await as(A, () => err(() => q(`update public.profiles set role='root' where id=$1`, [U1])))));
t('logo javascript: rejected', !!(await as(U1, () => err(() => q(`update public.profiles set logo_data_url='javascript:alert(1)' where id=$1`, [U1])))));
t('logo png data url accepted', (await as(U1, () => q(`update public.profiles set logo_data_url='data:image/png;base64,AAAA' where id=$1 returning id`, [U1]))).length === 1);

// 柜型预设
t('user inserts own preset', (await as(U1, () => q(`insert into public.container_presets(owner,name,length_cm,width_cm,height_cm,max_payload_kg) values ($1,'Mine',500,200,200,1000) returning id`, [U1]))).length === 1);
t('user cannot insert preset for someone else', !!(await as(U1, () => err(() => q(`insert into public.container_presets(owner,name,length_cm,width_cm,height_cm,max_payload_kg) values ($1,'X',5,5,5,5)`, [U2])))));
t('user cannot insert shared preset (owner null)', !!(await as(U1, () => err(() => q(`insert into public.container_presets(owner,name,length_cm,width_cm,height_cm,max_payload_kg) values (null,'X',5,5,5,5)`)))));
t('u1 sees 5, u2 sees 4, admin sees 5', (await as(U1, () => q('select 1 from public.container_presets'))).length === 5 && (await as(U2, () => q('select 1 from public.container_presets'))).length === 4 && (await as(A, () => q('select 1 from public.container_presets'))).length === 5);
const shared = (await q('select id from public.container_presets where owner is null limit 1'))[0].id;
const mine = (await q(`select id from public.container_presets where name='Mine'`))[0].id;
t('user cannot update shared preset', (await as(U1, () => q(`update public.container_presets set name='x' where id=$1 returning id`, [shared]))).length === 0);
t('user cannot delete shared preset', (await as(U1, () => q(`delete from public.container_presets where id=$1 returning id`, [shared]))).length === 0);
t('u2 cannot update/delete u1 preset', (await as(U2, () => q(`update public.container_presets set name='x' where id=$1 returning id`, [mine]))).length === 0 && (await as(U2, () => q(`delete from public.container_presets where id=$1 returning id`, [mine]))).length === 0);
t('user cannot hand own preset to another owner', !!(await as(U1, () => err(() => q(`update public.container_presets set owner=$2 where id=$1`, [mine, U2])))));
t('admin can update shared preset', (await as(A, () => q(`update public.container_presets set max_payload_kg=30000 where id=$1 returning id`, [shared]))).length === 1);
t('invalid preset dims rejected', !!(await as(U1, () => err(() => q(`insert into public.container_presets(owner,name,length_cm,width_cm,height_cm,max_payload_kg) values ($1,'Bad',0,1,1,1)`, [U1])))));
t('u1 can delete own preset', (await as(U1, () => q(`delete from public.container_presets where id=$1 returning id`, [mine]))).length === 1);

// 计算记录
const h1 = (await as(U1, () => q(`insert into public.calculation_history(name,owner_email,data) values ('calc1','u1@x.com','{"items":[]}') returning id`)))[0].id;
t('history owner defaults to caller', (await q('select owner from public.calculation_history where id=$1', [h1]))[0].owner === U1);
t('u2 sees no history', (await as(U2, () => q('select * from public.calculation_history'))).length === 0);
t('admin sees history', (await as(A, () => q('select * from public.calculation_history'))).length === 1);
t('user cannot insert history as someone else', !!(await as(U1, () => err(() => q(`insert into public.calculation_history(owner,name,data) values ($1,'x','{}')`, [U2])))));
t('u2 cannot delete u1 history', (await as(U2, () => q(`delete from public.calculation_history where id=$1 returning id`, [h1]))).length === 0);
t('history cannot be edited', (await as(U1, () => q(`update public.calculation_history set name='x' where id=$1 returning id`, [h1]))).length === 0);
t('u1 deletes own history', (await as(U1, () => q(`delete from public.calculation_history where id=$1 returning id`, [h1]))).length === 1);

// 停用账号立刻失去数据访问 (等同旧版 TokenVersion 立即失效)
await as(A, () => q(`update public.profiles set status='inactive' where id=$1`, [U2]));
t('deactivated user instantly loses access', (await as(U2, () => q('select * from public.container_presets'))).length === 0);

// 取消 admin 后失去管理权限
await as(A, () => q(`update public.profiles set role='admin' where id=$1`, [U1]));
await as(A, () => q(`update public.profiles set role='user' where id=$1`, [U1]));
t('demoted admin loses admin powers', (await as(U1, () => q('select * from public.profiles'))).length === 1);

// revoke_sessions 只有 service_role 能执行
await q(`insert into auth.sessions(user_id) values ($1)`, [U1]);
t('authenticated cannot call revoke_sessions', !!(await as(U1, () => err(() => q('select public.revoke_sessions($1)', [U1])))));
await db.exec('set role service_role');
await db.query('select public.revoke_sessions($1)', [U1]);
await db.exec('reset role');
t('service_role revokes sessions', (await q('select count(*)::int c from auth.sessions where user_id=$1', [U1]))[0].c === 0);

console.log(failed ? `\n${failed} FAILED` : '\nall PASS');
process.exit(failed ? 1 : 0);
