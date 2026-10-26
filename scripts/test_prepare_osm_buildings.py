'building importer tests'

import unittest
import xml.etree.ElementTree as ET

from prepare_osm_buildings import extract_buildings

class BuildingRelationTests(unittest.TestCase):
    def test_split_outer_ring_is_joined_once(self):
        root = ET.fromstring("""
        <osm>
          <node id="1" lat="34" lon="-118"/>
          <node id="2" lat="34" lon="-117.999"/>
          <node id="3" lat="34.001" lon="-117.999"/>
          <node id="4" lat="34.001" lon="-118"/>
          <way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/></way>
          <way id="11"><nd ref="3"/><nd ref="4"/><nd ref="1"/></way>
          <relation id="20">
            <member type="way" ref="10" role="outer"/>
            <member type="way" ref="11" role="outer"/>
            <tag k="type" v="multipolygon"/>
            <tag k="building" v="yes"/>
            <tag k="height" v="12"/>
          </relation>
        </osm>
        """)
        buildings, skipped, relations, gaps = extract_buildings(root)
        self.assertEqual(len(buildings), 1)
        self.assertEqual(buildings[0]["osmId"], "relation/20/0")
        self.assertEqual(len(buildings[0]["footprint"]), 4)
        self.assertEqual(skipped["open"], 0)
        self.assertEqual(relations, 0)
        self.assertEqual(gaps, [])

    def test_inner_ring_creates_gap_instead_of_solid_building(self):
        root = ET.fromstring("""
        <osm>
          <node id="1" lat="34" lon="-118"/>
          <node id="2" lat="34" lon="-117.999"/>
          <node id="3" lat="34.001" lon="-117.999"/>
          <node id="4" lat="34.001" lon="-118"/>
          <way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/>
            <nd ref="4"/><nd ref="1"/></way>
          <relation id="20">
            <member type="way" ref="10" role="outer"/>
            <member type="way" ref="99" role="inner"/>
            <tag k="type" v="multipolygon"/>
            <tag k="building" v="yes"/>
          </relation>
        </osm>
        """)
        buildings, _, relations, gaps = extract_buildings(root)
        self.assertEqual(buildings, [])
        self.assertEqual(relations, 1)
        self.assertEqual(gaps[0]["bounds"]["south"], 34)

if __name__ == "__main__":
    unittest.main()
