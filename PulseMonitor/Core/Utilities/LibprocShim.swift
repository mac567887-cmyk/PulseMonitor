import Darwin

/// Swift bindings for libproc symbols used by ProcessService.
public enum Libproc {
    public static let PROC_PIDPATHINFO_MAXSIZE: Int32 = 4 * PATH_MAX

    @discardableResult
    public static func listAllPIDs(_ buffer: UnsafeMutablePointer<pid_t>?, _ buffersize: Int32) -> Int32 {
        proc_listallpids(buffer, buffersize)
    }

    @discardableResult
    public static func name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32 {
        proc_name(pid, buffer, buffersize)
    }

    @discardableResult
    public static func pidPath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32 {
        proc_pidpath(pid, buffer, buffersize)
    }

    @discardableResult
    public static func pidInfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32 {
        proc_pidinfo(pid, flavor, arg, buffer, buffersize)
    }
}

// libproc constants commonly missing from the Darwin module overlay.
public let PROC_PIDTASKINFO: Int32 = 4
public let PROC_PIDT_SHORTBSDINFO: Int32 = 13
