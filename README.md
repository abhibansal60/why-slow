# why-slow

An agent skill that finds out why your Linux machine feels slow. It runs read-only checks: load, memory and swap, RAM-backed `/tmp`, CPU temperature and throttling, OOM kills, journal warnings, stuck processes, indexers, dev servers and containers. Your agent then explains the likely causes, ranked with evidence. It changes nothing until you approve each fix, and it never touches processes you mark as protected, such as your tmux sessions or other agent sessions.

It works with Claude Code as a plugin, and with any agent that can run shell commands and read a `SKILL.md` (Codex, Cursor, Gemini CLI, opencode, and others).

## Start here: paste this to your agent

```
Set up why-slow (https://github.com/abhibansal60/why-slow) for me and run a first check.
1. Install it:
   - Claude Code: run `claude plugin marketplace add abhibansal60/why-slow` and `claude plugin install why-slow@why-slow`.
   - Any other agent: `git clone https://github.com/abhibansal60/why-slow ~/.local/share/why-slow`, then link or copy
     ~/.local/share/why-slow/skills/why-slow into your skills folder (for example ~/.agents/skills/ or ~/.codex/skills/),
     or just read its SKILL.md and follow it.
2. Learn my setup with read-only commands: `ps -eo pid,ppid,comm --forest | head -80`, `echo $XDG_CURRENT_DESKTOP`,
   `echo $TERM_PROGRAM`, `findmnt -no FSTYPE /tmp`. Work out which terminal, multiplexer (tmux, zellij, screen) and agent
   session manager I use, and which processes are your own.
3. Propose a ~/.config/why-slow/config based on skills/why-slow/config.example, with those protected, and show it to me.
   Write it only after I say yes.
4. Run `bash <skill dir>/snapshot.sh yesterday`, then follow SKILL.md: report the likely causes ranked with evidence,
   and propose fixes one by one. Don't kill, stop or delete anything without my approval for that item.
```

After that, just tell your agent "my machine is slow since Tuesday" or "perf check".

## What it checks

| Area | How |
|---|---|
| Load, CPU, memory, swap, pressure stall info | `uptime`, `free`, `vmstat`, `/proc/pressure/*`, CPU sampled over 2s with `top` |
| Who uses memory and swap | Top RSS, per-process `VmSwap`, totals per process name |
| Long-running CPU hogs and anything new | Processes averaging over `CPU_PCT`, and processes started since the time you give |
| Disk | `df` space and inodes, `iostat`/`pidstat` if `sysstat` is installed |
| RAM-backed scratch space | Size of `/tmp`, `/dev/shm` and anything in `SCRATCH_DIRS`, with filesystem type |
| Heat | Thermal zones, `sensors`, average versus max MHz, governor, and whether the throttle counter is rising right now |
| Kernel | OOM kills, I/O errors, GPU hangs, soft lockups, thermal events (`journalctl -k`, no sudo) |
| Journal | Warnings since then, deduplicated, plus input-lag "system is too slow" lines |
| Services and containers | Failed systemd units (system and user), `docker`/`podman stats` |
| Background work | File indexers, package updaters, thumbnailers, dev servers and their ports, desktop apps' total RAM |

Every process in the lists is tagged `PROTECTED(...)` if your config says to leave it alone.

## Customize it

Copy [`skills/why-slow/config.example`](skills/why-slow/config.example) to `~/.config/why-slow/config`. It's plain `KEY=VALUE`, read and never executed.

- `PROTECT_NAMES`: process names never to kill. They're added to built-in defaults (desktop shells, display servers, login managers, audio, `sshd`). Start the value with `=` to replace the defaults.
- `PROTECT_ANCESTORS`: everything running under these is off limits too, for example `tmux: server,zellij` or your agent session manager. This keeps an agent from killing its own session or another agent's work.
- `SCRATCH_DIRS`, `CPU_PCT`, `SWAP_KB`, `TOP_N`: what to size up, and the thresholds.

For notes that should stick, like causes you've seen before on this machine or "never touch my VM", put them in `~/.config/why-slow/known-causes.md`. The skill reads that file on every run and offers to add new findings to it.

Check a single process yourself: `bash skills/why-slow/snapshot.sh --guard <PID>` prints why it's protected (exit 1) or `ok` (exit 0).

## Use it without an agent

```
bash skills/why-slow/snapshot.sh "2 days ago" | less
```

## Requirements

Linux with bash, procps, systemd's `journalctl`, and `mawk` or `gawk`. `sysstat` (`iostat`, `pidstat`), `lm-sensors`, `docker` and `podman` are used if present. Tested on Ubuntu 26.04; it should work on other systemd distros. macOS isn't supported.

## Test

```
bash skills/why-slow/test.sh
```

## License

MIT
