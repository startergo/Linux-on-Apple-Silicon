//
//  VirtualMachine.swift
//  LinuxVMCreator
//
//  Data model for a virtual machine.
//

import Foundation
import Virtualization
import SwiftUI

/// Represents the current state of a virtual machine
enum VMState: Codable, Equatable, CustomStringConvertible {
    case stopped
    case starting
    case running
    case stopping
    case paused
    case error(String)

    var description: String {
        switch self {
        case .stopped: return "stopped"
        case .starting: return "starting"
        case .running: return "running"
        case .stopping: return "stopping"
        case .paused: return "paused"
        case .error(let msg): return "error(\(msg))"
        }
    }

    var icon: String {
        switch self {
        case .stopped: return "circle"
        case .starting: return "circle.dashed"
        case .running: return "circle.fill"
        case .stopping: return "circle.dashed"
        case .paused: return "pause.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting: return .orange
        case .running: return .green
        case .stopping: return .orange
        case .paused: return .yellow
        case .error: return .red
        }
    }

    // Custom Codable implementation
    enum CodingKeys: String, CodingKey {
        case baseType, errorMessage
    }

    var baseType: String {
        switch self {
        case .stopped: return "stopped"
        case .starting: return "starting"
        case .running: return "running"
        case .stopping: return "stopping"
        case .paused: return "paused"
        case .error: return "error"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseType = try container.decode(String.self, forKey: .baseType)

        switch baseType {
        case "stopped": self = .stopped
        case "starting": self = .starting
        case "running": self = .running
        case "stopping": self = .stopping
        case "paused": self = .paused
        case "error":
            let errorMessage = try container.decode(String.self, forKey: .errorMessage)
            self = .error(errorMessage)
        default:
            throw DecodingError.dataCorruptedError(forKey: .baseType, in: container, debugDescription: "Invalid VMState type")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseType, forKey: .baseType)
        if case .error(let message) = self {
            try container.encode(message, forKey: .errorMessage)
        }
    }
}

/// Supported Linux distributions
enum LinuxDistribution: String, Codable, CaseIterable, Identifiable {
    case ubuntu = "Ubuntu"
    case debian = "Debian"
    case arch = "Arch Linux"
    case fedora = "Fedora"
    case centos = "CentOS"
    case alma = "AlmaLinux"
    case rocky = "Rocky Linux"
    case other = "Other"

    var id: String { rawValue }

    var recommendedISO: String {
        switch self {
        case .ubuntu:
            return "https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-arm64.iso"
        case .debian:
            return "https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-13.3.0-arm64-netinst.iso"
        case .arch:
            // Arch Linux has no official ARM64 ISO; EndeavourOS Ganymede is the recommended Arch-based ARM64 distro
            return "https://github.com/startergo/EndeavourOS-ISO-arm64/releases/latest"
        case .fedora:
            return "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Server/aarch64/iso/Fedora-Server-41-1.4-aarch64-netinst.iso"
        case .centos:
            return "https://mirrors.centos.org/mirrorlist?path=/9-stream/isos/aarch64/&release=9&arch=aarch64"
        case .alma:
            return "https://repo.almalinux.org/almalinux/10.1/isos/aarch64/AlmaLinux-10.1-aarch64-minimal.iso"
        case .rocky:
            return "https://download.rockylinux.org/pub/rocky/10.1/isos/aarch64/Rocky-10.1-aarch64-minimal.iso"
        case .other:
            return ""
        }
    }
    
    // Custom decoder to handle backward compatibility with old "Alma" case
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        // Map old "Alma" to new "alma"
        if rawValue == "Alma" {
            self = .alma
        } else if let distribution = LinuxDistribution(rawValue: rawValue) {
            self = distribution
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid distribution: \(rawValue)"
            )
        }
    }
}

/// Architecture type for virtual machines
enum Architecture: String, Codable, CaseIterable, Identifiable {
    case aarch64 = "ARM64 (Apple Silicon)"
    case x86_64 = "x86_64 (with Rosetta)"

    var id: String { rawValue }
}

/// Configuration for a new virtual machine
struct VMConfiguration {
    var name: String
    var distribution: LinuxDistribution
    var cpuCount: Int
    var memorySize: Int64 // in bytes
    var diskSize: Int64 // in bytes
    var architecture: Architecture
    var isoPath: URL?
    var enableNetwork: Bool
    var enableRosetta: Bool

