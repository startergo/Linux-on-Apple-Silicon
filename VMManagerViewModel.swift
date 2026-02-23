//
//  VMManagerViewModel.swift
//  LinuxVMCreator
//
//  View model for managing virtual machines.
//

import Foundation
import SwiftUI
import Combine
import Virtualization

/// View model responsible for managing virtual machines
@MainActor
class VMManagerViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var virtualMachines: [VirtualMachine] = []
    @Published var selectedVM: VirtualMachine?
    @Published var showingNewVMSheet = false
    @Published var showingDeleteAlert = false
    @Published var vmToDelete: VirtualMachine?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let saveFile: URL
    private var runningVMs: [UUID: VZVirtualMachine] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var canStartSelectedVM: Bool {
        guard let vm = selectedVM else { return false }
        return vm.state == .stopped
    }

    var canStopSelectedVM: Bool {
        guard let vm = selectedVM else { return false }
        return vm.state == .running || vm.state == .starting
    }

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("LinuxVMCreator", isDirectory: true)
        self.saveFile = appDirectory.appendingPathComponent("vms.json")

        loadVirtualMachines()
    }

    // MARK: - VM Lifecycle

    func createVM(from configuration: VMConfiguration, isoURL: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        // Create VM directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vmDirectory = appSupport
            .appendingPathComponent("LinuxVMCreator", isDirectory: true)
            .appendingPathComponent(configuration.name, isDirectory: true)

        try FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)

        // Create disk image
        let diskPath = vmDirectory.appendingPathComponent("disk.img")
        try await VirtualizationService.shared.createDisk(
            at: diskPath,
            size: UInt64(configuration.diskSize)
        )

        // Copy or link ISO
        let isoPath = vmDirectory.appendingPathComponent("install.iso")
        try FileManager.default.copyItem(at: isoURL, to: isoPath)

        // Create VM model
        let vm = VirtualMachine(
            name: configuration.name,
            distribution: configuration.distribution,
            cpuCount: configuration.cpuCount,
            memorySize: configuration.memorySize,
            diskSize: configuration.diskSize,
            diskPath: diskPath,
            isoPath: isoPath,
            architecture: configuration.architecture,
            enableNetwork: configuration.enableNetwork,
            enableRosetta: configuration.enableRosetta
        )

        virtualMachines.append(vm)
        selectedVM = vm
        saveVirtualMachines()
    }

    func startVM(at index: Int) {
        print("🔵 startVM called at index \(index)")
        guard index < virtualMachines.count else {
            print("❌ Index out of range")
            return
        }
        var vm = virtualMachines[index]
        print("🔵 Starting VM: \(vm.name), state: \(vm.state)")

        guard vm.state == .stopped else {
            print("❌ VM not stopped, state: \(vm.state)")
            return
        }

        // Update state asynchronously to avoid publishing during view updates
        Task { @MainActor in
            vm.state = .starting
            virtualMachines[index] = vm
            print("🔵 State set to starting")

            do {
                print("🔵 Creating and starting VM...")
                let vzVM = try await VirtualizationService.shared.createAndStartVirtualMachine(vm)
                runningVMs[vm.id] = vzVM
                vm.state = .running
                vm.lastUsedAt = Date()
                virtualMachines[index] = vm
                saveVirtualMachines()
                print("✅ VM started successfully!")
            } catch {
                let errorMsg = error.localizedDescription
                print("❌ Failed to start VM: \(errorMsg)")
                vm.state = .error(errorMsg)
                virtualMachines[index] = vm
                errorMessage = "Failed to start VM: \(errorMsg)"
            }
        }
    }

    func startSelectedVM() {
        guard let index = virtualMachines.firstIndex(where: { $0.id == selectedVM?.id }) else {
            return
        }
        startVM(at: index)
    }

    func stopVM(at index: Int) {
        guard index < virtualMachines.count else { return }
        var vm = virtualMachines[index]

        // Prevent invalid state transitions
        guard vm.state == .running || vm.state == .starting else {
            print("⚠️ Cannot stop VM '\(vm.name)' - current state: \(vm.state)")
            return
        }

        // Update state asynchronously to avoid publishing during view updates
        Task { @MainActor in
            // Double-check state hasn't changed since we started
            vm = virtualMachines[index]
            guard vm.state == .running || vm.state == .starting else {
                print("⚠️ VM state changed before stopping - aborting")
                return
            }
            
            vm.state = .stopping
            virtualMachines[index] = vm
            print("🔵 Stopping VM: \(vm.name)")

            if let vzVM = runningVMs[vm.id] {
                // Only try to stop if the VZVirtualMachine is actually running
                guard vzVM.state == .running || vzVM.state == .starting else {
                    print("⚠️ VZVirtualMachine not in running state: \(vzVM.state)")
                    vm.state = .stopped
                    runningVMs.removeValue(forKey: vm.id)
                    virtualMachines[index] = vm
                    saveVirtualMachines()
                    return
                }
                
                do {
                    try await VirtualizationService.shared.stopVirtualMachine(vzVM)
                    vm.state = .stopped
                    runningVMs.removeValue(forKey: vm.id)
                    virtualMachines[index] = vm
                    saveVirtualMachines()
                    print("✅ VM stopped successfully")
                } catch {
                    let errorMsg = error.localizedDescription
                    print("❌ Failed to stop VM: \(errorMsg)")
                    
                    // If it's an invalid state transition error, the VM is likely already stopped
                    if errorMsg.contains("Invalid virtual machine state transition") {
                        print("🔵 VM appears to be already stopped, cleaning up")
                        vm.state = .stopped
                        runningVMs.removeValue(forKey: vm.id)
                    } else {
                        vm.state = .error(errorMsg)
                        errorMessage = "Failed to stop VM: \(errorMsg)"
                    }
                    virtualMachines[index] = vm
                    saveVirtualMachines()
                }
            } else {
                // No running VM instance found, mark as stopped
                print("⚠️ No running VM instance found, marking as stopped")
                vm.state = .stopped
                virtualMachines[index] = vm
                saveVirtualMachines()
            }
        }
    }

    func stopSelectedVM() {
        guard let index = virtualMachines.firstIndex(where: { $0.id == selectedVM?.id }) else {
            return
        }
        stopVM(at: index)
    }

    func deleteVM(_ vm: VirtualMachine) {
        guard let index = virtualMachines.firstIndex(where: { $0.id == vm.id }) else {
            return
        }

        // Stop if running
        if let vzVM = runningVMs[vm.id] {
            vzVM.stop { _ in }
            runningVMs.removeValue(forKey: vm.id)
        }

        // Delete VM files
        let vmDirectory = vm.diskPath.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: vmDirectory)

        // Remove from list
        virtualMachines.remove(at: index)

        if selectedVM?.id == vm.id {
            selectedVM = virtualMachines.first
        }

        saveVirtualMachines()
    }
    
    // MARK: - VM Configuration Updates
    
    /// Update an existing VM's configuration (only when stopped)
    func updateVM(_ updatedVM: VirtualMachine, at index: Int) {
        guard index < virtualMachines.count else { return }
        let currentVM = virtualMachines[index]
        
        // Only allow updates when VM is stopped
        guard currentVM.state == .stopped else {
            errorMessage = "VM must be stopped to edit configuration"
            return
        }
        
        // If disk size increased, resize the disk file
        if updatedVM.diskSize > currentVM.diskSize {
            do {
                try FileManager.default.setAttributes(
                    [.size: updatedVM.diskSize],
                    ofItemAtPath: updatedVM.diskPath.path
                )
                print("✅ Resized disk to \(updatedVM.diskSize) bytes")
            } catch {
                errorMessage = "Failed to resize disk: \(error.localizedDescription)"
                return
            }
        }
        
        // Update the VM
        virtualMachines[index] = updatedVM
        
        // Update selected VM if it's the one being edited
        if selectedVM?.id == updatedVM.id {
            selectedVM = updatedVM
        }
        
        saveVirtualMachines()
        print("✅ Updated VM configuration for \(updatedVM.name)")
    }

    // MARK: - Persistence

    private func loadVirtualMachines() {
        guard FileManager.default.fileExists(atPath: saveFile.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: saveFile)
            var vms = try JSONDecoder().decode([VirtualMachine].self, from: data)
            
            // Reset all VMs to stopped state on load - VMs don't persist across app launches
            for i in 0..<vms.count {
                vms[i].state = .stopped
            }
            
            virtualMachines = vms
        } catch {
            errorMessage = "Failed to load VMs: \(error.localizedDescription)"
        }
    }

    private func saveVirtualMachines() {
        let appDirectory = saveFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        do {
            let data = try JSONEncoder().encode(virtualMachines)
            try data.write(to: saveFile)
        } catch {
            errorMessage = "Failed to save VMs: \(error.localizedDescription)"
        }
    }

    // MARK: - Validation

    func validateConfiguration(_ config: VMConfiguration) -> String? {
        if config.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "VM name cannot be empty"
        }

        if virtualMachines.contains(where: { $0.name == config.name }) {
            return "A VM with this name already exists"
        }

        if config.cpuCount < 1 || config.cpuCount > ProcessInfo.processInfo.processorCount {
            return "Invalid CPU count"
        }

        if config.memorySize < 512 * 1024 * 1024 {
            return "Memory must be at least 512 MB"
        }

        if config.diskSize < 8 * 1024 * 1024 * 1024 {
            return "Disk size must be at least 8 GB"
        }

        return nil
    }

    // MARK: - VM Access

    /// Get the running VZVirtualMachine instance for a VM
    func getRunningVM(id: UUID) -> VZVirtualMachine? {
        return runningVMs[id]
    }
}
