#!/usr/bin/env python3
"""Generate PulseMonitor Xcode project and source scaffolding helpers."""
import os, uuid, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "PulseMonitor")

def uid():
    return uuid.uuid4().hex[:24].upper()

# Collect all Swift files
swift_files = []
for dirpath, _, files in os.walk(SRC):
    for f in sorted(files):
        if f.endswith(".swift"):
            rel = os.path.relpath(os.path.join(dirpath, f), SRC)
            swift_files.append(rel)

print(f"Found {len(swift_files)} Swift files")
for s in swift_files:
    print(f"  {s}")

# Generate pbxproj
PBX = uid()
PROJ = uid()
TARGET = uid()
SOURCES_PHASE = uid()
RESOURCES_PHASE = uid()
FRAMEWORKS_PHASE = uid()
PRODUCT_REF = uid()
SOURCES_GROUP = uid()
PRODUCTS_GROUP = uid()
MAIN_GROUP = uid()
CONFIG_LIST_PROJ = uid()
CONFIG_LIST_TARGET = uid()
DEBUG_PROJ = uid()
RELEASE_PROJ = uid()
DEBUG_TARGET = uid()
RELEASE_TARGET = uid()
BUNDLE_FILE = uid()

file_refs = {}
build_files = {}
groups = {}

# Create groups by folder
folders = sorted(set(os.path.dirname(s) for s in swift_files))
# Also include empty root
folder_uids = {"": SOURCES_GROUP}
for folder in folders:
    parts = folder.split(os.sep) if folder else []
    path = ""
    for i, part in enumerate(parts):
        parent = path
        path = os.path.join(path, part) if path else part
        if path not in folder_uids:
            folder_uids[path] = uid()

for sf in swift_files:
    file_refs[sf] = uid()
    build_files[sf] = uid()

# Info.plist
info_plist_path = os.path.join(SRC, "Resources", "Info.plist")

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")

# PBXBuildFile
lines.append("/* Begin PBXBuildFile section */")
for sf in swift_files:
    lines.append(f"\t\t{build_files[sf]} /* {os.path.basename(sf)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[sf]} /* {os.path.basename(sf)} */; }};")
lines.append("/* End PBXBuildFile section */")
lines.append("")

# PBXFileReference
lines.append("/* Begin PBXFileReference section */")
lines.append(f"\t\t{PRODUCT_REF} /* PulseMonitor.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PulseMonitor.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for sf in swift_files:
    lines.append(f"\t\t{file_refs[sf]} /* {os.path.basename(sf)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {os.path.basename(sf)}; sourceTree = \"<group>\"; }};")
lines.append("/* End PBXFileReference section */")
lines.append("")

# PBXFrameworksBuildPhase
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")

# PBXGroup
lines.append("/* Begin PBXGroup section */")

# Helper: children of a folder
def children_of(folder):
    result_files = []
    result_subfolders = []
    prefix = folder + os.sep if folder else ""
    for sf in swift_files:
        d = os.path.dirname(sf)
        if d == folder:
            result_files.append(sf)
    for sub in folder_uids:
        if not sub:
            continue
        parent = os.path.dirname(sub)
        if parent == folder or (not folder and os.sep not in sub):
            if parent == folder:
                result_subfolders.append(sub)
    return result_files, result_subfolders

# Root main group
lines.append(f"\t\t{MAIN_GROUP} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{SOURCES_GROUP} /* PulseMonitor */,")
lines.append(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
lines.append("\t\t\t);")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")

lines.append(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{PRODUCT_REF} /* PulseMonitor.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")

for folder, fuid in sorted(folder_uids.items(), key=lambda x: x[0]):
    name = os.path.basename(folder) if folder else "PulseMonitor"
    path = name if folder else "PulseMonitor"
    files, subs = children_of(folder)
    lines.append(f"\t\t{fuid} /* {name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for sub in sorted(subs):
        sn = os.path.basename(sub)
        lines.append(f"\t\t\t\t{folder_uids[sub]} /* {sn} */,")
    for sf in sorted(files):
        lines.append(f"\t\t\t\t{file_refs[sf]} /* {os.path.basename(sf)} */,")
    lines.append("\t\t\t);")
    if folder:
        lines.append(f"\t\t\tpath = {name};")
    else:
        lines.append(f"\t\t\tpath = PulseMonitor;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

lines.append("/* End PBXGroup section */")
lines.append("")

# PBXNativeTarget
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{TARGET} /* PulseMonitor */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_TARGET} /* Build configuration list for PBXNativeTarget \"PulseMonitor\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
lines.append(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
lines.append(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append("\t\t\tname = PulseMonitor;")
lines.append("\t\t\tproductName = PulseMonitor;")
lines.append(f"\t\t\tproductReference = {PRODUCT_REF} /* PulseMonitor.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")

# PBXProject
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{PROJ} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
lines.append("\t\t\t\tLastUpgradeCheck = 1600;")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_PROJ} /* Build configuration list for PBXProject \"PulseMonitor\" */;")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
lines.append("\t\t\tdevelopmentRegion = en;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {MAIN_GROUP};")
lines.append(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{TARGET} /* PulseMonitor */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")

# Resources
lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")
lines.append("")

# Sources
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for sf in swift_files:
    lines.append(f"\t\t\t\t{build_files[sf]} /* {os.path.basename(sf)} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

# XCBuildConfiguration
lines.append("/* Begin XCBuildConfiguration section */")
for cfg_id, name in [(DEBUG_PROJ, "Debug"), (RELEASE_PROJ, "Release")]:
    lines.append(f"\t\t{cfg_id} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    lines.append(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = \"{'dwarf' if name=='Debug' else 'dwarf-with-dsym'}\";")
    if name == "Debug":
        lines.append("\t\t\t\tENABLE_TESTABILITY = YES;")
        lines.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
        lines.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
        lines.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
        lines.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
        lines.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    else:
        lines.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    lines.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    lines.append("\t\t\t\tSDKROOT = macosx;")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

for cfg_id, name in [(DEBUG_TARGET, "Debug"), (RELEASE_TARGET, "Release")]:
    lines.append(f"\t\t{cfg_id} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    lines.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = PulseMonitor/Resources/PulseMonitor.entitlements;")
    lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    lines.append("\t\t\t\tINFOPLIST_FILE = PulseMonitor/Resources/Info.plist;")
    lines.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/../Frameworks\";")
    lines.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    lines.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.pulsemonitor.app;")
    lines.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    lines.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    lines.append("\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;")
    lines.append("\t\t\t\tSWIFT_VERSION = 6.0;")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")

# XCConfigurationList
lines.append("/* Begin XCConfigurationList section */")
lines.append(f"\t\t{CONFIG_LIST_PROJ} /* Build configuration list for PBXProject \"PulseMonitor\" */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{DEBUG_PROJ} /* Debug */,")
lines.append(f"\t\t\t\t{RELEASE_PROJ} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append(f"\t\t{CONFIG_LIST_TARGET} /* Build configuration list for PBXNativeTarget \"PulseMonitor\" */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{DEBUG_TARGET} /* Debug */,")
lines.append(f"\t\t\t\t{RELEASE_TARGET} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f"\trootObject = {PROJ} /* Project object */;")
lines.append("}")

out = os.path.join(ROOT, "PulseMonitor.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"Wrote {out}")
