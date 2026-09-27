#!/usr/bin/env python3
"""Validate source/resource membership and identity of the checked-in Xcode project.
Requires openstep-parser and PyYAML. Does not invoke Xcode or compile an app.
"""
from pathlib import Path
from openstep_parser import OpenStepDecoder
import os, plistlib, yaml, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
with (root/'Goldfish.xcodeproj/project.pbxproj').open() as f:
    project=OpenStepDecoder.ParseFromFile(f)
objects=project['objects']
paths={}
def visit(identifier,parent=''):
    obj=objects[identifier]
    path=obj.get('path','')
    resolved=os.path.normpath(path if obj.get('sourceTree')=='SOURCE_ROOT' else os.path.join(parent,path))
    if obj['isa']=='PBXGroup':
        for child in obj.get('children',[]): visit(child,resolved)
    elif obj['isa']=='PBXFileReference': paths[identifier]=resolved
visit(objects[project['rootObject']]['mainGroup'])
spec=yaml.safe_load((root/'project.yml').read_text())
def declared(entries):
    found=set()
    for entry in entries:
        path=root/entry['path']
        if path.is_dir() and path.suffix!='.xcassets':
            found.update(str(p.relative_to(root)) for p in path.rglob('*.swift'))
        else: found.add(str(path.relative_to(root)))
    return found
for target in (o for o in objects.values() if o['isa']=='PBXNativeTarget'):
    specification=spec['targets'][target['name']]
    wanted=declared(specification.get('sources',[])+specification.get('resources',[]))
    actual=[]
    for phase in target['buildPhases']:
        for build in objects[phase].get('files',[]): actual.append(paths[objects[build]['fileRef']])
    assert len(actual)==len(set(actual)), f'Duplicate build entry in {target["name"]}'
    assert set(actual)==wanted, f'{target["name"]}: missing {wanted-set(actual)}, unexpected {set(actual)-wanted}'
    if target['name']=='Goldfish':
        for config in objects[target['buildConfigurationList']]['buildConfigurations']:
            settings=objects[config]['buildSettings']
            assert settings['PRODUCT_BUNDLE_IDENTIFIER']=='app.pond.goldfish'
            assert settings['PRODUCT_NAME']=='Goldfish'
            assert settings['INFOPLIST_KEY_CFBundleDisplayName']==specification['settings']['base']['INFOPLIST_KEY_CFBundleDisplayName']
    print(f'{target["name"]}: {len(actual)} source/resource entries match project.yml')
for obj in objects.values():
    if obj['isa']=='XCBuildConfiguration' and 'SWIFT_VERSION' in obj.get('buildSettings',{}):
        assert str(obj['buildSettings']['SWIFT_VERSION'])=='5.0'
scheme=ET.parse(root/'Goldfish.xcodeproj/xcshareddata/xcschemes/Goldfish.xcscheme')
assert scheme.find('.//TestableReference/BuildableReference').attrib['BlueprintName']=='GoldfishTests'
print('Project syntax, target identity, language mode and Goldfish scheme references: PASS')
