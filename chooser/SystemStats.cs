// CPU and memory readings for the bar.
//
// Both calls are plain documented Win32, chosen over anything richer because
// the bar samples them for the whole session on machines with little to
// spare: each reading here is one syscall and no allocation.

using System;
using System.Runtime.InteropServices;

namespace Winmarchy.Chooser;

public static class SystemStats
{
    // learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemtimes
    // Each out parameter is a FILETIME, which is a 64 bit value carried as
    // two 32 bit halves, so a ulong is layout compatible with it.
    // The documented catch: lpKernelTime "includes the amount of time the
    // system has been idle", so busy time is (kernel + user) minus idle.
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out ulong lpIdleTime, out ulong lpKernelTime, out ulong lpUserTime);

    // learn.microsoft.com/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex
    // dwLength must be set to the size of the structure before the call.
    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatusEx
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);

    private static ulong _lastIdle;
    private static ulong _lastKernel;
    private static ulong _lastUser;
    private static int _lastCpuPercent;

    // Percent busy since the previous call. The first call has no previous
    // sample to compare against and reports 0.
    public static int CpuPercent()
    {
        try
        {
            if (!GetSystemTimes(out var idle, out var kernel, out var user))
            {
                return _lastCpuPercent;
            }
            var idleDelta = idle - _lastIdle;
            var totalDelta = (kernel - _lastKernel) + (user - _lastUser);
            var hadSample = _lastKernel != 0;
            _lastIdle = idle;
            _lastKernel = kernel;
            _lastUser = user;
            if (!hadSample || totalDelta == 0)
            {
                return _lastCpuPercent;
            }
            var busy = (double)(totalDelta - idleDelta) / totalDelta * 100.0;
            if (busy < 0) { busy = 0; }
            if (busy > 100) { busy = 100; }
            _lastCpuPercent = (int)Math.Round(busy);
            return _lastCpuPercent;
        }
        catch
        {
            return _lastCpuPercent;
        }
    }

    // Percent of physical memory in use, the same number the yasb bar showed
    // as virtual_mem_percent.
    public static int MemoryPercent()
    {
        try
        {
            var status = new MemoryStatusEx();
            status.dwLength = (uint)Marshal.SizeOf<MemoryStatusEx>();
            if (!GlobalMemoryStatusEx(ref status))
            {
                return 0;
            }
            return (int)status.dwMemoryLoad;
        }
        catch
        {
            return 0;
        }
    }
}
