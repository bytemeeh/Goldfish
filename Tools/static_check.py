#!/usr/bin/env python3
"""Source/asset checks plus optional Swift syntax parsing. Never an iOS build."""
import json, plistlib, sys, re, os, shutil, subprocess
from pathlib import Path
import yaml
from tree_sitter import Language, Parser
import tree_sitter_swift
from PIL import Image
root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
failures, parser_limits = [], []
files = list(root.rglob('*.swift'))
for path in files:
    data = path.read_bytes()
    tree = parser.parse(data)
    def inspect(node):
        if node.has_error and not any(child.has_error for child in node.children):
            line = data.splitlines()[node.start_point.row].decode()
            # Known grammar limitations, also present in the exact imported baseline.
            inherited = (path.name == 'OnboardingViewModel.swift' and 'nonisolated(unsafe)' in line) or (path.name == 'SettingsViewModel.swift' and ' as? String ?? ' in line)
            item = {'file':str(path.relative_to(root)), 'line':node.start_point.row+1, 'node':node.type}
            (parser_limits if inherited else failures).append(item)
        for child in node.children: inspect(child)
    inspect(tree.root_node)
for path in root.rglob('*.json'):
    if 'Verification' in path.parts: continue
    content = json.loads(path.read_text())
    for image in content.get('images', []):
        if 'filename' in image and not (path.parent / image['filename']).is_file():
            failures.append('Missing asset: '+str(path.parent / image['filename']))
for suffix in ['*.plist','*.entitlements','*.xcprivacy']:
    for path in root.rglob(suffix): plistlib.loads(path.read_bytes())
project = yaml.safe_load((root/'project.yml').read_text())
for target in project['targets'].values():
    for source in target.get('sources', []) + target.get('resources', []):
        if not (root/source['path']).exists(): failures.append('Missing project path: '+source['path'])
settings=project['targets']['Goldfish']['settings']['base']
assert settings['PRODUCT_BUNDLE_IDENTIFIER']=='app.pond.goldfish'
assert settings['PRODUCT_NAME']=='Goldfish'
assert str(project['options']['deploymentTarget']['iOS'])=='17.0'
assert str(project['settings']['base']['SWIFT_VERSION'])=='5.0'
plist=plistlib.loads((root/'Goldfish/Info.plist').read_bytes())
assert settings['INFOPLIST_KEY_CFBundleDisplayName']==plist['CFBundleDisplayName']
assert project['targets']['Goldfish']['info']['properties']['CFBundleDisplayName']==plist['CFBundleDisplayName']
assert plist['NSContactsUsageDescription']
icon=Image.open(root/'Goldfish/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
assert icon.size==(1024,1024)
if 'A' in icon.getbands(): assert icon.getchannel('A').getextrema()==(255,255)
assets={p.stem for p in (root/'Goldfish/Assets.xcassets').glob('*.imageset')}
for path in files:
    for name in re.findall(r'(?:Image\(|UIImage\(named:\s*)"([^"\\]+)"',path.read_text()):
        if name not in assets: failures.append('Unresolved image '+name+' in '+str(path.relative_to(root)))
compiler = os.environ.get('GOLDFISH_SWIFTC') or shutil.which('swiftc')
syntax={'result':'NOT RUN: no Swift compiler found'}
if compiler:
    source_files=sorted(p for p in files if 'Assets/GenerateLinesAppIcon.swift' != str(p.relative_to(root)))
    result=subprocess.run([compiler,'-frontend','-parse','-swift-version','5',*[str(p) for p in source_files]],capture_output=True,text=True)
    syntax={'result':'PASS' if result.returncode==0 else 'FAIL','source_files':len(source_files),'scope':'Syntax only: no Apple SDK typechecking, linking or execution','compiler':subprocess.check_output([compiler,'--version'],text=True).strip()}
    if result.returncode: failures.append({'swift_parser':result.stderr})
report={'variant':plist['CFBundleDisplayName'],'swift_files_scanned':len(files),'failures':failures,'inherited_tree_sitter_limitations':parser_limits,'swift_syntax_parser':syntax,'result':'PASS' if not failures else 'FAIL','ios_compilation':'NOT RUN: no macOS/Xcode in authoring environment','ios_xctest':'NOT RUN','portable_tests':'See Verification/core-tests.log; run Tools/verify-core.py','simulator_screenshots':'NONE'}
print(json.dumps(report,indent=2))
sys.exit(bool(failures))
