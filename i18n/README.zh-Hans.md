[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

# Hackintosh Sequoia 恢复实验室

这是 Dell OptiPlex 7050 双启动开发工作站的私有运维参考。Monterey
12.7.6 作为长期安全恢复系统保留，Sequoia 15.7.7 作为开发系统使用。

已验证结果：

- OpenCore 1.0.7
- Intel HD530 通过 WhateverGreen 映射为 Kaby Lake `0x5912`
- 1536 MB 动态显存与 Metal 3
- Sequoia 系统卷保持 Apple 原始密封状态，不使用 OCLP 图形根补丁
- Monterey 和 Sequoia 动态共享同一个 APFS 容器空间

[英文主文档](../README.md)包含完整升级时间线、恢复流程、更新策略和
参考来源。本仓库不会提交 EFI、设备身份、密码、Apple 账户状态或 Apple
软件。

## 支持

[GitHub Sponsors](https://github.com/sponsors/lachlanchen) ·
[捐助](https://chat.lazying.art/donate) ·
[PayPal](https://paypal.me/RongzhouChen) ·
[Stripe](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400)

