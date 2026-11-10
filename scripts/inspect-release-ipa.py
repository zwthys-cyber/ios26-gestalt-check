#!/usr/bin/env python3
"""Inspect the public upstream archive on GitHub only, without executing its code."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import sys
import zipfile

ipa = Path(sys.argv[1])
expected = 'a9b6c802b938d4d12ba67d8045f4ba7a052ed692d3dae33802b920ef0f3a4f0b'
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
report = {'file': ipa.name, 'bytes': ipa.stat().st_size, 'sha256': digest,
          'matchesPublishedDigest': digest == expected, 'standardMainBundle': False}
ok = False
try:
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        report['firstEntries'] = names[:30]
        report['entryCount'] = len(names)
        report['compressionMethods'] = sorted({i.compress_type for i in archive.infolist()})
        report['allCRCValid'] = archive.testzip() is None
        candidates = [n for n in names if n.endswith('.app/Info.plist')]
        report['mainInfoCandidates'] = candidates
        shallow = [n for n in candidates if len(PurePosixPath(n).parts) == 3
                   and PurePosixPath(n).parts[0] == 'Payload']
        report['standardMainBundle'] = len(shallow) == 1
        if len(shallow) == 1:
            raw = archive.read(shallow[0])
            info = plistlib.loads(raw)
            report['infoFormat'] = 'binary' if raw.startswith(b'bplist') else 'XML'
            report['bundleIdentifier'] = info.get('CFBundleIdentifier')
            report['executable'] = info.get('CFBundleExecutable')
            executable = str(PurePosixPath(shallow[0]).parent / info['CFBundleExecutable'])
            report['hasExecutable'] = executable in names
            ok = report['allCRCValid'] and report['hasExecutable'] and digest == expected
except Exception as error:
    report['error'] = str(error)
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(0 if ok else 1)
