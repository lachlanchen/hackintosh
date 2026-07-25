[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

# Hackintosh Sequoia 復原實驗室

這是 Dell OptiPlex 7050 雙啟動開發工作站的私人維運參考。Monterey
12.7.6 保留為長期安全復原系統，Sequoia 15.7.7 作為開發系統。

已驗證結果：

- OpenCore 1.0.7
- Intel HD530 透過 WhateverGreen 映射為 Kaby Lake `0x5912`
- 1536 MB 動態顯示記憶體與 Metal 3
- Sequoia 系統卷維持 Apple 原始密封狀態，不使用 OCLP 圖形根補丁
- Monterey 與 Sequoia 動態共享同一個 APFS 容器空間

[英文主文件](../README.md)包含完整升級時間線、復原流程、更新政策與
參考來源。本儲存庫不提交 EFI、裝置身分、密碼、Apple 帳戶狀態或 Apple
軟體。

## 支持

[GitHub Sponsors](https://github.com/sponsors/lachlanchen) ·
[捐助](https://chat.lazying.art/donate) ·
[PayPal](https://paypal.me/RongzhouChen) ·
[Stripe](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400)

