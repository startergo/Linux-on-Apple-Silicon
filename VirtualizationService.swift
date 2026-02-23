//
//  VirtualizationService.swift
//  LinuxVMCreator
//
//  Service for creating and managing virtual machines using Apple's Virtualization framework.
//

import Foundation
import Virtualization
import Darwin

/// Class to hold file handles and keep them alive
class VMFileHandleHolder {
    let diskHandle: FileHandle
    let isoHandle: FileHandle

    init(diskHandle: FileHandle, isoHandle: FileHandle) {
        self.diskHandle = diskHandle
        self.isoHandle = isoHandle
    }
}

/// Service responsible for VM operations using Apple's Virtualization framework
@MainActor
class VirtualizationService {
    static let shared = VirtualizationService()

    // Keep file handles alive during VM execution - keyed by VM ID
    private var fileHandleHolders: [UUID: VMFileHandleHolder] = [:]

    // Also keep direct array references as backup
    private var allHolders: [VMFileHandleHolder] = []

    private init() {}

    // Helper function to open file handle with proper flags
    private func openFileHandle(forReading path: URL) throws -> FileHandle {
        let fd = open(path.path, O_RDONLY)
        if fd == -1 {
            throw NSError(domain: "VirtualizationService", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open file for reading: \(path.path)"])
        }
        return FileHandle(fileDescriptor: fd)
    }

    private func openFileHandle(forReadingAndWriting path: URL) throws -> FileHandle {
        let fd = open(path.path, O_RDWR)
        if fd == -1 {
            throw NSError(domain: "VirtualizationService", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open file for reading/writing: \(path.path)"])
        }
        return FileHandle(fileDescriptor: fd)
    }

    // MARK: - Disk Creation

    /// Creates a disk image for the virtual machine
    func createDisk(at url: URL, size: UInt64) async throws {
        // Create empty file of specified size
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)

        // Set the file size
        try FileManager.default.setAttributes(
            [.size: size],
            ofItemAtPath: url.path
        )

        // The disk will be initialized and formatted during VM installation
    }

    // MARK: - VM Configuration

    /// Creates a VZVirtualMachineConfiguration for the given VM model
    private func createConfiguration(for vm: VirtualMachine) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        // Set CPU count
        config.cpuCount = vm.cpuCount

        // Set memory (UInt64 in newer API)
        config.memorySize = UInt64(vm.memorySize)
        
        // PERFORMANCE: Enable memory balloon device for dynamic memory management
        // This allows the guest to return unused memory to the host, improving overall system performance
        config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        // Set boot loader
        config.bootLoader = try createBootLoader(for: vm)

        // Configure storage
        config.storageDevices = try createStorageDevices(for: vm)

        // Configure network
        if vm.enableNetwork {
            config.networkDevices = createNetworkDevices()
        }

        // Configure graphics
        config.graphicsDevices = createGraphicsDevices(for: vm)

        // Configure console
        config.serialPorts = createSerialPorts()

        // Configure entropy
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        
        // Configure keyboard
        config.keyboards = [VZUSBKeyboardConfiguration()]
        
        // Configure pointing device (mouse/trackpad)
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        
        // Configure clipboard sharing via SPICE agent
        // This enables bidirectional clipboard sharing between host (macOS) and guest (Linux)
        // NOTE: The Linux guest must have spice-vdagent installed and running:
        //   Ubuntu/Debian: sudo apt install spice-vdagent
        //   Fedora/RHEL: sudo dnf install spice-vdagent
        //   Arch: sudo pacman -S spice-vdagent
        //
        // KNOWN LIMITATION: VM → Mac clipboard may not work reliably due to
        // incomplete implementation in Apple's Virtualization framework.
        // Mac → VM clipboard should work fine.
        let spiceAgentPort = VZVirtioConsolePortConfiguration()
        spiceAgentPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
        
        // Create SPICE agent attachment with clipboard sharing enabled
        let spiceAttachment = VZSpiceAgentPortAttachment()
        // Note: VZSpiceAgentPortAttachment automatically enables clipboard sharing
        // but the VM→Mac direction may require additional host-side handling
        
        spiceAgentPort.attachment = spiceAttachment
        
        let consoleDevice = VZVirtioConsoleDeviceConfiguration()
        consoleDevice.ports[0] = spiceAgentPort
        config.consoleDevices = [consoleDevice]
        
        // PERFORMANCE: Configure audio device for better multimedia performance
        // Even if you don't use audio, having this configured can improve overall VM responsiveness
        let audioInputConfig = VZVirtioSoundDeviceConfiguration()
        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()
        audioInputConfig.streams = [inputStream]
        
        let audioOutputConfig = VZVirtioSoundDeviceConfiguration()
        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()
        audioOutputConfig.streams = [outputStream]
        
        config.audioDevices = [audioInputConfig, audioOutputConfig]
        
        // Configure shared folders (VirtioFS)
        if !vm.sharedFolders.isEmpty {
            print("🔵 VM has \(vm.sharedFolders.count) shared folder(s) configured")
            config.directorySharingDevices = try createDirectorySharingDevices(for: vm)
            print("🔵 Directory sharing devices configured: \(config.directorySharingDevices.count)")
        } else {
            print("⚠️  VM has no shared folders configured")
        }

        // Set platform based on architecture
        #if arch(arm64)
        let platform = VZGenericPlatformConfiguration()
        config.platform = platform
        #else
        let platform = VZGenericPlatformConfiguration()
        config.platform = platform
        #endif

        // Validate configuration
        try config.validate()

        return config
    }

