# 在 GitHub 上编译 iOS App

本仓库直接使用 YALA 的 Flutter iOS 工程，不整合 AX3000T 刷机工具。
Flutter 依赖、静态分析、自动测试和 Xcode 编译均由 GitHub 托管运行器执行，
不需要在个人服务器安装 Flutter、CocoaPods 或 Xcode，也不需要连接路由器。

## 下载与自行签名

1. 打开本仓库的 **Actions → Build iOS IPA**。
2. 选择成功的运行记录，或使用 **Run workflow** 手动编译。
3. 在页面底部 Artifacts 下载 `YALA-iOS-unsigned-运行编号`，解压。
4. 得到 `YALA-unsigned.ipa`、SHA-256 文件和 `verification.json` 验证报告。
5. 使用自己的签名工具和 Apple 账号签名后安装。未签名 IPA 不能直接安装。

该流程不需要向 GitHub 上传 Apple 证书或路由器密码。当前工程最低 iOS 版本为 15.0。
手动构建可选填版本号和构建编号；留空使用 `pubspec.yaml` 的版本。
此构建保留原作者署名，不设置上游的 `OFFICIAL_BUILD=true` 标记。

## 自动验证范围

推送至 main 或提交到 main 的 PR 会启动流程。首先检查 Dart 格式、
静态分析和测试，全部成功后分配两项独立的 macOS 任务：编译 arm64 iPhone release
应用，以及在 iPhone 模拟器上启动 App、验证登录页并保存截图。两项任务并行执行，
模拟器截图位于独立的 `YALA-iOS-simulator-运行编号` 产物中。
IPA 产物生成不代表模拟器任务已经成功，请同时检查整次工作流的结果。
打包检查平台、可执行文件架构、本地网络权限说明、Flutter 资源、IPA 目录和 ZIP 完整性。
Actions 页面保留测试日志、构建日志和产物；下载后也可核对 SHA-256。

这些检查不代表已经在真实 iPhone 或真实路由器上测试。安装后需要允许 iOS 的
“本地网络”访问，在同一个局域网内用路由器管理地址和 root 管理密码登录。

## AX3000T RD03v2 固件背景

用户提供的固件记录为 OpenWrt SNAPSHOT v2.0.2，修订
`r0+37778-bc808b8504`，管理地址曾设置为 `192.168.10.1`。
这属于固件发布版本，不应当成 OpenWrt 官方 2.0.2 版本。
YALA 使用 LuCI/ubus RPC，并支持 APK 包管理；是否具备全部 RPC 服务要以当前设备检查为准。

用户提供的只读检查已确认 `/ubus` 路径以及 `session.login`、`luci`、`file.exec`
（参数名为 `params`）、`iwinfo` 接口存在。未安装旧版 `luci-mod-rpc`，但 YALA
优先使用 ubus 登录，无需仅为旧接口先安装该包。HTTP 登录后实际 ACL 权限仍需 App 验证。
设备还运行 OpenClash；此构建保留现有功能，不新增 OpenClash 专用控制面板，
也不修改设备的代理、DNS 或防火墙配置。

该固件曾发生 ucode/LuCI/RPC ABI 配套问题。YALA 的“修复权限”功能会写入 ACL、
安装软件包并重启 RPC 服务；请先确认依赖配套再执行，不能将它当成只读检测。
编译过程不会触发这些操作。固件详情参考用户提供的
[硬件验证记录](https://github.com/zwthys-cyber/ax3000t-ish-client/blob/main/docs/HARDWARE-VALIDATION.zh-CN.md)。

SSH 登录路由器后可进行以下只读检查（iSH 的 localhost 不是路由器）：

```sh
cat /etc/openwrt_release
for p in luci-base luci-mod-rpc rpcd rpcd-mod-luci rpcd-mod-ucode rpcd-mod-iwinfo uhttpd uhttpd-mod-ubus; do
  apk info -e "$p"
done
ubus -v list session
ubus -v list luci
ubus -v list file
ubus -v list iwinfo
uci -q get uhttpd.main.ubus_prefix
```
