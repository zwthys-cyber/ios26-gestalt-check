// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Foundation

struct MGAccessCheckView: View {
    @State private var running = false
    @State private var report = "尚未验证。"

    var body: some View {
        List {
            Section {
                Text("第二版检测：尝试 geod 和直接容器查询两条新路线，再测试 MobileGestalt 文件的实际读写打开与权限释放。检测不会修改系统配置。")
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
            "Erosion iOS 26.6 permission check v2 (geod / class 13)",
            "时间：\(Date().formatted(.iso8601))",
            "系统：\(UIDevice.current.systemVersion) (\(buildNumber()))",
            "设备：\(machineName())",
            "此报告不包含 Apple ID、证书私钥或系统配置内容。"
        ]
        group = wq.getAppGroup()
        let hasGroup = fm.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
        lines.append(hasGroup ? "签名检查：存在可打开的 App Group 容器。" : "签名检查：没有可打开的 App Group；本轮两条查询不依赖此权限，继续检测。")
        lines.append("本轮不重复 worse_query。只检测固定 MobileGestalt 目标，不枚举其他应用数据。")
        let url = MGURL.fsGestaltURL
        let passed = MGCheckContainerRoutes({ message in
            lines.append(message)
        }, { phase in
            let inspection = inspectMGPermissions(at: url)
            lines.append("\(phase)：\(inspection.detail)")
            if inspection.passed { return .available }
            return inspection.writeOpenDenied ? .writeDenied : .unknown
        })
        lines.append(passed
            ? "结果：新路线通过临时读写打开与释放检查。尚未验证实际写入、地区修改或 Apple 智能功能。"
            : "结果：本轮未确认可用的新授权路线。请保留完整分阶段报告；这不是解锁成功。")
        lines.append("检测结束：未应用地区修改，未执行系统文件写入。")
        report = lines.joined(separator: "\n\n")
    }
}