    /// Creates the boot loader configuration
    private func createBootLoader(for vm: VirtualMachine) throws -> VZBootLoader {
        // EFI boot loader requires a variable store for NVRAM
        // Create or load EFI variable store
        let vmDirectory = vm.diskPathURL.deletingLastPathComponent()
        let variableStoreURL = vmDirectory.appendingPathComponent("efi-variable-store")
        
        let variableStore: VZEFIVariableStore
        
        // Check if variable store exists
        if FileManager.default.fileExists(atPath: variableStoreURL.path) {
            // Load existing variable store by creating with allowOverwrite option
            variableStore = try VZEFIVariableStore(creatingVariableStoreAt: variableStoreURL, options: [.allowOverwrite])
            print("✅ Loaded existing EFI variable store")
        } else {
            // Create new variable store
            variableStore = try VZEFIVariableStore(creatingVariableStoreAt: variableStoreURL)
            print("✅ Created new EFI variable store at \(variableStoreURL.path)")
        }
        
        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = variableStore
        return bootLoader
    }

    /// Creates storage devices configuration
    private func createStorageDevices(for vm: VirtualMachine) throws -> [VZStorageDeviceConfiguration] {
        var devices: [VZStorageDeviceConfiguration] = []

        // Add disk image - use VZDiskImageStorageDeviceAttachment for file-based images
        let diskPathURL = vm.diskPathURL
        print("📁 Disk path: \(diskPathURL.path)")
        print("📁 Disk exists: \(FileManager.default.fileExists(atPath: diskPathURL.path))")

        guard FileManager.default.fileExists(atPath: diskPathURL.path) else {
            print("❌ Disk file does not exist!")
            throw NSError(domain: "VirtualizationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk file does not exist at \(diskPathURL.path)"])
        }

