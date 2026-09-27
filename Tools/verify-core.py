#!/usr/bin/env python3
"""Compile and execute actual portable app services; not an iOS app build."""
from pathlib import Path
import os, re, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
swiftc = os.environ.get('GOLDFISH_SWIFTC', 'swiftc')
services = ['RelationshipForest', 'DiagramGeometry', 'StoreRecoveryService', 'VCardTextCodec', 'GroupTransferMetadata', 'VCardParser']
tests = ['RelationshipForestTests', 'DiagramGeometryTests', 'StoreRecoveryTests', 'VCardTextCodecTests', 'VCardParserTests']
with tempfile.TemporaryDirectory(prefix='goldfish-core-') as temp:
    build = Path(temp)
    library = build / ('libGoldfish.dylib' if os.uname().sysname == 'Darwin' else 'libGoldfish.so')
    subprocess.run([swiftc, '-swift-version', '5', '-emit-library', '-emit-module', '-module-name', 'Goldfish', '-enable-testing', '-emit-module-path', str(build/'Goldfish.swiftmodule'), *[str(root/'Services'/f'{s}.swift') for s in services], str(root/'Models/RelationshipType.swift'), str(root/'Models/ContactKind.swift'), '-o', str(library)], check=True)
    cases=[]
    for test in tests:
        names=re.findall(r'func (test\w+)\(', (root/'Tests'/f'{test}.swift').read_text())
        cases.append('testCase(['+', '.join(f'("{name}", {test}.{name})' for name in names)+'])')
    (build/'main.swift').write_text('import XCTest\nXCTMain(['+', '.join(cases)+'])\n')
    subprocess.run([swiftc, '-swift-version','5','-I',str(build),'-L',str(build),'-lGoldfish',*[str(root/'Tests'/f'{t}.swift') for t in tests],str(build/'main.swift'),'-o',str(build/'core-tests')],check=True)
    env=os.environ.copy();env['LD_LIBRARY_PATH']=str(build)+':'+env.get('LD_LIBRARY_PATH','')
    env['DYLD_LIBRARY_PATH']=str(build)+':'+env.get('DYLD_LIBRARY_PATH','')
    subprocess.run([str(build/'core-tests')],env=env,check=True)
