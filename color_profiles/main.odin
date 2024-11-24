package color_profiles

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sys/windows"
import "core:unicode/utf16"
import "collections:win_ext"

Color_Folder :: `C:\Windows\System32\spool\drivers\color`

MonitorData :: struct {
    hmon: windows.HMONITOR,
    deviceName: [32]u16,
}

to_str :: proc(char: []windows.WCHAR) -> string {
    str, err := windows.wstring_to_utf8(raw_data(char), len(char), context.allocator)
    return err == nil ? str : "(none)"
}

to_wide_str :: proc(str: string) -> []u16 {
    buf := make([]u16, len(str))
    utf16.encode_string(buf, str)
    return buf
}

print_str :: proc(desc: string, chars: []windows.WCHAR) {
    str := to_str(chars)
    defer delete(str)
    fmt.printfln("%s: %v", desc, str)
}

get_monitor :: proc(data: ^MonitorData) -> bool {
    params : windows.LPARAM
    windows.EnumDisplayMonitors(nil, nil, handle, int(uintptr(data)))

    handle :: proc "system" (hMonitor: windows.HMONITOR, hDC: windows.HDC, lpRect: windows.LPRECT, param: windows.LPARAM) -> windows.BOOL {
        context = runtime.default_context()
        mi := new(windows.MONITORINFOEXW)
        defer free(mi)
        mi.cbSize = size_of(mi^)

        if windows.GetMonitorInfoW(hMonitor, mi) == false {
            fmt.printfln("No monitor: %v", windows.GetLastError())
            return true
        }

        data : ^MonitorData = transmute(^MonitorData)uintptr(param)

        if to_str(mi.szDevice[:]) == to_str(data.deviceName[:]) {
            data.hmon = hMonitor
            return false
        }

        return true
    }

    return data.hmon != nil
}

get_active_profile :: proc(hdc: windows.HDC) -> (profile: string, ok: bool) {
    buf_size := new(windows.DWORD)
    defer free(buf_size)

    // https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-geticmprofilew
    // Docs say:
    // If this function succeeds, the return value is TRUE. It also returns TRUE if the lpszFilename parameter is NULL and the size required for the buffer is copied into lpcbName.
    // ^^ doesn't appear to be true when we're passing null for the filename so oh well
    win_ext.GetICMProfileW(hdc, buf_size, nil)

    (buf_size^ > 0) or_return

    active_profile := make([]u16, buf_size^)
    defer delete(active_profile)

    win_ext.GetICMProfileW(hdc, buf_size, raw_data(active_profile))

    return to_str(active_profile), true
}

get_normalized_display_id :: proc(id: []u16) -> string {
    id := to_str(id[:])
    split_id := strings.split(id, `\`)[0:2]
    normalized_id := strings.join(split_id, `\`)
    defer {
        delete(id)
        delete(split_id)
        delete(normalized_id)
    }

    return normalized_id[:]
}

// This helper ensures color profiles are set correctly for the displays set under `expected_profiles`.
// This works around issues where Windows may decide to reset the color profile upon unlock, wake, boot, or sneezing nearby.
main :: proc() {
    when ODIN_DEBUG {
        track : mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        defer mem.tracking_allocator_destroy(&track)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            for _, leak in track.allocation_map {
                fmt.printf("%v leaked %m\n", leak.location, leak.size)
            }
            for bad_free in track.bad_free_array {
                fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
            }
        }
    }

    // A map assocating the first couple parts of the display id to the ICC file names that should be set
    expected_profiles := map[string]string {
        "MONITOR\\DEL42AC" = "DEL42AC_24-07-06.icc",
        "MONITOR\\DEL40C2" = "DELL_UP3216Q_24-07-06.icc",
    }
    defer delete(expected_profiles)

    device := new(windows.DISPLAY_DEVICEW)
    device.cb = size_of(device^)
    defer free(device)

    for dev_num : u32 = 0;; dev_num += 1 {
        defer fmt.println()

        // Find a display at the display offset
        (windows.EnumDisplayDevicesW(nil, dev_num, device, win_ext.EDD_GET_DEVICE_INTERFACE_NAME) == true) or_break

        device_name : [32]u16 = device.DeviceName

        d := raw_data(&device.DeviceName)

        device := new(windows.DISPLAY_DEVICEW)
        device.cb = size_of(device^)
        defer free(device)

        // Try to enumerate monitor info for the given display
        (windows.EnumDisplayDevicesW(d, 0, device, 0) == true) or_continue

        // Check that the monitor is actually active
        bitset := transmute(win_ext.Display_State_Flags_Set)device.StateFlags
        (.DISPLAY_DEVICE_ACTIVE in bitset) or_continue

        fmt.println("Active display")
        //        print_str("\tDevice key", device.DeviceKey[:])
        //        print_str("\tDevice string", device.DeviceString[:])
        //        print_str("\tDevice name", device.DeviceName[:])
        print_str("\tDevice id", device.DeviceID[:])

        monitor_data := MonitorData{ deviceName = device_name }
        get_monitor(&monitor_data) or_continue

        hdc := win_ext.CreateDCW(nil, raw_data(&device_name), nil, nil)
        (hdc != nil) or_continue
        defer windows.DeleteDC(hdc)

        active_profile, ap_ok := get_active_profile(hdc)
        (ap_ok == true) or_continue

        defer delete(active_profile)

        fmt.printfln("\tActive Profile: %s", active_profile)

        id := get_normalized_display_id(device.DeviceID[:])

        (id in expected_profiles) or_continue

        profile_path := strings.concatenate({ Color_Folder, `\`, expected_profiles[id] })
        defer delete(profile_path)

        fmt.printfln("\tExpected Profile: %v", profile_path)

        if (strings.contains(active_profile, expected_profiles[id]) == false) {
            fmt.printfln("\t🔴 Need to set correct color profile")
            wide_path := to_wide_str(profile_path)
            defer delete(wide_path)

            // Disassociate the current profile so we can set it as the default again
            win_ext.WcsDisassociateColorProfileFromDevice(.WCS_PROFILE_MANAGEMENT_SCOPE_CURRENT_USER, raw_data(wide_path), raw_data(&device.DeviceKey))

            // Reassociate
            if win_ext.WcsAssociateColorProfileWithDevice(.WCS_PROFILE_MANAGEMENT_SCOPE_CURRENT_USER, raw_data(wide_path), raw_data(&device.DeviceKey)) == true {
                fmt.println("\t✅ Set color profile successfully")
            } else {
                fmt.printfln("\t❌ Problem setting profile: %v", windows.GetLastError())
            }
        } else {
            fmt.println("\t🌈 Correct color profile loaded")
        }
    }
}
