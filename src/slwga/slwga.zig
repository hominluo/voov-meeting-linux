// Minimal Software Licensing API stub for Wine.
//
// wemeet_platform.dll imports SLIsGenuineLocal() from SLWGA.dll. Windows
// ships that DLL in System32; Wine does not implement it, so the import fails
// and the whole VooV process tree dies at load time. This stub reports that
// Windows is genuine and is copied next to the application's DLLs.
//
// Build:
//   zig cc -target x86_64-windows-gnu slwga.zig -o SLWGA.dll
// (The checked-in SLWGA.dll is the output of this command with Zig 0.16.0.)

const std = @import("std");

// HRESULT SLIsGenuineLocal(const GUID *pGenuineGuid, SL_GENUINE_STATE
// *pGenuineState, OSVERSIONINFOEX *pOsVersion)
export fn SLIsGenuineLocal(
    genuine_guid: ?*const anyopaque,
    genuine_state: *u32,
    os_version: ?*anyopaque,
) callconv(.winapi) i32 {
    _ = genuine_guid;
    _ = os_version;
    genuine_state.* = 0; // SL_GEN_STATE_IS_GENUINE
    return 0; // S_OK
}
