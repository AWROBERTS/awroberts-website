#!/bin/bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (macOS Side, Apple Virtualization.framework)
# ============================================================================
# This script runs on the Mac mini and:
#   1. Validates the autoinstall ISO copied from Mint
#   2. Creates VM disk images (OS + HLS storage)
#   3. Writes a Swift helper that uses Virtualization.framework to boot the VM
#   4. Compiles and runs the Swift helper
#
# Requires macOS 13+ (Ventura) on Apple Silicon.
# No third-party tools (UTM, tart, etc.) — native Virtualization.framework only.
# ============================================================================

# === CONFIG ===
VM_NAME="worker-arm"
VM_DIR="$HOME/VMs/${VM_NAME}"

UBUNTU_ISO="$HOME/worker-ubuntu.iso"
SEED_ISO="$HOME/worker-seed.iso"

OS_DISK_SIZE_GB=20
HLS_DISK_SIZE_GB=20

RAM_MB=4096
CPU_COUNT=4

# === 1. Sanity checks ===
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Apple Virtualization.framework requires Apple Silicon (arm64)."
  exit 1
fi

SW_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$SW_VER" | cut -d. -f1)
if (( MACOS_MAJOR < 13 )); then
  echo "ERROR: macOS 13 (Ventura) or later required for full Virtualization.framework support. Got: $SW_VER"
  exit 1
fi

if [ ! -f "$UBUNTU_ISO" ]; then
  echo "ERROR: Ubuntu ISO not found at: $UBUNTU_ISO"
  exit 1
fi

if [ ! -f "$SEED_ISO" ]; then
  echo "ERROR: Seed ISO not found at: $SEED_ISO"
  exit 1
fi

mkdir -p "$VM_DIR"

# === 2. Create disk images ===
OS_DISK="$VM_DIR/os.img"
HLS_DISK="$VM_DIR/hls.img"

if [ ! -f "$OS_DISK" ]; then
  echo "Creating OS disk (${OS_DISK_SIZE_GB}GB)..."
  dd if=/dev/zero bs=1m count=$(( OS_DISK_SIZE_GB * 1024 )) of="$OS_DISK" 2>/dev/null
fi

if [ ! -f "$HLS_DISK" ]; then
  echo "Creating HLS disk (${HLS_DISK_SIZE_GB}GB)..."
  dd if=/dev/zero bs=1m count=$(( HLS_DISK_SIZE_GB * 1024 )) of="$HLS_DISK" 2>/dev/null
fi

# === 3. Write Swift VM runner ===
SWIFT_RUNNER="$VM_DIR/run-vm.swift"

cat > "$SWIFT_RUNNER" <<'SWIFT'
import Virtualization
import Foundation

guard CommandLine.arguments.count == 7 else {
    fputs("Usage: run-vm <ubuntu-iso> <seed-iso> <os-disk> <hls-disk> <ram-mb> <cpu-count>\n", stderr)
    exit(1)
}

let ubuntuISO  = CommandLine.arguments[1]
let seedISO    = CommandLine.arguments[2]
let osDisk     = CommandLine.arguments[3]
let hlsDisk    = CommandLine.arguments[4]
let ramMB      = Int(CommandLine.arguments[5]) ?? 4096
let cpuCount   = Int(CommandLine.arguments[6]) ?? 4

// --- Boot loader: EFI (required for Linux on Apple Virtualization) ---
let efi = VZEFIBootLoader()
let efiStoreURL = URL(fileURLWithPath: osDisk + ".efi")
let efiStore: VZEFIVariableStore
if FileManager.default.fileExists(atPath: efiStoreURL.path) {
    efiStore = VZEFIVariableStore(url: efiStoreURL)
} else {
    efiStore = try! VZEFIVariableStore(creatingVariableStoreAt: efiStoreURL, options: [])
}
efi.variableStore = efiStore

// --- CPU & memory ---
let config = VZVirtualMachineConfiguration()
config.cpuCount = cpuCount
config.memorySize = UInt64(ramMB) * 1024 * 1024
config.bootLoader = efi

// --- Storage: Ubuntu installer ISO (boot) ---
let ubuntuAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: ubuntuISO), readOnly: true)
let ubuntuDevice = VZVirtioBlockDeviceConfiguration(attachment: ubuntuAttachment)

// --- Storage: cloud-init seed ISO (CIDATA) ---
let seedAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: seedISO), readOnly: true)
let seedDevice = VZVirtioBlockDeviceConfiguration(attachment: seedAttachment)

// --- Storage: OS disk ---
let osAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: osDisk), readOnly: false)
let osDevice = VZVirtioBlockDeviceConfiguration(attachment: osAttachment)

// --- Storage: HLS disk ---
let hlsAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: hlsDisk), readOnly: false)
let hlsDevice = VZVirtioBlockDeviceConfiguration(attachment: hlsAttachment)

config.storageDevices = [ubuntuDevice, seedDevice, osDevice, hlsDevice]

// --- Network: NAT (DHCP) ---
let network = VZVirtioNetworkDeviceConfiguration()
network.attachment = VZNATNetworkDeviceAttachment()
config.networkDevices = [network]

// --- Serial console (stdout) ---
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
let serialPort = VZFileHandleSerialPortAttachment(
    fileHandleForReading: FileHandle.standardInput,
    fileHandleForWriting: FileHandle.standardOutput
)
serial.attachment = serialPort
config.serialPorts = [serial]

// --- Entropy ---
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

try! config.validate()

let vm = VZVirtualMachine(configuration: config)

let sema = DispatchSemaphore(value: 0)
vm.start { result in
    switch result {
    case .success:
        print("VM started successfully.")
    case .failure(let err):
        fputs("Failed to start VM: \(err)\n", stderr)
        exit(1)
    }
}

// Keep process alive until VM stops
NotificationCenter.default.addObserver(forName: NSNotification.Name("VZVirtualMachineStateDidChange"), object: vm, queue: nil) { _ in
    if vm.state == .stopped || vm.state == .error {
        sema.signal()
    }
}

sema.wait()
SWIFT

echo "Swift VM runner written to: $SWIFT_RUNNER"

# === 4. Compile and run Swift VM runner ===
SWIFT_BIN="$VM_DIR/run-vm"

echo "Compiling Swift VM runner..."
swiftc \
  -framework Virtualization \
  -o "$SWIFT_BIN" \
  "$SWIFT_RUNNER"


ENTITLEMENTS="$VM_DIR/entitlements.plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.virtualization</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing VM runner with virtualization entitlement..."
codesign --sign - --entitlements "$ENTITLEMENTS" --force "$SWIFT_BIN"

echo "Starting VM '${VM_NAME}' via Apple Virtualization.framework..."
"$SWIFT_BIN" \
  "$UBUNTU_ISO" \
  "$SEED_ISO" \
  "$OS_DISK" \
  "$HLS_DISK" \
  "$RAM_MB" \
  "$CPU_COUNT"

echo "VM started. Autoinstall is running inside the VM."
echo "Mint can begin polling for SSH on the worker IP."