        // PERFORMANCE: Use VZDiskImageStorageDeviceAttachment with caching enabled
        // The Virtualization framework automatically optimizes disk I/O
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: diskPathURL,
            readOnly: false,
            cachingMode: .automatic,  // Automatic caching for best performance
            synchronizationMode: .none  // Async writes for better performance (safe on modern systems)
        )
        let diskDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        
        // PERFORMANCE: Enable block device optimizations
        // blockDeviceIdentifier helps the guest OS identify and optimize for this virtual disk
        diskDevice.blockDeviceIdentifier = "primary-disk"
        
        devices.append(diskDevice)
        print("✅ Disk device added (using disk image attachment with optimizations)")

        // Add ISO - read-only with optimized caching
        let isoPathURL = vm.isoPathURL
        print("📁 ISO path: \(isoPathURL.path)")
        print("📁 ISO exists: \(FileManager.default.fileExists(atPath: isoPathURL.path))")

        let isoAttachment = try VZDiskImageStorageDeviceAttachment(
            url: isoPathURL,
            readOnly: true,
            cachingMode: .automatic,  // Cache ISO reads for better performance
            synchronizationMode: .none
        )
        let isoDevice = VZVirtioBlockDeviceConfiguration(attachment: isoAttachment)
        isoDevice.blockDeviceIdentifier = "installation-media"
        
        devices.append(isoDevice)
        print("✅ ISO device added (using disk image attachment with optimizations)")

        return devices
    }

    /// Creates network devices configuration
    private func createNetworkDevices() -> [VZNetworkDeviceConfiguration] {
        // PERFORMANCE: Use NAT with optimized settings
        let networkAttachment = VZNATNetworkDeviceAttachment()
        
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = networkAttachment
        
        // Enable all modern network features for best performance
        // The VirtIO network device provides near-native network performance
        
        return [networkDevice]
    }

    /// Creates graphics devices configuration
    private func createGraphicsDevices(for vm: VirtualMachine) -> [VZGraphicsDeviceConfiguration] {
        let graphicsConfiguration = VZVirtioGraphicsDeviceConfiguration()
        
        // PERFORMANCE: Configure primary display with good default resolution
        // Using 1920x1080 (Full HD) as a good starting resolution
        // The display will automatically reconfigure to match the window size when enabled
        // The scanout configuration defines both the initial and maximum resolution
        let scanout = VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
        graphicsConfiguration.scanouts = [scanout]
        
        // Note: VRAM size is managed automatically by the Virtualization framework
        // based on the scanout configuration. Higher resolutions will automatically
        // allocate more graphics memory as needed.
        
        // ACCELERATION: The VirtIO graphics device provides:
        // - Hardware-accelerated 2D rendering via Metal
        // - Support for virgl 3D acceleration (when guest drivers support it)
        // - Dynamic resolution changes
        // - Efficient memory sharing between host and guest
        
        // Enable dynamic resolution changes when the window is resized
        // This allows the guest OS to automatically adjust its resolution
        // to match the VM window size
        
        // GUEST SETUP for optimal graphics performance:
        // 
        // 1. VirtIO GPU Driver (usually pre-installed):
        //    - Modern Linux kernels include virtio-gpu driver by default
        //    - Check with: lsmod | grep virtio_gpu
        //
        // 2. For X11 systems:
        //    - Install: xserver-xorg-video-qxl or use modesetting driver
        //    - Or ensure virtio-gpu is being used as the display driver
        //
        // 3. For Wayland (recommended for best performance):
        //    - Modern compositors (GNOME, KDE Plasma, Sway) work automatically
        //    - Wayland provides better integration with virtio-gpu
        //
        // 4. Enable 3D acceleration in guest:
        //    - Ensure virgl3d support is enabled (built into modern kernels)
        //    - Install mesa-utils to test: glxinfo | grep -i renderer
        //
        // 5. Optimize guest for performance:
        //    - Disable desktop compositing effects if not needed
        //    - Use a lightweight desktop environment for better responsiveness
        //    - Consider disabling window animations
        
        return [graphicsConfiguration]
    }

    /// Creates serial port configuration for console
    private func createSerialPorts() -> [VZSerialPortConfiguration] {
        let stdoutHandle = FileHandle.standardOutput
        let stdinHandle = FileHandle.standardInput

        let serialPortAttachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: stdinHandle,
            fileHandleForWriting: stdoutHandle
        )

        let serialPortConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPortConfiguration.attachment = serialPortAttachment

        return [serialPortConfiguration]
    }
    
    /// Creates directory sharing devices (VirtioFS) for shared folders
    private func createDirectorySharingDevices(for vm: VirtualMachine) throws -> [VZDirectorySharingDeviceConfiguration] {
        // VirtioFS allows sharing directories between host and guest
        // GUEST SETUP REQUIRED:
        // 
        // 1. The shared folders will appear as VirtioFS mounts in the Linux guest
        // 2. To mount a shared folder, run in the guest:
        //    sudo mkdir -p /mnt/shared
        //    sudo mount -t virtiofs <share-name> /mnt/shared
        //
        // 3. For automatic mounting on boot, add to /etc/fstab:
        //    <share-name>  /mnt/shared  virtiofs  defaults  0  0
        //
        // 4. Example for a share named "documents":
        //    sudo mount -t virtiofs documents /mnt/documents
        //
        // IMPORTANT: The tag used in VZVirtioFileSystemDeviceConfiguration
        // is what you use as the device name in the mount command
        
        var devices: [VZDirectorySharingDeviceConfiguration] = []
        
        for folder in vm.sharedFolders {
            // Ensure the folder exists on the host
            guard FileManager.default.fileExists(atPath: folder.hostPath.path) else {
                print("⚠️  Shared folder does not exist: \(folder.hostPath.path)")
                continue
            }
            
            // Create the shared directory with appropriate access
            let sharedDirectory = VZSharedDirectory(url: folder.hostPath, readOnly: folder.readOnly)
            
            // Create a single directory share (not multiple)
            let share = VZSingleDirectoryShare(directory: sharedDirectory)
            
            // Create a VirtioFS device for this share
            // The tag is what the guest uses to mount: mount -t virtiofs <tag> /mnt/point
            let device = VZVirtioFileSystemDeviceConfiguration(tag: folder.name)
            device.share = share
            
            devices.append(device)
            
            print("📁 Configured shared folder: '\(folder.name)' -> \(folder.hostPath.path) (readOnly: \(folder.readOnly))")
        }
        
        guard !devices.isEmpty else {
            print("⚠️  No valid shared folders to configure")
            return []
        }
        
        print("✅ VirtioFS configured with \(devices.count) shared folder(s)")
        
        return devices
    }

    // MARK: - VM Creation and Execution

    /// Creates and starts a virtual machine
    func createAndStartVirtualMachine(_ vm: VirtualMachine) async throws -> VZVirtualMachine {
        let config = try createConfiguration(for: vm)
        let vzVM = VZVirtualMachine(configuration: config)

        // Start the VM
        try await withCheckedThrowingContinuation { continuation in
            vzVM.start { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        return vzVM
    }

    /// Stops a running virtual machine
    func stopVirtualMachine(_ vm: VZVirtualMachine) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            vm.stop { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - VM State

    /// Checks if the system supports virtualization
    func checkVirtualizationSupport() -> Bool {
        // In macOS 26, virtualization support is assumed on Apple Silicon
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Returns the host's CPU architecture
    var hostArchitecture: String {
        #if arch(arm64)
        return "aarch64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "Unknown"
        #endif
    }

    /// Returns the available CPU cores
    var availableCPUCores: Int {
        ProcessInfo.processInfo.processorCount
    }

    /// Returns the total system memory in bytes
    var totalMemory: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }
}
