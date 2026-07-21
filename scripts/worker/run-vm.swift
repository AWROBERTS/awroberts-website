import Virtualization
import Foundation

guard CommandLine.arguments.count == 8 else {
    fputs("Usage: run-vm <autoinstall-iso|none> <cidata-iso|none> <os-disk> <hls-disk> <ram-mb> <cpu-count> <mac>\n", stderr)
    exit(1)
}

let isoPath    = CommandLine.arguments[1]
let ciDataPath = CommandLine.arguments[2]
let osDisk     = CommandLine.arguments[3]
let hlsDisk    = CommandLine.arguments[4]
let ramMB      = Int(CommandLine.arguments[5]) ?? 4096
let cpuCount   = Int(CommandLine.arguments[6]) ?? 4
let macStr     = CommandLine.arguments[7]

let efi = VZEFIBootLoader()
let efiStoreURL = URL(fileURLWithPath: osDisk + ".efi")
let efiStore: VZEFIVariableStore
if FileManager.default.fileExists(atPath: efiStoreURL.path) {
    efiStore = VZEFIVariableStore(url: efiStoreURL)
} else {
    efiStore = try! VZEFIVariableStore(creatingVariableStoreAt: efiStoreURL, options: [])
}
efi.variableStore = efiStore

let config = VZVirtualMachineConfiguration()
config.cpuCount = cpuCount
config.memorySize = UInt64(ramMB) * 1024 * 1024
config.bootLoader = efi

var storageDevices: [VZStorageDeviceConfiguration] = []

if isoPath != "none" {
    let isoAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: isoPath), readOnly: true)
    storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: isoAttachment))
}

if ciDataPath != "none" {
    let ciDataAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: ciDataPath), readOnly: true)
    storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: ciDataAttachment))
}

let osAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: osDisk), readOnly: false)
storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: osAttachment))

let hlsAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: hlsDisk), readOnly: false)
storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: hlsAttachment))

config.storageDevices = storageDevices

let network = VZVirtioNetworkDeviceConfiguration()
network.attachment = VZNATNetworkDeviceAttachment()
if let mac = VZMACAddress(string: macStr) {
    network.macAddress = mac
}
config.networkDevices = [network]

let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
let serialPort = VZFileHandleSerialPortAttachment(
    fileHandleForReading: FileHandle.standardInput,
    fileHandleForWriting: FileHandle.standardError
)
serial.attachment = serialPort
config.serialPorts = [serial]

config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

try! config.validate()

final class VMDelegate: NSObject, VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        fputs("Guest stopped (powered off).\n", stderr)
        exit(0)
    }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        fputs("VM stopped with error: \(error)\n", stderr)
        exit(0)
    }
}

let vm = VZVirtualMachine(configuration: config, queue: DispatchQueue.main)
let delegate = VMDelegate()

DispatchQueue.main.async {
    vm.delegate = delegate
    vm.start { result in
        switch result {
        case .success:
            fputs("VM started successfully.\n", stderr)
        case .failure(let err):
            fputs("Failed to start VM: \(err)\n", stderr)
            exit(1)
        }
    }
}

RunLoop.main.run()
