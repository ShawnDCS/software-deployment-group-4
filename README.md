# SWE40006 Group 4 — DevOps Pipeline

A **Number Guessing Game** delivered by a fully automated pipeline:
push code to GitHub → Jenkins tests and packages it → it is tried on a private test server →
it goes live on the production server with zero downtime. A Grafana dashboard monitors production.

| | Link |
|---|---|
| Play the game | https://swe40006-g4-game.koreacentral.cloudapp.azure.com |
| Monitoring dashboard (Grafana) | https://swe40006-g4-game.koreacentral.cloudapp.azure.com/grafana/ |
| Build server (Jenkins, team IPs only) | http://swe40006-g4-jenkins.koreacentral.cloudapp.azure.com:8080 |
| Docker images | https://hub.docker.com/r/shawnraj07/guessgame |

> The servers switch off automatically at **23:00 Malaysia time** every night to save credit.
> If a link doesn't load, start them first (Part 2, step 1).

---

## Part 1 — Just looking (anyone, no setup)

1. **Play:** open the game link above in any browser or phone. Click **New Game**, type a number
   from 1 to 100, press **Guess**. You have 10 tries; the fewest tries in a win becomes the best score.
2. **See which version is live:** read the footer at the bottom of the page, e.g.
   `v1.0 · Build #6 · Commit: 3beb658 · Host: prod-blue (blue)`.
3. **See the monitoring:** open the Grafana link and log in (ask a team member for the password).
   The *Guessgame Production* dashboard opens by itself.
4. **Make the CPU graph jump:** open `https://swe40006-g4-game.koreacentral.cloudapp.azure.com/stress`
   in a new tab, wait ~30 seconds, and watch *CPU usage* and *Container CPU* rise in Grafana.

---

## Part 2 — Team member: everyday use

Everything below runs in a terminal **from this repository folder** on the team laptop
(it has the SSH key `~/.ssh/swe40006_g4_ed25519` and the Azure CLI logged in).

### Step 1 — Start the servers (about 2 minutes)
```sh
az login                 # only if `az account show` says you're logged out (MFA may be asked)
sh infra/start-all.sh
```
Jenkins, monitoring, Nginx and the game all come back by themselves. Addresses never change.

### Step 2 — Get the passwords (never stored in git)
```sh
ssh -F infra/ssh_config g4-prod    sudo grep PASSWORD /opt/monitoring/.env   # Grafana, user: admin
ssh -F infra/ssh_config g4-jenkins sudo grep PASSWORD /opt/jenkins/.env      # Jenkins, user: admin
```

### Step 3 — Release a change (fully automatic)
```sh
git checkout main && git pull
git checkout -b my-change
# ...edit files, e.g. app/src/config.js...
cd app && npm ci && npm test && cd ..       # optional: run the tests locally first
git commit -am "Describe the change"
git push -u origin my-change
gh pr create --base main                    # a teammate approves, then merge on GitHub
```
Merging into `main` starts Jenkins within seconds. Watch it at Jenkins → `guessgame`.
The 8 stages: **Checkout → Test → Build → Push → Deploy Test → Smoke Test → Deploy Prod → Verify**.
About a minute later the new build is live (check the page footer). If any stage fails,
production is not touched.

### Step 4 — Run the pipeline again without a code change
Jenkins → `guessgame` → **Build Now**, or:
```sh
sh infra/jenkins-build.sh
```

### Step 5 — Roll back to the previous build (about 15 seconds)
```sh
cat deploy/lib.sh deploy/rollback.sh | ssh -F infra/ssh_config g4-prod sudo -u deploy sh -s
```
Run it again to roll forward. A rollback marker appears in Grafana.

### Step 6 — Check what is running
```sh
ssh -F infra/ssh_config g4-prod 'cat /var/lib/app-deploy/current-release; docker ps -a'
ssh -F infra/ssh_config g4-test 'docker ps'          # test server (reached through Jenkins)
```

### Step 7 — Stop the servers when you're done
```sh
sh infra/stop-all.sh
```
Stopped servers cost only ~$0.50/day (disks + addresses) instead of ~$2.50/day.

---

## Part 3 — Presentation demo (Level 4)

