import json
from pathlib import Path

from models import NutritionProfileRequest, NutritionProfileResponse


def test_contract_fixture_validates_against_models() -> None:
    contract_path = Path(__file__).resolve().parents[2] / "Contracts" / "nutrition_profile_contract.json"
    contract = json.loads(contract_path.read_text())

    request = NutritionProfileRequest.model_validate(contract["request"])
    response = NutritionProfileResponse.model_validate(contract["response"])

    assert request.schema_version == 1
    assert response.schema_version == 1
    assert response.daily_calories == 1650
