// 复制本档为 config.js, 填入 Supabase 控制台 → Project Settings → API 里的两个值。
// anon key 本来就是公开用的 (数据靠行级权限 RLS 保护), 但「service_role key」绝对不能放在这里!
window.APP_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT-REF.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-PUBLIC-KEY',
};