Full minute-by-minute script: [`docs/demo-script.md`](docs/demo-script.md). In short:
1. Show the live site on **v1.0, range 1–100**.
2. In `app/src/config.js` set `NUMBER_RANGE_MAX: 50` and `VERSION: '2.0'`.
3. `git commit -am "Reduce number range to 1-50" && git push origin main`
4. Jenkins starts by itself; ~1 minute later the site shows **v2.0** and "between 1 and 50",
   with the best score kept and zero failed requests.

---

## Part 4 — Run the app on your own computer

Needs Node.js 22 and (optionally) Docker.
```sh
cd app
npm ci
npm test          # 35 tests + coverage report (must stay ≥ 80%)
npm start         # http://localhost:3000
```
With Docker:
```sh
docker build -t guessgame:local app/
docker run --rm -p 3000:3000 guessgame:local
```

---

## Part 5 — Rebuild everything from scratch

Only needed if the Azure resources are deleted. Run in order; each script explains itself at the top.

| Step | Command | What it does |
|---|---|---|
| 0 | `sh infra/00-preflight.sh` | Read-only checks: login, region policy, quotas, VM sizes |
| 1 | `sh infra/01-network.sh` | Resource group, network, firewalls |
| 2 | `sh infra/02-vms.sh` | The 3 Ubuntu VMs (billing starts here) |
| 3 | `sh infra/03-bootstrap.sh` | Docker, swap, `deploy` user |
| 4 | `sh infra/04-jenkins.sh` | Jenkins (configured as code) + its SSH access to test/prod |
| 5 | `sh infra/05-monitoring.sh` | Prometheus + Grafana on production |
| 6 | `sh infra/06-prod-nginx.sh` | Nginx on production |
| 7 | `sh infra/07-https.sh` | Free HTTPS certificate + redirect |

Then: put a Docker Hub access token in `/opt/jenkins/.env` on the Jenkins VM
(`DOCKERHUB_TOKEN=...`, then `docker compose up -d --force-recreate` in `/opt/jenkins`),
and add the GitHub webhook to `http://<jenkins-address>:8080/github-webhook/`.
Settings such as region, VM sizes and allowed IPs are in `infra/config.sh`.

---

## Part 6 — Troubleshooting

| Problem | Fix |
|---|---|
| Site doesn't load | Servers are probably off → `sh infra/start-all.sh` |
| Can't SSH or open Jenkins | Your internet IP isn't allowed. `curl ifconfig.me`, add it to `TEAM_IPS` in `infra/config.sh`, run `sh infra/01-network.sh` |
| `az` says MFA / AADSTS50076 | Run `az login` again (the error prints the exact command) |
| Pipeline fails at **Push** | Docker Hub token expired → create a new one and update `/opt/jenkins/.env` |
| A push doesn't start Jenkins | GitHub → Settings → Webhooks → Recent deliveries must show 200; the Jenkins VM must be running |
| Game shows 502 | `ssh -F infra/ssh_config g4-prod 'docker ps -a; sudo nginx -t'` — or roll back (Part 2, step 5) |

More detail: [`docs/runbook.md`](docs/runbook.md).

---

## What's where

| Folder | Contents |
|---|---|
| `app/` | Game source (Node.js 22 / Express), tests, Dockerfile |
| `Jenkinsfile` | The pipeline, as code |
| `jenkins/` | Custom Jenkins image, plugins, Configuration-as-Code |
| `infra/` | Azure scripts (00 → 07), start/stop, SSH shortcuts |
| `deploy/` | Test deploy, smoke test, blue-green prod deploy, rollback |
| `nginx/` | Production web server config |
| `monitoring/` | Prometheus, Grafana (dashboard included), exporters |
| `docs/` | Runbook, demo script, problem log (25 problems), versions |
| `evidence/` | Console output captured at every level for the report |

## Status

| Level | Result |
|---|---|
| L1 | 3 Azure VMs, Jenkins as code, GitHub with branch protection |
| L2 | Prometheus targets all UP; `/stress` → game container 100% CPU on the dashboard |
| L3 | 8-stage pipeline deploys the game publicly |
| L4 | Push → live in **63 s**, triggered by GitHub webhook |
| Extras | Blue-green with **0 failed requests in 1,200+**, automatic + manual rollback, Grafana deploy markers, HTTPS |
