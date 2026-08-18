# QuickDict / 快捷查词

快捷查词是一款轻量的 macOS 菜单栏词典。它支持系统词典、可选的离线 ECDICT、macOS Services 选中文本查询、单词收藏、复习排期、历史记录和 JSON 备份。

![快捷查词查词界面](docs/app-store-screenshots/01-instant-lookup.png)

## 安装

- [从中国大陆 Mac App Store 下载](https://apps.apple.com/cn/app/id6799547792)
- 系统要求：macOS 13 或更高版本

快捷查词是菜单栏应用，启动后不会显示 Dock 图标或常驻主窗口。请在屏幕顶部菜单栏寻找书本图标；点开后可手动查词、打开单词本、下载离线词典或退出应用。

## 功能

- 从当前 App 的“服务”菜单查询选中的英文或中文文本
- 使用 macOS 系统词典与可选的离线 ECDICT
- 收藏单词、句子和上下文，并按轻量间隔复习
- 管理查询历史与单词本
- 导出、合并导入 JSON 数据备份
- 可选使用 Wikipedia、Datamuse、Hacker News 和用户自己的 Gemini API Key 补充结果
- App Store 版本不请求输入监控或辅助功能权限

## 从源码构建

要求：

- macOS 13+
- Xcode 与 Command Line Tools
- Swift 5.9+

运行单元测试：

```bash
swift test
```

构建 App：

1. 打开 `QuickDict.xcodeproj`。
2. 选择 `QuickDict` scheme 和 “My Mac”。
3. 在 Xcode 中运行。

项目也保留了 `project.yml`；安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 后可运行 `scripts/generate_xcode_project.sh` 重新生成 Xcode 工程。

本地开发用的 Swift Package 构建不带 `APP_STORE` 编译条件，会包含旧版全局快捷键实验路径；正式 App Store target 使用 `APP_STORE`，只通过标准 macOS Services 接收选中文本。

## 数据与网络

收藏、历史、复习进度、设置和离线词典保存在用户 Mac 上。应用没有开发者账号系统、广告、跟踪或分析 SDK。

ECDICT 数据不会打包进仓库或 App。用户选择下载时，应用会从 [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT) 获取其发布的数据库；该数据集遵循其上游许可。

完整说明见 [隐私文档](docs/PRIVACY.md) 和 [公开隐私页面](https://kexin94yyds.github.io/quickdict-support/privacy.html)。

## 参与贡献

欢迎提交 Issue 或 Pull Request。提交前请运行 `swift test`，并确保没有加入 API Key、证书、数据库、用户备份或构建产物。

- [问题与建议](https://github.com/kexin94yyds/QuickDict/issues)
- [帮助与支持](https://kexin94yyds.github.io/quickdict-support/)

## 许可证

源代码采用 [MIT License](LICENSE)。第三方服务、系统框架和可选下载的数据集仍遵循各自条款。
