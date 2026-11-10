// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

struct MGPermissionInspection {
    let readable: Bool
    let writable: Bool
    let validPlist: Bool
    let detail: String
    var writeOpenDenied: Bool = false
    var passed: Bool { readable && writable && validPlist }
}

// Checks actual file descriptors. Never writes, truncates, renames or deletes
// the target, even when an O_RDWR descriptor is successfully obtained.
func inspectMGPermissions(at url: URL) -> MGPermissionInspection {
    func result(_ readable: Bool, _ writable: Bool, _ valid: Bool, _ detail: String, denied: Bool = false) -> MGPermissionInspection {
        MGPermissionInspection(readable: readable, writable: writable, validPlist: valid, detail: detail, writeOpenDenied: denied)
    }
    let reader = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard reader >= 0 else {
        let code = errno
        return result(false, false, false, "读取被拒绝：errno=\(code) (\(String(cString: strerror(code))))")
    }
    defer { close(reader) }
    var original = stat()
    guard fstat(reader, &original) == 0,
          (original.st_mode & S_IFMT) == S_IFREG,
          original.st_size > 0, original.st_size <= 16 * 1024 * 1024 else {
        return result(false, false, false, "目标不是有效大小的普通文件。")
    }
    var bytes = Data(count: Int(original.st_size))
    let readOK = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress else { return false }
        var offset = 0
        while offset < buffer.count {
            let count = pread(reader, base.advanced(by: offset), buffer.count - offset, off_t(offset))
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    guard readOK else { return result(false, false, false, "无法完整读取目标文件。") }
    guard let root = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) as? [String: Any],
          let extra = root["CacheExtra"] as? [String: Any], !extra.isEmpty,
          let cache = root["CacheData"] as? Data, !cache.isEmpty else {
        return result(true, false, false, "可读取，但文件未通过 MobileGestalt 基础结构检查。")
    }
    let writer = open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard writer >= 0 else {
        let code = errno
        return result(true, false, true, "读取成功；读写打开被拒绝：errno=\(code) (\(String(cString: strerror(code))))", denied: code == EPERM || code == EACCES)
    }
    defer { close(writer) }
    var current = stat()
    guard fstat(writer, &current) == 0,
          current.st_ino == original.st_ino, current.st_dev == original.st_dev,
          current.st_size == original.st_size else {
        return result(true, false, true, "检查过程中目标文件发生变化，请重新验证。")
    }
    return result(true, true, true, "本机文件读取、结构检查与 O_RDWR 打开成功。未执行任何文件写入；这不代表功能已经解锁。")
}
