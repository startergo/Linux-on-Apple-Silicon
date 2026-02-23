//
//  VMDetailView.swift
//  LinuxVMCreator
//
//  Detailed view of a single virtual machine.
//

import SwiftUI
import Virtualization
import AppKit

// MARK: - Console Window Controller

/// Singleton to manage console windows and keep them alive
@MainActor
final class VMConsoleWindowController {
    static let shared = VMConsoleWindowController()
    private var windows: [NSWindow] = []
    
    private init() {}
    
    func addWindow(_ window: NSWindow) {
        // Remove closed windows
        windows.removeAll { $0.isVisible == false }
        
        // Add new window
        windows.append(window)
        
        // Setup close notification
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                Task { @MainActor in
                    self?.windows.removeAll { $0 === window }
                }
            }
        }
    }
}

struct VMDetailView: View {
    let vm: VirtualMachine
    @EnvironmentObject var vmManager: VMManagerViewModel
    @State private var showingEditSheet = false
    @State private var mountInstructionType: MountInstructionType = .manual
    @State private var detectedIPAddress: String?
    
    private enum MountInstructionType {
        case manual, fstab, systemd
    }

    // Get the current VM state from vmManager to ensure reactivity
    private var currentVM: VirtualMachine? {
        vmManager.virtualMachines.first(where: { $0.id == vm.id })
    }
    
    // Try to detect the VM's IP address from DHCP leases
    private func detectVMIPAddress() {
        Task {
            let ipAddress = await VMNetworkDetector.detectIPAddress(for: vm)
            await MainActor.run {
                detectedIPAddress = ipAddress
            }
        }
    }
    
    // Open console in a separate window
    private func openConsoleWindow() {
        let consoleView = VMConsoleView(vm: vm)
            .environmentObject(vmManager)
        
        let hostingController = NSHostingController(rootView: consoleView)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "\(vm.name) - Console"
        window.setContentSize(NSSize(width: 1024, height: 768))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 800, height: 600)
        window.makeKeyAndOrderFront(nil)
        window.center()
        
