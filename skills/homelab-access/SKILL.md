---
name: homelab-access
description: How to reach the homelab hosts — the two SSH accounts (s vs claude-ops) and what each can do, aliases, per-host shell quirks, and what is deliberately NOT reachable. Load before any command that touches a VM, the firewall, or the NAS.
---

# Homelab Access

Agents run on the **coding VM** (`192.168.178.73`, hostname `code`, user `s`). Every host below
is reachable over SSH with the **`~/.ssh/claude-ops`** ed25519 key via aliases in `~/.ssh/config`.
**Use the alias, never a raw IP** — a bare `ssh root@<ip>` offers the default `id_ed25519` key
instead and fails `Permission denied (publickey)`, which looks like a revoked grant but is not.

Inventory source of truth: `Server/server/coding/hosts.txt` (gitignored; `.example` is the
committed template). The `# >>> claude-ops <alias> >>>` blocks in `~/.ssh/config` are generated
by `Server/server/coding/setup-ssh-keys.sh` — edit `hosts.txt` and re-run it rather than
hand-editing those blocks, or the two drift.

## Three accounts, different powers — pick the right one

The single most useful thing on this page, and the easiest to get wrong: **three accounts are
reachable on every Linux VM with the same `claude-ops` key, and they are not a hierarchy.**

| | `s` — alias `<host>-vm` | `claude-ops` — alias `<host>-ops` | `svc-ops` — alias `<host>-svc` |
|---|---|---|---|
| In `docker` group | ✅ plain `docker` works | ❌ `permission denied … docker.sock` | ❌ (but `sudo docker` works) |
| `DOCKER_HOST=ssh://` | ✅ **use this** | ❌ | ❌ |
| Passwordless sudo | ❌ prompts | ✅ scoped | ✅ **`(ALL) NOPASSWD: ALL`** |
| sudo scope | — | only `/usr/bin/docker`, `/usr/bin/systemctl`, `/usr/local/bin/docker-compose` | **everything — full root** |

- **Container reads → `scripts/homelab ps|logs`** (runs `dockerq` via `<host>-ops`); **deploy/restart →
  `scripts/homelab deploy|restart`** (Semaphore `stack-deploy` template) — prefer these over raw
  `docker`/`DOCKER_HOST=ssh://` for anything scripted or repeatable.
- **`systemctl` / quick service work → `<host>-ops`.**
- **Anything else needing root** — editing `/etc`, `apt`, mounts, arbitrary files — **→ `<host>-svc`.**
  **Recorded root:** every `<host>-svc` session is I/O-recorded (`/var/log/sudo-io/svc-ops/`,
  `/var/log/sudo-svc-ops.log`) and every execve is audited (`ausearch --input-logs -k
  svc_ops_exec -ts recent`); use it only for what `scripts/homelab`/`dockerq`/`<host>-ops` can't
  do, and say why in the commit/report. `journalctl` is **not** granted to `claude-ops` — use
  `<host>-svc` for journal reads.
  **`coding.vm` exception:** no `claude-ops` user and no `coding-ops`/`coding-svc` aliases exist
  there — root is `ssh -i ~/.ssh/claude-ops svc-ops@127.0.0.1`.

```bash
DOCKER_HOST=ssh://cloud-vm docker compose ps          # as s
ssh cloud-ops 'sudo docker ps'                        # as claude-ops — the `sudo` is REQUIRED
ssh cloud-ops 'sudo -n systemctl restart docker'      # as claude-ops
ssh media-svc 'sudo -n sed -i ... /etc/fstab'         # as svc-ops (full root)
```

### Three failure messages and what they actually mean

| What you see | What it means | Fix |
|---|---|---|
| `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock` | you ran a bare `docker …` as `claude-ops`, which is **not in the `docker` group** | prefix `sudo`, or use `<host>-vm` |
| `sudo: a terminal is required to read the password` | you ran something **outside** `claude-ops`'s three-binary sudo scope. It is *not* a TTY problem — no `-t`/`-S` will help | use `<host>-svc` |
| `/proc/<pid>/fdinfo/N: Permission denied`, or `wchan` reading `0` | you are inspecting a **container** process's `/proc` through `docker exec -u 0`; the container has no `CAP_SYS_PTRACE` | read `/proc` from the **host** as `<host>-svc` |

**Debugging a hung process in a container: go in through the host, not through `docker exec`.**
`docker exec -u 0 <ctr> cat /proc/<pid>/fdinfo/3` is refused even as uid 0, so the most
diagnostic fields are exactly the ones you cannot see from inside. From `<host>-svc`,
`sudo -n ps -eo pid,etime,pcpu,stat,wchan:24,args` finds the host-side PID and its kernel wait
channel in one shot, and `/proc/<pid>/task/*/wchan`, `/proc/<pid>/task/*/stat` and
`/proc/<pid>/fdinfo/*` then tell you whether it is blocked on I/O (`D` state, `rpc_wait_*` on
NFS) or deadlocked in userspace (`S` state, `futex_do_wait`), and how far its input/output fds
actually got. This is what separates "stuck on the NAS" from "stuck on itself" — worth knowing
here, because this homelab has a real NFS-wedge failure mode that looks identical from outside.

