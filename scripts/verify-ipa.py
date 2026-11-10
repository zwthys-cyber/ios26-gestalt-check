#!/usr/bin/env python3
"""GitHub macOS runner package checks; does not claim iPhone runtime support."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile


def run(*args):
    return subprocess.run(args, check=True, capture_output=True)


reports = []
for filename in sys.argv[1:]:
    ipa = Path(filename)
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(ipa) as archive:
            assert archive.testzip() is None, 'IPA ZIP checksum failure'
            archive.extractall(temp)
        apps = list((Path(temp) / 'Payload').glob('*.app'))
        assert len(apps) == 1, 'Expected one application'
        app = apps[0]
        bundles = [app] + list((app / 'PlugIns').glob('*.appex'))
        common = None
        details = []
        for bundle in bundles:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            assert info['MinimumOSVersion'] == '26.0', info['MinimumOSVersion']
            assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
            executable = bundle / info['CFBundleExecutable']
            architectures = run('lipo', '-archs', str(executable)).stdout.decode().split()
            assert 'arm64' in architectures, architectures
            run('codesign', '--verify', '--strict', str(bundle))
            entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', '-', '--xml', str(bundle)).stdout)
            groups = entitlements.get('com.apple.security.application-groups', [])
            assert isinstance(groups, list) and groups and all(isinstance(g, str) and g.startswith('group.') for g in groups)
            common = set(groups) if common is None else common.intersection(groups)
            metadata = run('codesign', '-dvv', str(bundle)).stderr.decode()
            assert 'Signature=adhoc' in metadata
            assert 'TeamIdentifier=not set' in metadata
            assert not (bundle / 'embedded.mobileprovision').exists()
            details.append({'bundle': info['CFBundleIdentifier'], 'minimumOS': info['MinimumOSVersion'], 'architectures': architectures, 'appGroups': groups})
        assert common, 'Application and extension need a common App Group'
        reports.append({'ipa': ipa.name, 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(), 'packageVerified': True, 'signature': 'ad-hoc; re-signing required', 'deviceRuntimeTested': False, 'appleIntelligenceUnlocked': False, 'bundles': details})
print(json.dumps(reports, indent=2))
