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
`run_simulator` 默认为关闭，只有需要检查模拟器启动或登录页截图时才勾选。
此构建保留原作者署名，不设置上游的 `OFFICIAL_BUILD=true` 标记。

## 自动验证范围

推送至 main 或提交到 main 的 PR 会启动流程。首先检查 Dart 格式、
静态分析和测试，全部成功后编译 arm64 iPhone release 应用并导出 IPA。
默认跳过耗时较长的模拟器任务，模拟器不再影响日常 IPA 构建的完成状态。

需要模拟器验证时，手动运行工作流并勾选 `run_simulator`。该任务会启动 App、
验证登录页并保存截图，产物为 `YALA-iOS-simulator-运行编号`。
它与 IPA 编译并行执行；勾选后仍需检查模拟器任务是否成功。
模拟器被跳过时，不表示 App 启动已经通过该项验证。
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
“更多 → OpenClash”提供安装/运行状态、Mihomo 版本、启动/停止/重启服务、
规则/全局/直连模式切换和手动代理组的节点选择。自动测速、故障转移组只展示当前节点。
通过当前路由器的已认证 `file.exec` 会话调用本机控制接口；234 起，RPC 命令权限
不足时自动使用 App 保存的路由器账户通过 SSH（22 端口）连接，不修改 ACL。
要求路由器安装 curl，并具备 RPC 命令执行权限或可用的 SSH 登录；
控制密钥仅在路由器本机读取，不保存到手机，也不需要开放控制端口。
只有用户主动操作时才改变服务、模式或节点，不自动安装/升级插件或内核。
一次刷新合并状态、版本、模式和代理组读取，避免反复建立 SSH 连接。
服务操作可能短暂影响网络；后台命令完成后才检查运行状态和控制接口就绪情况，
失败、超时或切换路由器都不会误报完成。
App 尚需在真实 iPhone 上验证这些操作。

构建号 235 起，节点名称或控制接口响应中的 `Access denied` 等文字不会被当成
RPC 权限拒绝。只有 RPC 权限拒绝才触发 SSH 回退；已经执行但失败的命令不会
通过另一种连接方式重试。未设置控制端口时，读取和控制均使用默认的 9090。
OpenClash 页面新增“资源与诊断日志”，沿用项目主题和可折叠卡片，分别展示物理
可用内存、交换空间、zram 实际内存占用和系统负载。资源只在打开或手动刷新时读取；
日志由用户手动读取，限制读取量并隐藏常见敏感字段和 URL，不后台轮询、不上传日志。

构建号 236 起，“订阅与配置”支持订阅新增、编辑、启用/停用、删除和手动更新；
新订阅使用 HTTP/HTTPS YAML 地址，已有订阅的转换、过滤等高级字段保持原值。
更新使用 OpenClash 自带脚本的 `norestart` 方式，完成后需要主动切换配置或重启应用。
配置支持列表、UTF-8 YAML 文件导入、新建、编辑、删除、切换并重启服务。
编辑器上限为 64 KiB，在手机检查 YAML 语法，不代表内核语义检查已经通过。
写入前检查内容版本，已有文件先备份再原子替换；不能删除当前选中的配置，
拒绝路径穿越和符号链接。备份留在路由器 `/etc/openclash/.yala-backups`。
订阅地址只在用户编辑时读取并默认隐藏，不写入 App 日志或构建产物。
配置编辑器按需读取文件原文，可能包含节点凭据；内容不写入 App 本地存储或日志。
管理功能需要路由器已具备 ucode 及 fs、uci、digest 模块，不会自动安装这些依赖。
这些操作不会自动安装软件包，也不启用第三方在线订阅转换。

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

## 无线开关权限兼容

构建号 234 起，SSID 和射频开关使用 LuCI 的 `uci.set → uci.apply` 流程，
不再要求默认 LuCI ACL 未授予的 `uci.commit` 或额外的 shell 命令权限。
写入、应用或核验失败时提示具体 RPC 阶段；清理失败不会覆盖原始错误，
也不会声称已经回滚。此修改不会自动安装 RPC 包或放宽路由器 ACL。
主动关闭当前连接的 SSID/射频仍会断开手机 Wi-Fi，请保留其他管理通道。
