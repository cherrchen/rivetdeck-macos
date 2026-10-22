#!/usr/bin/env python3
"""Regenerate the small dependency-free Xcode app project after adding Swift files."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
files = sorted(str(p.relative_to(root)) for p in (root/'Sources').rglob('*.swift') if 'DSHProbe' not in p.parts)
objects = []
def obj(name, content):
    objects.append(f'{uid(name)} = {{ {content} }};')
for path in files:
    obj(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {uid(path)};')
obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = RivetdeckNative.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = ({uid("app")},); name = Products; sourceTree = "<group>";')
obj('main', f'isa = PBXGroup; children = ({",".join(uid(p) for p in files)},{uid("products")},); sourceTree = "<group>";')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(uid("build:"+p) for p in files)},); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
base = '''SWIFT_VERSION = 6.0; ENABLE_DEBUG_DYLIB = NO; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; CLANG_ENABLE_MODULES = YES; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; CODE_SIGN_STYLE = Automatic; PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = dev.rivetdeck.native; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Rivetdeck Native"; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools"; INFOPLIST_KEY_NSSupportsAutomaticTermination = NO; INFOPLIST_KEY_NSSupportsSuddenTermination = NO; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; COMBINE_HIDPI_IMAGES = YES;'''
for name in ('Debug','Release'):
    specific = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if name == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    obj('config:'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {base} {specific} }};')
    obj('projectconfig:'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ }};')
for prefix, key in [('targetconfigs','config:'),('projectconfigs','projectconfig:')]:
    obj(prefix, f'isa = XCConfigurationList; buildConfigurations = ({uid(key+"Debug")},{uid(key+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = RivetdeckNative; productName = RivetdeckNative; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 1640; LastUpgradeCheck = 1640; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(root/'RivetdeckNative.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
(root/'RivetdeckNative.xcodeproj/xcshareddata/xcschemes/RivetdeckNative.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="RivetdeckNative.app" BlueprintName="RivetdeckNative" ReferencedContainer="container:RivetdeckNative.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="YES" customWorkingDirectory="$PROJECT_DIR" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="RivetdeckNative.app" BlueprintName="RivetdeckNative" ReferencedContainer="container:RivetdeckNative.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')
