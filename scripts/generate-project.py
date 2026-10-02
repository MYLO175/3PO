#!/usr/bin/env python3
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
uid=lambda s:hashlib.sha1(s.encode()).hexdigest()[:24].upper()
files=sorted((root/'MissionControl').rglob('*.swift'))+sorted((root/'MissionControl').rglob('*.js'))
objects=[]
def obj(key,value): objects.append(f'{uid(key)} = {{ {value} }};')
refs=[]; builds=[]; resources=[]
for p in files:
    path=str(p.relative_to(root)); ref=uid(path); build=uid('build'+path); refs.append(ref)
    typ='sourcecode.swift' if p.suffix=='.swift' else 'sourcecode.javascript'
    obj(path,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = "{path}"; sourceTree = SOURCE_ROOT;')
    obj('build'+path,f'isa = PBXBuildFile; fileRef = {ref};')
    (builds if p.suffix=='.swift' else resources).append(build)
obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = "Mission Control.app"; sourceTree = BUILT_PRODUCTS_DIR;')
obj('main',f'isa = PBXGroup; children = ({",".join(refs+[uid("products")])}); sourceTree = "<group>";')
obj('products',f'isa = PBXGroup; children = ({uid("product")}); name = Products; sourceTree = "<group>";')
for key,typ,ls in [('sources','PBXSourcesBuildPhase',builds),('resources','PBXResourcesBuildPhase',resources),('frameworks','PBXFrameworksBuildPhase',[])]: obj(key,f'isa = {typ}; buildActionMask = 2147483647; files = ({",".join(ls)}); runOnlyForDeploymentPostprocessing = 0;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = MissionControl; productName = "Mission Control"; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
for mode in ['Debug','Release']:
    obj('p'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; }}; name = {mode};')
    settings='PRODUCT_BUNDLE_IDENTIFIER = com.mylomichael.missioncontrol; PRODUCT_NAME = "Mission Control"; INFOPLIST_FILE = MissionControl/Info.plist; GENERATE_INFOPLIST_FILE = NO; DEVELOPMENT_TEAM = 4NYCBX3QPX; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "Apple Development"; CODE_SIGN_ENTITLEMENTS = MissionControl/MissionControl.entitlements; ENABLE_HARDENED_RUNTIME = YES; SWIFT_VERSION = 5.0; COMBINE_HIDPI_IMAGES = YES;'
    if mode=='Debug': settings+=' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;'
    obj('t'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
for kind,prefix in [('project','p'),('target','t')]: obj(kind+'configs',f'isa = XCConfigurationList; buildConfigurations = ({uid(prefix+"Debug")},{uid(prefix+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project=root/'MissionControl.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
