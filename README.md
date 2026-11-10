> 此仓库用于在 GitHub Actions 验证和编译 Erosion 检测版、GestaltX 原版。
> **不是已验证的 iOS 26.6 解锁版本。** 保留上游功能版本限制。
> Erosion「功能修改 → 本机权限验证」现为 v2：检测 geod class 12 和 MobileGestalt class 13 两条不同于 worse_query 的临时授权路线。检测固定目标的读取、结构、O_RDWR 打开和授权释放，不写系统配置，也不保留已获得的权限。
> GitHub 仅测试构建、打包、内嵌权限及文件检测逻辑；真实 iPhone 沙盒权限和 Apple 智能效果未在 CI 验证。
> IPA 为 ad-hoc 签名，需要使用自己的证书及具备 App Group 的描述文件重新签名后安装。验证版使用独立 Bundle ID。
> Erosion 上游基准：`76a9f1e490e4c533438ca722666598a11ebe9598`；GestaltX 基准：`36110fd7544ceefdc419e13d337ec515e3ec53dc`。
> 新查询依据：[Geod-MCM-PoC](https://github.com/0xjohnnydev/Geod-MCM-PoC/tree/1d64e79d326dd8643a7b70dc1899dd3c07f69591) 的公开接口研究。上游称支持 iOS 26，但没有据此认定 iPhone18,2 / 23G71 可用；需要本机 v2 报告。CI 的模拟测试只验证拒绝分支、固定路径检查和清理逻辑。

<div align="center">
  <br>
  <a href="https://github.com/Kianuni/Erosion-CN/releases/latest"><img src="./PreviewIcon.png" alt="App Icon" width="150"></a>
  <br>
  <h1>Erosion-CN</h1>
  <p>基于 <a href="https://github.com/forcequitOS/worse_query">worse_query</a> 的 iOS / iPadOS 系统配置与 MobileGestalt 研究工具箱（简体中文防白苹果安全加固版）</p>
  <p>支持 iOS / iPadOS 27.0 – 27.2 / 27.3 beta 1（完整支持）以及 iOS / iPadOS 26.x（部分支持）。</p>
  <a href="https://github.com/Kianuni/Erosion-CN/releases/latest"><img alt="GitHub Releases" src="https://img.shields.io/github/v/release/Kianuni/Erosion-CN?style=flat-square&color=CF7D46&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC"></a>
  <a href="https://github.com/jailbreakdotparty/Erosion"><img alt="Upstream Repo" src="https://img.shields.io/badge/%E4%B8%8A%E6%B8%B8%E4%BB%93%E5%BA%93-jailbreakdotparty%2FErosion-3868DB?style=flat-square"></a>
  <a href="./LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue?style=flat-square"></a>
</div>

---

## 项目简介与核心改进

**Erosion-CN** 分支衍生自官方上游项目 **[jailbreakdotparty/Erosion](https://github.com/jailbreakdotparty/Erosion)**，完成了 **100% 简体中文界面本地化**，修复了原版多项严重真机 Bug，并进行了系统级防白苹果安全加固与底层能力扩展：

1. **修复重启后修改自动失效还原（反弹回原厂状态）的严重 Bug**
   - 原版在未手动切换过设置开关时，`mgWriteAtomically` 默认返回 `false`，导致实际走了临时文件替换（`replaceItemAt`），破坏了系统缓存文件的 Inode 与 `_mobilegestalt` POSIX 属主权限，设备一重启即被系统丢弃重建；同时原版在 iOS 27 上额外注入了非缓存键 `RegionInfo`（`zHeENZu+wbg7PUprwNwBWg`），触发开机缓存合法性校验整包重置。
   - 本分支已默认强制锁定原位覆盖写入，严格遵循 iOS 27 原厂缓存键结构，并自动匹配写入对应机型的监管型号（`RegulatoryModelNumber`），**真正做到持久化生效、重启不反弹**。
2. **修复内置 Plist 编辑器破坏布尔值与相机浮点参数导致「相机黑屏」的严重 Bug**
   - 原版 `PlistManager` 将 `CFBoolean`（`<true/>` / `<false/>`）以及整数值 `Double`（如相机变焦倍率 `1.0`、`2.0`、`5.0` 等）误判转换为了 `<integer>` 整型，导致编辑保存 `MobileGestalt` 后系统相机取景直接黑屏。
   - 本分支改用 `CFBooleanGetTypeID()` 与 `CFNumberIsFloatType()` 精确识别底层 CoreFoundation 类型，保留原始 Plist 根类型与编码格式，并对未修改项执行 **100% 原样无损直通（Lossless Pass-through）**，彻底解决相机黑屏问题。
3. **零 0 字节窗口原位写入协议（`pwrite` + 按需尾截断 + `F_FULLFSYNC`）**
   - 重构底层文件 I/O：不再先执行 `ftruncate(fd, 0)` 清空系统文件，而是直接从偏移 `0` 原位覆盖写入、写完后按需裁剪尾部，并调用 `fcntl(fd, F_FULLFSYNC)` 强制刷新 APFS 与物理闪存缓存，断电或异常中断绝不留空文件。
4. **写入前变更对比预览（Diff Preview）+ 写后全量读回校验与自动回滚**
   - 点击「应用」时逐条展示所有待修改键值与十六进制槽位对比（`修改前 → 修改后`）；
   - 写入前自动保存 `PreApplyGestalt.plist` 快照，写入后立即从磁盘读回并做二进制 Plist 反序列化与严格类型校验，一旦出现任何不一致立即自动原位回滚。
5. **本机 `libMobileGestalt.dylib` 运行时动态偏移解析（零硬编码）**
   - 在设备运行时只读扫描内存中加载的 `/usr/lib/libMobileGestalt.dylib` 查询描述符表，实时计算当前机型与当前系统版本的 `CacheUUID`、总槽位数及布尔槽位偏移（`green-tea`、`not-green-tea`、`wapi`）；
   - **严格多重校验门控**：仅当本机 `CacheUUID` 唯一匹配、总长度精确等于 `槽位数 × 9`、有效位 `validity == 1`、8 字节槽位填充全为 `0` 且无任何无关字节变动时才允许修改；解析未通过时自动锁定开关并拦截写入。
6. **跨机型 / 跨系统升级三重指纹防呆与云备份隔离**
   - 本地备份文件自动标记 `isExcludedFromBackup = true`，防止通过 iCloud / 电脑换机迁移时将旧设备的缓存备份带入新设备；
   - 还原原始备份时强制核对 `CacheVersion`、`CacheUUID` 与本机硬件 `ProductType`；系统 OTA 升级后首次打开可自动识别新版本构建号并提示刷新备份。
7. **重签证书 `App Group` 自动探测与高危软砖项拆除**
   - 运行时通过 `SecTaskCopyValueForEntitlement` 与纯 Swift Mach-O `LC_CODE_SIGNATURE` 签名段解析自动匹配任意重签工具注入的可用 `group.*` 容器；
   - 默认移除并拦截上游版本中存在软砖/无限设置向导隐患的高危功能（如 iPhone 正则盲改切片的 iPadOS 模式、个人零售设备的监管模式开关、非缓存键注入等）。
8. **完善机型适配与实用工具优化**
   - 补全 iPhone 15 / 16 / 17 / Air / 18 / Duo 全系列及 M 系列 iPad 监管型号映射与硬件特征表，修复原版“80% 充电上限”与“开机提示音”硬件判断互换笔误及自定义键值恒写入 `true` 的 Bug；
   - 新增 iOS 26/27「液态玻璃低功耗渲染（省电模式）」开关与机型外层描述同步；
   - 修复文件浏览器搜索栏失效与失焦清空问题，提升高 Inode 容器扫描上限并新增核心缓存目录 0 秒一键直达入口。

---

## 系统兼容性

> [!IMPORTANT]
> 操作前请务必通过电脑完整备份设备重要数据！修改系统底层配置存在潜在风险，仅供安全研究与学习交流，请仅在本人持有的设备上使用并自行承担风险。

- **iOS / iPadOS 27.0 – 27.2**、**27.3 beta 1**（完整支持所有功能，包括 `MobileGestalt` 读取与安全写入）
- **iOS / iPadOS 26.0 – 26.7.2**（部分支持：可使用锁屏壁纸、拨号键盘美化与部分容器浏览；受底层沙盒限制，iOS 26 不支持写入系统 `MobileGestalt`）

---

## 安装与签名要求

> [!WARNING]
> 本项目底层依赖至少一个有效的 `App Group` 容器权限。请使用支持保留或注入 App Group 的个人 Apple ID 自签工具（如 **SideStore / AltStore / Feather / Sideloadly / Impactor / iLoader**）或带 App Group 权限的开发者证书签名安装。

1. 前往 [Releases 页面](https://github.com/Kianuni/Erosion-CN/releases/latest) 下载最新的 `Erosion_v0.5.1_zh-Hans.ipa`。
2. 使用上述签名工具安装至设备；首次运行可在「主页」日志确认已成功识别 `App Group`。
3. 详细使用说明与原厂状态恢复教程请查阅：
   - 📘 [USAGE_GUIDE.md（安装与使用指南）](./USAGE_GUIDE.md)
   - 🔄 [RESTORE_CHA.md（无损恢复出厂状态指南）](./RESTORE_CHA.md)

---

## 自行编译

在安装有 Xcode 26 / 27 的 macOS 环境中克隆本仓库并执行构建脚本即可生成未签名 `.ipa`（已自动内嵌标准 entitlements）：

```bash
git clone https://github.com/Kianuni/Erosion-CN.git
cd Erosion-CN
chmod +x ipabuild.sh
./ipabuild.sh
```

---

## 致谢与开源许可 (Credits & License)

本项目基于 **[GNU General Public License v3.0 (GPLv3)](./LICENSE)** 开源，谨向上游作者与社区研究者致以诚挚感谢：

### 特别致谢（特性借鉴与研究参考）
- **[huamidev / GestaltX](https://github.com/huamidev/GestaltX)** — 特别感谢 `GestaltX` 项目的优秀工程设计与思路启发，本分支的本机 `libMobileGestalt.dylib` 查询描述符动态偏移解析、变更对比预览（Diff Preview）、写后磁盘读回校验、运行时重签 `App Group` 自动探测以及液态玻璃低功耗渲染键值等改进均借鉴并参考了 `GestaltX` 的设计。
- **[KirbySD](https://www.v2ex.com/t/1246550)** — 感谢分享 `MobileGestalt` 二进制 `CacheData` 中 `green-tea` / `not-green-tea` 布尔槽位的原始研究思路。
- **[PoomSmart / MGKeys](https://github.com/PoomSmart/MGKeys)** — 感谢长期维护与整理 `MobileGestalt` 混淆键值映射表。

### 上游主项目与漏洞研究致谢
- **[jailbreakdotparty / Erosion](https://github.com/jailbreakdotparty/Erosion)** & **[lunginspector](https://github.com/lunginspector)** — 上游主仓库与核心架构作者
- **[forcequitOS](https://github.com/forcequitOS)** & **[0xjohnnydev](https://github.com/0xjohnnydev)** — `worse_query` 沙盒研究作者
- **[skadz108](https://github.com/skadz108)** & **[rooootdev](https://github.com/rooootdev)** — 后端功能组件维护者
- **[neonmodder123](https://github.com/neonmodder123)** — 免越狱注销方案作者

---

## 免责声明

本项目仅供 iOS 系统安全研究、逆向工程学习与技术交流使用。请严格遵守所在地法律法规与电信合规要求，切勿用于任何非法用途；开发者不对因使用本软件造成的任何数据丢失、功能异常或售后问题承担责任。
