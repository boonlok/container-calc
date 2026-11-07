# 集装箱装载计算器 Flutter Web 版

Flutter 重写版, 后端沿用 Supabase (表结构与权限见 `../web/supabase/schema.sql`, 设置步骤见 `../web/README.md` 的第一、二节)。
推送到 `main` 后由 `.github/workflows/deploy.yml` 自动测试、建置并发布到 GitHub Pages。

## 本地运行

```bash
flutter pub get
flutter run -d chrome
```
不带参数时是**演示模式** (资料只在内存里, 第一个注册的账号自动成为管理员), 不需要 Supabase 就能试用全部功能。

连接 Supabase:
```bash
flutter run -d chrome --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
```
线上版本的这两个值放在 GitHub 仓库的 **Settings → Secrets and variables → Actions → Variables**。
绝不要把 Supabase 的 service_role key 放进这里。

## 测试

```bash
flutter analyze
flutter test
```
- `test/golden_test.dart`: 装箱算法与网页版 (`../JavaScript.html`) 逐项比对 47 个情境, 基准由 `node tool/make_golden.js` 产生
- `test/render_test.dart`: 3D/2D 绘图指令、工人注意事项、资料清洗
- `test/backend_pdf_test.dart`: 账号规则、历史记录格式 (可读网页版的 gzip 记录)、PDF (A3 横向、页数)
- `test/widget_test.dart`: 注册 → 计算 → 混装特写 → 历史 → 登出清空

## 结构

| 路径 | 内容 |
|---|---|
| `lib/core/` | 数据模型、装箱算法 (纯 Dart) |
| `lib/render/` | 工人注意事项、2D 视图、等轴测 3D: 都输出平台无关的绘图指令 |
| `lib/services/` | 后端接口 + Supabase / 内存两种实现、历史记录编码、PDF 导出 |
| `lib/state/` | 全局状态 |
| `lib/ui/` | 画面 |
| `assets/fonts/` | Noto Sans SC 子集 (SIL OFL, GB2312 全部汉字), 由 `../web/tools/make-font.mjs` 产生 |

## 与网页版的差异

- **3D**: Flutter 自绘的等轴测图 (正交投影), 不是 WebGL 透视; 只画看得到的外壳面, 几万箱也流畅。
- **PDF**: 视图是矢量图 (不是截图), 中文按需嵌入字形, 文字可选取。字体里没有的冷僻字 (GB2312 以外, 例如部分繁体字) 目前无法显示, 网页版会退回图片。
- **打印**: 在新分页打开 PDF, 从那里打印。
- **没有移植**: 开机动画、装箱动画、数字滚动等纯视觉效果; 物品库 (Item Master, 网页版前端也没用到)。
- **新注册/启用的邮件通知**: 与 Supabase 网页版相同, 尚未实现。

## 工人装柜模式

计算完成后按「开始装柜」, 或用「工人二维码」/ PDF 第一页的二维码交给现场工人 (手机扫码, 不用登入)。

- **顺序**: 从柜底装到柜门, 每一列是一步: 放什么、横几排、几层、共几箱, 这一列的正面图和它在柜里的位置。
- **进度**: 存在工人自己的手机上, 关掉再开会接着做; 不同手机之间不同步。
- **位置**: 工人模式从柜底量起, 货物顶住柜底, 空隙留在柜门这边。PDF 和结果页仍依原约定从柜门量起。
- **链接内容**: 计划放在网址 # 后面 (不会送到服务器), 含柜型和物品名称, 不含客户和公司资料。物品太多放不进二维码时只给链接。
