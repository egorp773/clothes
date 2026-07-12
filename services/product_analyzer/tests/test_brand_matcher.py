from app.ocr.brand_matcher import BrandMatcher


def test_ocr_brand_corrections():
    matcher = BrandMatcher(threshold=70)
    assert matcher.match(["N1KE"]).brand_id == "nike"
    assert matcher.match(["CARHART"]).brand_id == "carhartt"
    assert matcher.match(["STUS5Y"]).brand_id == "stussy"


def test_unknown_brand_remains_empty():
    assert BrandMatcher().match(["100% COTTON", "SIZE M"]) is None
