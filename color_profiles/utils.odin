package color_profiles

import "collections:win_ext"
import "core:fmt"
import "core:strings"
import "core:sys/windows"
import "core:unicode/utf16"
import "core:encoding/json"
import "core:os"

ExtendedDisplayInfo :: struct {
    using display: windows.DISPLAY_DEVICEW,
    InterfaceName: [32]u16,
}

MonitorConfig :: struct {
    monitors: map[string]string,
}

parse_config :: proc(path: string) -> (monitors: map[string]string, ok: bool) {
    data, load_ok := os.read_entire_file_from_filename(path)
    if !load_ok {
        fmt.eprintfln("Could not read config file at %s", path)
        return
    }
    defer delete(data)

    config := MonitorConfig{}

    err := json.unmarshal(data, &config, .JSON5, context.temp_allocator)

    if err != nil {
        fmt.eprintfln("Failed to parse the json file: %s", err)
        return
    }

    return config.monitors, true
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

get_active_displays :: proc() -> [dynamic]ExtendedDisplayInfo {
    displays := make([dynamic]ExtendedDisplayInfo, 0)

    // Find a display at each display offset
    for dev_num : u32 = 0;; dev_num += 1 {
        interface_info := windows.DISPLAY_DEVICEW{}
        interface_info.cb = size_of(interface_info)
        (windows.EnumDisplayDevicesW(nil, dev_num, &interface_info, win_ext.EDD_GET_DEVICE_INTERFACE_NAME) == true) or_break

        // Needed when creating a hardware context
        interface_name := interface_info.DeviceName
        // Needed to query infor an individual monitor
        device_name := raw_data(&interface_info.DeviceName)

        device := ExtendedDisplayInfo{}
        device.cb = size_of(device)

        // Try to enumerate monitor info for the given display or continue to the next one
        (windows.EnumDisplayDevicesW(device_name, 0, &device, 0) == true) or_continue

        device.InterfaceName = interface_name

        // Check that the monitor is actually active
        bitset := transmute(win_ext.Display_State_Flags_Set)device.StateFlags
        (.DISPLAY_DEVICE_ACTIVE in bitset) or_continue

        append(&displays, device)
    }

    return displays
}

print_display_info :: proc(device: ^ExtendedDisplayInfo) {
    fmt.printfln("Active display - %s", device.InterfaceName)
    fmt.printfln("\tDevice key: %s", device.DeviceKey)
    fmt.printfln("\tDevice string: %s", device.DeviceString)
    fmt.printfln("\tDevice name: %s", device.DeviceName)
    fmt.printfln("\tDevice id: %s", device.DeviceID)

    hdc := get_display_context(device.InterfaceName[:])
    defer windows.DeleteDC(hdc)

    active_profile, ok := get_active_profile(hdc)
    defer delete(active_profile)

    if ok {
        fmt.println("\tActive Profile:", active_profile)
    }
}

get_display_context :: proc(interface_name: []u16) -> windows.HDC {
    return win_ext.CreateDCW(nil, raw_data(interface_name), nil, nil)
}

get_active_profile :: proc(hdc: windows.HDC) -> (profile: string, ok: bool) {
    buf_size := windows.DWORD{}

    // https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-geticmprofilew
    // Docs say:
    // If this function succeeds, the return value is TRUE. It also returns TRUE if the lpszFilename parameter is NULL and the size required for the buffer is copied into lpcbName.
    // ^^ doesn't appear to be true when we're passing null for the filename so oh well
    win_ext.GetICMProfileW(hdc, &buf_size, nil)

    (buf_size > 0) or_return

    active_profile := make([]u16, buf_size)
    defer delete(active_profile)

    win_ext.GetICMProfileW(hdc, &buf_size, raw_data(active_profile))

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
