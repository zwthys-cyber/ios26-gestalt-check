//
//  ErosionApp.swift
//  Erosion
//
//  Created by lunginspector on 8/14/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

let device = UIDevice.current
let fm = FileManager.default
var weOnADebugBuild = false
var pipe = Pipe()
var sema = DispatchSemaphore(value: 0)

@main
struct ErosionApp: App {
    @StateObject private var mgr = ErosionManager.shared
    @State private var currentTab = 0
    
    init() {
        UserDefaults.standard.register(defaults: [
            "mgWriteAtomically": true,
            "maxInode": 15000000
        ])
        if !UserDefaults.standard.bool(forKey: "mgAtomicDefaultMigrated") {
            UserDefaults.standard.set(true, forKey: "mgWriteAtomically")
            UserDefaults.standard.set(true, forKey: "mgAtomicDefaultMigrated")
        }
        
        setvbuf(stdout, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        #if DEBUG
        weOnADebugBuild = true
        #else
        weOnADebugBuild = false
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            #if MG_DIAGNOSTIC_ONLY
            NavigationStack {
                MGAccessCheckView()
            }
            #else
            TabView {
                ContentView()
                    .tabItem {
                        Label("主页", systemImage: "house")
                    }
                    .id(0)
                TweaksView()
                    .tabItem {
                        Label("功能修改", systemImage: "wrench.and.screwdriver")
                    }
                    .id(1)
                FMRootView()
                    .tabItem {
                        Label("文件浏览", systemImage: "folder")
                    }
                    .id(2)
            }
            .environmentObject(mgr)
            .onAppear {
                pipe.fileHandleForReading.readabilityHandler = { fh in
                    let data = fh.availableData
                    
                    if data.isEmpty {
                        fh.readabilityHandler = nil
                        sema.signal()
                        return
                    }
                    
                    guard let text = String(data: data, encoding: .utf8) else {
                        return
                    }
                    
                    DispatchQueue.main.async {
                        mgr.logOutput.append(text)
                    }
                }
                print("")
                print("[*] Erosion v\(AppInfo.appVersion) (\(build))")
                print("[*] 运行环境：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)，设备标识符：\(machineName()) (\(buildNumber()))")
                if !isSupported() && !weOnADebugBuild {
                    Alertinator.shared.alert(title: "当前 \(device.systemName) 版本暂不支持！", body: AppMsg.unsupported, showCancel: false, actionLabel: "退出", action: { exitinator() })
                }
                group = wq.getAppGroup()
                print("(wq) 当前使用 App Group：\(group)")
            }
            .overlay {
                if mgr.shouldRespring {
                    RespringView()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                }
            }
            #endif
        }
    }
}

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}
