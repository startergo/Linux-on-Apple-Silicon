# Shared Folders Guide

This guide explains how to use the folder sharing feature in LinuxVMCreator to share directories between your Mac and Linux VMs.

## Overview

The shared folders feature uses **VirtioFS** (Virtualization Filesystem), which is Apple's implementation of the virtio file system protocol. This allows efficient, high-performance file sharing between the macOS host and Linux guests.

## Quick Start

1. **Stop your VM** (required)
2. Click **"Edit"** → **"Shared Folders"** → **"Add Folder"**
3. Select a folder from your Mac
4. **Save** and **start the VM**
5. In the VM detail view, choose your preferred mounting method:
   - **Manual**: Temporary mount (until reboot)
   - **Auto-Mount (fstab)**: Permanent mount using /etc/fstab
   - **Auto-Mount (systemd)**: Permanent mount using systemd units
6. Copy the commands and run them in your Linux VM

**Important:** Replace `foldername` with the exact name shown in the app (case-sensitive).

## Mounting Methods

### Option 1: Manual Mount (Temporary)

Good for testing or one-time access. Mount is lost on reboot.

```bash
sudo mkdir -p /mnt/documents
sudo mount -t virtiofs documents /mnt/documents
```

### Option 2: Auto-Mount with fstab (Traditional)

Permanent mount that survives reboots. Works on all distributions.

```bash
# 1. Create mount point
sudo mkdir -p /mnt/documents

# 2. Backup and edit fstab
sudo cp /etc/fstab /etc/fstab.backup
echo 'documents  /mnt/documents  virtiofs  defaults  0  0' | sudo tee -a /etc/fstab

# 3. Mount immediately
sudo mount -a

# 4. Verify
df -h | grep virtiofs
```

### Option 3: Auto-Mount with systemd (Recommended)

Modern approach with better error handling and logging.

```bash
# 1. Create mount point
sudo mkdir -p /mnt/documents

# 2. Create systemd mount unit
sudo tee /etc/systemd/system/mnt-documents.mount << 'EOF'
[Unit]
Description=Mount VirtioFS share: documents

[Mount]
What=documents
Where=/mnt/documents
Type=virtiofs
Options=defaults

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable mnt-documents.mount
sudo systemctl start mnt-documents.mount

# 4. Verify
sudo systemctl status mnt-documents.mount
```

**Tip:** The app provides ready-to-copy commands for all methods in the VM detail view!

## How to Configure Shared Folders

### 1. In the LinuxVMCreator App

1. **Stop your VM** (shared folders can only be configured when the VM is stopped)
2. Click the **"Edit"** button in the VM detail view
3. Scroll to the **"Shared Folders"** section
4. Click **"Add Folder"** and select a folder from your Mac
5. The folder will be added with a default name (e.g., `documents`, `downloads`)
6. You can toggle between **read-only** and **read-write** modes by clicking the lock icon
7. Click **"Save Changes"**

### 2. In Your Linux VM

After configuring shared folders in the app and starting your VM, choose one of the mounting methods above. The app provides copy-paste ready commands in the VM detail view under the "Shared Folders" section.

## Common Use Cases

### Sharing Your Documents Folder
Perfect for accessing your Mac's documents from the VM:
- Host: `/Users/yourname/Documents` → VM name: `documents`
- Mount in VM: `sudo mount -t virtiofs documents /mnt/documents`

### Sharing a Development Project
Share a code project between Mac and Linux:
- Host: `/Users/yourname/Projects/myproject` → VM name: `myproject`
- Mount in VM: `sudo mount -t virtiofs myproject /mnt/myproject`

### Read-Only Downloads
Share downloads but prevent the VM from modifying them:
- Host: `/Users/yourname/Downloads` → VM name: `downloads` (read-only)
- Mount in VM: `sudo mount -t virtiofs downloads /mnt/downloads`

## Performance Tips

