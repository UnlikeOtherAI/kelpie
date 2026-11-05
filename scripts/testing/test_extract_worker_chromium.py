import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location(
    "extract_worker_chromium", Path(__file__).with_name("extract-worker-chromium.py")
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ExtractTests(unittest.TestCase):
    def test_valid_binary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "chrome.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("chrome-linux64/chrome", b"fixture")
            MODULE.extract(str(archive), str(root / "result"))
            self.assertEqual((root / "result/chrome-linux64/chrome").read_bytes(), b"fixture")

    def test_rejects_escape_and_symlink_before_extraction(self):
        for name, symlink in [("../escape", False), ("chrome-linux64/link", True)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "chrome.zip"
                with zipfile.ZipFile(archive, "w") as output:
                    item = zipfile.ZipInfo(name)
                    if symlink:
                        item.create_system = 3
                        item.external_attr = (stat.S_IFLNK | 0o777) << 16
                    output.writestr(item, b"payload")
                with self.assertRaises(ValueError):
                    MODULE.extract(str(archive), str(root / "result"))
                self.assertFalse((root / "result").exists())


if __name__ == "__main__":
    unittest.main()
