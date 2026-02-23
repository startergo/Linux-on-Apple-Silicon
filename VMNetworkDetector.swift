//
//  VMNetworkDetector.swift
//  LinuxVMCreator
//
//  Detects IP addresses of running VMs from DHCP leases.
//

import Foundation

@MainActor
struct VMNetworkDetector {
    /// Attempt to detect the IP address of a running VM
    /// This checks common DHCP lease files on macOS
    static func detectIPAddress(for vm: VirtualMachine) async -> String? {
        // Try different methods to detect the IP
        
        // Method 1: Check macOS DHCP leases file
        if let ip = await checkDHCPLeases(for: vm) {
            return ip
        }
        
        // Method 2: Parse ARP cache (less reliable)
        if let ip = await checkARPCache() {
            return ip
        }
        
        return nil
    }
    
    /// Check DHCP leases file for VM's MAC address
    private static func checkDHCPLeases(for vm: VirtualMachine) async -> String? {
        // Common DHCP lease file locations on macOS
        let leasePaths = [
            "/var/db/dhcpd_leases",
            "/private/var/db/dhcpd_leases"
        ]
        
        for leasePath in leasePaths {
            let leaseURL = URL(fileURLWithPath: leasePath)
            
            guard let leaseData = try? Data(contentsOf: leaseURL),
                  let _ = String(data: leaseData, encoding: .utf8) else {
                continue
            }
            
            // Parse lease file (plist format on macOS)
            if let plist = try? PropertyListSerialization.propertyList(
                from: leaseData,
                options: [],
                format: nil
            ) as? [String: Any] {
                // Look through leases for recent entries
                // This is a simplified approach - real implementation would need
                // to match VM's MAC address
                
                // For now, just return the most recent IP from the bridge network
                if let ip = findRecentBridgeIP(in: plist) {
                    return ip
                }
            }
        }
        
        return nil
    }
    
    /// Check ARP cache for recent entries on the bridge network
    private static func checkARPCache() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-a"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Parse ARP output looking for bridge interfaces
            // Format: hostname (192.168.64.x) at aa:bb:cc:dd:ee:ff on bridge100 ifscope [ethernet]
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("bridge") {
                    // Extract IP address from format: (192.168.64.x)
                    if let match = line.range(of: #"\((\d+\.\d+\.\d+\.\d+)\)"#, options: .regularExpression) {
                        let ipWithParens = String(line[match])
                        let ip = ipWithParens.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                        return ip
                    }
                }
            }
        } catch {
            print("❌ Failed to check ARP cache: \(error)")
        }
        
        return nil
    }
    
    /// Find the most recent IP address from bridge network in DHCP leases
    private static func findRecentBridgeIP(in plist: [String: Any]) -> String? {
        // This is a placeholder - actual implementation would need to:
        // 1. Match VM's MAC address from Virtualization framework
        // 2. Find corresponding IP in DHCP leases
        // 3. Verify it's still valid
        
        // For now, return nil to indicate detection is not available
        return nil
    }
}
