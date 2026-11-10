# Demo script — 15 minutes (Week 11)

Prep (before the slot, ~10 min early):
1. `sh infra/start-all.sh` (if stopped). Open tabs: game, Grafana dashboard, Jenkins `guessgame` job,
   GitHub repo, Docker Hub repo. Log in to Jenkins and Grafana.
2. Make sure prod is on **v1.0, range 1–100** and play one game so a best score exists.
3. Terminal A: `ssh -F infra/ssh_config g4-prod` · Terminal B: repo root on `main`, pulled.
4. Set Grafana time range to "Last 15 minutes".

| Time | Level | Show | Say |
|---|---|---|---|
| 0:00–1:30 | — | Architecture slide | GitHub → Jenkins (VM1) → Docker Hub → test VM2 → prod VM3 (Nginx blue/green) + Prometheus/Grafana. Everything is code: JCasC, Jenkinsfile, infra scripts. |
| 1:30–3:30 | L1 | Azure VM list; GitHub branch protection; Jenkins job + a green build's stage view | Three separate servers; test has no public IP; Jenkins reaches test/prod over the private network with its own SSH key. |
| 3:30–5:30 | L2 | Grafana dashboard. Open `http://<prod>/stress` in a new tab | CPU panel and "Container CPU" for the live colour climb to ~100% of one vCPU within ~30 s. |
| 5:30–6:30 | L3 | Play the game on the public URL; point at footer (v1.0, build, commit, prod-blue/green) | Deployed only by the pipeline; smoke test played a real game on the test server first. |
| 6:30–7:00 | L4 | Terminal A: start the zero-downtime loop: `while true; do curl -s -o /dev/null -w '%{http_code} ' http://localhost/health; sleep 0.5; done` | Watch: it must never print anything but 200. |
| 7:00–7:30 | L4 | Terminal B: edit `app/src/config.js`: `NUMBER_RANGE_MAX: 50`, `VERSION: '2.0'`; `git commit -am "Reduce number range to 1-50" && git push origin main` | (Admin can push to `main`; teammates go through PRs.) |
| 7:30–11:30 | L4 | Jenkins: build starts by itself within seconds ("Started by GitHub push"). Walk the stages as they run | Tests → image → Docker Hub → test VM → smoke test → prod blue-green. |
| 11:30–12:30 | Extra | Deploy Prod log lines: *Starting green container… Health check passed… Switching Nginx to green… Reload complete* | Terminal A loop: still all 200 — zero downtime. |
| 12:30–13:30 | L4 | Refresh game: footer **v2.0**, new build #, "between 1 and 50"; best score still there | State survives because both colours mount `/var/lib/app-data`. |
| 13:30–14:30 | Extra | Grafana: red "Deployments" annotation at the switch time; earlier ROLLBACK annotation from the broken-build test | Broken build never reached users; rollback is automatic. |
| 14:30–15:00 | — | — | Wrap up: problems we hit (problem log) and what we'd do next (NAT gateway, HTTPS, bigger prod VM). |

**Notes**
- The test server listens on port **3000** (the brief said 3002; changed — see problem log #1).
  `ssh -F infra/ssh_config g4-test curl -s localhost:3000/health`
- If the webhook is slow, show GitHub → Settings → Webhooks → Recent deliveries (200).
- Fallback if Jenkins is slow: show `evidence/L4/` logs and the measured push→live time.
- After the demo: revert config.js (100 / "1.0") via PR so the next rehearsal starts from v1.0.
