import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / 'noise_webtool.py'
spec = importlib.util.spec_from_file_location('noise_webtool', MODULE_PATH)
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)


class SettingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.device = Path(self.tmp.name)
        for field in web.STATUS_FIELDS:
            (self.device / field).write_text('0\n')
        for field in web.FREQUENCY_FIELDS:
            (self.device / field).write_text('200\n')

    def test_frequencies_and_pwm(self):
        web.write_settings(self.device, {'dds_frequency_hz': 2_000_000,
                                        'fm_frequency_hz': 1000,
                                        'pwm_reference': 1023})
        status = web.read_status(self.device)
        self.assertEqual(status['dds_frequency_hz'], '2000000')
        self.assertEqual(status['fm_frequency_hz'], '1000')
        self.assertEqual(status['pwm_reference'], '1023')
        self.assertNotIn('amplitude', status)

    def test_validate_entire_request_before_writing(self):
        for field, value in [('dds_frequency_hz', -1), ('fm_frequency_hz', 16000000),
                             ('dds_frequency_hz', True), ('fm_frequency_hz', 1.5),
                             ('amplitude', 0), ('pwm_reference', 1024),
                             ('../anything', 1)]:
            with self.subTest(field=field, value=value):
                with self.assertRaises(ValueError):
                    web.write_settings(self.device, {'generator': 'dds', field: value})
                self.assertEqual((self.device / 'generator').read_text(), '0\n')

    def test_old_driver_remains_readable_but_cannot_write_frequency(self):
        (self.device / 'dds_frequency_hz').unlink()
        self.assertIsNone(web.read_status(self.device)['dds_frequency_hz'])
        with self.assertRaisesRegex(ValueError, 'Update'):
            web.write_settings(self.device, {'dds_frequency_hz': 1000})
        self.assertFalse((self.device / 'dds_frequency_hz').exists())

    def test_bounds(self):
        for hz in (0, web.MAX_FREQUENCY_HZ):
            web.write_settings(self.device, {'dds_frequency_hz': hz})
            self.assertEqual(web.read_status(self.device)['dds_frequency_hz'], str(hz))


if __name__ == '__main__':
    unittest.main()
