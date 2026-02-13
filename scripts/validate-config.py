#!/usr/bin/env python3
"""Validate infrastructure config files using repository JSON Schema."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

ASSIGNMENT_RE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        match = ASSIGNMENT_RE.match(line)
        if not match:
            raise ValueError(f"{path}:{line_no}: invalid assignment syntax")

        key, raw_value = match.groups()
        value = raw_value.strip()

        if value and value[0] in {'"', "'"}:
            quote = value[0]
            if len(value) < 2 or value[-1] != quote:
                raise ValueError(f"{path}:{line_no}: unclosed quoted value")
            value = value[1:-1]

        if "${" in value or "$(" in value or "`" in value:
            raise ValueError(f"{path}:{line_no}: interpolation is not allowed")

        data[key] = value

    return data


def _type_ok(instance: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(instance, dict)
    if expected == "string":
        return isinstance(instance, str)
    return True


def _validate(instance: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    errors: list[str] = []

    expected_type = schema.get("type")
    if expected_type and not _type_ok(instance, expected_type):
        return [f"{path}: expected {expected_type}"]

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                errors.append(f"{path}: missing required property '{key}'")

        additional_properties = schema.get("additionalProperties", True)
        properties = schema.get("properties", {})
        if additional_properties is False:
            for key in instance:
                if key not in properties:
                    errors.append(f"{path}: unexpected property '{key}'")

        for key, prop_schema in properties.items():
            if key in instance:
                errors.extend(_validate(instance[key], prop_schema, f"{path}.{key}"))

    if isinstance(instance, str):
        enum = schema.get("enum")
        if enum is not None and instance not in enum:
            errors.append(f"{path}: '{instance}' is not one of {enum}")

        const = schema.get("const")
        if const is not None and instance != const:
            errors.append(f"{path}: '{instance}' must equal '{const}'")

        min_length = schema.get("minLength")
        if min_length is not None and len(instance) < min_length:
            errors.append(f"{path}: length must be >= {min_length}")

        pattern = schema.get("pattern")
        if pattern is not None and re.search(pattern, instance) is None:
            errors.append(f"{path}: '{instance}' does not match /{pattern}/")

    not_schema = schema.get("not")
    if not_schema is not None:
        if not _validate(instance, not_schema, path):
            errors.append(f"{path}: value matches a forbidden schema")

    for branch in schema.get("allOf", []):
        errors.extend(_validate(instance, branch, path))

    if_clause = schema.get("if")
    then_clause = schema.get("then")
    if if_clause is not None and then_clause is not None:
        if not _validate(instance, if_clause, path):
            errors.extend(_validate(instance, then_clause, path))

    return errors


def validate_profile(path: pathlib.Path, schema: dict[str, Any]) -> None:
    payload = parse_env_file(path)
    payload["PROFILE_NAME"] = path.stem
    errors = _validate(payload, schema)
    if errors:
        raise ValueError(f"{path}: schema validation failed: {'; '.join(errors)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate env profile files")
    parser.add_argument("--schema", default="schemas/env-profile.schema.json")
    parser.add_argument("profiles", nargs="*")
    args = parser.parse_args()

    schema = json.loads(pathlib.Path(args.schema).read_text(encoding="utf-8"))
    profile_paths = [pathlib.Path(p) for p in args.profiles] or sorted(pathlib.Path("env").glob("*.env"))

    if not profile_paths:
        raise ValueError("no profile files found")

    for profile in profile_paths:
        validate_profile(profile, schema)
        print(f"validated {profile}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as err:
        print(f"validation error: {err}", file=sys.stderr)
        raise SystemExit(1)
