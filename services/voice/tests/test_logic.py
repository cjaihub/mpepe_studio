import unittest

from voice.logic import (
    ClipStats, clip_problems, engine_for, enrollment_report, safe_uid, sign_stream_token, split_phrases, verify_stream_token,
)


class LogicTest(unittest.TestCase):
    def test_engine_routing(self):
        self.assertEqual(engine_for("sw-KE"), "clone")
        self.assertEqual(engine_for("FR"), "clone")
        self.assertEqual(engine_for("yo"), "convert")
        self.assertEqual(engine_for("ha"), "convert")
        self.assertEqual(engine_for(""), "convert")

    def test_phrases_are_short_and_complete(self):
        text = "Habari yako? Niko sawa kabisa. " + "neno " * 80
        parts = split_phrases(text, max_chars=60)
        self.assertEqual(parts[0], "Habari yako?")
        self.assertTrue(all(len(p) <= 61 for p in parts))
        self.assertEqual(" ".join(parts).split(), text.split())
        self.assertEqual(split_phrases("   "), [])

    def test_clip_quality(self):
        good = ClipStats("a", 10, -20, -55, 0)
        self.assertEqual(clip_problems(good), [])
        self.assertIn("too_quiet", clip_problems(ClipStats("b", 10, -45, -70, 0)))
        self.assertIn("noisy", clip_problems(ClipStats("c", 10, -20, -28, 0)))
        self.assertIn("too_loud", clip_problems(ClipStats("d", 10, -10, -50, 0.01)))
        self.assertIn("too_short", clip_problems(ClipStats("e", 2, -20, -55, 0)))

    def test_enrollment_needs_a_minute_of_clean_speech(self):
        clips = [ClipStats(f"c{i}", 10, -20, -50 - i, 0) for i in range(6)]
        r = enrollment_report(clips)
        self.assertTrue(r["enough"])
        self.assertEqual(r["reference"][0], "c5")  # cleanest first
        self.assertLessEqual(len(r["reference"]), 2)
        short = enrollment_report(clips[:3] + [ClipStats("n", 10, -20, -25, 0)])
        self.assertFalse(short["enough"])
        self.assertEqual(short["retake"][0]["clip"], "n")

    def test_stream_tokens(self):
        key = b"k" * 32
        t = sign_stream_token(key, "user_123456", "call1", ttl_s=60, now=1000)
        self.assertEqual(verify_stream_token(key, t, now=1010)["uid"], "user_123456")
        self.assertIsNone(verify_stream_token(key, t, now=2000))  # expired
        self.assertIsNone(verify_stream_token(b"x" * 32, t, now=1010))  # wrong key
        body, sig = t.split(".")
        self.assertIsNone(verify_stream_token(key, body + "." + sig[:-2] + "AA", now=1010))
        self.assertIsNone(verify_stream_token(key, "junk", now=1010))

    def test_uid_check(self):
        self.assertTrue(safe_uid("Abc_123-xyz"))
        self.assertFalse(safe_uid("../etc"))


if __name__ == "__main__":
    unittest.main()
