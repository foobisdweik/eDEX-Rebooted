# Codex Findings

## HIGH - Hardware MODEL uses hostname

- File: `crates/edex-core/src/sysinfo.rs:482`
- Root cause: `SysinfoService::system()` populated the hardware model from `System::host_name()`, so the UI displayed hostnames such as `FirasMac.local` instead of a model identifier.
- Status: fixed in PR `codex/native-finding-002-hw-model` by resolving `hw.model` with `sysctlbyname`, caching it lazily, and keeping the existing FFI shape.

## MEDIUM - Block-device filesystem type is debug-quoted

- File: `crates/edex-core/src/sysinfo.rs:462`
- Root cause: `block_devices()` formatted `d.file_system().to_string_lossy()` with `Debug`, producing user-facing values with embedded quotes such as `"apfs"`.
- Status: fixed in PR `codex/native-latent-bug-hunt` by emitting the lossy string directly, with `block_devices_fs_type_is_not_debug_quoted` as a regression test.

## MEDIUM - CPU average can trap on finite out-of-range loads

- File: `macos/eDEXNative/Sources/EdexDomainSupport/Cpu/CpuinfoSupport.swift:36`
- Root cause: `EdexCpuinfoFormatter.average(loads:)` filtered non-finite values but still cast the rounded finite mean to `Int` without checking `Int` range.
- Status: fixed in PR `codex/native-latent-bug-hunt` with a strict upper-bound guard and `testAverageRejectsOutOfIntRangeLoads`.

## MEDIUM - TOPLIST formatters can trap or emit `inf%` for huge finite values

- File: `macos/eDEXNative/Sources/EdexDomainSupport/Toplist/ToplistSupport.swift:111`
- Root cause: `percentText(_:)` guarded the input value but not overflow during `value * 10`, and integer formatting used a non-strict upper bound for `Int`.
- Status: fixed in PR `codex/native-latent-bug-hunt` by rejecting non-finite rounded values and using a strict `Int.max` upper bound, with `testPercentTextHandlesOutOfIntRangeWithoutCrashing`.

## MEDIUM - TOPLIST runtime text can trap at the `Double(Int.max)` boundary

- File: `macos/eDEXNative/Sources/EdexDomainSupport/Toplist/ToplistSupport.swift:200`
- Root cause: `runtimeText(started:now:)` accepted `diff <= Double(Int.max)`, but `Double(Int.max)` rounds to an unrepresentable boundary for `Int`.
- Status: fixed in PR `codex/native-latent-bug-hunt` with a strict upper-bound guard and `testRuntimeTextRejectsOutOfIntRangeInterval`.

## LOW - Hardware serial, UUID, and SKU are empty placeholders

- File: `crates/edex-core/src/sysinfo.rs:484`
- Root cause: `SystemInfo` leaves `serial`, `uuid`, and `sku` as empty strings; sourcing stable values would require choosing macOS data sources and privacy behavior.
- Status: deferred - reason: deterministic local fix needs a product decision about which identifiers are acceptable to expose through the existing Hardware panel.

## LOW - Chassis model and type are placeholders

- File: `crates/edex-core/src/sysinfo.rs:493`
- Root cause: `chassis()` still uses hostname for `model` and hard-codes `chassis_type` to `Laptop`, which can be wrong for desktop Macs.
- Status: deferred - reason: safe fix needs a reliable hardware-family mapping or another approved macOS source; changing this without a tested mapping risks replacing one placeholder with another.

## LOW - PTY metadata casts OS PIDs through `i32`

- File: `crates/edex-core/src/pty.rs:217`
- Root cause: PTY metadata bridges `u32` IDs into `pid_t`-shaped APIs with `as i32` casts.
- Status: deferred - reason: macOS `pid_t` is signed and the values come from OS process IDs; a checked helper would be low risk, but no reachable failing case was identified in this audit.

## LOW - Battery numeric casts rely on battery crate ranges

- File: `crates/edex-core/src/sysinfo.rs:1243`
- Root cause: battery percentage and time remaining use direct numeric casts from runtime battery values.
- Status: deferred - reason: values are constrained by the battery crate and hardware source, and this branch does not add a mockable battery seam for a deterministic regression test.
