#!/usr/bin/env python3
"""Compile production sources into an isolated XCTest runner. All test networking is intercepted.

The production @main entry point is omitted and cloud credential storage is replaced in temporary copies.
Keychain integration is not covered; real app stores and accounts are not used.
Requires Xcode and an installed iOS simulator runtime. Artifacts remain under the printed temporary path.
"""
from pathlib import Path
import argparse, json, plistlib, shutil, subprocess, tempfile, uuid, sys, fcntl
sys.dont_write_bytecode = True
parser = argparse.ArgumentParser(description='Run isolated SwiftData/URLProtocol sync regression tests on a booted simulator.')
parser.add_argument('--destination', help='Explicit xcodebuild destination; defaults to the first booted iOS simulator.')
parser.add_argument('--storekit', action='store_true', help='Run isolated StoreKit local purchase tests only; no real App Store purchases.')
parser.add_argument('--purchase-preview', action='store_true', help='Run isolated purchase UI fixture; finish with its QA button, no purchases')
args = parser.parse_args()
if args.purchase_preview: args.storekit = True
# Hostless runners share the simulator's standard preferences. Concurrent runs
# can change account scope underneath each other and invalidate network fixtures.
run_lock = (Path(tempfile.gettempdir()) / 'trvelma-sync-regression.lock').open('a')
try:
    fcntl.flock(run_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    parser.error('Another sync regression run is active; run these tests serially.')
base = Path(tempfile.mkdtemp(prefix='trvelma-sync-regression-'))
root = Path(__file__).resolve().parents[1] / 'Wishlist'
app=base/'WishlistApp.swift'; app.write_text((root/'WishlistApp.swift').read_text().replace('@main\n',''))
# An unsigned, hostless XCTest runner cannot use the app's Keychain entitlement.
# Replace only credential storage in a temporary auth source; login and directory logic remain production code.
auth_source = root / 'Views/Login/AuthViewModel.swift'
auth_text = auth_source.read_text()
start = auth_text.index('private enum SecureCloudSession {')
end = auth_text.index('private enum PasswordKeychain {', start)
auth_copy = base / 'AuthViewModel.swift'
auth_copy.write_text(auth_text[:start] + """private enum SecureCloudSession {
    private static var values: [String: String] = [:]
    @discardableResult static func save(_ value: String, key: String) -> Bool { values[key] = value; return true }
    static func load(key: String) -> String? { values[key] }
    static func delete(key: String) { values.removeValue(forKey: key) }
}

extension AuthViewModel {
    func clearIsolatedTestSession() {
        SecureCloudSession.delete(key: "auth.cloud.accessToken")
        SecureCloudSession.delete(key: "auth.cloud.refreshToken")
        logout()
    }
}

""" + auth_text[end:])
# A hostless runner has no application bundle for UNUserNotificationCenter.
# Record cancellation at the system boundary; keep all persistence decisions intact.
reminder_source = root / 'Views/Trips/NewTripFormModel.swift'
reminder_copy = base / 'NewTripFormModel.swift'
reminder_text = reminder_source.read_text()
reminder_call = 'UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(for: tripID))'
assert reminder_text.count(reminder_call) == 1
# The hostless runner cannot access the device notification daemon. Record
# migration inputs at that boundary, just as cancellation is recorded below.
reminder_text = reminder_text.replace(
    'static func refreshPendingMessages(_ messages: [UUID: TripReminderMessage], isCurrent: @MainActor () -> Bool = { !Task.isCancelled }) async {',
    'static func refreshPendingMessages(_ messages: [UUID: TripReminderMessage], isCurrent: @MainActor () -> Bool = { !Task.isCancelled }) async { return;')
reminder_copy.write_text(reminder_text.replace('enum TripReminderScheduler {', 'enum TripReminderScheduler {\n    static var cancelledTripIDs: [UUID] = []', 1).replace(reminder_call, 'cancelledTripIDs.append(tripID)', 1))
objects={}
def obj(isa, **kwargs):
 k=uuid.uuid4().hex[:24].upper(); objects[k]={'isa':isa,**kwargs}; return k
refs=[]; builds=[]
for p in sorted(root.rglob('*.swift')):
 if p.name.startswith('._'): continue
 if p.name=='WishlistApp.swift': p=app
 if p == auth_source: p=auth_copy
 if p == reminder_source: p=reminder_copy
 ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(p),sourceTree='<absolute>');refs.append(ref)
 builds.append(obj('PBXBuildFile',fileRef=ref))
