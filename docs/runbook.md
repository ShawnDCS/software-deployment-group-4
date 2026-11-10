# Runbook — SWE40006 Group 4 pipeline

Everything below is run from the repo root on the team laptop unless it says otherwise.
SSH shortcuts: `ssh -F infra/ssh_config g4-jenkins | g4-prod | g4-test` (g4-test jumps through Jenkins).

## Addresses

| What | URL / address |
|---|---|
| Game (production) | http://swe40006-g4-game.koreacentral.cloudapp.azure.com |
| Grafana | http://swe40006-g4-game.koreacentral.cloudapp.azure.com/grafana/ (also `:3030/grafana/`) |
| Jenkins | http://swe40006-g4-jenkins.koreacentral.cloudapp.azure.com:8080 (team IPs only) |
| GitHub | https://github.com/ShawnDCS/software-deployment-group-4 |
| Docker Hub | https://hub.docker.com/r/shawnraj07/guessgame |
| VM private IPs | Jenkins 10.40.1.10 · test 10.40.1.20 · prod 10.40.1.30 |

## Passwords (never stored in git)

- Jenkins `admin`: `ssh -F infra/ssh_config g4-jenkins sudo grep PASSWORD /opt/jenkins/.env`
- Grafana `admin`: `ssh -F infra/ssh_config g4-prod sudo grep PASSWORD /opt/monitoring/.env`

## Daily start / stop (saves student credit)

```sh
sh infra/start-all.sh     # ~2 min; Jenkins, monitoring and the game restart automatically
sh infra/stop-all.sh      # deallocate; disks + IPs still cost ~$0.50/day
```
VMs also auto-shutdown at 23:00 Malaysia time. Public IPs/DNS names never change.

## Deploy

Push or merge to `main` → GitHub webhook → Jenkins runs Checkout → Test → Build → Push →
Deploy Test → Smoke Test → Deploy Prod (blue-green) → Verify. Nothing manual.

Manual re-run: Jenkins → `guessgame` → *Build Now*, or `sh infra/jenkins-build.sh`.

## What is live?

```sh
ssh -F infra/ssh_config g4-prod 'cat /var/lib/app-deploy/current-release; docker ps -a --filter name=guessgame'
```
The page footer also shows version, build, commit and colour.

## Roll back (instant, to the previous build)

```sh
cat deploy/lib.sh deploy/rollback.sh | ssh -F infra/ssh_config g4-prod sudo -u deploy sh -s
```
Restarts the stopped previous colour, health-checks it, switches Nginx, updates the state file,
adds a Grafana annotation. To roll forward again, run it a second time or re-run the pipeline.

## Troubleshooting

| Symptom | Check |
|---|---|
| Game returns 502 | `ssh g4-prod 'docker ps -a; sudo nginx -t; cat /etc/nginx/conf.d/guessgame-upstream.conf'` — upstream port must match a running container (blue 3001, green 3002) |
| Pipeline fails at Push | Docker Hub token in `/opt/jenkins/.env` expired → new token, then `cd /opt/jenkins && docker compose up -d --force-recreate` |
| Push to GitHub doesn't start a build | GitHub repo → Settings → Webhooks → Recent deliveries (must be 200). If GitHub's IP ranges changed: re-run `infra/01-network.sh` |
| Can't SSH / open Jenkins | Your public IP changed or isn't in `TEAM_IPS` (`infra/config.sh`); `curl ifconfig.me`, add it, re-run `01-network.sh` |
| Prod slow / swapping | Grafana "Memory" + "Swap used" panels. VM3 has 1 GB; resize to B2als_v2 if needed (problem log #9) |
| Grafana unreachable on :3030 | Some networks block the port; use `/grafana/` on port 80 |
