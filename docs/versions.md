# Versions

Exact versions used by the project. The brief's version numbers are outdated; these replace them.
Never use `latest` — every image/package below is pinned.

## Application (Phase 0, recorded 2026-11-10)

| Component | Version | Notes |
|---|---|---|
| Node.js (base image) | `node:22-alpine` → Node v22.23.4 at build time | Brief said Node 20; 20 is end-of-life, 22 is the current LTS line |
| Express | 5.3.0 | Brief said Express 4; 5.x is the current stable major |
| prom-client | 15.1.3 | npm marks it deprecated in favour of `@prometheus-io/client` (same project, renamed) — see problem log |
| Jest | 30.5.2 | dev only |
| supertest | 7.3.2 | dev only |
| Docker (local dev, Docker Desktop) | Engine 29.8.2 | |
| Docker Engine on VMs (docker-ce apt repo) | 29.9.3, Compose 5.7.0 | installed by `infra/03-bootstrap-common.sh` |

## Infrastructure (filled in during Phases 1–2)

| Component | Version |
|---|---|
| Ubuntu Server | 22.04 LTS gen2 (image 22.04.202610220), region koreacentral |
| Jenkins | `jenkins/jenkins:2.580.2-lts-jdk21` (current LTS; the jdk17 line stopped updating in March 2026). Plugins pinned in `jenkins/plugins.txt` |
| Docker CLI inside Jenkins | `docker:29.9.3-cli` (static binary + buildx) |
| Prometheus | `prom/prometheus:v3.15.1` (3.16.0 was 5 days old; took latest patch of previous minor) |
| Grafana | `grafana/grafana:13.2.5` (13.3.0 was a fresh .0 release) |
| Node Exporter | `prom/node-exporter:v1.12.1` |
| cAdvisor | `ghcr.io/google/cadvisor:v0.60.6` (images moved from gcr.io to ghcr.io) |
| Nginx | 1.30.6 from the nginx.org stable apt repo, `apt-mark hold` (Ubuntu's own package is 1.18) |
