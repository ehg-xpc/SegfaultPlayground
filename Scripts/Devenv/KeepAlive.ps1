#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Prevents RDP idle disconnection and Azure Dev Box auto-hibernate.

.DESCRIPTION
    Simulates minimal user activity by injecting a zero-delta mouse move via
    SendInput. The cursor does not move and no window receives focus events,
    but Windows updates GetLastInputInfo, which keeps the session "active"
    from the perspective of:
      - RDP idle-timeout policies (Terminal Services MaxIdleTime)
      - Azure Dev Box auto-stop / auto-hibernate schedules
      - Windows lock-screen timeout

    Designed to run as a scheduled task under the interactive session.
    Exits silently if no interactive desktop is available.
#>

$ErrorActionPreference = 'Stop'

# SendInput goes through the system input stream rather than a specific
# window's message queue, so it does not steal focus the way SendKeys does.
# A MOUSEEVENTF_MOVE with dx=dy=0 still updates GetLastInputInfo but produces
# no visible cursor movement.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KeepAliveInput {
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int    dx;
        public int    dy;
        public uint   mouseData;
        public uint   dwFlags;
        public uint   time;
        public IntPtr dwExtraInfo;
    }

    // Native INPUT is a tagged union; we only use the MOUSEINPUT variant, which
    // is the largest member, so its size matches sizeof(INPUT) on both x86 and
    // x64. The compiler will insert the 4-byte alignment gap before `mi` on x64.
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT {
        public uint        type;
        public MOUSEINPUT  mi;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const uint INPUT_MOUSE        = 0;
    private const uint MOUSEEVENTF_MOVE   = 0x0001;

    public static void Nudge() {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type     = INPUT_MOUSE;
        inputs[0].mi.dx    = 0;
        inputs[0].mi.dy    = 0;
        inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE;
        SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@

[KeepAliveInput]::Nudge()
