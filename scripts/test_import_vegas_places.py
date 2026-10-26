import unittest
from import_vegas_places import convert

class PlaceImportTests(unittest.TestCase):
    def test_preserves_source_name_coordinates_and_center_provenance(self):
        rows, skipped = convert({'elements':[
            {'type':'node','id':1,'lat':36.19,'lon':-115.28,'tags':{'name':'Source Café','brand':'Brand','amenity':'cafe','addr:street':'Source Road','access':'customers'}},
            {'type':'way','id':2,'center':{'lat':36.2,'lon':-115.25},'tags':{'name':'Source Park','leisure':'park'}},
        ]})
        by_id={r['id']:r for r in rows}
        self.assertEqual(by_id['node/1']['latitude'],36.19)
        self.assertEqual(by_id['node/1']['name'],'Source Café')
        self.assertEqual(by_id['node/1']['access'],'customers')
        self.assertEqual(by_id['way/2']['precision'],'mapped feature center')
        self.assertEqual(by_id['node/1']['sourceUrl'],'https://www.openstreetmap.org/node/1')
        self.assertEqual(skipped,{})
    def test_missing_invalid_inactive_and_duplicate_records_are_not_invented(self):
        source={'type':'node','id':1,'lat':36.19,'lon':-115.28,'tags':{'name':'Valid'}}
        rows, skipped=convert({'elements':[source,source,{'type':'node','id':2,'tags':{'name':'Missing'}},
            {**source,'id':3,'lat':37}, {**source,'id':4,'tags':{'name':'Old','disused':'yes'}}]})
        self.assertEqual(len(rows),1)
        self.assertEqual(sum(skipped.values()),4)
    def test_partial_or_malformed_snapshot_fails(self):
        for data in ({'remark':'timeout','elements':[]},{'elements':None}):
            with self.assertRaises(ValueError): convert(data)

if __name__ == '__main__': unittest.main()
