/// Supabase 设置: 建置时用 --dart-define 传入 (GitHub Actions 里来自仓库的 Variables), 不写死在代码里。
/// 没有设置时, App 以「演示模式」运行 (资料只在内存里, 重新整理就消失)。
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
