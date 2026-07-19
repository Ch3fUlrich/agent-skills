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

## Two accounts, complementary powers — pick the right one

This is the single most useful thing on this page, and it is easy to get wrong: **`s` and
`claude-ops` are both reachable on every Linux VM, and neither is a superset of the other.**

| | `s` — alias `<host>-vm` | `claude-ops` — alias `<host>-ops` |
|---|---|---|
| In `docker` group | ✅ plain `docker` works | ❌ plain `docker` → `permission denied … docker.sock` |
| `DOCKER_HOST=ssh://` | ✅ **use this** | ❌ |
| Passwordless sudo | ❌ prompts for a password | ✅ **NOPASSWD**, scoped |
| sudo scope | — | exactly `/usr/bin/docker`, `/usr/bin/systemctl`, `/usr/local/bin/docker-compose` |

So: **container work → `<host>-vm`. `systemctl` or root-owned paths → `<host>-ops`.**

```bash
DOCKER_HOST=ssh://cloud-vm docker compose ps      # container work, as s
ssh cloud-ops 'sudo -n systemctl restart nfs-client.target'   # service work, as claude-ops
```

**"Claude cannot sudo" is only true for `s`.** `sudo systemctl …` *is* available via the `-ops`
aliases. Before filing something in `manual_todo.md` as user-only, check whether it is just
`systemctl` or `docker` — if so, `claude-ops` can already do it. Anything outside those three
binaries (apt, editing `/etc`, partitioning, Proxmox, Tailscale admin) genuinely is manual.

## Hosts

| Alias | Address | User | Shell | Status | Notes |
|---|---|---|---|---|---|
| `cloud-vm` / `cloud-ops` | .159 | `s` / `claude-ops` | bash | ✅ | Jellyfin/*arr, NFS client, LidMeta, Harbor |
| `manage-vm` / `manage-ops` | .160 | `s` / `claude-ops` | bash | ✅ | Authelia, Semaphore, Ansible control |
| `media-vm` / `media-ops` | .161 | `s` / `claude-ops` | bash | ✅ | Media stack |
| `hosting-vm` / `hosting-ops` | .162 | `s` / `claude-ops` | bash | ✅ | Public-facing hosting |
| `opnsense` | **.76** | `root` | **csh** | ✅ | Edge firewall. Also `opnsense-vm`. See quirks |
| `omv-vm` | .153 | `root` | bash | ❌ | OpenMediaVault NAS. **Key not installed** — see below |

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

## The NAS is not provisioned

`omv-vm` (.153) refuses the key: `Permission denied (publickey,password)`. Port 22 *does*
answer — sshd offers auth methods — so the host is up; the `claude-ops` pubkey simply was never
added to its `authorized_keys`. Installing it needs the NAS root password, which agents do not
have. Standing manual task (`Server/manual_todo.md`).

**Never add the NAS to the Ansible `[homelab]` inventory.** `os-update.yml`,
`manage-unattended-upgrades.yml` and `reboot-host.yml` must never touch it; they carry
`excluded_hosts: [omv, nas, openmediavault, truenas]` as a backstop. NFS exports live here, and
a fleet reboot would take the media stack down with it.

## Verify access

```bash
for h in cloud-vm manage-vm media-vm hosting-vm cloud-ops manage-ops media-ops hosting-ops; do
  printf '%-12s ' "$h"; ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" 'id -un' 2>&1 | tail -1
done
ssh -o BatchMode=yes opnsense "sh -c 'hostname'"              # csh — needs the wrapper
ssh -o BatchMode=yes cloud-ops 'sudo -n -l' | tail -3          # confirm the NOPASSWD scope
ssh -G opnsense | grep -E '^(hostname|user|identityfile) '     # what an alias resolves to
```

`BatchMode=yes` matters: without it a failed key auth hangs on an interactive password prompt.

*Verified end-to-end 2026-07-19: all 8 Linux aliases + `opnsense` authenticate; `omv-vm` does not.*
