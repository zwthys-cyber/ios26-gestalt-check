// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

// The upstream query replaces App Group Library/Caches temporarily. Refuse to
// invoke it if doing so would delete cached data or follow an existing symlink.
func prepareMGCheckCaches(at groupRoot: URL) -> String? {
    let files = FileManager.default
    let library = groupRoot.appendingPathComponent("Library", isDirectory: true)
    let caches = library.appendingPathComponent("Caches", isDirectory: true)
    for url in [library, caches] {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            guard errno == ENOENT else { return "无法检查 App Group 缓存目录；停止检测。" }
            do {
                try files.createDirectory(at: url, withIntermediateDirectories: false)
            } catch {
                return "无法准备 App Group 缓存目录；停止检测。"
            }
            guard lstat(url.path, &info) == 0 else { return "无法复核 App Group 缓存目录；停止检测。" }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            return "App Group 缓存路径不是普通目录；停止检测，不移除现有内容。"
        }
    }
    do {
        guard try files.contentsOfDirectory(atPath: caches.path).isEmpty else {
            return "App Group 缓存目录非空；停止检测以保留现有数据。请使用独立的空 App Group 后重试。"
        }
    } catch {
        return "无法确认 App Group 缓存目录为空；停止检测。"
    }
    return nil
}

private func mgQueryFailure(_ code: Int64) -> String {
    switch code {
    case -1: return "容器访问或 sandbox token 激活失败"
    case -2: return "系统库或必要接口不可用"
    case -3: return "无法创建查询"
    case -4: return "App Group 临时链接创建失败"
    case -5: return "查询未返回可用容器"
    case -6: return "系统未签发非空 sandbox token"
    case -255: return "目标目录不存在"
    default: return "查询返回未识别的错误"
    }
}

// Injectable callbacks let GitHub tests exercise the complete decision and
// release flow without invoking private APIs or touching a system cache.
func checkMGWorseQueryRoutes(
    hasAppGroup: Bool,
    prepare: () -> String?,
    inspect: () -> MGPermissionInspection,
    query: (Bool) -> Int64,
    release: (Int64) -> Void,
    record: (String) -> Void
) -> Bool {
    guard hasAppGroup else {
        record("没有可打开的 App Group；停止 worse_query 检测。")
        return false
    }
    let baseline = inspect()
    record("初始文件权限：\(baseline.detail)")
    guard !baseline.passed else {
        record("初始检测已能读写打开；未申请新授权，不能归因于本轮路线。请彻底退出应用后重试。")
        return false
    }
    guard baseline.writeOpenDenied else {
        record("未获得明确的只读权限基线，停止检测。")
        return false
    }

    for alternate in [false, true] {
        record(alternate ? "路线 B：worse_query 备用模式（alt_flags=true）"
                         : "路线 A：worse_query 标准模式（alt_flags=false）")
        if let problem = prepare() {
            record(problem)
            return false
        }
        let handle = query(alternate)
        record(handle >= 0 ? "查询成功：获得临时权限句柄。"
                           : "查询失败：返回值 \(handle)；\(mgQueryFailure(handle))。")
        let during: MGPermissionInspection
        do {
            // Includes handle zero and permission-inspection failures.
            defer { if handle >= 0 { release(handle) } }
            during = inspect()
            record("查询后实际文件检测：\(during.detail)")
        }
        let after = inspect()
        record("释放临时权限后复检：\(after.detail)")
        guard after.writeOpenDenied else {
            record("未确认恢复为读写打开被拒绝；停止后续检测。请彻底退出应用。")
            return false
        }
        guard handle >= 0 else { continue }
        if during.passed {
            record("本路线通过：临时授权期间可读写打开，释放后读写打开被拒绝。尚未测试写入。")
            return true
        }
    }
    return false
}
