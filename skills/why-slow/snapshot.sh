#!/usr/bin/env bash
# why-slow: read-only snapshot of why a Linux machine feels slow. Changes nothing.
# Usage: snapshot.sh [since]      since = any `date -d` / journalctl --since value, default "yesterday"
#        snapshot.sh --guard PID  prints why PID is protected (exit 1), or "ok" (exit 0)
# Config: $WHY_SLOW_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/why-slow/config (see config.example)
set -u
since="${1:-yesterday}"

# Defaults. Lists are comma-separated process names (as in /proc/PID/comm, max 15 chars).
PROTECT_NAMES="systemd,init,gnome-shell,kwin_wayland,kwin_x11,plasmashell,Xorg,Xwayland,gdm,gdm3,sddm,lightdm,dbus-daemon,pipewire,wireplumber,pulseaudio,sshd"
PROTECT_ANCESTORS="sshd"
SCRATCH_DIRS="/tmp,/dev/shm"
CPU_PCT=20
SWAP_KB=20000
TOP_N=15

cfg="${WHY_SLOW_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/why-slow/config}"
if [ -f "$cfg" ]; then
  # Plain KEY=VALUE lines, never sourced. PROTECT_* values are appended to the defaults; a leading = replaces them.
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"
    case "$k" in
      PROTECT_NAMES|PROTECT_ANCESTORS)
        if [ "${v:0:1}" = "=" ]; then printf -v "$k" '%s' "${v:1}"; else printf -v "$k" '%s,%s' "${!k}" "$v"; fi ;;
      SCRATCH_DIRS|CPU_PCT|SWAP_KB|TOP_N) printf -v "$k" '%s' "$v" ;;
    esac
  done < <(grep -E '^[A-Z_]+=' "$cfg")
fi

sec() { printf '\n=== %s ===\n' "$1"; }
in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }
ppid_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f2; }
# Prints why a PID must not be touched, or nothing.
guard() {
  local p=$1 c
  c=$(cat "/proc/$p/comm" 2>/dev/null) || return
  # A protected ancestor (say the tmux server) is itself protected: killing it kills everything under it.
  in_list "$c" "$PROTECT_NAMES,$PROTECT_ANCESTORS" && { echo "PROTECTED($c)"; return; }
  while p=$(ppid_of "$p") && [ "${p:-0}" -gt 1 ]; do
    c=$(cat "/proc/$p/comm" 2>/dev/null)
    in_list "$c" "$PROTECT_ANCESTORS" && { echo "PROTECTED(inside $c:$p)"; return; }
  done
}
# Appends the guard tag to ps output whose first column is a PID.
tag() { while read -r pid rest; do [ "$pid" = PID ] && { echo "$pid $rest"; continue; }; echo "$pid $rest $(guard "$pid")"; done; }
if [ "$since" = --guard ]; then
  pid="${2:?usage: snapshot.sh --guard PID}"
  [ -d "/proc/$pid" ] || { echo "no such process: $pid"; exit 2; }
  why=$(guard "$pid"); [ -n "$why" ] && { echo "$why"; exit 1; }; echo ok; exit 0
fi
thr() { cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count 2>/dev/null || echo 0; }

sec "config"
echo "file: $cfg $([ -f "$cfg" ] || echo '(none, using defaults)')"
echo "protect names: $PROTECT_NAMES"
echo "protect descendants of: $PROTECT_ANCESTORS"

sec "load / memory / pressure"
uptime; echo "cpus: $(nproc)"; free -h; swapon --show 2>/dev/null
for r in cpu memory io; do [ -r /proc/pressure/$r ] && echo "psi $r: $(head -1 /proc/pressure/$r)"; done
vmstat 1 3

sec "top CPU (sampled over 2s; pid ppid elapsed cpu% rss_kb comm)"
# ps %cpu is a lifetime average, so sample with top for current usage.
top -bn2 -d2 -w 200 | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ && $9+0 > 0 {print $1, $9}' | sort -k2 -rn | head -"$TOP_N" |
  while read -r pid cpu; do [ -d "/proc/$pid" ] || continue; printf '%s %s %s cpu=%s %s %s\n' "$pid" "$(ppid_of "$pid")" "$(ps -o etime= -p "$pid" | tr -d ' ')" "$cpu" "$(ps -o rss= -p "$pid" | tr -d ' ')" "$(cat /proc/$pid/comm 2>/dev/null)"; done | tag

sec "top memory (pid ppid elapsed rss_kb args)"
ps -eo pid,ppid,etime,rss,args --sort=-rss | head -"$((TOP_N + 1))" | cut -c1-150 | tag

sec "top swap users (pid swap_kb comm)"
for p in /proc/[0-9]*; do s=$(awk '/^VmSwap/{print $2}' "$p/status" 2>/dev/null)
  [ "${s:-0}" -gt "$SWAP_KB" ] && echo "${p#/proc/} $s $(cat "$p/comm")"; done | sort -k2 -rn | head -"$TOP_N" | tag

sec "process groups over 150 MB (total RSS, count, name)"
ps -eo rss=,comm= | awk '{r[$2]+=$1; n[$2]++} END {for (c in r) if (r[c] > 150000) printf "%6d MB %4d x %s\n", r[c]/1024, n[c], c}' | sort -rn

