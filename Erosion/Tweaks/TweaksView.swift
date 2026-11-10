//
//  TweaksView.swift
//  Erosion
//
//  Created by lunginspector on 8/26/26.
//

import SwiftUI


struct TweaksView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("本机权限验证（支持在 iOS 26.6 运行）", destination: MGAccessCheckView())
                } header: {
                    HeaderLabel("兼容性验证", symbol: "checkmark.shield")
                }
                Section {
                    NavigationLink("自定义锁屏壁纸", destination: PosterBoardView())
                    NavigationLink("拨号键盘美化", destination: KeypadView())
                } header: {
                    HeaderLabel("美化外观", symbol: "paintbrush")
                }
                
                Section {
                    if raveSupported() || weOnADebugBuild {
                        NavigationLink("MobileGestalt 修改", destination: GestaltView())
                        NavigationLink("系统配置与监管", destination: ConfigView())
                    }
                    NavigationLink("任意文件替换", destination: OperationsView())
                } header: {
                    HeaderLabel("系统底层", symbol: "gear")
                }
            }
            .navigationTitle("功能修改")
        }
    }
}
