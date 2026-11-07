-- ============================================================
--  集装箱装载计算器 Supabase 数据库结构 (Postgres + 行级权限 RLS)
--  在 Supabase 控制台 → SQL Editor 整份贴上执行一次即可 (可重复执行)。
--  账号隔离由数据库本身强制执行, 不再依赖每个接口手写检查。
-- ============================================================

-- ---------- 账号资料 profiles ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'user' check (role in ('admin', 'user')),
  status text not null default 'inactive' check (status in ('active', 'inactive')),
  company_name text not null default '' check (char_length(company_name) <= 100),
  company_address text not null default '' check (char_length(company_address) <= 300),
  logo_data_url text not null default '' check (
    char_length(logo_data_url) <= 200000 and
    (logo_data_url = '' or logo_data_url ~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$')),
  created_at timestamptz not null default now(),
  last_login timestamptz
);
alter table public.profiles enable row level security;

-- ---------- 工具函数 (需要 profiles 表已存在) ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and status = 'active');
$$;

create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
  using (public.is_admin() or (id = auth.uid() and public.is_active()))
  with check (public.is_admin() or (id = auth.uid() and public.is_active()));
-- 不开放 insert / delete: 由下方触发器建立, 删除只能由 auth.users 级联

-- 新用户注册 → 自动建立 profile。第一个账号自动成为已启用的 admin, 之后的账号为待审核 inactive
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  perform pg_advisory_xact_lock(424242); -- 避免两人同时注册变成两个「第一个管理员」
  select not exists (select 1 from public.profiles) into first_user;
  insert into public.profiles (id, email, role, status, company_name, company_address)
  values (
    new.id, lower(new.email),
    case when first_user then 'admin' else 'user' end,
    case when first_user then 'active' else 'inactive' end,
    left(coalesce(new.raw_user_meta_data ->> 'company_name', ''), 100),
    left(coalesce(new.raw_user_meta_data ->> 'company_address', ''), 300));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 保护关键栏位: 一般用户不能改自己的 role/status; admin 不能取消自己的管理员权限或停用自己
create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if; -- service role / SQL Editor
  if new.id <> old.id or new.email <> old.email or new.created_at <> old.created_at then
    raise exception 'Immutable field';
  end if;
  if not public.is_admin() then
    if new.role <> old.role or new.status <> old.status then
      raise exception '没有权限 No permission';
    end if;
  elsif old.id = auth.uid() and (new.role <> old.role or new.status <> old.status) then
    raise exception '不能修改自己的角色或状态 Cannot change your own role/status';
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_trg on public.profiles;
create trigger protect_profile_trg before update on public.profiles
  for each row execute function public.protect_profile();

-- ---------- 柜型预设 container_presets ----------
-- owner 为空 = 系统共用预设 (所有启用账号可看, 仅 admin 可改)
create table if not exists public.container_presets (
  id bigint generated always as identity primary key,
  owner uuid references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  length_cm numeric not null check (length_cm > 0),
  width_cm numeric not null check (width_cm > 0),
  height_cm numeric not null check (height_cm > 0),
  max_payload_kg numeric not null check (max_payload_kg > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.container_presets enable row level security;

drop policy if exists presets_select on public.container_presets;
create policy presets_select on public.container_presets for select
  using (public.is_active() and (owner is null or owner = auth.uid() or public.is_admin()));
drop policy if exists presets_insert on public.container_presets;
create policy presets_insert on public.container_presets for insert
  with check (public.is_active() and owner = auth.uid());
drop policy if exists presets_update on public.container_presets;
create policy presets_update on public.container_presets for update
  using (public.is_active() and (owner = auth.uid() or public.is_admin()))
  with check (public.is_active() and (owner = auth.uid() or public.is_admin()));
drop policy if exists presets_delete on public.container_presets;
create policy presets_delete on public.container_presets for delete
  using (public.is_active() and (owner = auth.uid() or public.is_admin()));

insert into public.container_presets (owner, name, length_cm, width_cm, height_cm, max_payload_kg)
select null, v.name, v.l, v.w, v.h, v.p
from (values
  ('20GP (20呎标准柜)', 589, 235, 239, 28180),
  ('40GP (40呎标准柜)', 1203, 235, 239, 26580),
  ('40HC (40呎高柜)', 1203, 235, 269, 28600),
  ('45HC (45呎高柜)', 1355, 235, 269, 27600)
) as v(name, l, w, h, p)
where not exists (select 1 from public.container_presets where owner is null);

-- ---------- 计算记录 calculation_history ----------
create table if not exists public.calculation_history (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id) on delete cascade,
  owner_email text not null default '',
  name text not null check (char_length(name) <= 200),
  total_items int not null default 0,
  total_containers int not null default 0,
  summary text not null default '' check (char_length(summary) <= 500),
  data jsonb not null check (octet_length(data::text) <= 2000000),
  created_at timestamptz not null default now()
);
create index if not exists calculation_history_owner_idx on public.calculation_history (owner, created_at desc);
alter table public.calculation_history enable row level security;

drop policy if exists history_select on public.calculation_history;
create policy history_select on public.calculation_history for select
  using (public.is_active() and (owner = auth.uid() or public.is_admin()));
drop policy if exists history_insert on public.calculation_history;
create policy history_insert on public.calculation_history for insert
  with check (public.is_active() and owner = auth.uid());
drop policy if exists history_delete on public.calculation_history;
create policy history_delete on public.calculation_history for delete
  using (public.is_active() and (owner = auth.uid() or public.is_admin()));

-- ---------- 管理员重设密码后让对方所有登录失效 (只给 Edge Function 的 service role 用) ----------
create or replace function public.revoke_sessions(uid uuid) returns void
language sql security definer set search_path = public, auth as $$
  delete from auth.sessions where user_id = uid;
$$;
revoke all on function public.revoke_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_sessions(uuid) to service_role;
