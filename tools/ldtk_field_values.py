"""Write the editor value and exported value together, so LDtk saves keep overrides."""
from copy import deepcopy

VALUE_IDS = {"String":"V_String", "Multilines":"V_String", "FilePath":"V_String",
             "Bool":"V_Bool", "Int":"V_Int", "Float":"V_Float"}


def set_value(field: dict, value, kind: str | None = None) -> None:
    kind = kind or field["__type"]
    if kind not in VALUE_IDS:
        raise ValueError(f"Campo LDtk nao escalar ou nao suportado: {kind}")
    field["__value"] = deepcopy(value)
    field["realEditorValues"] = [{"id":VALUE_IDS[kind], "params":[deepcopy(value)]}]


def preserve_editor_values(instance: dict) -> None:
    for field in instance.get("fieldInstances", []):
        if field["__type"] in VALUE_IDS and field.get("__value") is not None:
            set_value(field, field["__value"])