sec "long-running processes using >= ${CPU_PCT}% CPU on average (pid elapsed cpu% comm)"
ps -eo pid=,etimes=,etime=,%cpu=,comm= | awk -v t="$CPU_PCT" '$4 >= t && $2 > 600 {print $1, $3, $4, $5}' | tag

sec "processes started since $since (pid start cpu% rss_kb comm)"
cut=$(date -d "$since" +%s 2>/dev/null || echo 0); now=$(date +%s)
ps -eo pid=,etimes=,%cpu=,rss=,comm= | awk -v c="$cut" -v n="$now" '(n - $2) >= c && ($3 >= 2 || $4 >= 200000) {print $1, strftime("%F_%T", n - $2), $3, $4, $5}' | sort -k3 -rn | head -"$TOP_N" | tag

sec "disk space / inodes"
df -hT -x devtmpfs -x squashfs -x efivarfs -x overlay 2>/dev/null | grep -v -E ' /(run|sys)/'
df -i / | tail -1

sec "scratch dirs (tmpfs here lives in RAM)"
IFS=',' read -ra dirs <<< "$SCRATCH_DIRS"
for d in "${dirs[@]}"; do
  d="${d/#\~/$HOME}"; [ -d "$d" ] || continue
  echo "$d: $(findmnt -no FSTYPE -T "$d") $(du -xsh "$d" 2>/dev/null | cut -f1)"
  du -xsh "$d"/* "$d"/.[!.]* 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'
done

sec "disk I/O"
if command -v iostat >/dev/null; then iostat -dxy 1 1 | grep -v -E '^(loop|zram|Linux)|^$'
else echo "iostat missing (sysstat package); /proc/pressure/io above covers I/O stalls"; fi
command -v pidstat >/dev/null && pidstat -d 1 2 | awk '/^Average/ && $5+$6 > 100'

sec "thermals / frequency / throttling"
for z in /sys/class/thermal/thermal_zone*; do t=$(cat "$z/temp" 2>/dev/null); [ "${t:-0}" -gt 1000 ] && echo "$(cat "$z/type") $((t / 1000))C"; done
command -v sensors >/dev/null && sensors 2>/dev/null | grep -E -i 'package|tctl|tdie|fan' | head -6
max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 0)
grep MHz /proc/cpuinfo | awk -v m="$max" '{s+=$4; n++} END {if (n) printf "avg %.0f MHz, max %d MHz\n", s/n, m/1000}'
echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null) profile: $(powerprofilesctl get 2>/dev/null) power: $(cat /sys/class/power_supply/*/status 2>/dev/null | tr '\n' ' ')"
a=$(thr); sleep 5; echo "package throttle events: $(thr) total, +$(($(thr) - a)) in last 5s"

sec "kernel: OOM / disk / GPU / thermal since $since"
journalctl -k --since "$since" -q --no-pager 2>/dev/null | grep -i -E 'out of memory|killed process|oom-kill|i/o error|nvme.*(error|timeout)|ata[0-9].*error|amdgpu.*(error|timeout)|i915.*(error|hang)|nouveau|nvrm|thermal|throttl|hogged CPU|soft lockup|hung_task' | tail -20

sec "warnings since $since (deduped, top $TOP_N)"
journalctl -p warning --since "$since" -q --no-pager 2>/dev/null | cut -d' ' -f5- | grep -v -E '^ *(#|==)' |
  sed -E 's/0x[0-9a-f]+/0xN/g; s/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -"$TOP_N" | cut -c1-200
echo "\"system is too slow\" input-lag lines: $(journalctl --since "$since" -q --no-pager 2>/dev/null | grep -c 'system is too slow')"

sec "systemd failed units"
systemctl --failed --no-pager --no-legend 2>/dev/null; systemctl --user --failed --no-pager --no-legend 2>/dev/null

sec "containers"
command -v docker >/dev/null && docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' 2>&1 | head -10
command -v podman >/dev/null && podman stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' 2>&1 | head -10

sec "indexers / updaters / dev servers / thumbnailers"
ps -eo pid,ppid,etime,%cpu,rss,args | grep -E -i 'localsearch|tracker-miner|baloo|packagekit|unattended-upgr|apt-get|dpkg|dnf|snapd|fwupd|flatpak|next dev|next-server|vite|webpack|nodemon|astro|glycin|thumbnail' | grep -v -E 'grep|snapshot.sh' | cut -c1-150 | tag
echo "listening dev-style servers:"; ss -ltnpH 2>/dev/null | awk '{print "  " $4, $6}' | grep -E 'node|python|bun|deno|ruby|java' | head -10

sec "desktop apps (total RSS)"
ps -eo comm=,rss= | awk '$1 ~ /chrome|chromium|firefox|brave|electron|code|slack|discord|teams|zoom|spotify|ChatGPT|claude/ {r[$1]+=$2; n[$1]++} END {for (c in r) printf "%6d MB %4d x %s\n", r[c]/1024, n[c], c}' | sort -rn

sec "recent package activity"
command -v snap >/dev/null && snap changes 2>/dev/null | tail -3
[ -r /var/log/dpkg.log ] && grep -h -E ' (install|upgrade) ' /var/log/dpkg.log | tail -5
[ -r /var/log/dnf.log ] && grep -h -E 'Upgrade|Install' /var/log/dnf.log | tail -5
exit 0