**"Claude cannot sudo" is false.** It is true only for `s`. `svc-ops` has unrestricted
passwordless root on all four Linux VMs (verified 2026-07-20), and it is what Ansible
playbooks with `become: true` should run as — no become password needed. **Before filing
anything in `manual_todo.md` as user-only because it "needs sudo", check `svc-ops` first.**
Genuinely manual = Proxmox, the NAS, Fritzbox, Tailscale admin, and other external accounts —
not root on the VMs.

## Hosts

| Alias | Address | Users | Shell | Status | Notes |
|---|---|---|---|---|---|
| `cloud-{vm,ops,svc}` | .159 | `s` / `claude-ops` / `svc-ops` | bash | ✅ | Jellyfin/*arr, NFS client, LidMeta, Harbor |
| `manage-{vm,ops,svc}` | .160 | `s` / `claude-ops` / `svc-ops` | bash | ✅ | Authelia, Semaphore, Ansible control |
| `media-{vm,ops,svc}` | .161 | `s` / `claude-ops` / `svc-ops` | bash | ✅ | Media stack |
| `hosting-{vm,ops,svc}` | .162 | `s` / `claude-ops` / `svc-ops` | bash | ✅ | Public-facing hosting |
| `opnsense` | **.76** | `root` | **csh** | ✅ | Edge firewall. Also `opnsense-vm`. See quirks |
| `omv-vm` | .153 | `root` | bash | ✅ | OpenMediaVault NAS (Debian 12 + OMV 7). **root only** — see below |

`pfsense-vm` (.156) is **decommissioned** — `No route to host`. OPNsense at `.76` replaced it.
If you find that alias anywhere, it is stale.

The four `-vm` aliases carry `ControlMaster auto` multiplexing, because `DOCKER_HOST=ssh://`
opens many short-lived API calls and trips sshd's `MaxStartups` throttle
(`kex_exchange_identification: Connection reset`).

Internal DNS resolves `<host>.vm` (`cloud.vm`, `manage.vm`, `omv.vm`, `proxmox.vm`) from the
coding VM. Prefer those names over hardcoded IPs in configs — the repo's Caddy/Unbound setup is
deliberately subnet-move-proof.

## Quirks that will waste your time

**ICMP is blocked on `.76` and `.153`.** `ping` reports unreachable for hosts that are fully up.
Never use ping as a liveness test here — use `ssh <alias> true`, or a TCP probe.

**OPNsense root shell is `csh`, not bash.** A bash-syntax command returns
`Illegal variable name.` (on `$(...)`) or `Ambiguous output redirect` (on `2>&1`). Both are
*successful logins* with a shell parse error — not auth failures. Wrap anything non-trivial:

```bash
ssh opnsense "sh -c 'echo \$(hostname); cmd 2>&1'"
ssh opnsense sh -s < script.sh          # or pipe a whole script
```

**OPNsense config changes** need `require_once("config.inc"); require_once("util.inc");` before
`write_config()` (not `functions.inc`). Editing `/conf/config.xml` directly is ignored by
configd until `service configd restart`. For the REST API, use the `opnsense-api` skill.

**Serena cannot open gitignored files** (`Path … is ignored; cannot access for safety reasons`).
`hosts.txt` is one — use the built-in Read/Edit for it specifically.

## The NAS — reachable, but the rules are different

`omv-vm` (.153) accepts the `claude-ops` key **as `root`** (installed 2026-07-20; before that it
returned `Permission denied (publickey,password)`). Debian 12 + OpenMediaVault 7.

**`root` is the only account.** There is no `s`, `claude-ops` or `svc-ops` here — those exist
only on the Ubuntu VMs. So `<host>-ops`/`<host>-svc` have no NAS equivalent, and Ansible against
the NAS logs in as root with `ansible_become=false`.

**Never add the NAS to the Ansible `[homelab]` inventory.** That group is what `os-update.yml`,
`manage-unattended-upgrades.yml`, `reboot-host.yml` and `prune-docker.yml` target, and none may
touch the box serving the NFS exports — a fleet reboot or volume prune would take the media
stack down. They carry `excluded_hosts: [omv, nas, openmediavault, truenas]` as a backstop, but
inventory membership is the real control. The NAS has its own `nas` group and its own playbook
(`omv-update.yml`), which asserts it is not pointed anywhere else.

**Updating it:** use `apt upgrade` (safe subset), not `omv-upgrade`. OMV's wrapper is
`dist-upgrade --auto-remove --allow-unauthenticated`, which on a live NFS server can remove or
replace packages and restart `nfs-server` under mounted clients. Measured 2026-07-20: the safe
subset took 79 of 81 updates with 0 removals; the two it held back were a new kernel, which only
matters after a reboot that would drop every client anyway.

## Verify access

```bash
for p in vm ops svc; do for n in cloud manage media hosting; do
  printf '%-12s ' "$n-$p"; ssh -o BatchMode=yes -o ConnectTimeout=8 "$n-$p" 'id -un' 2>&1 | tail -1
done; done
ssh -o BatchMode=yes opnsense "sh -c 'hostname'"              # csh — needs the wrapper
ssh -o BatchMode=yes cloud-ops 'sudo -n -l' | tail -3          # confirm the NOPASSWD scope
ssh -G opnsense | grep -E '^(hostname|user|identityfile) '     # what an alias resolves to
```

`BatchMode=yes` matters: without it a failed key auth hangs on an interactive password prompt.

*Verified end-to-end 2026-07-19: all 8 Linux aliases + `opnsense` authenticate; `omv-vm` does not.*
