using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class TVMode {
    // ---- DPI awareness: must be set before any geometry query below, or
    // coordinates come back virtualized/scaled instead of real pixels. ----
    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);
    public static void EnsureDpiAware() {
        SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFOEX {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    public class MonitorInfo {
        public string DeviceName;
        public int Left, Top, Right, Bottom;
        public bool Primary;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    private delegate bool MonitorEnumDelegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumDelegate lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    private const uint MONITORINFOF_PRIMARY = 0x1;

    public static List<MonitorInfo> GetMonitors() {
        EnsureDpiAware();
        var results = new List<MonitorInfo>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate (IntPtr hMonitor, IntPtr hdc, ref RECT rect, IntPtr data) {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (GetMonitorInfo(hMonitor, ref mi)) {
                results.Add(new MonitorInfo {
                    DeviceName = mi.szDevice,
                    Left = mi.rcMonitor.Left,
                    Top = mi.rcMonitor.Top,
                    Right = mi.rcMonitor.Right,
                    Bottom = mi.rcMonitor.Bottom,
                    Primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0
                });
            }
            return true;
        }, IntPtr.Zero);
        return results;
    }

    // ---- Window enumeration / manipulation ----
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

    private const uint GA_ROOT = 2;
    private const int SW_RESTORE = 9;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_SHOWWINDOW = 0x0040;

    public class WinInfo {
        public IntPtr Handle;
        public uint ProcessId;
        public string Title;
        public int Left, Top, Right, Bottom;
    }

    // Real top-level, visible, titled windows belonging to the given process
    // ids. Excludes the many invisible helper/tooltip windows a modern
    // browser process also owns.
    public static List<WinInfo> GetTopLevelWindowsForProcesses(HashSet<uint> pids) {
        EnsureDpiAware();
        var results = new List<WinInfo>();
        EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
            if (!IsWindowVisible(hWnd)) return true;
            if (GetAncestor(hWnd, GA_ROOT) != hWnd) return true; // only true top-level
            int len = GetWindowTextLength(hWnd);
            if (len == 0) return true;
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (!pids.Contains(pid)) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            RECT r;
            GetWindowRect(hWnd, out r);
            results.Add(new WinInfo { Handle = hWnd, ProcessId = pid, Title = sb.ToString(), Left = r.Left, Top = r.Top, Right = r.Right, Bottom = r.Bottom });
            return true;
        }, IntPtr.Zero);
        return results;
    }

    public static WinInfo GetForegroundWindowInfo() {
        EnsureDpiAware();
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return null;
        return GetWindowInfo(h);
    }

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    // Info for an arbitrary window handle, not just the foreground one -
    // used to check a specific target window's CURRENT state (position,
    // minimized or not) before deciding whether it needs moving/
    // fullscreening again, so an already-correct window is left alone
    // instead of having F11 (a toggle) blindly re-sent to it.
    public static WinInfo GetWindowInfo(IntPtr hWnd) {
        EnsureDpiAware();
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        int len = GetWindowTextLength(hWnd);
        var sb = new StringBuilder(len + 1);
        GetWindowText(hWnd, sb, sb.Capacity);
        RECT r;
        GetWindowRect(hWnd, out r);
        return new WinInfo { Handle = hWnd, ProcessId = pid, Title = sb.ToString(), Left = r.Left, Top = r.Top, Right = r.Right, Bottom = r.Bottom };
    }

    public static bool IsMinimized(IntPtr hWnd) {
        return IsIconic(hWnd);
    }

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll")]
    private static extern uint GetCurrentThreadId();

    // A background/hidden process's SetForegroundWindow calls get silently
    // ignored by Windows once its "recent input event" allowance from
    // being double-clicked has expired - confirmed live: a real
    // double-click run left "Claude" itself as the foreground window
    // afterward, well after enough time (infra check + Magpie startup)
    // had passed for that allowance to lapse, and the target window ended
    // up minimized because keystrokes meant for it (F11, Magpie's hotkey)
    // went to whatever WAS actually focused instead.
    //
    // The standard, reliable fix: temporarily attach this thread's input
    // queue to the current foreground window's thread, which makes
    // Windows treat this thread as if it were already focused, letting
    // SetForegroundWindow succeed for real instead of being ignored.
    private static void ForceForeground(IntPtr hWnd) {
        IntPtr foreground = GetForegroundWindow();
        uint foregroundPid;
        uint foregroundThread = GetWindowThreadProcessId(foreground, out foregroundPid);
        uint currentThread = GetCurrentThreadId();
        bool attached = foregroundThread != 0 && foregroundThread != currentThread &&
            AttachThreadInput(currentThread, foregroundThread, true);
        try {
            ShowWindow(hWnd, SW_RESTORE);
            SetForegroundWindow(hWnd);
        } finally {
            if (attached) AttachThreadInput(currentThread, foregroundThread, false);
        }
    }

    public static void MoveWindowTo(IntPtr hWnd, int x, int y, int width, int height) {
        EnsureDpiAware();
        ForceForeground(hWnd);
        SetWindowPos(hWnd, IntPtr.Zero, x, y, width, height, SWP_NOZORDER | SWP_SHOWWINDOW);
    }

    public static void Focus(IntPtr hWnd) {
        ForceForeground(hWnd);
    }

    // ---- Raw key-combo sending. Magpie's Win+Shift+A hotkey can't be
    // produced by System.Windows.Forms.SendKeys (no Windows-key support),
    // so every hotkey-style combo here goes through keybd_event instead;
    // SendKeys is only used elsewhere for literal text typing. ----
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public const byte VK_LWIN = 0x5B;
    public const byte VK_SHIFT = 0x10;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_F11 = 0x7A;
    public const byte VK_T = 0x54;
    public const byte VK_A = 0x41;

    public static void SendKeyCombo(byte[] vks) {
        foreach (var vk in vks) keybd_event(vk, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        for (int i = vks.Length - 1; i >= 0; i--) keybd_event(vks[i], 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
