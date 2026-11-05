/// Discuz 页面上那堆「提示」里，有些根本不是提示。
///
/// 编辑页会在正文上方渲染一条编辑记录：
///
/// > 本帖最后由 Aiopr·皇者 于 2026-10-31 17:32 编辑
/// > 更新内容：…… 只要登录了每天打开一次软件就会自动签到 ……
///
/// 它用的是 `.alert_info` 这个容器，和真正的错误提示同一个选择器。早先保存
/// 修改后服务端跳回帖子页，客户端把这条记录当成「页面消息」，又因为记录里
/// 引用了正文中的「登录」二字被判成错误，于是停在编辑页弹一条红字。
///
/// 更重要的是：这条记录不是正文。编辑时若把它塞进输入框，保存后又会被
/// 写成正文的一部分，下一次编辑再叠一条新的，越滚越脏。
library;

/// 是不是「本帖最后由 … 编辑」这类编辑记录。
bool isEditNote(String text) => text.trimLeft().startsWith('本帖最后由');

/// 编辑记录在 HTML 里的容器：`<i class="pstatus">` 和 `.comiis_edit`。
final RegExp _editNoteHtml = RegExp(
  r'<(i|em|span|div|p)[^>]*class="[^"]*(pstatus|comiis_edit)[^"]*"[^>]*>.*?</\1>',
  dotAll: true,
  caseSensitive: false,
);

/// 纯文本形式的编辑记录。
///
/// 时间格式各模板不一：`2026-11-6`、`2026-11-06`、`2026/11/6` 都见过，月份
/// 和日期补不补零没有规律，所以这里只认「本帖最后由」开头、到「编辑」收尾，
/// 按行吃掉。
final RegExp _editNoteText = RegExp(
  r'^[ \t\u3000]*本帖最后由[^\n]{0,80}?编辑[^\n]*',
  multiLine: true,
);

/// 从正文里剔掉编辑记录。
///
/// 既处理带标签的（帖子 HTML），也处理已经被转成纯文本的（编辑框初值）。
String stripEditNote(String text) {
  var result = text.replaceAll(_editNoteHtml, '');
  result = result.replaceAll(_editNoteText, '');
  // 剔除后常留下空行，正文顶部的空行没必要留着。
  result = result.replaceAll(RegExp(r'^[ \t\u3000]*\n+'), '');
  return result.trim();
}
