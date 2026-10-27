import tempfile
import unittest
from pathlib import Path

import yaml

from make_sovits_config_portable import migrate, portable_path


class PortableConfigTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="portable_sovits_")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.model = "GPT_weights_v2ProPlus/MyGO_高松灯_v2pp.ckpt"
        destination = self.root / self.model
        destination.parent.mkdir()
        destination.touch()
        self.config_path = self.root / "GPT_SoVITS/configs/tts_infer.yaml"
        self.config_path.parent.mkdir(parents=True)
        self.original = yaml.safe_dump({
            "custom": {
                "device": "cuda",
                "is_half": True,
                "t2s_weights_path": (
                    "C:/GPT-SoVITS-v2pro-20250604-nvidia50/" + self.model
                ),
            }
        })
        self.config_path.write_text(self.original, encoding="utf-8")

    def test_preview_does_not_write(self):
        self.assertEqual(len(migrate(self.root)), 1)
        self.assertEqual(self.config_path.read_text(encoding="utf-8"), self.original)
        self.assertFalse(list(self.config_path.parent.glob("*.bak")))

    def test_apply_keeps_settings_backup_and_is_idempotent(self):
        self.assertEqual(len(migrate(self.root, apply=True)), 1)
        settings = yaml.safe_load(self.config_path.read_text(encoding="utf-8"))["custom"]
        self.assertEqual(settings["t2s_weights_path"], self.model)
        self.assertEqual(settings["device"], "cuda")
        self.assertIs(settings["is_half"], True)
        backup = self.config_path.with_name(self.config_path.name + ".before-portable.bak")
        self.assertEqual(backup.read_text(encoding="utf-8"), self.original)
        self.assertEqual(migrate(self.root, apply=True), [])
        self.assertEqual(backup.read_text(encoding="utf-8"), self.original)

    def test_external_missing_and_relative_paths_are_preserved(self):
        paths = [
            "D:/other_models/voice.ckpt",
            "C:/GPT-SoVITS-v2pro-20250604-nvidia50/missing.ckpt",
            self.model,
            "C:/GPT-SoVITS-v2pro-20250604-nvidia50/../outside.ckpt",
        ]
        for value in paths:
            self.assertEqual(portable_path(value, self.root), value)


if __name__ == "__main__":
    unittest.main()
