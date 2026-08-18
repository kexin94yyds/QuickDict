# 快捷查词隐私说明

公开页面：https://kexin94yyds.github.io/quickdict-support/privacy.html

快捷查词默认在本机处理查词记录、收藏、复习进度、离线词典与设置，不建立开发者账号，也不使用广告、跟踪或分析 SDK。

## 权限用途

- 所选文本：Mac App Store 版本不请求输入监控或辅助功能权限，也不监听全局键盘事件。只有用户主动调用 macOS“用快捷查词查询”服务时，当前 App 才会把所选文本交给快捷查词。
- 剪贴板：只有用户主动选择菜单栏中的“测试查词 (手动)”时，快捷查词才读取当前剪贴板中的纯文本。
- 用户选择的文件：只在用户主动导入或导出词典、数据备份或旧版数据文件夹时访问所选位置。
- 网络：用于用户发起的 Wikipedia、Hacker News、Datamuse、ECDICT 下载，以及用户自行配置 Gemini API Key 后的中文转英文备用查询。

## 本地数据

单词本、查询历史、复习进度、复习设置、ECDICT 文件、联网释义缓存和图片缓存存放在快捷查词的 macOS 沙盒容器中。数据备份不会包含 Gemini API Key 或 ECDICT 数据库。Gemini API Key 存放在 macOS Keychain。

## 第三方请求

启用联网释义或 Gemini 备用查询时，查询词可能直接发送给对应第三方服务。快捷查词开发者不运营中转服务器，不接收这些查询，也不出售个人数据。用户可以不设置 Gemini API Key，并继续使用系统词典和离线 ECDICT。

## 删除与联系

用户可在 App 内删除单条记录；移除 App 及其沙盒容器可删除本机数据。隐私或支持问题可通过公开支持中心提交：https://github.com/kexin94yyds/quickdict-support/issues/new/choose
