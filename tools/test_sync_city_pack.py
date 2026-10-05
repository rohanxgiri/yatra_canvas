"""Exercise failed asset replacement without touching the real project assets."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from tools.sync_city_pack import sync

FACTORY=Path(__file__).resolve().parents[2]/'YatraCanvas-DataFactory'
sys.path.insert(0,str(FACTORY))


class SyncRollbackTest(unittest.TestCase):
    def test_validation_failure_restores_previous_pack_and_index(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); source=root/'export';source.mkdir()
            (source/'payload').write_text('new')
            target=root/'assets';previous=target/'fixture';previous.mkdir(parents=True)
            (previous/'payload').write_text('old')
            (previous/'manifest.json').write_text(json.dumps({'pack_version':'old'}))
            (target/'index.json').write_text('{"fixture":{"pack_version":"old"}}')
            index=(target/'index.json').read_bytes()
            manifest={'city_id':'fixture','pack_version':'new','source_release':'new'}
            def validate(path):
                if Path(path)==previous:raise ValueError('Failed installed inventory')
                return manifest
            with patch('datafactory.app_pack.export_app_pack',return_value={**manifest,'output':str(source)}), patch('datafactory.app_pack.validate_app_pack',side_effect=validate):
                with self.assertRaisesRegex(ValueError,'installed'):
                    sync('Fixture',FACTORY,target=target)
            self.assertEqual((previous/'payload').read_text(),'old')
            self.assertEqual((target/'index.json').read_bytes(),index)
            self.assertFalse(list(target.glob('.previous-*')))

if __name__=='__main__':unittest.main()
