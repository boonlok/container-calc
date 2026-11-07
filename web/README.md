# Supabase + 静态托管版 Setup Guide

这是 Apps Script 版的迁移版本：**前端代码与 Apps Script 版共用同一套文件**（`../Index.html`、`../Auth.html` …），
`build.js` 把它们合成一个静态 `dist/index.html`，再由 `api-supabase.js` 把原本的 `google.script.run`
换成 Supabase。账号隔离由数据库的行级权限 (RLS) 强制执行。Apps Script 版 (`../Code.gs`) 完全不受影响，可继续使用。

## 一、建立 Supabase 项目 (约 10 分钟)

1. 到 [supabase.com](https://supabase.com) 新建项目 (免费方案即可)，记下 **Project URL** 与 **anon public key**
   (Project Settings → API)。**service_role key 绝对不要放进前端或 config.js。**
2. **SQL Editor** → 新建查询 → 把 `supabase/schema.sql` 整份贴上执行 (可重复执行)。
   这会建立 `profiles` / `container_presets` / `calculation_history` 三张表、触发器和所有权限规则，并预填 4 种标准柜型。
3. **Authentication → Providers → Email**：
   - **关闭「Confirm email」**（新账号要等管理员审核，所以不需要邮箱确认；开着的话，注册后要先点邮件链接才能继续）。
   - 把最小密码长度设为 6 或更高 (前端要求至少 6)。
4. **Authentication → Email Templates → Reset Password**：把内容改成显示 6 位验证码，例如
   ```html
   <h2>密码重设验证码 Password reset code</h2>
   <p>您的验证码 Your code: <b>{{ .Token }}</b></p>
   <p>如果不是您本人操作，请忽略此邮件。If this was not you, ignore this email.</p>
   ```
   (前端的「忘记密码」流程是：邮箱收验证码 → 输入验证码 + 新密码。)
5. **Authentication → SMTP Settings**：**强烈建议设置自己的 SMTP** (Resend / SendGrid / Gmail 应用密码等)。
   Supabase 内建邮件服务每小时只能寄几封，「忘记密码」很容易被限流。
6. **Authentication → Rate Limits** 保持默认即可 (登录/注册/寄信都有内建限速，取代了旧版的 CacheService 计数)。

## 二、部署管理员重设密码的 Edge Function

管理员重设「别人」的密码需要 service role，不能在浏览器里做：

```bash
npm i -g supabase            # 或用 npx supabase
supabase login
supabase link --project-ref <你的 Project ref>
supabase functions deploy admin-reset-password
```
函数会先用呼叫者的登入身份确认他是已启用的 admin，才会改密码并让对方所有登录失效。

## 三、建置与部署前端

```bash
cd web
cp config.example.js config.js     # 填入 SUPABASE_URL 与 SUPABASE_ANON_KEY
npm run build                       # 产出 web/dist/ (index.html + _headers)
```
把 `web/dist/` 整个目录部署到任何静态托管：Cloudflare Pages、Netlify、Vercel、GitHub Pages 都可以
(Cloudflare Pages / Netlify 会自动套用 `_headers`：禁止被别的网站 iframe 嵌入等安全标头)。

然后到 Supabase **Authentication → URL Configuration**，把 Site URL 设为你的网址。

## 四、首次使用

1. **先自己注册第一个账号** —— 数据库触发器会让第一个账号自动成为已启用的管理员，之后注册的都是「待审核」。
2. 之后新用户注册 → 管理员在「🛡 管理后台」把状态改为 Active 才能登入 (和旧版相同)。

## PDF 中文字体 (真正的文字, 不再是图片)

Supabase/静态版导出 PDF 时会：下载 `fonts/NotoSansSC-subset.ttf` (1.4MB, Noto Sans SC, SIL OFL, 见 `fonts/OFL.txt`)
与 `vendor/harfbuzz-subset.wasm` → 在浏览器里现场把字体裁成「这份 PDF 实际用到的字」(通常只有十几 KB) 嵌进 PDF。
文字因此是矢量字：清晰、可选取、可搜寻。字体里没有的冷僻字会自动退回「文字转图片」，所以任何情况都不会乱码。
实测 (2 个货柜、11 种物品): **6.9MB → 2.3MB，生成时间 13 秒 → 4 秒**；(2 个货柜、3 种物品) 2.9MB → 1.1MB。
Apps Script 版没有字体文件可下载，仍用「文字转图片」。

字体范围: GB2312 一级常用字 + 符号 + 日文假名 + 全角字符 (约 4900 字)。要增减字，改 `tools/make-font.mjs` 后重新执行
(需要 Noto Sans SC 可变字体原档，用法写在该文件开头)。

## 与 Apps Script 版的差异

| 项目 | Apps Script 版 | Supabase 版 |
|---|---|---|
| 密码保存 | 单次 SHA-256 + salt | Supabase Auth (bcrypt) |
| 账号隔离 | 每个函式手写检查 | 数据库 RLS 强制 (`tests/rls.test.mjs` 验证) |
| 停用/改角色后立即生效 | TokenVersion | 每次请求 RLS 都检查 `profiles.status/role`，立即生效 |
| 历史记录 | Sheet 单格 5 万字符 | jsonb (上限 2MB) |
| 忘记密码验证码 | 自己寄 6 位码 (MailApp) | Supabase 寄出 (模板里放 `{{ .Token }}`) |
| 登入失败锁定 | CacheService | Supabase 内建限速 |
| 速度 | 每次请求 1–2 秒 | 通常 100ms 内 |
| PDF 中文 | 每段文字一张图 (体积大) | 嵌入字体子集 (真文字, 体积约小 2/3) |
| 新注册/启用时的邮件通知 | 有 | **未迁移** (可用 Supabase Database Webhook + Edge Function 补上) |
| 物品库 Item Master | 后端函式 (前端未使用) | 未迁移 (前端本来就没用) |

## 测试

```bash
cd web && npm i && npm test
```
- `tests/rls.test.mjs`：用 PGlite (WASM 版 Postgres) 在本机执行 `schema.sql`，验证隔离、越权、触发器、约束。
  注意这是本机模拟的 Supabase 环境 (角色与 `auth.uid()` 是模拟的)，部署后仍建议用两个测试账号实际验证一次。
- `tests/shim.test.mjs`：用假的 Supabase 客户端验证 `google.script.run` 兼容层的函式名称、回传格式与错误讯息。

## 从旧版迁移数据 (选做)

旧 Sheet 里的历史记录 (`Calculation History` 的 Data JSON 栏) 可以导出后用 SQL Editor 的 `insert into public.calculation_history` 导入
(需要先有对应用户的 uuid)。密码杂凑无法迁移 (算法不同)，用户需要用「忘记密码」设定新密码。
