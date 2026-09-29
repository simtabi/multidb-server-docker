# Security policy

## Reporting a vulnerability

The preferred channel is GitHub private vulnerability reporting: open a private report at <https://github.com/simtabi/multidb-server-docker/security/advisories/new>. The report stays attached to the repository, with a draft advisory and a CVE request path. Email **security@simtabi.com** if you do not use GitHub.

Report security issues privately to **security@simtabi.com**. Do not open a
public issue for a vulnerability.

Include the affected image or script, the version or digest, reproduction
steps, and the impact you observed. We aim to acknowledge within three working
days and to ship a fix or a documented mitigation before any public
disclosure.

## Supported versions

The most recent minor release of multidb-server is supported. Engine images track
upstream PostgreSQL, MySQL, and MariaDB support windows; an engine major that
upstream has ended support for is removed from the version menu at the next
minor release, announced in `CHANGELOG.md`.

## Verifying what you run

Every published image carries a build-provenance attestation and an SBOM
generated in CI.

```bash
gh attestation verify oci://ghcr.io/simtabi/multidb-server-pg:17 --owner simtabi
```

Images are pinned by digest throughout this repository. If a digest in
`.env.example` or a compose file does not match what you pulled, treat that as
a security issue and report it.

## Security posture

- No ports are published by default; apps join the internal network by service name.
- Secrets are passed only via the `_FILE` convention or Docker secrets, never as
  plain environment values, and never baked into an image layer.
- `make check-env` refuses to start the stack with sentinel or placeholder
  passwords.
- Containers run with `cap_drop: ALL`, `no-new-privileges`, and resource limits.
- Database TLS uses a toolkit-internal CA created by `make certs`; the prod
  profile enforces TLS and refuses plaintext transport.

Reports of misconfiguration in these defaults are in scope and welcome.