    static let `default` = VMConfiguration(
        name: "New Linux VM",
        distribution: .ubuntu,
        cpuCount: 4,
        memorySize: 4 * 1024 * 1024 * 1024, // 4 GB
        diskSize: 64 * 1024 * 1024 * 1024, // 64 GB
        architecture: .aarch64,
        isoPath: nil,
        enableNetwork: true,
        enableRosetta: false
    )

    // Memory presets in GB
    static let memoryPresets: [Int64] = [
        2 * 1024 * 1024 * 1024,   // 2 GB
        4 * 1024 * 1024 * 1024,   // 4 GB
        8 * 1024 * 1024 * 1024,   // 8 GB
        16 * 1024 * 1024 * 1024,  // 16 GB
        32 * 1024 * 1024 * 1024,  // 32 GB
    ]

    // Disk size presets in GB
    static let diskPresets: [Int64] = [
        32 * 1024 * 1024 * 1024,  // 32 GB
        64 * 1024 * 1024 * 1024,  // 64 GB
        128 * 1024 * 1024 * 1024, // 128 GB
        256 * 1024 * 1024 * 1024, // 256 GB
        512 * 1024 * 1024 * 1024, // 512 GB
    ]

    /// Human-readable memory size in GB
    var memorySizeGB: Double {
        Double(memorySize) / (1024 * 1024 * 1024)
    }

    /// Human-readable disk size in GB
    var diskSizeGB: Double {
        Double(diskSize) / (1024 * 1024 * 1024)
    }
}

/// Shared folder configuration
struct SharedFolder: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    var name: String // Name visible in the VM (e.g., "shared", "documents")
    var hostPath: URL // Path on the Mac
    var readOnly: Bool // Whether the folder is read-only from the VM's perspective
    var mountPath: String // Where to mount in the VM (e.g., "/mnt/documents")
    
    init(id: UUID = UUID(), name: String, hostPath: URL, readOnly: Bool = false, mountPath: String? = nil) {
        self.id = id
        self.name = name
        self.hostPath = hostPath
        self.readOnly = readOnly
        // Default mount path if not specified
        self.mountPath = mountPath ?? "/mnt/\(name)"
    }
    
    // Custom coding keys to handle URL encoding
    enum CodingKeys: String, CodingKey {
        case id, name, readOnly, mountPath
        case hostPath = "hostPath"
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        readOnly = try container.decode(Bool.self, forKey: .readOnly)
        
        // Decode mountPath with backward compatibility
        if let mountPathValue = try? container.decode(String.self, forKey: .mountPath) {
            mountPath = mountPathValue
        } else {
            // Default for old data
            mountPath = "/mnt/\(name)"
        }
        
        let hostPathString = try container.decode(String.self, forKey: .hostPath)
        if hostPathString.hasPrefix("file://") {
            hostPath = URL(string: hostPathString) ?? URL(fileURLWithPath: hostPathString)
        } else {
            hostPath = URL(fileURLWithPath: hostPathString)
        }
    }
    
    /// Generate fstab entry for auto-mounting
    var fstabEntry: String {
        "\(name)  \(mountPath)  virtiofs  \(readOnly ? "ro," : "")defaults  0  0"
    }
    
    /// Generate systemd mount unit name
    var systemdUnitName: String {
        // Convert mount path to systemd unit name
        // /mnt/documents -> mnt-documents.mount
        let sanitized = mountPath.dropFirst().replacingOccurrences(of: "/", with: "-")
        return "\(sanitized).mount"
    }
    
    /// Generate systemd mount unit content
    var systemdUnitContent: String {
        """
        [Unit]
        Description=Mount VirtioFS share: \(name)
        
        [Mount]
        What=\(name)
        Where=\(mountPath)
        Type=virtiofs
        Options=\(readOnly ? "ro," : "")defaults
        
        [Install]
        WantedBy=multi-user.target
        """
    }
}

