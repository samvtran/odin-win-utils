package win_ext

foreign import icm32 "system:mscms.lib"
foreign import gdi32 "system:Gdi32.lib"

import "core:sys/windows"

@(default_calling_convention="system")
foreign gdi32 {
    CreateDCW :: proc (pwszDriver: windows.LPCWSTR, pwszDevice: windows.LPCWSTR, pszPort: windows.LPCWSTR, pdm: ^windows.DEVMODEW) -> windows.HDC ---

    GetICMProfileW :: proc (hdc: windows.HDC, pBufSize: windows.LPDWORD, pszFilename: windows.LPWSTR) -> windows.BOOL ---
}

@(default_calling_convention="system")
foreign icm32 {
    WcsDisassociateColorProfileFromDevice :: proc(scope: WCS_PROFILE_MANAGEMENT_SCOPE, pProfileName: windows.PCWSTR, pDeviceName: windows.PCWSTR) -> windows.BOOL ---
    WcsAssociateColorProfileWithDevice :: proc(scope: WCS_PROFILE_MANAGEMENT_SCOPE, pProfileName: windows.PCWSTR, pDeviceName: windows.PCWSTR) -> windows.BOOL ---
}

EDD_GET_DEVICE_INTERFACE_NAME :: 0x00000001

DISPLAY_DEVICE_ACTIVE :: 0x1
DISPLAY_DEVICE_MULTI_DRIVER :: 0x2
DISPLAY_DEVICE_PRIMARY_DEVICE :: 0x4
DISPLAY_DEVICE_MIRRORING_DRIVER :: 0x8
DISPLAY_DEVICE_VGA_COMPATIBLE :: 0x10
DISPLAY_DEVICE_REMOVABLE :: 0x20
DISPLAY_DEVICE_DISCONNECT :: 0x2000000
DISPLAY_DEVICE_REMOTE :: 0x4000000
DISPLAY_DEVICE_MODESPRUNED :: 0x8000000

Display_State_Flags :: enum windows.DWORD {
    DISPLAY_DEVICE_ACTIVE,
    DISPLAY_DEVICE_MULTI_DRIVER,
    DISPLAY_DEVICE_PRIMARY_DEVICE,
    DISPLAY_DEVICE_MIRRORING_DRIVER,
    DISPLAY_DEVICE_VGA_COMPATIBLE,
    DISPLAY_DEVICE_REMOVABLE,
    DISPLAY_DEVICE_DISCONNECT,
    DISPLAY_DEVICE_REMOTE,
    DISPLAY_DEVICE_MODESPRUNED,
}

Display_State_Flags_Set :: bit_set[Display_State_Flags; windows.DWORD]

WCS_PROFILE_MANAGEMENT_SCOPE :: enum windows.DWORD {
    WCS_PROFILE_MANAGEMENT_SCOPE_SYSTEM_WIDE = 0,
    WCS_PROFILE_MANAGEMENT_SCOPE_CURRENT_USER = 1,
}
