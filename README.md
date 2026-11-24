# MCT-HarmonyOS

MIFARE Classic Tool（MCT）的 HarmonyOS 原生移植版。

基于 Gerhard Klostermeier 的开源项目
[ikarus23/MifareClassicTool](https://github.com/ikarus23/MifareClassicTool)（GPL-3.0）
移植，使用 ArkTS / ArkUI 开发。界面与功能与原版保持一致（简体中文）。

## 功能

- **读标签**：通过密钥文件映射扇区密钥，读取 MIFARE Classic 标签并保存为转储文件
- **写标签**：写入块 / 值块 / 整卡转储
- **编辑 / 分析转储文件**：转储编辑器（内嵌 AC 解码器、diff、值块解码等）
- **编辑 / 新建密钥文件**：管理密钥字典（`.keys` 纯文本格式）
- **工具集**：标签信息、克隆 UID、差异比对、访问条件编/解码、值块编/解码、
  BCC 计算器、数据转换、UID 日志、导入/导出/转换文件
- **离线编辑模式**：无 NFC 设备也可编辑/分析转储与密钥文件
- 完整偏好设置（自定义扇区数、自动重连、重试认证、UID 自动复制等）

## 环境要求

- HarmonyOS NEXT（API 12+）设备，读取/写入标签时需支持 NFC
- 构建环境：DevEco Studio 5.0+ / HarmonyOS SDK

## 安装

1. 从 [Releases](../../releases) 下载 `entry-default-signed.hap` 并安装到设备；或
2. 用 DevEco Studio 打开本工程，连接设备后运行。

> 首次启动会显示免责声明。请确认理解 MIFARE Classic 操作风险后再使用；
> 向标签写入错误数据可能造成不可修复的损坏。

## 使用文档

详见 [docs/使用文档.md](docs/使用文档.md)。

## 许可证

本项目以 [GPL-3.0](LICENSE) 许可证发布，与上游项目一致。

MIFARE® 是 NXP Semiconductors 的注册商标。
