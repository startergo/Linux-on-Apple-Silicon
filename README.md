# Linux VM Creator for macOS

A user interface for creating and managing Linux virtual machines on macOS using Apple's Virtualization framework.

## Features

- **GUI-based VM Creation**: Easy-to-use SwiftUI interface for creating Linux VMs
- **Supported Distributions**: Pre-configured templates for Ubuntu, Debian, Arch Linux, Fedora, CentOS, AlmaLinux, and Rocky Linux
- **Hardware Configuration**: Customize CPU cores, memory, and disk size
- **Architecture Support**: Native ARM64 support on Apple Silicon, with optional Rosetta for x86_64 emulation
- **Network Configuration**: Built-in NAT networking support
- **VM Management**: Start, stop, and delete VMs from the interface

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4) recommended
- Xcode 15.0 or later
- Apple's Virtualization framework

## Architecture

The project follows the MVVM (Model-View-ViewModel) pattern:

```
LinuxVMCreator/
├── LinuxVMCreatorApp.swift       # App entry point
├── ContentView.swift             # Main window and VM list UI
├── VirtualMachine.swift          # VM model
├── VMManagerViewModel.swift      # Business logic and VM lifecycle
├── VirtualizationService.swift   # Apple Virtualization framework integration
├── VMDetailView.swift            # VM detail panel UI
└── VMNetworkDetector.swift       # Network detection for running VMs
```

## Building

```bash
open LinuxVMCreator.xcodeproj
```

Then build and run with **⌘R**. The Xcode project is fully configured — no additional setup required. See [XCODE_SETUP.md](XCODE_SETUP.md) for signing and troubleshooting details.

## Using the App

1. **Create a New VM**: Click "New VM" or press `Cmd+N`
2. **Select Distribution**: Choose a Linux distribution from the dropdown
3. **Download ISO**: Click "Download" to get the recommended ISO, or choose a custom one
4. **Configure Hardware**: Adjust CPU cores, memory, and disk size
5. **Create**: Click "Create" to build the VM
6. **Start VM**: Select the VM and click "Start" to boot

## Virtualization Framework APIs Used

### Key Classes

- `VZVirtualMachine`: Manages VM state and execution
- `VZVirtualMachineConfiguration`: Defines VM hardware configuration
- `VZLinuxBootLoader`: Boot loader for Linux guests
- `VZVirtioBlockDeviceConfiguration`: Virtio block device for storage
- `VZVirtioNetworkDeviceConfiguration`: Virtio network device
- `VZNATNetworkDeviceAttachment`: NAT networking attachment

### Documentation

- [Apple Virtualization Framework](https://developer.apple.com/documentation/virtualization)
- [VZVirtualMachine](https://developer.apple.com/documentation/virtualization/vzvirtualmachine)
- [VZLinuxBootLoader](https://developer.apple.com/documentation/virtualization/vzlinuxbootloader)

## Entitlements

The app requires the following entitlements (configured in `LinuxVMCreator.entitlements`):

```xml
<key>com.apple.security.virtualization</key>
<true/>
<key>com.apple.vm.networking</key>
<true/>
```

## Supported Linux Distributions

The following distributions have pre-configured ISO URLs:

| Distribution | Recommended ISO |
|-------------|-----------------|
| Ubuntu 24.04 | [Download](https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-arm64.iso) |
| Debian 12 | [Download](https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/) |
| Arch Linux | [Download](https://geo.archlinux.org/iso/) |
| Fedora 40 | [Download](https://download.fedoraproject.org/pub/fedora/linux/releases/) |
| CentOS Stream | [Download](https://mirrors.centos.org/mirrorlist) |
| AlmaLinux 9 | [Download](https://repo.almalinux.org/almalinux/9.x/isos/aarch64/) |
| Rocky Linux 9 | [Download](https://download.rockylinux.org/pub/rocky/9.x/isos/aarch64/) |

## Troubleshooting

### "Failed to start VM" Error

1. Ensure your Mac supports hardware virtualization
2. Check that the VM disk was created successfully
3. Verify the ISO file is valid

### Network Not Working

1. Check that `com.apple.vm.networking` entitlement is enabled
2. Ensure network access is allowed in System Settings

### Rosetta Not Available

Rosetta for Linux VMs requires macOS 15.0 (Sequoia) or later. Install Rosetta from Terminal:
```bash
softwareupdate --install-rosetta
```

## License

This project is provided as-is for educational purposes.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
