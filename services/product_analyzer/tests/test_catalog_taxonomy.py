from __future__ import annotations

import numpy as np

from app.catalog import (
    ALLOWED_ATTRIBUTES,
    CATEGORIES,
    CATEGORY_ATTRIBUTES,
    CATEGORY_MATERIALS,
    NORMALIZED_CATEGORIES,
    attribute_options_for,
    normalize_category,
)
from app.enrichment.visual_attributes import VisualAttributeSuggester


def test_taxonomy_has_unique_complete_canonical_categories():
    item_types = [definition.item_type for definition in CATEGORIES]
    assert len(item_types) == len(set(item_types))

    canonical = set(NORMALIZED_CATEGORIES.values())
    assert set(item_types) == set(NORMALIZED_CATEGORIES)
    assert canonical == set(CATEGORY_ATTRIBUTES)
    assert canonical == set(CATEGORY_MATERIALS)
    for category, attributes in CATEGORY_ATTRIBUTES.items():
        assert attributes, category
        assert set(attributes) <= set(ALLOWED_ATTRIBUTES), category
        assert set(CATEGORY_MATERIALS[category]) <= set(
            ALLOWED_ATTRIBUTES["material"]
        ), category


def test_sweater_and_other_frequent_aliases_do_not_collapse_to_hoodie():
    assert normalize_category("свитер") == "sweater"
    assert normalize_category("sweater") == "sweater"
    assert normalize_category("джемпер") == "sweater"
    assert normalize_category("худи") == "hoodie"
    assert normalize_category("блузка") == "blouse"
    assert normalize_category("пуховик") == "puffer"
    assert NORMALIZED_CATEGORIES["sweater"] == "sweater"


def test_common_marketplace_types_have_dedicated_classifier_prompts():
    required = {
        "tank_top",
        "long_sleeve",
        "polo",
        "blouse",
        "sweater",
        "cardigan",
        "turtleneck",
        "blazer",
        "puffer",
        "trench",
        "joggers",
        "leggings",
        "underwear",
        "swimwear",
        "heels",
        "loafers",
        "slippers",
        "wallet",
        "cap",
        "beanie",
        "hat",
        "gloves",
        "eyewear",
        "watch",
        "bracelet",
        "brooch",
    }
    definitions = {definition.item_type: definition for definition in CATEGORIES}
    assert required <= definitions.keys()
    for item_type in required:
        prompts = definitions[item_type].prompts
        assert len(prompts) >= 2
        assert any(prompt.isascii() for prompt in prompts)


def test_bracelet_materials_include_metals_and_exclude_clothing_fabrics():
    materials = set(CATEGORY_MATERIALS["bracelet"])
    assert {"metal", "steel", "silver", "gold"} <= materials
    assert "denim" not in materials
    assert "cotton" not in materials
    assert CATEGORY_ATTRIBUTES["bracelet"] == ("material", "style")


def test_category_specific_closures_and_styles_match_publication_ui():
    assert attribute_options_for("shoes", "closure") == (
        "none", "laces", "zip", "velcro", "buckle",
    )
    assert "buttons" not in attribute_options_for("bag", "closure")
    assert "streetwear" not in attribute_options_for("bracelet", "style")
    assert attribute_options_for("watch", "style") == (
        "classic", "sport", "casual", "smart", "luxury",
    )
    assert "unknown" in attribute_options_for("sweater", "material")


def test_visual_material_suggestions_use_category_specific_options():
    class Classifier:
        def __init__(self):
            self.material_options: set[str] = set()

        def score_text_options(self, embedding, options, temperature=12.0):
            values = list(options)
            if "metal" in values:
                self.material_options = set(values)
            return {value: 0.9 if value == "metal" else 0.01 for value in values}

    classifier = Classifier()
    suggestions = VisualAttributeSuggester(classifier).suggest(
        np.asarray([1.0, 0.0], dtype=np.float32),
        "bracelet",
    )

    material = next(item for item in suggestions if item.key == "material")
    assert material.value == "metal"
    assert "cotton" not in classifier.material_options
    assert "denim" not in classifier.material_options
