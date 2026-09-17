# Shell Scripting

A single system-information script that demonstrates the required features:
**variables**, **user input with `read -p`**, **`mkdir` and `touch`**, and **writing the running
process list into a file with `>` output redirection**.

Script: [`shellscript.sh`](shellscript.sh) · Sample output committed at
[`system_info/process.log`](system_info/process.log)

---

## The task

> Write a shell script that stores values in variables, takes input from the user with `read -p`,
> creates a directory with `mkdir` and a file with `touch`, and writes the running processes into
> that file using `>` output redirection.

---

## How it works

### 1. Variables and command substitution

```bash
HOSTNAME_VALUE=$(hostname)
KERNEL_VALUE=$(uname -r)
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
```

`$( )` is **command substitution** — it runs the command and substitutes its output. Collecting
these once at the top means the report is a consistent snapshot, and the values are reused rather
than shelling out repeatedly.

No space is allowed around `=`. `NAME = value` would be read as running a command called `NAME`.

### 2. User input with `read -p`

```bash
read -r -p "Enter a name for the output directory [system_info]: " DIR_NAME
DIR_NAME="${DIR_NAME:-system_info}"
```

- `-p` prints the prompt on the same line.
- `-r` stops backslashes being interpreted as escapes — you almost always want it.
- `${DIR_NAME:-system_info}` supplies a **default** when the variable is empty, so pressing Enter
  still works.

### 3. `mkdir`, `touch`, and `>` redirection

```bash
mkdir -p "${DIR_NAME}"
touch "${DIR_NAME}/${FILE_NAME}"
ps aux > "${DIR_NAME}/${FILE_NAME}"
```

- `mkdir -p` creates parent directories as needed and does not error if the directory already exists.
- `touch` creates an empty file (and updates the timestamp if it exists).
- `>` sends stdout to the file, **replacing** its contents. `>>` appends — the script uses `>>` at
  the end to add a timestamp footer, so both forms appear.

Every variable is quoted — `"${DIR_NAME}"`, not `$DIR_NAME`. Without quotes, a directory name
containing a space would split into two arguments and the script would misbehave.

---

## Running it — accepting the defaults

```bash
chmod +x shellscript.sh
./shellscript.sh
```

**Output**

```
$ ./shellscript.sh


==========================================
  System Information Script
==========================================
Date            : 2026-09-17 21:42:25
Hostname        : vm
Operating system: Ubuntu 24.04.4 LTS
Kernel          : 6.18.44-fc-v33
Architecture    : x86_64
Logged in as    : root
Uptime          : up 7 minutes
CPU cores       : 2
Memory          : 658Mi used of 7.8Gi
Disk (/)        : 19G / 252G (44% used)
==========================================

Enter a name for the output directory [system_info]: Enter a name for the process log file [process.log]: 
Created directory : system_info
Created file      : system_info/process.log
Wrote 74 running processes into system_info/process.log

Done. Preview of the first 5 lines:
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.3  0.0  20328  4280 ?        SLl  21:35   0:01 /process_api --firecracker-init --addr 0.0.0.0:2024 --max-ws-buffer-size 32768 --block-local-connections --listen-vsock-port 2024 --log-vsock-port 5002
root         2  0.0  0.0      0     0 ?        S    21:35   0:00 [kthreadd]
root         3  0.0  0.0      0     0 ?        S    21:35   0:00 [pool_workqueue_release]
root         4  0.0  0.0      0     0 ?        I<   21:35   0:00 [kworker/R-rcu_gp]
```

Pressing Enter at both prompts took the defaults, so the script created `system_info/process.log`
and wrote the running process list into it.

## Running it again — typing custom names

**Output**

```
$ ./shellscript.sh      # this time typing custom names instead of accepting the defaults

Enter a name for the output directory [system_info]: Enter a name for the process log file [process.log]: 
Created directory : sysreport
Created file      : sysreport/running_procs.txt
Wrote 76 running processes into sysreport/running_procs.txt

Done. Preview of the first 5 lines:
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.3  0.0  20328  4280 ?        SLl  21:35   0:01 /process_api --firecracker-init --addr 0.0.0.0:2024 --max-ws-buffer-size 32768 --block-local-connections --listen-vsock-port 2024 --log-vsock-port 5002
root         2  0.0  0.0      0     0 ?        S    21:35   0:00 [kthreadd]
root         3  0.0  0.0      0     0 ?        S    21:35   0:00 [pool_workqueue_release]
root         4  0.0  0.0      0     0 ?        I<   21:35   0:00 [kworker/R-rcu_gp]

$ ls -R sysreport system_info
sysreport:
running_procs.txt

system_info:
process.log

$ tail -4 system_info/process.log    # the >> append at the end of the script
root      2215  0.0  0.0   4480  3464 pts/0    Ss+  21:42   0:00 bash ./shellscript.sh
root      2238  0.0  0.0   8048  4416 pts/0    R+   21:42   0:00 ps aux

--- captured 2026-09-17 21:42:25 on vm ---

$ wc -l system_info/process.log
77 system_info/process.log
```

Typing `sysreport` and `running_procs.txt` created those instead, proving the input is actually used
rather than the defaults being hard-coded. The `tail` shows the `>>` footer appended after the
process list, and `wc -l` confirms the total: 1 header + the process rows + the 2-line footer.

---

## What I understood

**`>` versus `>>` is the bug you only make once.** `ps aux > file` replaces the file every run. Using
`>` inside a loop leaves you with only the final iteration's output. `>>` appends.

**Redirection happens before the command runs.** The shell truncates the target file first, which is
why `sort file > file` produces an empty file — it is emptied before `sort` ever reads it.

**`2>` is a separate stream.** `>` only redirects stdout; errors still hit the terminal. `2>` captures
stderr, `> file 2>&1` sends both to one place, and the order matters — `2>&1 > file` does *not* do
the same thing.

**`set -u` catches typos.** With it, referencing an undefined variable aborts the script instead of
silently substituting an empty string — which is how `rm -rf "$DIR/"` becomes `rm -rf /`. For
production scripts `set -euo pipefail` is the usual line.

**Quote everything.** `"${VAR}"` prevents word-splitting and glob expansion. The braces also
disambiguate: `"${FILE}_backup"` is clear, `"$FILE_backup"` refers to a different variable entirely.

**Defaults make a script non-interactive-friendly.** `${VAR:-default}` means the script still works
when piped input or a CI job provides nothing, instead of hanging on a prompt.

---

## Summary

| Requirement | Where it appears |
| --- | --- |
| Variables | `SCRIPT_NAME`, `HOSTNAME_VALUE`, `MEM_TOTAL`, … with `$( )` substitution |
| `read -p` for user input | directory name and file name prompts, with `:-` defaults |
| `mkdir` | `mkdir -p "${DIR_NAME}"` |
| `touch` | `touch "${DIR_NAME}/${FILE_NAME}"` |
| `>` output redirection | `ps aux > "${DIR_NAME}/${FILE_NAME}"` |
| `>>` append (extra) | timestamp footer written after the process list |
