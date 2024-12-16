package light_dark

import "core:fmt"
import "core:sys/windows"
import "core:unicode/utf16"
import "core:time"
import "core:mem"
import "core:flags"
import "core:os"

Personalize :: `Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`
Accent :: `Software\Microsoft\Windows\CurrentVersion\Explorer\Accent`

LightMode :: 1
DarkMode :: 0

Mode :: enum {
    Light,
    Dark,
}

Options :: struct {
    mode: Mode `args:"required"`,
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

write_dword :: proc(key: windows.HKEY, name: string, value: u32) -> bool {
    val : u32 = value
    name := to_wide_str(name)
    defer delete(name)
    
    if status := windows.RegSetKeyValueW(key, nil, raw_data(name), windows.REG_DWORD, &val, 4); status != 0 {
        fmt.println("Error setting registry value", status)
        return false
    }
    return true
}

open_registry_key :: proc(path: string, key: ^windows.HKEY) -> (ok: bool) {
    path := to_wide_str(path)
    defer delete(path)
    
    if status := windows.RegOpenKeyW(windows.HKEY_CURRENT_USER, raw_data(path), key); status != 0 {
        fmt.println("Error opening registry key", status)
        return false
    }
    
    return true
}

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
    
    opt: Options
    flags.parse_or_exit(&opt, os.args, .Odin)
    
    personalize_key := windows.HKEY{}

    val : u32 = LightMode if opt.mode == Mode.Light else DarkMode

    if !open_registry_key(Personalize, &personalize_key) {
        panic("Error opening personalize registry key")
    }

    write_dword(personalize_key, "AppsUseLightTheme", val)
    write_dword(personalize_key, "SystemUsesLightTheme", val)
    
    shell := to_wide_str("Shell_TrayWnd")
    defer delete(shell)
    
    hwnd := windows.FindWindowW(raw_data(shell), nil)
    
    if (hwnd == nil) {
        fmt.println("Error finding explorer.exe", windows.GetLastError())
        return
    }
    
    process := to_wide_str("explorer.exe")
    defer delete(process)
    
    windows.PostMessageA(hwnd, windows.WM_USER + 436, 0, 0)

    time.sleep(2 * time.Second)

    windows.ShellExecuteW(nil, nil, raw_data(process), nil, nil, windows.SW_HIDE)
};