using System.IO;
using System.Management;

namespace PulseMonitor.Core.Hardware;

public sealed class VolumeInfo
{
    public required string Name { get; init; }
    public required string FileSystem { get; init; }
    public ulong TotalBytes { get; init; }
    public ulong FreeBytes { get; init; }
    public bool BitLockerHint { get; init; }
}

public sealed class DiskInfo
{
    public required string Model { get; init; }
    public required string InterfaceType { get; init; }
    public ulong? SizeBytes { get; init; }
    public string? MediaType { get; init; }
    public string SmartNote { get; init; } =
        "NVMe SMART / wear requires IOCTL_STORAGE_QUERY_PROPERTY or vendor tools; not fabricated.";
}

public static class StorageAnalyzer
{
    public static IReadOnlyList<VolumeInfo> Volumes()
    {
        var list = new List<VolumeInfo>();
        foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady))
        {
            try
            {
                list.Add(new VolumeInfo
                {
                    Name = drive.Name,
                    FileSystem = drive.DriveFormat,
                    TotalBytes = (ulong)drive.TotalSize,
                    FreeBytes = (ulong)drive.AvailableFreeSpace,
                    BitLockerHint = drive.DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase)
                        && IsLikelyBitLocker(drive.Name)
                });
            }
            catch { }
        }
        return list;
    }

    public static IReadOnlyList<DiskInfo> PhysicalDisks()
    {
        var list = new List<DiskInfo>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_DiskDrive"))
            {
                using (obj)
                {
                    list.Add(new DiskInfo
                    {
                        Model = WmiHelper.StringProp(obj, "Model") ?? "Disk",
                        InterfaceType = WmiHelper.StringProp(obj, "InterfaceType") ?? "Unknown",
                        SizeBytes = WmiHelper.ULongProp(obj, "Size"),
                        MediaType = WmiHelper.StringProp(obj, "MediaType")
                    });
                }
            }
        }
        catch { }
        return list;
    }

    private static bool IsLikelyBitLocker(string root)
    {
        // Honest hint only: presence of System Volume Information + EncryptableVolume WMI is heavier;
        // we mark NTFS volumes when Win32_EncryptableVolume reports protection (best-effort).
        try
        {
            var letter = root.TrimEnd('\\');
            using var searcher = new ManagementObjectSearcher(
                @"root\CIMV2\Security\MicrosoftVolumeEncryption",
                "SELECT * FROM Win32_EncryptableVolume");
            foreach (ManagementObject obj in searcher.Get())
            {
                using (obj)
                {
                    var drive = WmiHelper.StringProp(obj, "DriveLetter");
                    if (!string.Equals(drive, letter, StringComparison.OrdinalIgnoreCase))
                        continue;
                    var status = WmiHelper.DoubleProp(obj, "ProtectionStatus");
                    return status is > 0;
                }
            }
        }
        catch { }
        return false;
    }
}