1. **VirtioFS is fast**: It's designed for near-native filesystem performance
2. **Use for development**: Great for editing code in macOS while building/testing in Linux
3. **Avoid excessive small file operations**: Like any network filesystem, many small operations are slower than fewer large operations
4. **Consider rsync for large transfers**: For one-time large file transfers, rsync might be faster

## Permissions

### File Ownership
- Files created in the shared folder from the VM will appear as owned by your Mac user
- Files created on Mac will be accessible in the VM based on read-only/read-write setting

### Read-Only vs Read-Write
- **Read-Only**: VM can read files but cannot modify, create, or delete them
- **Read-Write**: VM has full access to create, modify, and delete files
- **Recommendation**: Use read-only unless you specifically need write access

## Troubleshooting

### Shared Folder Doesn't Mount

**Error: "wrong fs type, bad option, bad superblock"**

This usually means VirtioFS isn't available or the tag name doesn't match. Try these steps:

1. **Check if VirtioFS kernel module is loaded:**
```bash
# Check if virtiofs module is available
lsmod | grep virtiofs

# If not loaded, try to load it
sudo modprobe virtiofs

# Check kernel support
cat /proc/filesystems | grep virtiofs
```

2. **List available VirtioFS devices:**
```bash
# Check system logs for VirtioFS devices
dmesg | grep -i virtiofs

# Look for virtio filesystem devices
ls -la /sys/bus/virtio/drivers/virtiofs/
```

3. **Verify the tag name matches exactly:**

The device name in the mount command must **exactly** match the folder name you configured in the app (case-sensitive). Check the VM detail view for the correct name.

```bash
# Wrong (if folder is named "documents")
sudo mount -t virtiofs Documents /mnt/documents

# Correct
sudo mount -t virtiofs documents /mnt/documents
```

4. **Check if the device appears in the system:**
```bash
# List all virtio devices
ls -la /sys/bus/virtio/devices/

# Check for filesystem devices and their mount tags
for d in /sys/bus/virtio/devices/virtio*/; do
    if [ -f "$d/mount_tag" ]; then
        echo "Found VirtioFS device with tag: $(cat $d/mount_tag)"
    fi
done
```

5. **Ensure the VM was restarted after adding shared folders:**

Shared folders are only configured when the VM starts. If you added folders while the VM was running, you need to:
- Stop the VM
- Start it again
- Then try mounting

Most modern Linux distributions (Ubuntu 20.04+, Fedora 32+, Debian 11+) include VirtioFS support by default.

### Permission Denied Errors

If you get "Permission denied" when accessing files:
1. Check if the folder is mounted read-only
2. Verify the folder exists on your Mac
3. Ensure your Mac user has permission to access the folder

### Folder Name Already Exists

If you see a duplicate name error:
1. The app will automatically append a number (e.g., `documents_1`)
2. You can rename folders by removing and re-adding them

### Mount Fails with "No such device"

Your Linux kernel might not have VirtioFS support:
```bash
# Check kernel version (needs 5.4+)
uname -r

# For older distributions, you may need to upgrade your kernel
# Ubuntu/Debian:
sudo apt update && sudo apt upgrade
sudo reboot
```

## Distribution-Specific Notes

### Ubuntu / Debian
VirtioFS is included by default in:
- Ubuntu 20.04 LTS and later
- Debian 11 (Bullseye) and later

### Fedora / RHEL / CentOS
VirtioFS is included by default in:
- Fedora 32 and later
- RHEL 8.3 and later
- CentOS Stream 8 and later

### Arch Linux
VirtioFS is included in the default kernel.

### Alpine Linux
You may need to manually load the module:
```bash
modprobe virtiofs
```

## Security Considerations

1. **Only share what you need**: Don't share your entire home directory unless necessary
2. **Use read-only when possible**: Prevents accidental modifications from the VM
3. **Be careful with sensitive data**: Remember the VM can access shared folders
4. **Consider encryption**: For sensitive projects, consider using encrypted containers

