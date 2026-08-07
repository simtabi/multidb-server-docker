# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository scaffold per `docs/SPEC.md` section 15.
- The complete `make verify` acceptance harness, written before the features it
  checks so every subsequent phase has something to heal against.
- `DESIGN.md`: pinned versions with digests, the arm64 extension matrix, the
  capacity truth table, and the decision log.
- `docs/SPEC.md` section 21 (scale, HA, sync) as an approved amendment.
- `scripts/check-env`, enforcing sentinel rejection, the `_FILE` convention,
  supported version menus, port-collision detection, and the prod guards
  (mandatory pooling, UI basic auth, 3-node etcd quorum).
- CI workflows for static analysis and the amd64/arm64 verify matrix.

### Fixed

- All shell is bash 3.2 compatible, so the toolkit runs on stock macOS
  (see `DESIGN.md` D-24).

[Unreleased]: https://github.com/simtabi/db-toolkit-docker/commits/main
