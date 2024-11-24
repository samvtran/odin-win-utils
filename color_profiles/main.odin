package color_profiles

import "collections:win_ext"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sys/windows"

Color_Folder :: `C:\Windows\System32\spool\drivers\color`

CONFIG_PATH :: #config(CONFIG, "color_profiles.json")

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

    expected_profiles, config_ok := parse_config(CONFIG_PATH)
    defer delete(expected_profiles)
    if config_ok == false {
        return
    }

    active_displays := get_active_displays()
    defer delete(active_displays)

    for &device in active_displays {
        defer fmt.println()

        print_display_info(&device)

        profile_name := expected_profiles[get_normalized_display_id(device.DeviceID[:])] or_continue

        profile_path := strings.concatenate({ Color_Folder, `\`, profile_name })
        defer delete(profile_path)
        fmt.printfln("\tExpected Profile: %v", profile_path)

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
    }
}
