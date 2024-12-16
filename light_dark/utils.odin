package light_dark

import "core:fmt"
import "core:sys/windows"
import "core:time"
import "core:os/os2"

exec :: proc(command: []string) -> (err: os2.Error) {
    r, w := os2.pipe() or_return
    defer os2.close(r)

    p : os2.Process
    {
        defer os2.close(w)

        p = os2.process_start({
            command = command,
            stdout = w,
        }) or_return
    }

    output := os2.read_entire_file(r, context.temp_allocator) or_return
    _ = os2.process_wait(p) or_return
    fmt.print(output)
    return
}

create_process :: proc(process: string) -> bool {
    process_info := windows.PROCESS_INFORMATION{ }
    startup := windows.STARTUPINFOW{ }
    startup.cb = size_of(startup)

    process_name := to_wide_str(process)
    defer delete(process_name)

    return windows.CreateProcessW(raw_data(process_name), nil, nil, nil, false, 0, nil, nil, &startup, &process_info) == windows.TRUE
}

stop_explorer :: proc() {
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
}

wait_for_stop :: proc(process: string) {
    wide_process := to_wide_str(process)
    defer delete(wide_process)

    start := time.now()

    hwnd := windows.FindWindowW(raw_data(wide_process), nil)
    if hwnd == nil {
        fmt.println("Process already stopped", process)
        return
    }

    for {
        if windows.IsWindow(hwnd) == windows.FALSE {
            fmt.println("Process window stopped", process)
            break
        }

        elapsed := time.diff(start, time.now())

        if time.duration_seconds(elapsed) > 5 {
            fmt.println("Timeout waiting for process to stop")
            break
        }

        fmt.println("Waiting for process to stop", process)
        time.sleep(100 * time.Millisecond)
    }
}