## Advanced: Creating Mount Scripts

Create a helper script in your VM for easy mounting:

```bash
#!/bin/bash
# save as /usr/local/bin/mount-shared

# Define your shared folders
SHARES=(
    "documents:/mnt/documents"
    "projects:/mnt/projects"
    "downloads:/mnt/downloads"
)

for share in "${SHARES[@]}"; do
    IFS=: read -r name mountpoint <<< "$share"
    
    # Create mount point if it doesn't exist
    sudo mkdir -p "$mountpoint"
    
    # Mount the share
    if ! mountpoint -q "$mountpoint"; then
        echo "Mounting $name to $mountpoint..."
        sudo mount -t virtiofs "$name" "$mountpoint"
    else
        echo "$mountpoint already mounted"
    fi
done

echo "All shared folders mounted!"
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/mount-shared
```

Then just run `mount-shared` after boot!

## Diagnostic Script

If you're having trouble, save this script to help diagnose VirtioFS issues:

```bash
#!/bin/bash
# save as: check-virtiofs.sh

echo "=== VirtioFS Diagnostic ==="
echo

echo "1. Kernel Support:"
if grep -q virtiofs /proc/filesystems; then
    echo "   ✓ VirtioFS is supported"
else
    echo "   ✗ VirtioFS is NOT in kernel"
fi
echo

echo "2. Kernel Module:"
if lsmod | grep -q virtiofs; then
    echo "   ✓ Module is loaded"
else
    echo "   ⚠ Module not loaded, trying to load..."
    sudo modprobe virtiofs && echo "   ✓ Loaded successfully" || echo "   ✗ Failed to load"
fi
echo

echo "3. Available VirtioFS Devices:"
found=0
for d in /sys/bus/virtio/devices/virtio*/; do
    if [ -f "$d/mount_tag" ]; then
        tag=$(cat "$d/mount_tag")
        echo "   ✓ Found device: $tag"
        found=1
    fi
done
if [ $found -eq 0 ]; then
    echo "   ✗ No VirtioFS devices found"
    echo "   → Make sure VM was restarted after adding shared folders"
fi
echo

echo "4. Already Mounted:"
if mount | grep -q virtiofs; then
    echo "   Currently mounted VirtioFS shares:"
    mount | grep virtiofs | while read line; do
        echo "   ✓ $line"
    done
else
    echo "   No VirtioFS shares currently mounted"
fi
echo

echo "5. Kernel Version:"
echo "   $(uname -r)"
echo "   (VirtioFS requires kernel 5.4 or newer)"
echo

echo "=== End Diagnostic ==="
```

Make it executable and run:
```bash
chmod +x check-virtiofs.sh
./check-virtiofs.sh
```

## Examples

### Example 1: Development Workflow
1. Share your project folder from Mac
2. Mount it in the VM at `/mnt/project`
3. Edit code in your favorite Mac editor (VS Code, etc.)
4. Build and test in the Linux VM
5. Changes are instantly visible in both environments

### Example 2: Data Processing
1. Share a data folder (read-only) from Mac
2. Process the data in Linux
3. Output results to a separate shared folder (read-write)
4. Analyze results on your Mac

### Example 3: Testing Installer Packages
1. Build .deb or .rpm packages on Mac (or in VM)
2. Share the package folder
3. Test installation in multiple VMs
4. All VMs can access the same packages

## Getting Help

If you encounter issues:
1. Check the Console.app logs for VirtioFS errors
2. Run `dmesg` in the Linux VM for kernel messages
3. Verify the folder exists and is accessible on your Mac
4. Ensure the VM is stopped when modifying shared folders
5. Try removing and re-adding the shared folder

---

**Note**: VirtioFS is only available on Apple Silicon Macs running macOS 12 (Monterey) or later with the Virtualization framework.
