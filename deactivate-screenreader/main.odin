package deactivatescreenreader

import win "core:sys/windows"

main :: proc() {
    win.SystemParametersInfoW(win.SPI_SETSCREENREADER, 0, nil, win.SPIF_SENDCHANGE)
}