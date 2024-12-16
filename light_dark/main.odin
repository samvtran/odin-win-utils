package light_dark

import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:sys/windows"

foreign import user32 "system:User32.lib"

@(default_calling_convention="system")
foreign user32 {
    SendNotifyMessageW :: proc(hwnd: windows.HWND, msg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) -> windows.BOOL ---
}

Personalize :: `Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`
Accent :: `Software\Microsoft\Windows\CurrentVersion\Explorer\Accent`

AppLightModeKey :: `AppsUseLightTheme`
SystemLightModeKey :: `SystemUsesLightTheme`

LightMode :: 1
DarkMode :: 0

Mode :: enum {
    Light,
    Dark,
}

Options :: struct {
    mode: Mode `args:"required"`,
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

    personalize_key := windows.HKEY{ }

    val : u32 = LightMode if opt.mode == Mode.Light else DarkMode

    if !open_registry_key(Personalize, &personalize_key) {
        panic("Error opening personalize registry key")
    }

    app_mode_matches := get_mode(personalize_key, AppLightModeKey) == val
    system_mode_matches := get_mode(personalize_key, SystemLightModeKey) == val

    if app_mode_matches && system_mode_matches {
        fmt.println("Mode already set")
        return
    }

    write_dword(personalize_key, AppLightModeKey, val)
    write_dword(personalize_key, SystemLightModeKey, val)

    {
        shell := to_wide_str("Shell_TrayWnd")
        defer delete(shell)
        hwnd := windows.FindWindowW(raw_data(shell), nil)

        if hwnd == nil {
            fmt.println("Error finding explorer.exe", windows.GetLastError())
            return
        }

        // Automatically apply system dark mode for the shell and other apps listening for this message
        param := to_wide_str("ImmersiveColorSet")
        defer delete(param)

        broadcast := windows.HWND(uintptr(0xffff))
        wparam := windows.WPARAM{ }
        lparam := windows.LPARAM(uintptr(raw_data(param)))

        SendNotifyMessageW(broadcast, windows.WM_SETTINGCHANGE, wparam, lparam)
    }
};