        // Keep window alive
        VMConsoleWindowController.shared.addWindow(window)
    }

    var body: some View {
        if let vm = currentVM {
            vmDetailContent(for: vm)
                .onChange(of: vm.state) { oldState, newState in
                    // Auto-open console when VM starts running
                    // Only trigger on transition from starting to running
                    if newState == .running && oldState == .starting {
                        openConsoleWindow()
                        // Try to detect IP address
                        detectVMIPAddress()
                    }
                }
                .onAppear {
                    // Try to detect IP if VM is already running
                    if vm.state == .running {
                        detectVMIPAddress()
                    }
                }
        } else {
            Text("VM not found")
        }
    }

    @ViewBuilder
    private func vmDetailContent(for vm: VirtualMachine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.name)
                            .font(.system(size: 28, weight: .bold))

                        HStack(spacing: 8) {
                            Image(systemName: vm.state.icon)
                                .foregroundColor(vm.state.color)

                            Text(stateText(for: vm))
                                .foregroundColor(vm.state.color)

                            Text("•")
                                .foregroundColor(.secondary)

                            Text(vm.distribution.rawValue)
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 13))
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 12) {
                        if vm.state == .stopped {
                            Button {
                                print("🟢 VMDetailView Start button clicked for \(vm.name)")
                                if let index = vmManager.virtualMachines.firstIndex(where: { $0.id == vm.id }) {
                                    print("🟢 Found VM at index \(index)")
                                    vmManager.startVM(at: index)
                                } else {
                                    print("❌ VM not found in list")
                                }
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else if vm.state == .running {
                            Button {
                                openConsoleWindow()
                            } label: {
                                Label("Open Console", systemImage: "terminal")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                if let index = vmManager.virtualMachines.firstIndex(where: { $0.id == vm.id }) {
                                    vmManager.stopVM(at: index)
                                }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        } else if vm.state == .starting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else if vm.state == .stopping {
                            ProgressView()
                                .controlSize(.small)
                            Text("Stopping...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // VM Configuration Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Configuration")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Spacer()
                        
                        // Edit button (only when VM is stopped)
                        if vm.state == .stopped {
                            Button {
                                showingEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ConfigItem(
                            icon: "cpu",
                            title: "CPU Cores",
                            value: "\(vm.cpuCount)"
                        )

                        ConfigItem(
                            icon: "memorychip",
                            title: "Memory",
                            value: String(format: "%.1f GB", vm.memorySizeGB)
                        )

                        ConfigItem(
                            icon: "videoprojector",
                            title: "VRAM",
                            value: "\(vm.vramSizeMB) MB"
                        )

                        ConfigItem(
                            icon: "internaldrive",
                            title: "Disk Size",
                            value: String(format: "%.0f GB", vm.diskSizeGB)
                        )

                        ConfigItem(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Architecture",
                            value: vm.architecture.rawValue
                        )

                        ConfigItem(
                            icon: "network",
                            title: "Network",
                            value: vm.enableNetwork ? "Enabled" : "Disabled"
                        )

                        ConfigItem(
                            icon: "arrow.triangle.2.circlepath.circle",
                            title: "Rosetta",
                            value: vm.enableRosetta ? "Enabled" : "Disabled"
                        )
                    }
                }

                Divider()

                // Storage Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Storage")
                        .font(.system(size: 18, weight: .semibold))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Virtual Disk")
                                    .font(.system(size: 13, weight: .medium))

                                Text(vm.diskPath.path)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let actualSize = vm.actualDiskSize {
                                Text(ByteCountFormatter.string(fromByteCount: actualSize, countStyle: .file))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        ProgressView(value: vm.actualDiskSize.map { Double($0) / Double(vm.diskSize) } ?? 0)
                            .progressViewStyle(.linear)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Installation ISO")
                                .font(.system(size: 13, weight: .medium))

                            Text(vm.isoPath.path)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: vm.isoExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(vm.isoExists ? .green : .red)
                    }
                }

                Divider()

                // Shared Folders Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Shared Folders")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Spacer()
                        
                        // Edit button (only when VM is stopped)
                        if vm.state == .stopped {
                            Button {
                                showingEditSheet = true
                            } label: {
                                Label("Manage", systemImage: "folder.badge.gearshape")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    if vm.sharedFolders.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No shared folders configured")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text("Share folders between your Mac and this VM")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(vm.sharedFolders) { folder in
                                SharedFolderRow(folder: folder)
                            }
                            
                            // Debug info
                            if vm.state == .running {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 11))
                                    Text("VM must be restarted after adding/changing shared folders")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        // Mount instructions with tabs
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 12))
                                Text("Setup Instructions:")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            
                            // Tab picker
                            Picker("Mount Type", selection: $mountInstructionType) {
                                Text("Manual").tag(MountInstructionType.manual)
                                Text("Auto-Mount (fstab)").tag(MountInstructionType.fstab)
                                Text("Auto-Mount (systemd)").tag(MountInstructionType.systemd)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            // Instructions based on selected type
                            Group {
                                switch mountInstructionType {
                                case .manual:
                                    manualMountInstructions(for: vm.sharedFolders)
                                case .fstab:
                                    fstabMountInstructions(for: vm.sharedFolders)
                                case .systemd:
                                    systemdMountInstructions(for: vm.sharedFolders)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Divider()

                // Info Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Information")
                        .font(.system(size: 18, weight: .semibold))

                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Created", value: vm.createdAt.formatted())
                        if let lastUsed = vm.lastUsedAt {
                            InfoRow(label: "Last Used", value: lastUsed.formatted())
                        }
                        InfoRow(label: "VM ID", value: vm.id.uuidString)
                        
                        // SSH Connection Info
                        if vm.state == .running, vm.enableNetwork {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                    Text("SSH Access")
                                        .font(.system(size: 13, weight: .medium))
                                    
                                    Spacer()
                                    
                                    // Refresh button
                                    Button {
                                        detectVMIPAddress()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Refresh IP address")
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    if let ipAddress = detectedIPAddress {
                                        // Show detected IP
                                        HStack(spacing: 4) {
                                            Text("IP Address:")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            
                                            Text(ipAddress)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                            
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(ipAddress, forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 9))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy IP address")
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Text("Connect:")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            
                                            Text("ssh user@\(ipAddress)")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                            
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString("ssh user@\(ipAddress)", forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 9))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy SSH command")
                                        }
                                        
                                        Text("💡 Enable SSH in VM: sudo systemctl enable --now sshd")
                                            .font(.system(size: 9))
                                            .foregroundColor(.orange)
                                            .padding(.top, 2)
                                    } else {
                                        // Show manual instructions
                                        HStack(spacing: 4) {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .padding(.trailing, 4)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Detecting IP address...")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                                
                                                Text("Or find manually in VM: ip addr show")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let currentVM = currentVM,
               let index = vmManager.virtualMachines.firstIndex(where: { $0.id == currentVM.id }) {
                VMEditSheet(vm: currentVM, vmIndex: index)
                    .environmentObject(vmManager)
            }
        }
    }

    private func stateText(for vm: VirtualMachine) -> String {
        switch vm.state {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .paused: return "Paused"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    // MARK: - Mount Instructions Helper Methods
    
    @ViewBuilder
    private func manualMountInstructions(for folders: [SharedFolder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mount manually (temporary, until reboot):")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(folders) { folder in
                    HStack(spacing: 4) {
                        Text("sudo mkdir -p \(folder.mountPath) && sudo mount -t virtiofs \(folder.name) \(folder.mountPath)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        
                        Button {
                            let command = "sudo mkdir -p \(folder.mountPath) && sudo mount -t virtiofs \(folder.name) \(folder.mountPath)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func fstabMountInstructions(for folders: [SharedFolder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to /etc/fstab for automatic mounting at boot:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                // Combined command
                let setupCommands = folders.map { "sudo mkdir -p \($0.mountPath)" }.joined(separator: " && ")
                let fstabEntries = folders.map { $0.fstabEntry }.joined(separator: "\n")
                let fullCommand = """
                # Create mount points
                \(setupCommands)
                
                # Add to /etc/fstab (backup first)
                sudo cp /etc/fstab /etc/fstab.backup
                echo '\(fstabEntries)' | sudo tee -a /etc/fstab
                
                # Mount all
                sudo mount -a
                """
                
                HStack(alignment: .top, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(fullCommand)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    .frame(maxHeight: 120)
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
                
                Text("⚠️ After adding to fstab, shared folders will mount automatically on every boot")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
    }
    
    @ViewBuilder
    private func systemdMountInstructions(for folders: [SharedFolder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create systemd mount units (recommended for modern distros):")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            if let firstFolder = folders.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example for '\(firstFolder.name)':")
                        .font(.system(size: 10, weight: .medium))
                    
                    let setupScript = """
                    # Create mount point
                    sudo mkdir -p \(firstFolder.mountPath)
                    
                    # Create systemd unit file
                    sudo tee /etc/systemd/system/\(firstFolder.systemdUnitName) << 'EOF'
                    \(firstFolder.systemdUnitContent)
                    EOF
                    
                    # Enable and start
                    sudo systemctl daemon-reload
                    sudo systemctl enable \(firstFolder.systemdUnitName)
                    sudo systemctl start \(firstFolder.systemdUnitName)
                    
                    # Verify
                    sudo systemctl status \(firstFolder.systemdUnitName)
                    """
                    
                    HStack(alignment: .top, spacing: 4) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(setupScript)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                        }
                        .frame(maxHeight: 150)
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(setupScript, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                    
                    if folders.count > 1 {
                        Text("Repeat for other folders: \(folders.dropFirst().map { $0.name }.joined(separator: ", "))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Config Item

struct ConfigItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
        }
    }
}

// MARK: - Shared Folder Row

struct SharedFolderRow: View {
    let folder: SharedFolder
    
    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folder.hostPath.path)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.readOnly ? "folder.badge.minus" : "folder")
                .font(.system(size: 20))
                .foregroundColor(folderExists ? .accentColor : .red)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .medium))
                    
                    if folder.readOnly {
                        Text("Read-Only")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(folder.hostPath.path)
                    .font(.system(size: 11))
                    .foregroundColor(folderExists ? .secondary : .red)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !folderExists {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("Folder not found on host")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Console View

struct VMConsoleView: View {
    let vm: VirtualMachine
    @EnvironmentObject var vmManager: VMManagerViewModel
    @State private var displayView: NSView?
    @State private var showingScreenshotMenu = false
    @State private var isSelectingRegion = false
    
    // Get the current VM state from vmManager to ensure reactivity
    private var currentVM: VirtualMachine? {
        vmManager.virtualMachines.first(where: { $0.id == vm.id })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(vm.name) - Console")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
                
                // Screenshot menu button
                Menu {
                    Button {
                        takeScreenshot(region: nil)
                    } label: {
                        Label("Capture Full Screen", systemImage: "rectangle.dashed")
                    }
                    
                    Button {
                        startRegionSelection()
                    } label: {
                        Label("Capture Region", systemImage: "viewfinder")
                    }
                } label: {
                    Label("Screenshot", systemImage: "camera")
                        .labelStyle(.iconOnly)
                        .help("Take screenshot of VM display")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20, height: 20)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            // VM Display View - use currentVM for reactive state
            if let currentVM = currentVM,
               currentVM.state == .running,
               let vzVM = vmManager.getRunningVM(id: vm.id) {
                ZStack {
                    VirtualMachineDisplayView(virtualMachine: vzVM, capturedView: $displayView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Region selection overlay
                    if isSelectingRegion {
                        RegionSelectionOverlay { region in
                            isSelectingRegion = false
                            if let region = region {
                                takeScreenshot(region: region)
                            }
                        }
                    }
                }
            } else {
                VStack {
                    Image(systemName: "display")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("VM Not Running")
                        .font(.system(size: 16, weight: .medium))

                    if let currentVM = currentVM {
                        if currentVM.state == .starting {
                            ProgressView()
                                .padding(.top, 8)
                            Text("Starting virtual machine...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } else {
                            Text("Start the virtual machine to view its display")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Start the virtual machine to view its display")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // Start region selection mode
    private func startRegionSelection() {
        isSelectingRegion = true
    }
    
    // Take a screenshot of the VM display
    private func takeScreenshot(region: CGRect?) {
        guard let view = displayView else {
            print("⚠️ Display view not available for screenshot")
            return
        }
        
        print("📸 Taking screenshot - View bounds: \(view.bounds)")
        if let region = region {
            print("📸 Region selected: \(region)")
        }
        
        // Create bitmap representation of the view
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("❌ Failed to create bitmap representation")
            return
        }
        
        view.cacheDisplay(in: view.bounds, to: bitmapRep)
        print("📸 Bitmap size: \(bitmapRep.pixelsWide) x \(bitmapRep.pixelsHigh)")
        
        // If capturing a region, crop the bitmap
        let finalBitmap: NSBitmapImageRep
        if let region = region {
            // Calculate scale factors
            let scaleX = CGFloat(bitmapRep.pixelsWide) / view.bounds.width
            let scaleY = CGFloat(bitmapRep.pixelsHigh) / view.bounds.height
            
            print("📸 Scale factors - X: \(scaleX), Y: \(scaleY)")
            
            // Convert region from view coordinates to bitmap coordinates
            // Note: AppKit uses bottom-left origin, so Y needs to be flipped
            let bitmapX = region.origin.x * scaleX
            let bitmapY = (view.bounds.height - region.origin.y - region.height) * scaleY
            let bitmapWidth = region.width * scaleX
            let bitmapHeight = region.height * scaleY
            
            let bitmapRect = CGRect(
                x: round(bitmapX),
                y: round(bitmapY),
                width: round(bitmapWidth),
                height: round(bitmapHeight)
            )
            
            print("📸 Bitmap region: \(bitmapRect)")
            
            // Create a new CGImage by cropping
            guard let fullImage = bitmapRep.cgImage,
                  let croppedCGImage = fullImage.cropping(to: bitmapRect) else {
                print("❌ Failed to crop CGImage")
                return
            }
            
            // Convert back to NSBitmapImageRep
            let croppedBitmapRep = NSBitmapImageRep(cgImage: croppedCGImage)
            finalBitmap = croppedBitmapRep
            
            print("✅ Cropped bitmap: \(finalBitmap.pixelsWide) x \(finalBitmap.pixelsHigh)")
        } else {
            finalBitmap = bitmapRep
        }
        
        // Convert to PNG data
        guard let pngData = finalBitmap.representation(using: .png, properties: [:]) else {
            print("❌ Failed to convert to PNG")
            return
        }
        
        // Save to Desktop with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let regionSuffix = region != nil ? "_region" : ""
        let filename = "\(vm.name)_\(timestamp)\(regionSuffix).png"
        
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fileURL = desktopURL.appendingPathComponent(filename)
        
        do {
            try pngData.write(to: fileURL)
            print("✅ Screenshot saved to: \(fileURL.path)")
            
            // Show notification or alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Screenshot Saved"
                alert.informativeText = "Saved to Desktop as:\n\(filename)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Show in Finder")
                
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
        } catch {
            print("❌ Failed to save screenshot: \(error)")
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Screenshot Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - Region Selection Overlay

struct RegionSelectionOverlay: View {
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    let onComplete: (CGRect?) -> Void
    
    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay with darkened areas outside selection
                if let rect = selectionRect {
                    // Darken everything first
                    Color.black.opacity(0.5)
                    
                    // Clear the selected area by overlaying the outline
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                } else {
                    // Full overlay when not selecting
                    Color.black.opacity(0.3)
                }
                
                // Selection rectangle with handles
                if let rect = selectionRect {
                    // Main selection border
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // Corner handles
                    Group {
                        // Top-left
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .position(x: rect.minX, y: rect.minY)
                        
                        // Top-right
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .position(x: rect.maxX, y: rect.minY)
                        
                        // Bottom-left
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .position(x: rect.minX, y: rect.maxY)
                        
                        // Bottom-right
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .position(x: rect.maxX, y: rect.maxY)
                    }
                    
                    // Coordinate info box
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Size: \(Int(rect.width)) × \(Int(rect.height)) px")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("Position: (\(Int(rect.minX)), \(Int(rect.minY)))")
                            .font(.system(size: 10, design: .monospaced))
                            .opacity(0.8)
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(6)
                    .position(
                        x: rect.maxX > geometry.size.width - 150 ? rect.minX - 80 : rect.maxX + 80,
                        y: max(20, min(rect.minY, geometry.size.height - 40))
                    )
                }
                
                // Instructions
                if startPoint == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Click and drag to select a region")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            Label("ESC to cancel", systemImage: "escape")
                            Label("Drag to select", systemImage: "hand.draw")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if startPoint == nil {
                            startPoint = value.startLocation
                            print("📍 Start point: \(value.startLocation)")
                        }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        if let rect = selectionRect, rect.width > 5 && rect.height > 5 {
                            print("✅ Selection complete: \(rect)")
                            onComplete(rect)
                        } else {
                            print("❌ Selection too small or invalid")
                            onComplete(nil)
                        }
                        startPoint = nil
                        currentPoint = nil
                    }
            )
            .onTapGesture {
                // Cancel if tapped without dragging
                print("❌ Selection cancelled (tap)")
                onComplete(nil)
            }
        }
        .onAppear {
            // Listen for ESC key to cancel
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC key
                    print("❌ Selection cancelled (ESC)")
                    onComplete(nil)
                    return nil
                }
                return event
            }
        }
    }
}

// MARK: - VirtualMachine Display View (AppKit Wrapper)

struct VirtualMachineDisplayView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine
    @Binding var capturedView: NSView?
    
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = true
        
        // Enable automatic reconfiguration immediately
        // This allows the VM to match the console window size
        view.automaticallyReconfiguresDisplay = true
        
        // Capture the view reference for screenshots
        DispatchQueue.main.async {
            capturedView = view
        }
        
        return view
    }
    
    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        // Update if needed
        if nsView.virtualMachine !== virtualMachine {
            nsView.virtualMachine = virtualMachine
        }
        
        // Ensure automatic reconfiguration is always enabled
        // This allows the VM display to match the console window size
        if !nsView.automaticallyReconfiguresDisplay {
            nsView.automaticallyReconfiguresDisplay = true
        }
        
        // Ensure we have the view reference
        if capturedView !== nsView {
            DispatchQueue.main.async {
                capturedView = nsView
            }
        }
    }
    
    // Make the view properly respond to size changes
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VZVirtualMachineView, context: Context) -> CGSize? {
        // Ensure we return valid dimensions
        let width = proposal.width ?? 800
        let height = proposal.height ?? 600
        
        // Make sure dimensions are positive
        return CGSize(
            width: max(width, 1),
            height: max(height, 1)
        )
    }
}

// MARK: - VM Edit Sheet

struct VMEditSheet: View {
    let vm: VirtualMachine
    let vmIndex: Int
    @EnvironmentObject var vmManager: VMManagerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var cpuCount: Int
    @State private var memoryGB: Double
    @State private var diskGB: Double
    @State private var vramMB: Int64
    @State private var enableNetwork: Bool
    @State private var enableRosetta: Bool
    @State private var isoPath: URL
    @State private var sharedFolders: [SharedFolder]
    @State private var showingISOPicker = false
    @State private var showingFolderPicker = false
    @State private var errorMessage: String?
    
    init(vm: VirtualMachine, vmIndex: Int) {
        self.vm = vm
        self.vmIndex = vmIndex
        _cpuCount = State(initialValue: vm.cpuCount)
        _memoryGB = State(initialValue: vm.memorySizeGB)
        _diskGB = State(initialValue: vm.diskSizeGB)
        _vramMB = State(initialValue: vm.vramSizeMB)
        _enableNetwork = State(initialValue: vm.enableNetwork)
        _enableRosetta = State(initialValue: vm.enableRosetta)
        _isoPath = State(initialValue: vm.isoPath)
        _sharedFolders = State(initialValue: vm.sharedFolders)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit VM Configuration")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Warning
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("VM must be stopped to edit")
                                .font(.system(size: 13, weight: .medium))
                            Text("Changes will take effect on next start")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    // CPU Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("CPU Cores")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        Stepper(value: $cpuCount, in: 1...ProcessInfo.processInfo.processorCount) {
                            Text("\(cpuCount) cores")
                                .font(.system(size: 13))
                        }
                        
                        Text("Available: \(ProcessInfo.processInfo.processorCount)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Memory Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "memorychip")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Memory (RAM)")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $memoryGB, in: 0.5...64, step: 0.5) {
                                Text("Memory")
                            }
                            
                            Text(String(format: "%.1f GB", memoryGB))
                                .font(.system(size: 13, weight: .medium))
                        }
                        
                        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
                        Text(String(format: "System total: %.1f GB", totalMemoryGB))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // VRAM Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "videoprojector")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Graphics Memory (VRAM)")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: Binding(
                                get: { Double(vramMB) },
                                set: { vramMB = Int64($0) }
                            ), in: 64...2048, step: 64) {
                                Text("VRAM")
                            }
                            
                            Text("\(vramMB) MB")
                                .font(.system(size: 13, weight: .medium))
                        }
                        
                        Text("Recommended: 512 MB for desktop, 1024 MB+ for graphics-intensive apps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Disk Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Disk Size")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $diskGB, in: vm.diskSizeGB...500, step: 1) {
                                Text("Disk")
                            }
                            
                            Text(String(format: "%.0f GB", diskGB))
                                .font(.system(size: 13, weight: .medium))
                        }
                        
                        Text("Note: Can only increase disk size, not decrease")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // ISO Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "opticaldisc")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Installation ISO")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isoPath.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                
                                Text(isoPath.path)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button("Change...") {
                                showingISOPicker = true
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        
                        Text("Tip: You can remove the ISO after OS installation to free up space")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Network Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Network")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        Toggle(isOn: $enableNetwork) {
                            Text("Enable Network (NAT)")
                                .font(.system(size: 13))
                        }
                    }
                    
                    Divider()
                    
                    // Rosetta Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Rosetta")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        Toggle(isOn: $enableRosetta) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Rosetta (Linux x86_64 support)")
                                    .font(.system(size: 13))
                                
                                Text("Allows running x86_64 Linux binaries on Apple Silicon")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if enableRosetta && vm.architecture != .aarch64 {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Rosetta is only available for ARM64 VMs")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    
                    Divider()
                    
                    // Shared Folders Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "folder.badge.gearshape")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Shared Folders")
                                .font(.system(size: 14, weight: .medium))
                            
                            Spacer()
                            
                            Button {
                                showingFolderPicker = true
                            } label: {
                                Label("Add Folder", systemImage: "plus")
                                    .font(.system(size: 11))
                            }
                            .controlSize(.small)
                        }
                        
                        if sharedFolders.isEmpty {
                            Text("No shared folders configured")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(sharedFolders) { folder in
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 12))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(folder.name)
                                                    .font(.system(size: 12, weight: .medium))
                                                
                                                if folder.readOnly {
                                                    Text("RO")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.secondary)
                                                        .cornerRadius(3)
                                                }
                                            }
                                            
                                            Text(folder.hostPath.path)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        // Toggle read-only
                                        Button {
                                            if let index = sharedFolders.firstIndex(where: { $0.id == folder.id }) {
                                                sharedFolders[index].readOnly.toggle()
                                            }
                                        } label: {
                                            Image(systemName: folder.readOnly ? "lock.fill" : "lock.open")
                                                .foregroundColor(folder.readOnly ? .orange : .green)
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                        .help(folder.readOnly ? "Read-Only" : "Read-Write")
                                        
                                        // Remove button
                                        Button {
                                            sharedFolders.removeAll { $0.id == folder.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red.opacity(0.7))
                                                .font(.system(size: 14))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove shared folder")
                                    }
                                    .padding(8)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        
                        Text("Tip: Mount in VM with: sudo mount -t virtiofs <name> /mnt/<name>")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save Changes") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 550, height: 750)
        .fileImporter(
            isPresented: $showingISOPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    isoPath = url
                }
            case .failure(let error):
                errorMessage = "Failed to select ISO: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Generate a clean name from the folder
                    let folderName = url.lastPathComponent
                        .replacingOccurrences(of: " ", with: "_")
                        .lowercased()
                    
                    // Check for duplicate names
                    var finalName = folderName
                    var counter = 1
                    while sharedFolders.contains(where: { $0.name == finalName }) {
                        finalName = "\(folderName)_\(counter)"
                        counter += 1
                    }
                    
                    // Add the new shared folder
                    let newFolder = SharedFolder(
                        name: finalName,
                        hostPath: url,
                        readOnly: false
                    )
                    sharedFolders.append(newFolder)
                }
            case .failure(let error):
                errorMessage = "Failed to select folder: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveChanges() {
        // Validate changes
        guard cpuCount >= 1 && cpuCount <= ProcessInfo.processInfo.processorCount else {
            errorMessage = "Invalid CPU count"
            return
        }
        
        guard memoryGB >= 0.5 else {
            errorMessage = "Memory must be at least 512 MB"
            return
        }
        
        guard diskGB >= vm.diskSizeGB else {
            errorMessage = "Cannot decrease disk size"
            return
        }
        
        // Update VM
        var updatedVM = vm
        updatedVM.cpuCount = cpuCount
        updatedVM.memorySize = Int64(UInt64(memoryGB * 1_073_741_824))
        updatedVM.diskSize = Int64(UInt64(diskGB * 1_073_741_824))
        updatedVM.vramSizeMB = vramMB
        updatedVM.enableNetwork = enableNetwork
        updatedVM.enableRosetta = enableRosetta
        updatedVM.sharedFolders = sharedFolders
        
        // Handle ISO change
        if isoPath != vm.isoPath {
            let vmDirectory = vm.diskPath.deletingLastPathComponent()
            let newISOPath = vmDirectory.appendingPathComponent("install.iso")
            
            // Remove old ISO if it exists
            try? FileManager.default.removeItem(at: newISOPath)
            
            // Copy new ISO
            do {
                try FileManager.default.copyItem(at: isoPath, to: newISOPath)
                updatedVM.isoPath = newISOPath
                print("✅ Updated ISO to: \(isoPath.lastPathComponent)")
            } catch {
                errorMessage = "Failed to copy ISO: \(error.localizedDescription)"
                return
            }
        }
        
        // Save to manager
        vmManager.updateVM(updatedVM, at: vmIndex)
        
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    VMDetailView(vm: VirtualMachine(
        name: "Ubuntu Server",
        distribution: .ubuntu,
        cpuCount: 4,
        memorySize: 4 * 1024 * 1024 * 1024,
        diskSize: 64 * 1024 * 1024 * 1024,
        diskPath: URL(fileURLWithPath: "/tmp/disk.img"),
        isoPath: URL(fileURLWithPath: "/tmp/ubuntu.iso"),
        architecture: .aarch64,
        enableNetwork: true,
        enableRosetta: false,
        sharedFolders: []
    ))
    .environmentObject(VMManagerViewModel())
}

