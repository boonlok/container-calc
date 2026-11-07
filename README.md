# 集装箱装载计算器 Container Loading Calculator
### Google Apps Script + Google Sheet 部署指南 Setup Guide

---

## 一、建立专案 Create the Project

1. 前往 [sheets.google.com](https://sheets.google.com)，新增一个空白 Google Sheet，命名为例如「集装箱装载计算器」。
2. 在该 Sheet 中，点选 **扩展功能 Extensions → Apps Script**，会打开一个新分页的 Apps Script 编辑器。
3. Apps Script 编辑器预设会有一个空的 `Code.gs`。

## 二、建立以下 8 个档案 Create these 8 files

在 Apps Script 编辑器左侧「档案 Files」旁按 **+**，依序建立：

| 档案类型 File type | 档名 (需完全一致) | 内容来源 |
|---|---|---|
| 脚本 Script | `Code` (已存在，直接改) | `Code.gs` |
| HTML | `Index` | `Index.html` |
| HTML | `Stylesheet` | `Stylesheet.html` |
| HTML | `Auth` | `Auth.html` |
| HTML | `Effects` | `Effects.html` |
| HTML | `JavaScript` | `JavaScript.html` |
| HTML | `Render` | `Render.html` |
| HTML | `Viewer3D` | `Viewer3D.html` |
| HTML | `Export` | `Export.html` |

> ⚠️ 建立 HTML 档案时，Apps Script 只需要输入名称 (例如 `Index`)，`.html` 副档名会自动加上。档名大小写必须完全一致，因为 `Code.gs` 里的 `include()` 是用档名字串去抓档案内容的。

把每个档案对应的内容整个复制贴上即可（覆盖预设内容）。

## 三、部署为网页应用 Deploy as Web App

1. 右上角 **部署 Deploy → New deployment（新增部署作业）**。
2. 类型选择齿轮图示 → **网页应用程式 Web app**。
3. 设定：
   - Execute as: **Me（我）**
   - Who has access: 依需求选 **只有我 Only myself**、**知道连结的使用者 Anyone with the link**，或限制在贵公司 Google Workspace 网域内。（注意：这跟登入系统是两回事——这里控制的是「谁能打开这个网页」，网页打开后还需要再用帐号密码登入才能使用工具本身。）
4. 点 **部署 Deploy**，首次会跳出 Google 权限授权画面 (要求存取 Google Sheet)，按照指示完成授权（这是正常的，因为程式需要读写 Sheet）。
5. 部署完成后会得到一个网址，这就是可以直接打开使用的工具网址。之后修改程式码，只要「管理部署作业 → 编辑 → 新版本」就能更新，不需要重新分享网址。

## 四、首次使用 First Run

### 1. 注册第一个帐号 (会自动成为管理员)

打开网页会先看到**登入画面**。点「注册新帐号 Register」，填入邮箱+密码（可选填公司名称/地址，之后也能改）。**第一个注册的帐号会自动成为管理员 (admin) 并直接启用**，可以马上登入使用。

### 2. 后续新使用者注册

之后其他人再注册，帐号预设是「**待审核 inactive**」状态，注册完会看到提示「请等待管理员启用」。这时候需要：
1. 用管理员帐号登入
2. 点右上角「🛡 管理后台 Admin」
3. 找到该帐号，按「编辑 Edit」，把 Status 改成 **Active**，保存

在此之前，该帐号是无法登入的（会看到「此帐号尚未启用」的提示）。

### 3. 一般使用者能做什么 / 不能做什么

| 操作 | 一般 User | Admin |
|---|---|---|
| 编辑自己的公司资料 / Logo (右上角「我的资料」) | ✅ | ✅ |
| 修改自己的密码 | ✅ | ✅ |
| 查看/编辑所有人的资料 | ❌ | ✅ (管理后台) |
| 设定任何帐号的 Active / Inactive 状态 | ❌ | ✅ |
| 变更任何帐号的角色 (User ⇄ Admin) | ❌ | ✅ |
| 重设别人的密码 | ❌ | ✅ |

Admin 无法停用或取消自己的管理员权限（系统会挡下来），避免不小心把自己锁在外面。

### 4. Sheet 结构

首次打开网页时，程式会自动在 Google Sheet 里建立四个工作表：
- **Container Presets** — 已预填 20GP / 40GP / 40HC / 45HC 四种常见柜型尺寸（**行业参考值，建议依货代提供的实际规格核对调整**）。
- **Item Master** — 常用物品库的后端函式已备妥 (`getItemMaster`/`saveItemToMaster`)，前端选择器尚未实作，可下次再补上。
- **Calculation History** — 每次按「保存此次计算」会记一笔完整记录，含原始输入与完整计算结果，方便日后查阅。
- **Users** — 帐号资料表，密码相关的两栏 (PasswordHash / Salt) 已预设隐藏，请不要手动显示或编辑这两栏，也不建议在 Sheet 上直接改其他帐号的栏位（改了不会触发 TokenVersion 递增，该使用者的旧登入不会立即失效），一律透过管理后台操作。

---

## 帐号系统安全性说明 Security Notes

这套帐号系统是**自建的**（不依赖 Google 帐号登入），实作方式：

- 密码从不存明文，是用 **SHA-256 + 每人独立的随机 salt** 杂凑后才存进 Sheet。
- 登入后核发一个**有签章的 token**（类似简化版 JWT，用 HMAC-SHA256 签章，无法被使用者伪造），存在浏览器的 localStorage，有效期 7 天。
- 每次操作都会重新比对 Sheet 上该帐号「当前」的启用状态与一个版本号 (TokenVersion)——所以 admin 停用某帐号、或使用者自己改密码时，**旧的登入会立即失效**，不必等 token 过期。
- 签章用的密钥存在 Apps Script 的 Script Properties，首次执行时自动产生一次，之后固定不变（除非手动清除）。

**请注意这不是银行级别的资安强度**，比较适合内部、人数有限的工具使用。如果需要更严谨的身份验证（例如配合公司现有的 SSO/Workspace 帐号），建议改用 Apps Script 原生的 `Session.getActiveUser()`，我可以协助改写。

---

## 系统逻辑说明 How It Works

**装箱演算法 Packing algorithm**：这是一套已用 Node.js 独立验证过的贪婪演算法 (greedy heuristic)：
1. 每样物品的箱数 = 总 PCS ÷ 每箱 PCS，无条件进位。
2. 系统会尝试每一种已启用的柜型，模拟把目前剩余物品（依体积大小排序）依序填入，只允许箱子做「水平 90° 旋转」（长宽互换），高度方向固定不翻转。
3. 同一个货柜内，不同物品会各自占用一段连续的「深度区块」(像书架分层一样前后排列)，每一段内部是整齐的 Horizontal × Vertical 网格。
4. 每一轮都挑选「空间利用率最高」的柜型来装载当前剩余物品，直到所有物品装完，或侦测到有物品尺寸超过所有柜型 (会在结果页明确警示，并列出未能装载的品项)。
5. 若填写了「重量」栏位，系统也会同时检查载重上限——重货优先受重量限制，系统会自动倾向选用较小柜型以提高整体利用率（更符合实际报价逻辑）。

这不是全域最优解（3D 装箱问题在数学上是 NP-hard），是业界常见、可解释、能产生整齐可视化排列的实用近似解，实际装箱时仍建议由有经验的师傅现场微调。

**PDF 报告排版 (A3 横向)**：PDF 现在以 A3 横向输出 (与样本同为横向；要改直向，把 `Export.html` 的 `PDF_ORIENTATION` 改为 `'portrait'`)。每个货柜依序有：① 样本式第一页 ② 装柜顺序与工人注意事项页 ③ 视角总览页 (6 角度) ④ 混装柜才有的「各物品区块特写」页——每个物品区块从门侧斜视、顶视、右侧视三个角度单独高亮拍摄，其余物品淡化，并附该区块的旋转方向、起讫位置、留隙、高低差等注意事项。第一页起会依你上传的样本排版重现——公司 Logo/名称/地址表头、Shipping Information 表、Shipping Item 表 (①②③ 编号，箱规以 mm 显示，最多 9 样，超过会在表格下方註记)、Accessory 配件表、Drawn/Checked/Confirmed 签名表，接着才是 3D 视图、Right View 剖面图、Front/Back View 马赛克图、多角度视角合集。若本次计算有多个货柜，会先加一页总览页（样本没有这个，是因为样本预设一次只有一种柜型；有多柜时这页能帮忙一眼看懂全貌），每个货柜各自一份完整的样本式报告。

**标题文字**：样本 PDF 上的标题是日文「コンテナ積載方法」，考虑到不确定所有使用情境都需要日文，目前改成中英双语「集装箱装载方案 CONTAINER LOADING METHOD」，如果你需要完全比照日文原文，告诉我，一行代码就能改。

**视觉特效 Tech Effects**：`Effects.html` 提供了数字滚动计数、长条图动画、按钮涟漪效果、画面切换转场等共用工具，套用在结果面板的统计数字、货柜利用率长条图、登入/主画面/个人资料/管理后台的转场上。所有动画都有遵守使用者的「减少动态效果」系统设定 (`prefers-reduced-motion`)，打印/PDF 时也会自动关闭。

---

---

## 疑难排解 Troubleshooting

### 打开网页 / 登入时出现 `userCodeAppPanel` 或 `createOAuthDialog` 相关的报错

这是 **Google Apps Script 自己内部的授权沙盒机制**在报错，不是这个专案代码里的问题（程式码完全没有引用这个网址/机制）。请依序排查：

1. 确认打开的是「已部署的正式网址」（`.../exec` 结尾），不是编辑器里的预览或 `.../dev` 网址。
2. 回 Apps Script 编辑器，在函式下拉选单选一个函式（例如 `doGet`）手动执行一次，让 Google 的权限画面重新跳出来，同意所有权限。
3. 强制刷新页面 (Ctrl+Shift+R)。
4. 换无痕视窗或换浏览器测试——如果无痕视窗正常，通常是原浏览器的第三方 Cookie 被挡掉或有扩充功能干扰。
5. 重新部署一个新版本（部署 → 管理部署作业 → 编辑 → 新版本）。

## 已知限制与下次可延伸方向 Known Limitations / Ideas for Next Session

- 目前箱子只允许在水平面旋转 90°（不会被立起来倒放）。
- 物品常用库 (Item Master) 后端函式已就绪，前端选择/载入界面尚未实作。
- 帐号系统的 session 是 stateless token，没有「查看目前有哪些装置登入中」或「一键踢除所有登入」的介面（技术上已经支援底层机制 TokenVersion，只是还没做操作界面）。
- 货运信息 (Shipment Info) 目前是每次填写、每次导出时读取，尚未跟着「保存此次计算」一起存进历史记录；如果需要保存/载入完整的货运信息也可以下次补上。
- 若网页开启后 3D 视图或字体没有正常显示，多半是所在网路环境的防火墙/代理挡掉了外部 CDN (Google Fonts、Three.js、jsPDF)，请确认网路设定允许存取这些外部资源。



## 本次更新 (混装特写 + A3)
- **约定**：柜门在左侧 (3D 的 -X 端)，`startLength` 为离柜门距离；柜门正视/柜底正视两个总览视角已与此约定对齐 (之前这两个标签方向相反)。
- **混装柜特写**：同一柜装多种物品时，视角合集分为「整柜总览」与「各物品区块特写」，每区块附 PCS/箱、H×V×深、重量及工人注意事项 (`describeAllocation`，在 `Viewer3D.html`)。
- **注册即登入**：第一个注册的账号 (admin) 注册后自动登入；其后账号仍需 admin 启用，所以只提示等待审核。
- **安全**：已删除 `Code.gs` 里含明文密码的 `setup_SecureCredentials`。如果那组账号密码曾经被存档/分享过，请务必改密码。
- **注意**：`Auth.html` 里的 `DEV_SKIP_LOGIN` 目前是 `true` (跳过登入)；正式使用前请改回 `false`，改回后再给数据读写函数加 `requireAuth_` 才不会影响访客模式。
- **历史记录**：主画面“📂 历史记录 History”可浏览、载入、删除已保存的计算。保存内容超过 Sheets 单格 50000 字元上限时，只存物品清单，载入后自动重新计算。后端 `getCalculationHistory` 现回传精简清单 (原本回传 Date 物件和大型 JSON，容易在前端取不到)，行号加了范围检查，避免误删表头。
- **登录验证 + 资料隔离**：`DEV_SKIP_LOGIN` 已改回 `false`。所有数据接口（柜型、物品库、历史）现在第一个参数是登录 token，并在后端验证。柜型/物品库/历史各加了 `Owner` 栏（旧 Sheet 会自动补栏）：Owner 为空是共用预设（所有人可看、仅 admin 可改）；一般用户只看得到共用 + 自己的，也只能改自己的；历史记录只有本人和 admin 可读。登入过期时前端会自动回到登录页。修改类操作加了 `LockService` 锁，避免同时操作造成行号错位。
- **忘记密码**：登录页「忘记密码」→ 邮箱收 6 位验证码（15 分钟有效、最多试 5 次、同邮箱 60 秒内只能要一次、不泄露邮箱是否已注册）→ 设新密码，旧登录全部失效。需要 `MailApp` 权限（首次部署会要求授权）。
- **测试**：`tests/backend.test.js` 用模拟的 Apps Script 环境测登录、隔离、越权、重设密码；在项目目录运行 `node tests/backend.test.js`。


## 本次更新 (安全修复 + 性能 + 算法)
- **测试**：`tests/` 目录现含 `backend.test.js` (40 项)、`algorithm.test.js` (装箱算法，含随机回归：新算法不会比旧的差)、`check.js` (一键做所有文件的 JS 语法检查并跑全部测试)：`node tests/check.js`。
- **安全**：
  - Sheet 公式注入防护 (`safeCell_`)：公司名称/地址、历史名称、柜型/物品名称写入前，以 `= + - @` 开头的文字会被强制成纯文字；邮箱不允许这些开头。
  - 载入历史记录时一律清洗 (`sanitizeItems` / `sanitizeResult`)：数字强制转型、颜色只收 `#rrggbb`、文字限长，防止别人写入的恶意记录在 admin 浏览器里执行脚本；清洗失败会改用物品清单重新计算。
  - 登出或被强制登出后直接重新载入页面，不再残留上一个帐号的物品/结果/柜型/货运信息。
  - `emergencyResetPassword` 不再把账号密码写在代码里 (任何没有结尾下划线的函式都能被网页呼叫)；改为在「项目设置 → 脚本属性」设 `EMERGENCY_EMAIL` / `EMERGENCY_PASSWORD`，执行后自动删除。
  - 去掉 `setXFrameOptionsMode(ALLOWALL)` (防点击劫持)。**如果你把工具嵌在 Google Sites 等页面里，需要在 `Code.gs` 的 `doGet` 里把那一行取消注释。**
  - 注册：加锁、全站每小时限 30 个 (防止塞满 Sheet 和耗尽邮件配额)、长度限制；role/status 只接受合法值；token 签章比对改为定时间比较；Logo 只接受 png/jpeg data URL 且 ≤ 48000 字元。
- **Bug**：
  - admin 编辑自己的账号 (哪怕只改公司名) 会被自己踢出登入 —— 现在只有 role/status 真的改变才会让对方登入失效。
  - 用户对象里的 `Date` 栏位 (CreatedDate/LastLogin) 转成字串，避免 `google.script.run` 回传 null。
  - PDF「No.」栏的 ①②③ 以前用内建字体会乱码，现在走图片方式；表格里过长的中文文字缩小到放得进格子。
  - 3D 以前把最后一列画满 (多画箱子)，现在只画实际箱数，顺序与「从一侧靠边排放」一致。
  - Logo 上传：先试 PNG，太大就缩小，最后才用 JPEG (铺白底，不再变黑底)，上限 45000 字元。
  - 物品输入验证：数量/尺寸必须大于 0，重量不能为负；重量栏位标示为「每箱」。
- **装柜算法**：改为「物品排序 (体积/高度/底面积) × 选柜策略 (利用率/刚好装完最小柜/装得最多)」共 9 种组合各算一遍，取 (未装箱数、柜数、总柜容积、平均利用率) 最好的一套；第一个组合就是原算法，所以不会更差。例如 1000 箱 50×40×30 以前是 40HC+20GP，现在 1×45HC。排列方向也改为优先选占用柜长较短的。
- **3D 性能**：每个物品区块用一个 InstancedMesh + 合并边线 (26000 箱的场景 4 次 draw call，建场景约 50ms)；改为按需渲染 (页面隐藏/没有动作时不画)；释放漏掉的几何体和材质；同一货柜不重建场景；视角截图每个货柜只拍一次，画面/打印/PDF 共用，截图像素比降到 1；背景网格动画改用 transform，不再每帧重绘整页。
- **PDF 体积/速度**：`compress: true`、3D 截图改 JPEG、小图用 FAST 压缩、相同文字只描绘一次、逐柜生成并显示进度 (不再整个页面卡住)。CDN 版本固定为 jspdf 2.5.1 / jspdf-autotable 3.8.2。
- **历史记录**：每笔有稳定 `Id` (不再靠会错位的行号)，旧记录首次列出时自动补 Id；列表只读元数据栏位；保存时 gzip+base64 压缩 (大结果也能完整放进单格)；载入时同时还原货运信息与配件清单。
- **效能**：用户查找只读 Email 栏再读该行 (不再每次请求读出全部用户的 Logo)。


## 三个版本 Three Versions

| 目录 | 版本 | 说明 |
|---|---|---|
| 根目录 (`Code.gs`, `*.html`) | Apps Script + Google Sheets | 原版 |
| `web/` | 静态网页 + Supabase | 共用根目录前端, 见 `web/README.md` |
| `flutter_app/` | **Flutter Web + Supabase** | 自动部署到 GitHub Pages, 见 `flutter_app/README.md` |
