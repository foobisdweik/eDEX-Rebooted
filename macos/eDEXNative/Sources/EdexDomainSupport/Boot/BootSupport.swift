import Foundation

// Phase 6.5 boot screen support — pure, FFI-free module.
//
// Encodes the legacy renderer.js boot sequence: 85-line fake kernel log with
// a synthetic kernel-version line injected after display index 1, variable
// per-line timing matching the JS displayLine() switch, and nointro gating.

// MARK: - Boot log lines

public enum BootLines {
    /// 85 decoded lines from the legacy boot_log.txt. Internal empty lines
    /// (lines 24, 42, 47, 83, 84) are preserved; only the trailing empty
    /// string produced by the multiline literal is stripped.
    /// HTML entities (&lt; &gt; &quot; &#039;) are pre-decoded in the literal
    /// so SwiftUI Text displays literal angle brackets and quotes.
    public static let rawLines: [String] = {
        var lines = rawBootLogString.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }()

    /// Synthetic kernel-version line injected into the display stream after
    /// line index 1, matching the legacy JS fall-through at i===2.
    public static func syntheticKernelLine(appVersion: String, date: String) -> String {
        "eDEX-UI Kernel version \(appVersion) boot at \(date); root:xnu-1699.22.73~1/RELEASE_X86_64"
    }
}

// MARK: - Timing

public enum BootTiming {
    /// Maps a 0-based line index (0..84) to the delay that follows displaying
    /// that line. Faithfully reproduces the JS displayLine() switch-case table
    /// where i_after = index + 1 (JS increments i before the switch):
    ///
    ///   i===2           → 500 ms  (includes synthetic kernel-line injection)
    ///   i===4           → 500 ms
    ///   i>4 && i<25     → 30 ms
    ///   i===25          → 400 ms
    ///   i===42          → 300 ms
    ///   i>42 && i<82    → 25 ms
    ///   i===83          → 25 ms
    ///   i>=83 && i<85   → 300 ms
    ///   default         → pow(1 - i/1000, 3) × 25 ms
    public static func delay(forLine index: Int) -> TimeInterval {
        let i = index + 1
        let total = BootLines.rawLines.count
        switch i {
        case 2:                                         return 0.500
        case 4:                                         return 0.500
        case let v where v > 4 && v < 25:               return 0.030
        case 25:                                        return 0.400
        case 42:                                        return 0.300
        case let v where v > 42 && v < 82:              return 0.025
        case 83:                                        return 0.025
        case let v where v >= total - 2 && v < total:   return 0.300
        default:
            return pow(1.0 - Double(i) / 1000.0, 3) * 0.025
        }
    }
}

// MARK: - Config

public enum BootSequenceConfig {
    /// Returns true when the boot log animation should be skipped.
    public static func shouldSkipLog(nointro: Bool) -> Bool { nointro }
}

// MARK: - Boot stage

/// Tracks which phase of the boot overlay is active.
public enum EdexBootStage: Equatable, Sendable {
    /// Log-scroll stage: fake kernel messages scrolling in.
    case logScroll
    /// Title-flash stage: "eDEX-UI" h1 with theme border animation.
    case titleFlash
    /// Sequence complete; the overlay is removed.
    case complete
}

// MARK: - Raw boot log literal (HTML entities pre-decoded)

