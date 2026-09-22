using System;
using System.Runtime.InteropServices;

// All P/Invoke + struct marshaling happens INSIDE this compiled type, so
// PowerShell only ever calls simple static methods with primitive args -
// avoids known rough edges with by-ref structs marshaled across the
// PowerShell dynamic-invocation boundary.

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields;
    public int dmPositionX, dmPositionY;
    public int dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
}

public static class VDisplay {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    const uint EDD_GET_DEVICE_INTERFACE_NAME = 0x00000001;
    const int ENUM_CURRENT_SETTINGS = -1;
    const int DM_PELSWIDTH = 0x80000, DM_PELSHEIGHT = 0x100000, DM_DISPLAYFREQUENCY = 0x400000;
    const uint CDS_UPDATEREGISTRY = 0x01, CDS_NORESET = 0x10000000;

    public static string ListAdapters() {
        var sb = new System.Text.StringBuilder();
        for (uint i = 0; i < 8; i++) {
            var dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, i, ref dd, 0)) {
                int err = Marshal.GetLastWin32Error();
                sb.AppendLine("adapter " + i + ": EnumDisplayDevices failed, Win32 error " + err);
                break;
            }
            bool active = (dd.StateFlags & 1) != 0;
            var dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(dm);
            bool got = EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, ref dm);
            sb.AppendLine("adapter " + i + ": " + dd.DeviceName + " | " + dd.DeviceString);
            sb.AppendLine("  active=" + active + "  DeviceID=" + dd.DeviceID);
            if (got) sb.AppendLine("  current=" + dm.dmPelsWidth + "x" + dm.dmPelsHeight + "@" + dm.dmDisplayFrequency + "Hz");
        }
        return sb.ToString();
    }

    // Returns the device interface path (what Sunshine's output_name needs)
    // for the display adapter whose DeviceString contains nameContains.
    public static string GetDeviceInterfacePath(string nameContains) {
        for (uint i = 0; i < 12; i++) {
            var dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
            bool active = (dd.StateFlags & 1) != 0;
            if (active && dd.DeviceString != null && dd.DeviceString.IndexOf(nameContains, StringComparison.OrdinalIgnoreCase) >= 0) {
                // enumerate the monitor under this adapter with the interface-name flag
                var mon = new DISPLAY_DEVICE();
                mon.cb = Marshal.SizeOf(mon);
                if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, EDD_GET_DEVICE_INTERFACE_NAME)) {
                    return mon.DeviceID; // this is the \\?\DISPLAY#...#{GUID} path
                }
                return "adapter found but no monitor interface: " + dd.DeviceName;
            }
        }
        return "NOT FOUND";
    }

    public static string SetResolution(string nameContains, int width, int height, int hz) {
        for (uint i = 0; i < 12; i++) {
            var dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
            bool active = (dd.StateFlags & 1) != 0;
            if (active && dd.DeviceString != null && dd.DeviceString.IndexOf(nameContains, StringComparison.OrdinalIgnoreCase) >= 0) {
                var dm = new DEVMODE();
                dm.dmSize = (short)Marshal.SizeOf(dm);
                dm.dmPelsWidth = width;
                dm.dmPelsHeight = height;
                dm.dmDisplayFrequency = hz;
                dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
                // Apply directly (no CDS_NORESET) - single-display change,
                // no need to stage+commit across multiple adapters.
                int result = ChangeDisplaySettingsEx(dd.DeviceName, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
                string msg = "ChangeDisplaySettingsEx on " + dd.DeviceName + " returned " + result + " (0=success)";
                // Re-read actual current mode to confirm, don't just trust the return code.
                var check = new DEVMODE();
                check.dmSize = (short)Marshal.SizeOf(check);
                if (EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, ref check)) {
                    msg += " | now reads: " + check.dmPelsWidth + "x" + check.dmPelsHeight + "@" + check.dmDisplayFrequency + "Hz";
                }
                return msg;
            }
        }
        return "adapter not found (active): " + nameContains;
    }
}