from flight_editor_harness import generate
harness = base / 'FlightEditorHarness.swift'
harness.write_text(generate(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from settlement_form_harness import generate as generate_settlement_form
settlement_harness = base / 'SettlementFormHarness.swift'
settlement_harness.write_text(generate_settlement_form(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(settlement_harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from business_card_harness import generate as generate_business_card
card_harness = base / 'BusinessCardHarness.swift'
card_harness.write_text(generate_business_card(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(card_harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from completion_harness import generate as generate_completion
completion_harness = base / 'CompletionHarness.swift'
completion_harness.write_text(generate_completion(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(completion_harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from flight_display_harness import generate as generate_flight_display
flight_display_harness = base / 'FlightDisplayHarness.swift'
flight_display_harness.write_text(generate_flight_display(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(flight_display_harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from flight_persistence_harness import generate as generate_flight_persistence
flight_persistence_harness = base / 'FlightPersistenceHarness.swift'
flight_persistence_harness.write_text(generate_flight_persistence(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(flight_persistence_harness),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
from smart_input_harness import generate as generate_smart_input
smart_input = base / 'SmartInputHarness.swift'
smart_input.write_text(generate_smart_input(root))
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(smart_input),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
test=base/'SyncRegressionTests.swift'
shutil.copyfile(Path(__file__).parent / 'tests/SyncRegressionTests.swift', test)
ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(test),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
storekit_resources=[]
if args.storekit:
    config=base/'TrvelMA.storekit'
    shutil.copyfile(root.parent/'StoreKit/TrvelMA.storekit',config)
    if args.purchase_preview:
        fixture = json.loads(config.read_text())
        metadata = json.loads((root.parent/'docs/billing-1.1-product-localizations.json').read_text())
        by_id = {p['product_id']: p for p in metadata['products'].values()}
        for product in fixture['products'] + [p for g in fixture['subscriptionGroups'] for p in g['subscriptions']]:
            product['localizations'] = [{'locale':code.replace('-','_'),'displayName':copy['name'],'description':copy['description']} for code,copy in by_id[product['productID']]['localizations'].items()]
        config.write_text(json.dumps(fixture, ensure_ascii=False, indent=2))
    ref=obj('PBXFileReference',lastKnownFileType='text',path=str(config),sourceTree='<absolute>');refs.append(ref)
    storekit_resources.append(obj('PBXBuildFile',fileRef=ref))
    storekit_test=base/'StoreKitLocalTests.swift'
    shutil.copyfile(Path(__file__).parent/'tests/StoreKitLocalTests.swift',storekit_test)
    if args.purchase_preview:
        storekit_test.write_text((Path(__file__).parent/'tests/PurchaseUIPreview.swift').read_text())
    ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(storekit_test),sourceTree='<absolute>');refs.append(ref);builds.append(obj('PBXBuildFile',fileRef=ref))
product=obj('PBXFileReference',explicitFileType='wrapper.cfbundle',path='SyncRegression.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=obj('PBXGroup',children=refs+[products],sourceTree='<group>')
sources=obj('PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
frameworks=obj('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
resources=obj('PBXResourcesBuildPhase',buildActionMask=2147483647,files=storekit_resources,runOnlyForDeploymentPostprocessing=0)
settings={'PRODUCT_NAME':'SyncRegression','PRODUCT_BUNDLE_IDENTIFIER':'com.trvelma.acceptance.sync-regression','SDKROOT':'iphonesimulator','SUPPORTED_PLATFORMS':'iphonesimulator','IPHONEOS_DEPLOYMENT_TARGET':'26.0','SWIFT_VERSION':'5.0','SWIFT_APPROACHABLE_CONCURRENCY':'YES','SWIFT_DEFAULT_ACTOR_ISOLATION':'MainActor','SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGNING_ALLOWED':'NO','ENABLE_TESTABILITY':'YES','TARGETED_DEVICE_FAMILY':'1,2','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']}
conf=obj('XCBuildConfiguration',name='Debug',buildSettings=settings)
configs=obj('XCConfigurationList',buildConfigurations=[conf],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
target=obj('PBXNativeTarget',name='SyncRegression',productName='SyncRegression',productReference=product,productType='com.apple.product-type.bundle.unit-test',buildConfigurationList=configs,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[])
host_target=None
if args.storekit:
    # StoreKitTest requires an application host, not the hostless xctest tool.
    host_source=base/'StoreKitQAApp.swift'
    host_source.write_text('import SwiftUI\n@main struct StoreKitQAApp: App { var body: some Scene { WindowGroup { Text("StoreKit QA") } } }\n')
    host_ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(host_source),sourceTree='<absolute>');objects[group]['children'].append(host_ref)
    host_product=obj('PBXFileReference',explicitFileType='wrapper.application',path='StoreKitQA.app',sourceTree='BUILT_PRODUCTS_DIR');objects[products]['children'].append(host_product)
    host_sources=obj('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[obj('PBXBuildFile',fileRef=host_ref)],runOnlyForDeploymentPostprocessing=0)
    host_frameworks=obj('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    host_resource_files=[]
    if args.purchase_preview:
        locale_ref=obj('PBXFileReference',lastKnownFileType='text.json.xcstrings',path=str(root/'Localizable.xcstrings'),sourceTree='<absolute>')
        objects[group]['children'].append(locale_ref)
        host_resource_files.append(obj('PBXBuildFile',fileRef=locale_ref))
    host_resources=obj('PBXResourcesBuildPhase',buildActionMask=2147483647,files=host_resource_files,runOnlyForDeploymentPostprocessing=0)
    host_settings=dict(settings)
    host_settings.update(PRODUCT_NAME='StoreKitQA',PRODUCT_BUNDLE_IDENTIFIER='com.trvelma.acceptance.storekit-host',CODE_SIGNING_ALLOWED='YES',CODE_SIGN_IDENTITY='-',INFOPLIST_KEY_UILaunchScreen_Generation='YES',INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES')
    host_conf=obj('XCBuildConfiguration',name='Debug',buildSettings=host_settings)
    host_configs=obj('XCConfigurationList',buildConfigurations=[host_conf],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
    host_target=obj('PBXNativeTarget',name='StoreKitQA',productName='StoreKitQA',productReference=host_product,productType='com.apple.product-type.application',buildConfigurationList=host_configs,buildPhases=[host_sources,host_frameworks,host_resources],buildRules=[],dependencies=[])
    settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/StoreKitQA.app/StoreKitQA',BUNDLE_LOADER='$(TEST_HOST)',CODE_SIGNING_ALLOWED='YES',CODE_SIGN_IDENTITY='-')
    objects[conf]['buildSettings']=settings
    objects[target]['dependencies']=[obj('PBXTargetDependency',target=host_target)]
pc=obj('XCBuildConfiguration',name='Debug',buildSettings={})
pcl=obj('XCConfigurationList',buildConfigurations=[pc],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
project=obj('PBXProject',attributes={'LastUpgradeCheck':'2600'},buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target]+([host_target] if host_target else []))
proj=base/'SyncRegression.xcodeproj';proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project}))
schemes=proj/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
buildref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SyncRegression.xctest" BlueprintName="SyncRegression" ReferencedContainer="container:SyncRegression.xcodeproj"/>'
(schemes/'SyncRegression.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{buildref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref}</TestableReference></Testables></TestAction></Scheme>''')

if args.destination:
    destination = args.destination
else:
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))['devices']
    booted = [device for runtime, entries in devices.items() if '.iOS-' in runtime for device in entries if device['state'] == 'Booted']
    if not booted:
        raise SystemExit('Boot an iOS simulator first, or specify --destination.')
    destination = 'platform=iOS Simulator,id=' + booted[0]['udid']
log = base / 'test.log'
print('Isolated test artifacts:', base, flush=True)
command = ['xcodebuild', '-project', str(proj), '-scheme', 'SyncRegression', '-destination', destination,
           '-derivedDataPath', str(base / 'build'), '-resultBundlePath', str(base / 'results'), 'test']
if args.purchase_preview: command.append('-only-testing:SyncRegression/PurchaseUIOnlyTests')
elif args.storekit: command.append('-only-testing:SyncRegression/StoreKitLocalIntegrationTests')
with log.open('w') as output:
    result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
for line in log.read_text().splitlines():
    if 'Test Case ' in line or 'Executed ' in line or 'error:' in line or '** TEST ' in line:
        print(line)
raise SystemExit(result.returncode)
