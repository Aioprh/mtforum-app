# MT论坛 客户端

MT论坛（bbs.binmt.cc）的 Flutter 原生客户端。基于 Discuz 移动端页面解析，不使用 WebView 套壳。

## 功能

- 首页信息流：最新 / 回复 / 热门 / 精华，官方公告
- 版块分类与版块主题列表
- 帖子详情：原生富文本渲染、楼层分页、图片查看、回复、收藏、分享
- 消息提醒：我的帖子 / 坛友互动 / 系统提醒 / 应用提醒，提醒直达帖子、用户或私信
- 登录、搜索、发帖
- 我的：资料、我的主题 / 回复 / 收藏、我的关注 / 我的粉丝、主题切换、关于
- Cookie 本地持久化；纯 Dart 实现站点 `acw_sc__v2` 安全校验

## 目录结构

```
lib/
  core/       配置、HTTP 会话、WAF 求解、主题
  data/       模型与 Discuz 页面解析
  state/      全局状态
  ui/pages/   页面
  ui/widgets/ 通用组件与帖子 HTML 渲染
```

## 本地构建

```bash
flutter pub get
flutter build apk --release              # 通用包
flutter build apk --release --target-platform android-arm64  # arm64 单架构
```

产物位于 `build/app/outputs/flutter-apk/`。

## 云端构建

推送到 `main` 或手动触发 `Build APK` workflow，会自动构建并上传 APK 产物。
推送 `v*` 标签会额外创建 GitHub Release 并附加 APK。

```bash
git tag v1.0.1
git push origin v1.0.1
```

## 说明

- 当前 release 使用 debug 签名，便于直接安装测试；正式分发请配置自己的签名。
- 站点可能更新前端模板或安全校验，如解析失效请对照 `lib/data/forum_repository.dart` 调整选择器。
