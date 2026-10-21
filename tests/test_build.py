import csv
import html
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build


class BuilderRoutingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.contacts = build.load_contacts(build.BOOKINGS)

    def roster(self, **changes):
        row = dict(slug="test-builder", first_name="Avery", company="Test Builder",
                   province="Ontario", btr_contact="bob", first_drop="no")
        row.update(changes)
        path = self.root / "builders.csv"
        with path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=row.keys())
            writer.writeheader()
            writer.writerow(row)
        return path

    def test_calendar_follows_assigned_contact_not_province(self):
        for rep in ("bob", "colin"):
            with self.subTest(rep=rep):
                rows = build.load_builders(self.roster(btr_contact=rep), self.contacts)
                self.assertEqual(rows[0]["booking_url"], self.contacts[rep]["booking_url"])

    def test_invalid_assignment_preserves_previous_build(self):
        output = self.root / "dist"
        output.mkdir()
        previous = output / "index.html"
        previous.write_text("previous build")
        for rep in ("", "bbo"):
            with self.subTest(rep=rep):
                with patch.object(build, "DATA", self.roster(btr_contact=rep)), patch.object(build, "DIST", output):
                    with self.assertRaises(ValueError):
                        build.main()
                self.assertEqual(previous.read_text(), "previous build")

    def test_unsafe_slug_is_rejected(self):
        for slug in ("../outside", "builder/child", "Builder Name"):
            with self.subTest(slug=slug), self.assertRaises(ValueError):
                build.load_builders(self.roster(slug=slug), self.contacts)

    def test_campaign_uses_selected_design_and_review_keeps_both(self):
        templates = [Path("template.html"), Path("template-b.html")]
        plan = build.plan_pages([{"slug": "builder"}], [{"slug": "sample"}], templates)
        self.assertEqual([(slug, tpl.name) for slug, tpl, _ in plan], [
            ("builder", "template.html"), ("sample", "template.html"), ("sample-b", "template-b.html")])

    def test_duplicate_or_reserved_routes_are_rejected(self):
        templates = [Path("template.html"), Path("template-b.html")]
        for campaign in ([{"slug": "same"}, {"slug": "same"}], [{"slug": "assets"}], [{"slug": "sample-b"}]):
            with self.subTest(campaign=campaign), self.assertRaises(ValueError):
                build.plan_pages(campaign, [{"slug": "sample"}], templates)

    def test_company_and_calendar_are_html_escaped(self):
        row = build.load_builders(self.roster(company='Homes & Builders "North"'), self.contacts)[0]
        rendered = build.render('<a href="{{booking_url}}">{{company}}</a>', row)
        self.assertIn('Homes &amp; Builders &quot;North&quot;', rendered)
        self.assertIn('href="' + html.escape(self.contacts["bob"]["booking_url"], quote=True) + '"', rendered)
        self.assertNotIn("{{", rendered)


if __name__ == "__main__":
    unittest.main()
