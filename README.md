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
