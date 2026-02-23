//
//  LinuxVMCreatorApp.swift
//  LinuxVMCreator
//
//  A user interface for creating and managing Linux VMs on macOS
//  using Apple's Virtualization framework.
//

import SwiftUI

@main
struct LinuxVMCreatorApp: App {
    @StateObject private var vmManager = VMManagerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vmManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Machine...") {
                    vmManager.showingNewVMSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Virtual Machine") {
                Button("Start") {
                    vmManager.startSelectedVM()
                }
                .disabled(!vmManager.canStartSelectedVM)

                Button("Stop") {
                    vmManager.stopSelectedVM()
                }
                .disabled(!vmManager.canStopSelectedVM)

                Divider()

                Button("Delete...") {
                    vmManager.showingDeleteAlert = true
                }
                .disabled(vmManager.selectedVM == nil)
            }
        }
    }
}
