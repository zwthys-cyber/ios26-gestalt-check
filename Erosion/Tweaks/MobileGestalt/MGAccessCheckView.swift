// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Foundation

struct MGAccessCheckView: View {
    @State private var running = false
    @State private var report = "尚未验证。"

    var body: some View {
        List {
            Section {
                Text("先检查签名中的 App Group，再请求本机 MobileGestalt 目录权限并测试读写打开。检测不会修改系统配置。")
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
            "Erosion iOS 26.6 permission check v1",
            "时间：\(Date().formatted(.iso8601))",
            "系统：\(UIDevice.current.systemVersion) (\(buildNumber()))",
            "设备：\(machineName())",
            "此报告不包含 Apple ID、证书私钥或系统配置内容。"
        ]
        group = wq.getAppGroup()
        guard fm.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
            lines.append("签名检查失败：当前签名没有可打开的 App Group 容器。请用支持 App Group 的描述文件重新签名；这是签名问题，尚未测试系统权限。")
            report = lines.joined(separator: "\n\n")
            return
        }
        lines.append("签名检查通过：存在可打开的 App Group 容器。")
        let url = MGURL.fsGestaltURL
        let before = inspectMGPermissions(at: url)
        if before.passed {
            lines.append("现有权限：\(before.detail)")
        } else {
            let access = wq.grantAccess(path: url.deletingLastPathComponent().path)
            lines.append("worse_query 目录授权：\(access.0 ? "通过" : "失败")；返回值 \(access.1)")
            if !access.0 { lines.append("授权说明：\(access.2)") }
            let after = inspectMGPermissions(at: url)
            lines.append("实际文件检测：\(after.detail)")
            if !after.passed {
                lines.append("结果：当前环境没有通过本机修改的前置验证。修改系统版本判断、重新编译或换界面，均不能替代缺失的文件访问权限。")
            }
        }
        lines.append("检测结束：未应用地区修改，未执行系统文件写入。")
        report = lines.joined(separator: "\n\n")
    }
}
