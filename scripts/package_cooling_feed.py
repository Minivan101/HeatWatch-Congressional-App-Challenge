'package the cooling data'

import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ('official-directory.json', '_headers', 'index.html', 'README.txt')

def package():
    folder = ROOT / 'release/cooling-feed'
    data = json.loads((folder / FILES[0]).read_text())
    installed = json.loads((ROOT / 'data/cooling_centers/official_directory.json').read_text())
    if data != installed:
        raise ValueError('Release differs from reviewed installed snapshot; prepare again.')
    destination = ROOT / 'release/cooling-feed.zip'
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in FILES:
            file = folder / name
            if file.stat().st_size > 25 * 1024 * 1024:
                raise ValueError('File exceeds static Pages asset limit.')
            archive.write(file, arcname=name)
    manifest = {
        'revision': data['revision'], 'stationCount': data['stationCount'],
        'assertionCount': data['assertionCount'], 'published': False,
        'files': {name: hashlib.sha256((folder / name).read_bytes()).hexdigest() for name in FILES},
        'zipSha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
        'scope': 'Public static files only; no Functions, paid resources or secret files.',
    }
    (ROOT / 'release/cooling-feed-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return destination

if __name__ == '__main__':
    print(f'Prepared {package()}. Not published.')
