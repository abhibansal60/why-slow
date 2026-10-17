---
name: why-slow
description: Find out why a Linux machine feels slow, laggy, hot or out of memory, using read-only checks (load, memory and swap, tmpfs, CPU temperature and throttling, OOM kills, journal warnings, stuck processes, indexers, dev servers, containers), then propose fixes the user approves one by one. Use when the user says their computer, laptop, desktop, workstation or system is slow, laggy, freezing, hot, swapping or running out of memory, or asks for a "perf check" or "why is my machine slow".
---

# why-slow

Diagnose first, change nothing. Every kill, stop, restart or delete needs the user's approval for that exact item.

## Rules

1. **Read-only until approved.** Don't kill, stop, restart, renice or delete anything, and don't change sysctl, services or config on your own. For each proposed fix, show the PID, parent, what it is, what it costs (CPU %, RSS, swap, how long it has run) and the exact command. Then wait. A general "go ahead" covers the items you listed and nothing else. Re-ask for anything that can't be undone, like deleting files.
2. **Respect the protect list.** `snapshot.sh` tags processes `PROTECTED(...)` when their name, or the name of any ancestor, is on the user's protect list. It also tags the chain it runs under (agent, shell, terminal, multiplexer) `PROTECTED(own session)`; your own helpers, such as MCP servers, aren't tagged, so check `pstree -sap <PID>` before proposing an agent-looking process. Never propose killing a protected process. Before proposing any fix, run `snapshot.sh --guard <PID>`; exit 1 means hands off. You can still report what a protected process costs and suggest the user deal with it.
3. **Never stop your own session or the user's.** That means the agent's own process tree, the terminal it runs in, the desktop session, the display server, the login manager, and the shell.
4. **Files.** Before suggesting deleting anything, check whether a running process has it open: `find /proc/[0-9]*/fd -lname '<path>*' 2>/dev/null` prints `/proc/<PID>/fd/<n>` for each open file under it. If one does, suggest cleaning it up from inside that program instead.
5. **No sudo prompts.** If a command needs a password, use an unprivileged alternative (`journalctl -k` instead of `dmesg`) and say what you couldn't see.

## Steps

1. **Snapshot.** Run `bash <skill dir>/snapshot.sh [since]`, where `since` is when the slowness started (default `yesterday`; anything `date -d` accepts). It takes about 15 seconds and prints sections. Each section degrades gracefully if a tool is missing.
2. **Load the user's notes.** If `${XDG_CONFIG_HOME:-~/.config}/why-slow/known-causes.md` exists, read it. It holds causes already seen on this machine and the user's preferences.
3. **Dig in.** For each suspect: `pstree -sap <PID>`, `cat /proc/<PID>/cmdline | tr '\0' ' '`, `ls -l /proc/<PID>/fd`, journal lines around its start time (`journalctl --since "<start>" --until "<start + 5 min>"`), and `ps -o lstart= -p <PID>`. Line up start times with when the user says the slowness began.
4. **Report.** Give a ranked list of likely causes, each with its evidence and the fix you'd propose, following rule 1. Then list what you ruled out, briefly.
5. **After an approved fix**, re-measure (load, temperatures, throttle delta, free and swap) and show before and after.
6. **Offer to remember.** If you found a cause that isn't in `known-causes.md`, offer to add a row there.

## Reading the snapshot

| Signal | Usually means |
|---|---|
| A process at ~100% of one core for hours, under the desktop shell, a sandbox (`bwrap`) or a file manager | A stuck thumbnailer or image loader (`glycin-*`, `*-thumbnailer`, `tumblerd`). It's safe to kill; the parent restarts it when needed. |
| High package temperature, throttle counter rising, MHz below max | Heat. Find the process keeping the CPU busy first. If it's still hot when idle, check the fan and vents. |
| Swap nearly full, `psi memory` above 0, OOM kills in the kernel log | Memory pressure. See the top memory, top swap and process-group lists. |
| Big `shared` in `free`, large `/tmp` or `/dev/shm` on tmpfs | Files in tmpfs live in RAM: model weights, venvs, build caches. |
| Many copies of the same agent, editor or MCP server process | Old agent or IDE sessions left open, each with its own helper servers |
| `psi io` high, `%util` near 100, I/O errors in the kernel log | Disk bottleneck or a failing disk (`smartctl -a`, which needs sudo, so ask the user) |
| `localsearch`, `tracker-miner`, `baloo` busy | Desktop file indexer crawling |
| `packagekit`, `apt`, `dnf`, `snapd`, `fwupd`, `flatpak` busy | Background updates; they usually finish on their own |
| Dev servers (`next dev`, `vite`, `webpack`, `nodemon`) or containers left running | Forgotten work. Cheap to stop, but the user may want them. |
| "system is too slow" lines (libinput), "Disabling unresponsive app" | A symptom of CPU starvation or compositor lag, not a cause |
| Repeated "already disposed" warnings naming one shell extension | A buggy desktop extension. Disabling it is the user's choice. |

## Customizing

The user's config lives at `${XDG_CONFIG_HOME:-~/.config}/why-slow/config` (override it with `WHY_SLOW_CONFIG`). See `config.example` next to this file. Keys: `PROTECT_NAMES`, `PROTECT_ANCESTORS`, `SCRATCH_DIRS`, `CPU_PCT`, `SWAP_KB`, `TOP_N`. Write or change the config only when the user asks.
