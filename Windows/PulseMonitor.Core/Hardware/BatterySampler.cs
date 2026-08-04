using System.Runtime.InteropServices;

namespace PulseMonitor.Core.Hardware;

public static class BatterySampler
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte Reserved1;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);

    public static (double? percent, bool? charging) Sample()
    {
        if (!GetSystemPowerStatus(out var sps))
            return (null, null);
        if (sps.BatteryFlag == 128 || sps.BatteryLifePercent == 255)
            return (null, null); // no battery
        var charging = sps.ACLineStatus == 1;
        return (sps.BatteryLifePercent, charging);
    }
}
