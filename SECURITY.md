# Security policy

## Reporting a vulnerability

Don't open a public issue. Use GitHub's private
[security advisory](https://github.com/gsamuele78/Infra-Iam-PKI/security/advisories/new)
for this repository, or contact the maintainer directly. Include:

- the affected file or service and the version (git tag or commit);
- steps to reproduce, or a proof of concept;
- the impact if you know it (secret exposure, certificate issuance by an
  unauthorized party, SSO bypass, container escape).

Expect a first answer within 5 business days.

### Suspected CA compromise

If you believe the CA keys, the provisioner passwords or a one-time token
leaked, contact the maintainer directly and immediately; don't wait for the
advisory flow. The response is to stop `step-ca`, revoke what was issued
and re-enroll the hosts (`doc/infra-pki/`).

## Scope

This repo ships infrastructure configuration: Docker Compose files,
Dockerfiles, Caddy/Keycloak/OOD configuration and operator scripts.
Vulnerabilities in the upstream images and packages (step-ca, Keycloak,
PostgreSQL, Caddy, Open OnDemand, RStudio, oauth2-proxy) go to their
projects. The RStudio stack is vendored from
[R-studioConf](https://github.com/gsamuele78/R-studioConf): report issues
in it there.

## Baseline

- The CA API is reachable only through the Caddy L4 proxy, restricted to
  `ALLOWED_IPS`; PostgreSQL ports are never published.
- Trust is bootstrapped by fingerprint (`step ca root --fingerprint`), never
  with `--insecure`. Hosts enroll with a one-time token and renew with SSH-POP.
- Every image is pinned, every container has memory and CPU limits, and no
  service mounts the Docker socket except through `docker-socket-proxy`.
- Passwords are written to files, never passed on a command line.
- `.env` files and site data (`config/site/`) are gitignored; the validator
  fails if one is tracked.

## Supported versions

Only the latest tag (see `CHANGELOG.md`). There is no long-term branch.