/// Virtual machine model
struct VirtualMachine: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    var name: String
    var distribution: LinuxDistribution
    var cpuCount: Int
    var memorySize: Int64
    var diskSize: Int64
    var diskPath: URL
    var isoPath: URL
    var state: VMState
    var architecture: Architecture
    var enableNetwork: Bool
    var enableRosetta: Bool
    var sharedFolders: [SharedFolder]
    var createdAt: Date
    var lastUsedAt: Date?
    var vramSizeMB: Int64 // Graphics memory in MB (default: 512 MB)

    // Custom coding keys to handle URL encoding
    enum CodingKeys: String, CodingKey {
        case id, name, distribution, cpuCount, memorySize, diskSize, state, architecture, enableNetwork, enableRosetta, sharedFolders, createdAt, lastUsedAt, vramSizeMB
        case diskPath = "diskPath"
        case isoPath = "isoPath"
    }

    // Custom init from decoder to handle URL strings
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        distribution = try container.decode(LinuxDistribution.self, forKey: .distribution)
        cpuCount = try container.decode(Int.self, forKey: .cpuCount)
        memorySize = try container.decode(Int64.self, forKey: .memorySize)
        diskSize = try container.decode(Int64.self, forKey: .diskSize)
        architecture = try container.decode(Architecture.self, forKey: .architecture)
        enableNetwork = try container.decode(Bool.self, forKey: .enableNetwork)
        enableRosetta = try container.decode(Bool.self, forKey: .enableRosetta)
        state = try container.decode(VMState.self, forKey: .state)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        
        // Decode shared folders with backward compatibility
        sharedFolders = (try? container.decode([SharedFolder].self, forKey: .sharedFolders)) ?? []
        
        // Decode VRAM with backward compatibility (default 512 MB)
        vramSizeMB = (try? container.decode(Int64.self, forKey: .vramSizeMB)) ?? 512

        // Handle URLs - decode from string or URL
        let diskPathString = try container.decode(String.self, forKey: .diskPath)
        if diskPathString.hasPrefix("file://") {
            diskPath = URL(string: diskPathString) ?? URL(fileURLWithPath: diskPathString)
        } else {
            diskPath = URL(fileURLWithPath: diskPathString)
        }

        let isoPathString = try container.decode(String.self, forKey: .isoPath)
        if isoPathString.hasPrefix("file://") {
            isoPath = URL(string: isoPathString) ?? URL(fileURLWithPath: isoPathString)
        } else {
            isoPath = URL(fileURLWithPath: isoPathString)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        distribution: LinuxDistribution,
        cpuCount: Int,
        memorySize: Int64,
        diskSize: Int64,
        diskPath: URL,
        isoPath: URL,
        state: VMState = .stopped,
        architecture: Architecture,
        enableNetwork: Bool,
        enableRosetta: Bool,
        sharedFolders: [SharedFolder] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        vramSizeMB: Int64 = 512 // Default 512 MB VRAM
    ) {
        self.id = id
        self.name = name
        self.distribution = distribution
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.diskSize = diskSize
        self.diskPath = diskPath
        self.isoPath = isoPath
        self.state = state
        self.architecture = architecture
        self.enableNetwork = enableNetwork
        self.enableRosetta = enableRosetta
        self.sharedFolders = sharedFolders
        self.vramSizeMB = vramSizeMB
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// Human-readable memory size
    var memorySizeGB: Double {
        Double(memorySize) / (1024 * 1024 * 1024)
    }

    /// Human-readable disk size
    var diskSizeGB: Double {
        Double(diskSize) / (1024 * 1024 * 1024)
    }

    /// Check if the VM disk exists
    var diskExists: Bool {
        FileManager.default.fileExists(atPath: diskPathURL.path)
    }

    /// Check if the ISO exists
    var isoExists: Bool {
        FileManager.default.fileExists(atPath: isoPathURL.path)
    }

    /// Get the resolved file URL (handles both URL strings and file paths)
    var diskPathURL: URL {
        // Get the actual file path, handling percent encoding
        if diskPath.scheme == "file", let path = diskPath.path.removingPercentEncoding {
            return URL(fileURLWithPath: path)
        }
        return diskPath
    }

    var isoPathURL: URL {
        // Get the actual file path, handling percent encoding
        if isoPath.scheme == "file", let path = isoPath.path.removingPercentEncoding {
            return URL(fileURLWithPath: path)
        }
        return isoPath
    }

    /// Get disk file size
    var actualDiskSize: Int64? {
        guard diskExists else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: diskPathURL.path)[.size] as? Int64) ?? nil
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: VirtualMachine, rhs: VirtualMachine) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
