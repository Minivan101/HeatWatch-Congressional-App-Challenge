import copy
import gzip
import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('review', Path(__file__).with_name('review_cooling_sources.py'))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.task = next(t for t in review.source_tasks() if t['id'] == 'blue-diamond-library-facility')
        self.original = (review.RESEARCH / self.task['file']).read_bytes()
        self.data = json.loads((review.RESEARCH / 'facility-coordinate-sources.json').read_text())[0]['originalStructuredData']

    def html(self, data):
        return ('<html><script type="application/ld+json">' + json.dumps(data) + '</script></html>').encode()

    def test_same_facility_values_ignore_page_telemetry_changes(self):
        result = review.compare(self.task, self.html(self.data))
        self.assertEqual(result['status'], 'unchanged')
        self.assertNotEqual(result['baselineSha256'], result['downloadSha256'])

    def test_geographic_change_needs_review(self):
        changed = copy.deepcopy(self.data)
        changed['geo']['latitude'] += 0.1
        self.assertEqual(review.compare(self.task, self.html(changed))['status'], 'needs-review')

    def test_missing_facility_data_needs_review(self):
        self.assertEqual(review.compare(self.task, b'<html>Gone</html>')['status'], 'needs-review')

    def test_cooling_layer_formatting_is_ignored_but_changes_are_reviewed(self):
        task = next(t for t in review.source_tasks() if t['id'] == 'qr-county-layer-records')
        data = json.loads((review.RESEARCH / task['file']).read_text())
        self.assertEqual(review.compare(task, json.dumps(data).encode())['status'], 'unchanged')
        data['features'][0]['geometry']['coordinates'][0] += 0.1
        self.assertEqual(review.compare(task, json.dumps(data).encode())['status'], 'needs-review')

    def test_address_template_changes_do_not_hide_visible_changes(self):
        task = next(t for t in review.source_tasks() if t['id'] == 'courtyard-homeless-resource-center-address-evidence')
        original = (review.RESEARCH / task['file']).read_bytes()
        self.assertEqual(review.compare(task, original + b'<script>nonce()</script>')['status'], 'unchanged')
        self.assertEqual(review.compare(task, original + b'<p>Facility moved</p>')['status'], 'needs-review')

    def test_gzip_transport_does_not_look_like_a_document_change(self):
        task = next(t for t in review.source_tasks() if t['id'] == 'updated-2026-en')
        original = (review.RESEARCH / task['file']).read_bytes()
        self.assertEqual(review.compare(task, gzip.compress(original))['status'], 'unchanged')

    def test_pdf_change_needs_review_and_never_sets_open(self):
        task = next(t for t in review.source_tasks() if t['id'] == 'aug-en')
        result = review.compare(task, b'changed pdf')
        self.assertEqual(result['status'], 'needs-review')
        self.assertNotIn('open', result)

if __name__ == '__main__':
    unittest.main()
