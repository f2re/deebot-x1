import unittest

from aiohttp import web

from dashboard.app import validate_requested_areas


class ValidateRequestedAreasTests(unittest.TestCase):
    def setUp(self) -> None:
        self.available = [
            {"id": "kitchen", "name": "Кухня"},
            {"id": "hall", "name": "Коридор"},
        ]

    def test_accepts_and_deduplicates_mapped_areas(self) -> None:
        self.assertEqual(
            validate_requested_areas(["kitchen", "hall", "kitchen"], self.available),
            ["kitchen", "hall"],
        )

    def test_rejects_unmapped_area(self) -> None:
        with self.assertRaises(web.HTTPBadRequest):
            validate_requested_areas(["bedroom"], self.available)

    def test_rejects_empty_request(self) -> None:
        with self.assertRaises(web.HTTPBadRequest):
            validate_requested_areas([], self.available)

    def test_rejects_non_string_area_id(self) -> None:
        with self.assertRaises(web.HTTPBadRequest):
            validate_requested_areas([123], self.available)


if __name__ == "__main__":
    unittest.main()
