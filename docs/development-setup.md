# Development setup

This repository pins local tool versions with [mise](https://mise.jdx.dev/) in `mise.toml`.

## One-command setup

After installing `mise` itself, run:

```bash
mise install && make bootstrap
```

This installs the pinned versions used by project automation and then verifies that local versions match exactly.

## Keep your environment updated

When tool versions change in `mise.toml`, refresh and verify with:

```bash
mise install --upgrade && make bootstrap
```

## Daily local checks

```bash
make preflight
```

This runs formatting checks, shell linting, config validation, and Bats tests with the same pinned runtime/toolchain.
