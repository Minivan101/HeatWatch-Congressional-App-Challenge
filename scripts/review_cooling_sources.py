'check cooling sources'

import argparse
import datetime as dt
import hashlib
import gzip
import io
import json
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / 'data/cooling_centers/research'

def source_tasks():
    data = json.loads((RESEARCH / 'cooling-stations-research.json').read_text())
    tasks = [{k: s[k] for k in ['id', 'url', 'file', 'sha256']} for s in data['sources']]
    coords = json.loads((RESEARCH / 'county-map-coordinate-sources.json').read_text())
    tasks.append({'id': 'county-resource-map-kml', 'url': coords['sourceUrl'],
                  'file': coords['file'], 'sha256': coords['sha256']})
    for item in json.loads((RESEARCH / 'facility-coordinate-sources.json').read_text()):
        tasks.append({'id': item['stationId'] + '-facility', 'url': item['sourceUrl'],
                      'file': item['file'], 'sha256': item['sha256']})
    for sid, url, file in [
        ('county-directory', 'https://www.clarkcountynv.gov/government/departments/fire/cooling-stations', 'sources/county-directory.html'),
        ('county-activation-notice', 'https://www.clarkcountynv.gov/news/cooling-stations-activated', 'sources/september-notice.html'),
        ('county-stay-cool', 'https://allin.clarkcountynv.gov/Initiative/StayCool', 'sources/stay-cool.html'),
    ]:
        tasks.append({'id': sid, 'url': url, 'file': file,
                      'sha256': hashlib.sha256((RESEARCH / file).read_bytes()).hexdigest()})
    layer = json.loads((RESEARCH / 'county-cooling-layer-evidence.json').read_text())
    for snapshot in layer['snapshots']:
        tasks.append({'id': Path(snapshot['file']).stem, 'url': snapshot['url'],
                      'file': snapshot['file'], 'sha256': snapshot['sha256']})
    for item in json.loads((RESEARCH / 'additional-address-evidence.json').read_text()):
        tasks.append({'id': item['stationId'] + '-address-evidence', 'url': item['sourceUrl'],
                      'file': item['file'], 'sha256': item['sha256']})
    update = json.loads((RESEARCH / 'reviewed-source-update-2026-10-11.json').read_text())
    tasks.extend({k: source[k] for k in ['id', 'url', 'file', 'sha256']}
                 for source in update['sources'])
    return tasks

def decoded_content(task, content):

    if task['file'].endswith('.pdf') and content.startswith(b'\x1f\x8b'):
        with gzip.GzipFile(fileobj=io.BytesIO(content)) as stream:
            content = stream.read(5242881)
        if len(content) > 5242880:
            raise ValueError('PDF exceeds source review limit')
    return content

def compare(task, content):
    content = decoded_content(task, content)
    digest = hashlib.sha256(content).hexdigest()
    new_pdf_links = []
    if task['id'] == 'county-directory':
        old = (RESEARCH / task['file']).read_text()
        current = content.decode('utf-8', errors='replace')
        pattern = r'[^\s"<>]+\.pdf(?:\?[^\s"<>]*)?'
        new_pdf_links = sorted(set(re.findall(pattern, current, re.I)) - set(re.findall(pattern, old, re.I)))
    changed = digest != task['sha256']
    if task['id'].startswith('qr-'):
        try:
            changed = json.loads(content) != json.loads((RESEARCH / task['file']).read_bytes())
        except (ValueError, UnicodeDecodeError):
            changed = True
    if task['id'].endswith('-address-evidence') and task['file'].endswith('.html'):
        def visible(raw):
            from html import unescape
            text = raw.decode('utf-8')
            text = re.sub(r'<(script|style)\b[^>]*>.*?</\1>', '', text, flags=re.S | re.I)
            return re.sub(r'\s+', ' ', unescape(re.sub('<[^>]+>', ' ', text))).strip()
        changed = visible(content) != visible((RESEARCH / task['file']).read_bytes())
    if task['id'].endswith('-facility'):

        def structured(raw):
            class Parser(HTMLParser):
                def __init__(self): super().__init__(); self.capture = False; self.values = []
                def handle_starttag(self, tag, attrs):
                    self.capture = tag == 'script' and dict(attrs).get('type') == 'application/ld+json'
                def handle_endtag(self, tag):
                    if tag == 'script': self.capture = False
                def handle_data(self, value):
                    if self.capture: self.values.append(value)
            parser = Parser(); parser.feed(raw.decode('utf-8'))
            return next(json.loads(v) for v in parser.values if isinstance(json.loads(v), dict) and 'geo' in json.loads(v))
        try:
            changed = structured(content) != structured((RESEARCH / task['file']).read_bytes())
        except (ValueError, StopIteration):
            changed = True
    return {'id': task['id'], 'url': task['url'], 'baselineSha256': task['sha256'],
            'downloadSha256': digest,
            'status': 'needs-review' if changed else 'unchanged',
            'newPdfLinks': new_pdf_links}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--heat-event', action='store_true', help='Daily review cadence; otherwise weekly')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    output = args.output or ROOT / 'data/cooling_centers/maintenance' / now.strftime('%Y-%m-%dT%H%M%SZ')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for task in source_tasks():
        file = output / (task['id'] + '.download')
        try:
            subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                '--proto', '=https', '--proto-redir', '=https', '--max-time', '20',
                '--max-filesize', '5242880', task['url'], '--output', str(file)], check=True,
                capture_output=True)
            content = decoded_content(task, file.read_bytes())
            file.write_bytes(content)
            result = compare(task, content)
            result['downloadFile'] = file.name
        except (subprocess.SubprocessError, OSError, ValueError, EOFError) as error:
            result = {'id': task['id'], 'url': task['url'], 'status': 'unavailable', 'error': type(error).__name__}
        results.append(result)
        print(task['id'] + ': ' + result['status'], flush=True)
    report = {'checkedAt': now.isoformat(), 'cadence': 'daily' if args.heat_event else 'weekly',
              'nextCheckDue': (now + dt.timedelta(days=1 if args.heat_event else 7)).isoformat(),
              'currentActivationConfirmed': False, 'results': results}
    (output / 'review.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Cooling source review', '', f"Checked {report['checkedAt']}; next check due {report['nextCheckDue']}.",
             '', 'Source changes require a person to review the documents. A source check does not confirm facility opening.', '',
             '| Source | Result |', '|---|---|']
    lines += [f"| {r['id']} | {r['status']} |" for r in results]
    lines += ['', 'Review new notices, dates, every site/address/phone/hour/restriction, coordinate changes and source conflicts.',
              'Keep unknowns explicit. Do not promote a new document to verified-open or update the app automatically.',
              'After review, stage an increasing revision and run the Dart validator/tests. Publish only to approved free hosting.',
              'Keep the last reviewed dataset if sources or update validation fail.']
    (output / 'review.md').write_text('\n'.join(lines) + '\n')
    print('Report: ' + str(output / 'review.md'))

if __name__ == '__main__':
    main()
