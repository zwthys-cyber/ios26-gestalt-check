// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Foundation

struct MGAccessCheckView: View {
    @State private var running = false
    @State private var report = "尚未验证。"

    var body: some View {
        List {
            Section {
                Text("v3 检测：复测 worse_query 的标准和备用模式，检查 MobileGestalt 文件读写打开及临时权限释放。只在应用 App Group 的空缓存目录中准备临时链接，不写入系统文件。")
                Text("GitHub 编译成功只证明软件可以构建。本机权限和 Apple 智能是否可用，需要分别验证。")
                    .foregroundStyle(.secondary)
                Button(running ? "正在验证…" : "开始本机验证") {
                    running = true
                    Task { @MainActor in
                        await Task.yield()
                        runCheck()
                        running = false
                    }
                }
                .disabled(running)
            }
            Section("验证报告") {
                Text(report)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                ShareLink("分享验证报告", item: report)
                    .disabled(running || report == "尚未验证。")
            }
        }
        .navigationTitle("本机权限验证")
    }

    private func runCheck() {
        var lines = [
            "Erosion permission check v3 (worse_query / post-OTA)",
            "时间：\(Date().formatted(.iso8601))",
            "系统：\(UIDevice.current.systemVersion) (\(buildNumber()))",
            "设备：\(machineName())",
            "此报告不包含 Apple ID、证书私钥或系统配置内容。"
        ]
        group = wq.getAppGroup()
        let groupRoot = fm.containerURL(forSecurityApplicationGroupIdentifier: group)
        lines.append(groupRoot != nil ? "签名检查：存在可打开的 App Group 容器。" : "签名检查：没有可打开的 App Group。")
        lines.append("本轮复测 worse_query，不重复 v2 的 geod / class 13 查询。只检测固定 MobileGestalt 目标。")
        let url = MGURL.fsGestaltURL
        let passed = checkMGWorseQueryRoutes(
            hasAppGroup: groupRoot != nil,
            prepare: {
                guard let groupRoot else { return "App Group 不可用。" }
                return prepareMGCheckCaches(at: groupRoot)
            },
            inspect: { inspectMGPermissions(at: url) },
            query: { alternate in
                worse_query(url.deletingLastPathComponent().path, group, alternate, false)
            },
            release: { worse_query_release($0) },
            record: { lines.append($0) }
        )
        lines.append(passed
            ? "结果：worse_query 通过临时读写打开与释放检查。尚未验证实际写入、地区修改或 Apple 智能功能。"
            : "结果：本轮未确认 worse_query 通过完整权限检查。请保留分阶段报告。")
        lines.append("检测结束：未应用地区修改，未执行系统文件写入。")
        report = lines.joined(separator: "\n\n")
    }
}
