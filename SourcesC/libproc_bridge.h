#ifndef PULSEMONITOR_BRIDGE_H
#define PULSEMONITOR_BRIDGE_H

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>

/// Code signing status for a process.
///
/// `csops` lives in libSystem and is used by `codesign(1)`, but its header
/// (`sys/codesign.h`) ships only with the kernel sources, so the entry point and
/// the few flags needed here are declared directly. Values match xnu's
/// `osfmk/kern/cs_blobs.h`.
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#define PM_CS_OPS_STATUS 0
#define PM_CS_VALID 0x00000001
#define PM_CS_HARD 0x00000100
#define PM_CS_PLATFORM_BINARY 0x04000000

/// `P_TRANSLATED` from `sys/proc.h`, marking a process running under Rosetta.
#define PM_P_TRANSLATED 0x00020000

#endif /* PULSEMONITOR_BRIDGE_H */
