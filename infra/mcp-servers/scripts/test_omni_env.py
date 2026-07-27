import unittest
from unittest.mock import patch
import _omni_env


class TestOmniEnv(unittest.TestCase):
    @patch("_omni_env._inspect")
    def test_detect_network_custom(self, mock_inspect):
        mock_inspect.return_value = "custom-network  "
        net = _omni_env.detect_network()
        self.assertEqual(net, "custom-network")
        mock_inspect.assert_called_once_with("omnigraph-server", "{{range $n,$_ := .NetworkSettings.Networks}}{{$n}} {{end}}")

    @patch("_omni_env._inspect")
    def test_detect_network_fallback(self, mock_inspect):
        mock_inspect.return_value = None
        net = _omni_env.detect_network(default="fallback-net")
        self.assertEqual(net, "fallback-net")

    @patch("_omni_env._inspect")
    def test_detect_minio_store_volume(self, mock_inspect):
        mock_inspect.return_value = "volume|vol_name|/var/minio|/data\n"
        kind, val = _omni_env.detect_minio_store()
        self.assertEqual(kind, "volume")
        self.assertEqual(val, "vol_name")

    @patch("_omni_env._inspect")
    def test_detect_minio_store_bind(self, mock_inspect):
        mock_inspect.return_value = "bind||/host/path/minio|/data\n"
        kind, val = _omni_env.detect_minio_store()
        self.assertEqual(kind, "bind")
        self.assertEqual(val, "/host/path/minio")

    @patch("_omni_env._inspect")
    def test_detect_minio_store_absent(self, mock_inspect):
        mock_inspect.return_value = None
        kind, val = _omni_env.detect_minio_store()
        self.assertIsNone(kind)
        self.assertIsNone(val)

    def test_describe(self):
        desc = _omni_env.describe("test-net", "volume", "my-vol")
        self.assertEqual(desc, "network=test-net volume=my-vol")

        desc_none = _omni_env.describe("test-net", None, None)
        self.assertEqual(desc_none, "network=test-net minio=<not detected>")


if __name__ == "__main__":
    unittest.main()
