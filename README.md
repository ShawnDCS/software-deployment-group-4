# SWE40006 Group 4 — DevOps Pipeline

Number Guessing Game delivered by a Level 4 pipeline:
GitHub → Jenkins (VM1) → Docker Hub → test server (VM2) → production server (VM3, Nginx, Prometheus + Grafana).

| Folder | What it is |
|---|---|
| `app/` | Node.js 22 / Express game, Jest tests, Dockerfile |
| `Jenkinsfile` | Pipeline definition (pipeline as code) |
| `jenkins/` | Custom Jenkins image + Configuration-as-Code |
| `infra/` | Azure CLI scripts that build the 3 VMs (run in order 00 → 04) |
| `deploy/` | Scripts Jenkins runs on the test/prod servers |
| `monitoring/` | Prometheus + Grafana stack for production |
| `docs/` | Versions, problem log, runbook, demo script |
| `evidence/` | Console output captured at each level for the report |

Run the app locally: `cd app && npm ci && npm test && npm start` → http://localhost:3000

## Status (2026-11-10)

| Level | Result | Evidence |
|---|---|---|
| L1 | 3 Azure VMs, Jenkins via JCasC, GitHub with branch protection, manual builds #1–#2 green | `evidence/L1/` |
| L2 | Prometheus targets all UP; Grafana dashboard; `/stress` → game container 100% CPU | `evidence/L2/` |
| L3 | Full pipeline build #3: tests, image on Docker Hub, test deploy + smoke test, prod deploy + public verify | `evidence/L3/` |
| L4 | PR merge → webhook → build #4 "Started by GitHub push", **63 s push → live** | `evidence/L4/` |
| Extras | Blue-green with health-gated switch, automatic rollback on a broken build, manual rollback, Grafana annotations, **0 failed requests** in 1,200+ during switches | `evidence/L5/` |

See `docs/runbook.md` (operations), `docs/demo-script.md` (15-min demo), `docs/problem-log.md` (23 problems + open items).
