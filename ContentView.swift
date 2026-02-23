//
//  ContentView.swift
//  LinuxVMCreator
//
//  Main view for the Linux VM Creator application.
//

import SwiftUI
import OSLog

struct ContentView: View {
    @EnvironmentObject var vmManager: VMManagerViewModel

    private let logger = Logger(subsystem: "com.example.LinuxVMCreator", category: "ContentView")

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .sheet(isPresented: $vmManager.showingNewVMSheet) {
            NewVMConfigurationSheet()
                .environmentObject(vmManager)
        }
        .alert("Delete Virtual Machine", isPresented: $vmManager.showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let vm = vmManager.vmToDelete {
                    vmManager.deleteVM(vm)
                }
            }
        } message: {
            if let vm = vmManager.vmToDelete {
                Text("Are you sure you want to delete \"\(vm.name)\"? This action cannot be undone.")
            }
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            vmList
            Divider()
            quickActionsView
        }
        .frame(minWidth: 200)
        .navigationTitle("Virtual Machines")
    }

    private var vmList: some View {
        List(vmManager.virtualMachines, selection: $vmManager.selectedVM) { vm in
            VMListItem(vm: vm)
                .tag(vm)
                .contextMenu {
                    contextMenuItems(for: vm)
                }
        }
    }

    private func contextMenuItems(for vm: VirtualMachine) -> some View {
        Group {
            Button("Start") {
                logger.log("Context menu: Start VM \(vm.name)")
                startVM(vm)
            }
            .disabled(vm.state != .stopped)
            Button("Stop") {
                logger.log("Context menu: Stop VM \(vm.name)")
                stopVM(vm)
            }
            .disabled(vm.state == .stopped)
            Divider()
            Button("Delete") {
                logger.log("Context menu: Delete VM \(vm.name)")
                vmManager.vmToDelete = vm
                vmManager.showingDeleteAlert = true
            }
        }
    }

    private var quickActionsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    logger.log("New VM button clicked")
                    vmManager.showingNewVMSheet = true
                } label: {
                    Label("New VM", systemImage: "plus")
                }
                .help("Create a new virtual machine")

                Spacer()

                if let vm = vmManager.selectedVM {
                    Button {
                        logger.log("Quick action: Start VM \(vm.name)")
                        startVM(vm)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(vm.state != .stopped)

                    Button {
                        logger.log("Quick action: Stop VM \(vm.name)")
                        stopVM(vm)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(vm.state == .stopped)
                }
            }
            .padding(12)

            // Error message bar (separate from buttons)
            if let error = vmManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        vmManager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .padding(.horizontal, 12)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailView: some View {
        Group {
            if let vm = vmManager.selectedVM {
                VMDetailView(vm: vm)
                    .id(vm.id) // Force view recreation when selection changes
            } else {
                VMEmptyStateView()
            }
        }
    }

    private func startVM(_ vm: VirtualMachine) {
        logger.log("Starting VM: \(vm.name)")
        if let index = vmManager.virtualMachines.firstIndex(where: { $0.id == vm.id }) {
            vmManager.startVM(at: index)
        } else {
            logger.error("VM not found in list: \(vm.name)")
        }
    }

    private func stopVM(_ vm: VirtualMachine) {
        logger.log("Stopping VM: \(vm.name)")
        if let index = vmManager.virtualMachines.firstIndex(where: { $0.id == vm.id }) {
            vmManager.stopVM(at: index)
        } else {
            logger.error("VM not found in list: \(vm.name)")
        }
    }
}

// MARK: - VM List Item

struct VMListItem: View {
    let vm: VirtualMachine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.state.icon)
                .foregroundColor(vm.state.color)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.name)
                    .font(.system(size: 13, weight: .medium))

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitleText: String {
        "\(vm.cpuCount) cores • \(ByteCountFormatter.string(fromByteCount: vm.memorySize, countStyle: .memory))"
    }
}

// MARK: - Empty State

struct VMEmptyStateView: View {
    @EnvironmentObject var vmManager: VMManagerViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Virtual Machine Selected")
                    .font(.system(size: 20, weight: .semibold))

                Text(messageText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if vmManager.virtualMachines.isEmpty {
                Button {
                    print("Create VM button clicked in empty state")
                    vmManager.showingNewVMSheet = true
                } label: {
                    Label("Create Virtual Machine", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageText: String {
        vmManager.virtualMachines.isEmpty
            ? "Create your first Linux virtual machine to get started"
            : "Select a virtual machine from the list or create a new one"
    }
}

// MARK: - New VM Configuration Sheet

struct NewVMConfigurationSheet: View {
    @EnvironmentObject var vmManager: VMManagerViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var vmName: String = ""
    @State private var cpuCount: Int = 2
    @State private var memorySize: Int = 2048
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Virtual Machine Name") {
                    TextField("Name", text: $vmName)
                }
                
                Section("Resources") {
                    Stepper("CPU Cores: \(cpuCount)", value: $cpuCount, in: 1...8)
                    Stepper("Memory: \(memorySize) MB", value: $memorySize, in: 512...8192, step: 512)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Virtual Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createVM()
                    }
                    .disabled(vmName.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func createVM() {
        // TODO: Implement VM creation
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(VMManagerViewModel())
}