// swiftlint:disable:next line_length
private let rawBootLogString = """
Welcome to eDEX-UI!
vm_page_bootstrap: 987323 free pages and 53061 wired pages
kext submap [0xffffff7f8072e000 - 0xffffff8000000000], kernel text [0xffffff8000200000 - 0xffffff800072e000]
zone leak detection enabled
standard timeslicing quantum is 10000 us
mig_table_max_displ = 72
TSC Deadline Timer supported and enabled
eDEXACPICPU: ProcessorId=1 LocalApicId=0 Enabled
eDEXACPICPU: ProcessorId=2 LocalApicId=2 Enabled
eDEXACPICPU: ProcessorId=3 LocalApicId=1 Enabled
eDEXACPICPU: ProcessorId=4 LocalApicId=3 Enabled
eDEXACPICPU: ProcessorId=5 LocalApicId=255 Disabled
eDEXACPICPU: ProcessorId=6 LocalApicId=255 Disabled
eDEXACPICPU: ProcessorId=7 LocalApicId=255 Disabled
eDEXACPICPU: ProcessorId=8 LocalApicId=255 Disabled
calling mpo_policy_init for TMSafetyNet
Security policy loaded: Safety net for Rollback (TMSafetyNet)
calling mpo_policy_init for Sandbox
Security policy loaded: Seatbelt sandbox policy (Sandbox)
calling mpo_policy_init for Quarantine
Security policy loaded: Quarantine policy (Quarantine)
Copyright (c) 1982, 1986, 1989, 1991, 1993, 2015
The Regents of the University of Adelaide. All rights reserved.

HN_ Framework successfully initialized
using 16384 buffer headers and 10240 cluster IO buffer headers
IOAPIC: Version 0x20 Vectors 64:87
ACPI: System State [S0 S3 S4 S5] (S3)
PFM64 0xf10000000, 0xf0000000
[ PCI configuration begin ]
eDEXIntelCPUPowerManagement: Turbo Ratios 0046
eDEXIntelCPUPowerManagement: (built 13:08:12 Jun 18 2011) initialization complete
console relocated to 0xf10000000
PCI configuration changed (bridge=16 device=4 cardbus=0)
[ PCI configuration end, bridges 12 devices 16 ]
mbinit: done [64 MB total pool size, (42/21) split]
Pthread support ABORTS when sync kernel primitives misused
com.eDEX.eDEXFSCompressionTypeZlib kmod start
com.eDEX.eDEXTrololoBootScreen kmod start
com.eDEX.eDEXFSCompressionTypeZlib load succeeded
com.eDEX.eDEXFSCompressionTypeDataless load succeeded

eDEXIntelCPUPowerManagementClient: ready
BTCOEXIST off
wl0: Broadcom BCM4331 802.11 Wireless Controller
5.100.98.75

FireWire (OHCI) Lucent ID 5901 built-in now active, GUID c82a14fffee4a086; max speed s800.
rooting via boot-uuid from /chosen: F5670083-AC74-33D3-8361-AC1977EE4AA2
Waiting on <dict ID="0"><key>IOProviderClass</key><string ID="1">
IOResources</string><key>IOResourceMatch</key><string ID="2">boot-uuid-media</string></dict>
Got boot device = IOService:/eDEXACPIPlatformExpert/PCI0@0/eDEXACPIPCI/SATA@1F,2/
eDEXIntelPchSeriesAHCI/PRT0@0/IOAHCIDevice@0/eDEXAHCIDiskDriver/SarahI@sTheBestDriverIOAHCIBlockStorageDevice/IOBlockStorageDriver/
eDEX SSD TS128C Media/IOGUIDPartitionScheme/Customer@2
BSD root: disk0s2, major 14, minor 2
Kernel is LP64
IOThunderboltSwitch::i2cWriteDWord - status = 0xe00002ed
IOThunderboltSwitch::i2cWriteDWord - status = 0x00000000
IOThunderboltSwitch::i2cWriteDWord - status = 0xe00002ed
IOThunderboltSwitch::i2cWriteDWord - status = 0xe00002ed
eDEXUSBMultitouchDriver::checkStatus - received Status Packet, Payload 2: device was reinitialized
MottIsAScrub::checkstatus - true, Mott::Scrub
[IOBluetoothHCIController::setConfigState] calling registerService
AirPort_Brcm4331: Ethernet address e4:ce:8f:46:18:d2
IO80211Controller::dataLinkLayerAttachComplete():  adding eDEXEFINVRAM notification
IO80211Interface::efiNVRAMPublished():
Created virtif 0xffffff800c32ee00 p2p0
BCM5701Enet: Ethernet address c8:2a:14:57:a4:7a
Previous Shutdown Cause: 3
NTFS driver 3.8 [Flags: R/W].
NTFS volume name BOOTCAMP, version 3.1.
DSMOS has arrived
en1: 802.11d country code set to 'US'.
en1: Supported channels 1 2 3 4 5 6 7 8 9 10 11 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165
m_thebest
MacAuthEvent en1   Auth result for: 00:60:64:1e:e9:e4  MAC AUTH succeeded
MacAuthEvent en1   Auth result for: 00:60:64:1e:e9:e4 Unsolicited  Auth
wlEvent: en1 en1 Link UP
AirPort: Link Up on en1
en1: BSSID changed to 00:60:64:1e:e9:e4
virtual bool IOHIDEventSystemUserClient::initWithTask(task*, void*, UInt32):
Client task not privileged to open IOHIDSystem for mapping memory (e00002c1)


Boot Complete
"""
