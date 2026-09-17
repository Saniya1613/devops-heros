# Linux Fundamentals

Four tasks: links, user creation, the systemd journal, and a command reference.

Run on **Ubuntu 24.04** with systemd and `systemd-journald` active. Every command below was
actually executed and the terminal output is pasted verbatim.

---

## Task 1 — Soft link vs hard link

**What this does:** creates both link types against the same file, then deletes the original to expose the difference between them.

```bash
mkdir -p ~/linklab && cd ~/linklab
echo "original content, line 1" > original.txt
ln -s original.txt soft.link      # symbolic / soft link
ln    original.txt hard.link      # hard link
ls -li
stat original.txt hard.link soft.link | grep -E "File:|Inode:|Links:"
```

**Output**

```
$ cd ~/linklab && ls -li
total 8
1335309 -rw-r--r-- 2 root root 25 Sep 17 21:39 hard.link
1335309 -rw-r--r-- 2 root root 25 Sep 17 21:39 original.txt
1335310 lrwxrwxrwx 1 root root 12 Sep 17 21:39 soft.link -> original.txt

$ stat original.txt hard.link soft.link | grep -E "File|Inode|Links"
  File: original.txt
Device: 0,41	Inode: 1335309     Links: 2
  File: hard.link
Device: 0,41	Inode: 1335309     Links: 2
  File: soft.link -> original.txt
Device: 0,41	Inode: 1335310     Links: 1

$ cat soft.link
original content, line 1
$ cat hard.link
original content, line 1
```

Read the first column of `ls -li` — that is the **inode number**:

| File | Inode | Link count |
| --- | --- | --- |
| `original.txt` | **1335309** | 2 |
| `hard.link` | **1335309** | 2 |
| `soft.link` | 1335310 | 1 |

`original.txt` and `hard.link` share one inode. They are not "the file and a copy" — they are **two
names for the same file**. Neither is the original; the filesystem does not distinguish them.
`soft.link` has its own inode and is only 12 bytes: just enough to store the text `original.txt`.

### The deletion test

**What this does:** removes the original filename and shows which link survives.

```bash
rm original.txt
cat hard.link      # works
cat soft.link      # broken
```

**Output**

```
$ rm original.txt        # delete the ORIGINAL file

$ ls -li
total 4
1335309 -rw-r--r-- 1 root root 25 Sep 17 21:39 hard.link
1335310 lrwxrwxrwx 1 root root 12 Sep 17 21:39 soft.link -> original.txt

$ cat hard.link          # still works - the data is still there
original content, line 1

$ cat soft.link          # broken - it pointed at a NAME that is gone
cat: soft.link: No such file or directory

$ stat hard.link | grep -E "Inode|Links"   # link count dropped 2 -> 1
Device: 0,41	Inode: 1335309     Links: 1

$ echo "original content, line 1" > original.txt   # recreate the name
$ cat soft.link          # symlink heals - it resolves by name
original content, line 1
$ ls -li                 # but the new file has a DIFFERENT inode to hard.link
total 8
1335309 -rw-r--r-- 1 root root 25 Sep 17 21:39 hard.link
1335329 -rw-r--r-- 1 root root 25 Sep 17 21:40 original.txt
1335310 lrwxrwxrwx 1 root root 12 Sep 17 21:39 soft.link -> original.txt
```

This is the whole lesson:

- **`hard.link` still works.** `rm` does not delete file data — it removes a *directory entry* and
  decrements the inode's link count. The count went `2 → 1`, so the data stayed. Only when the count
  reaches 0 does the kernel free the blocks.
- **`soft.link` broke** with `No such file or directory`, because it stores the *name*
  `original.txt` and that name no longer resolves. This is a **dangling symlink**.
- Recreating a file called `original.txt` **healed the symlink**, but `ls -li` shows the new file has
  inode `1335329` — a completely different file. The symlink now points at unrelated data that happens
  to share the name, while `hard.link` still holds the original inode `1335309`.

| | Hard link | Soft link |
| --- | --- | --- |
| Points to | the **inode** (the data) | a **path string** |
| Own inode | no, shares the target's | yes |
| Survives target deletion | **yes** | no, dangles |
| Can cross filesystems | **no** | yes |
| Can link a directory | no (not for normal users) | yes |
| Shown by `ls -l` | looks like a normal file | `soft.link -> original.txt` |

In practice symlinks are what you nearly always want — `/usr/bin/python3` and rolling `current ->
release-2024-01-15` deployment directories are symlinks. Hard links show up in deduplicating backup
tools, where many snapshots share one copy of an unchanged file.

---

## Task 2 — `adduser` vs `useradd`

**What this does:** creates one user with each command and compares what actually got set up.

```bash
useradd testuser1
adduser --disabled-password --gecos "" testuser2
```

**Output**

```
########## useradd — the low-level binary ##########
$ useradd testuser1
$ grep testuser1 /etc/passwd
testuser1:x:1001:1001::/home/testuser1:/bin/sh
$ ls -ld /home/testuser1        # no home directory was created
ls: cannot access '/home/testuser1': No such file or directory
$ passwd -S testuser1           # L = locked, no password set
testuser1 L 2026-09-17 0 99999 7 -1

########## adduser — the Debian/Ubuntu friendly wrapper ##########
$ adduser --disabled-password --gecos "" testuser2
info: Adding user `testuser2' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `testuser2' (1002) ...
info: Adding new user `testuser2' (1002) with group `testuser2 (1002)' ...
info: Creating home directory `/home/testuser2' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `testuser2' to supplemental / extra groups `users' ...
info: Adding user `testuser2' to group `users' ...

$ grep testuser2 /etc/passwd
testuser2:x:1002:1002:,,,:/home/testuser2:/bin/bash
$ ls -ld /home/testuser2        # home directory created
drwxr-x--- 2 testuser2 testuser2 4096 Sep 17 21:40 /home/testuser2
$ ls -a /home/testuser2         # skeleton files copied from /etc/skel
.
..
.bash_logout
.bashrc
.profile
$ ls -a /etc/skel
.
..
.bash_logout
.bashrc
.profile

$ grep -E "testuser1|testuser2" /etc/group
users:x:100:testuser2
testuser1:x:1001:
testuser2:x:1002:

########## clean up ##########
$ userdel -r testuser2 && userdel testuser1
userdel: testuser2 mail spool (/var/mail/testuser2) not found
deleted
$ grep -cE "testuser" /etc/passwd
0
0
```

The names look interchangeable and are not:

| | `useradd testuser1` | `adduser testuser2` |
| --- | --- | --- |
| What it is | low-level binary, part of `shadow-utils`, on every Linux | Perl script wrapping `useradd`, **Debian/Ubuntu only** |
| Home directory | **not created** (`No such file or directory`) | created, `drwxr-x---`, owned by the user |
| `/etc/skel` copied | no | yes — `.bashrc`, `.profile`, `.bash_logout` |
| Login shell | `/bin/sh` (the `useradd` default) | `/bin/bash` |
| Password | locked, unset (`passwd -S` → **L**) | prompts interactively (suppressed here with `--disabled-password`) |
| Extra groups | none | added to `users` |
| Output | silent | narrates every step |

`useradd` did the bare minimum: it wrote a line to `/etc/passwd` and created a matching group. The
account exists but cannot log in and has nowhere to put files. `adduser` produced an account that is
actually usable.

Both create a **user private group** matching the username — visible in `/etc/group` as
`testuser1:x:1001:` and `testuser2:x:1002:`. That is standard Debian practice: a new file's default
group is the user's own, so a permissive umask cannot accidentally expose files to other people.

The practical rule: **`adduser` when a human will use the account, `useradd` in scripts** — it is
POSIX-standard, present on RHEL and Alpine too, and its behaviour does not change between distros.
`useradd -m -s /bin/bash` gets you most of the way to `adduser` behaviour portably.

Cleanup matters: `userdel -r` removes the home directory as well, `userdel` alone leaves it orphaned.

---

## Task 3 — `journalctl`

**What this does:** queries the systemd journal by count, boot, priority, tag and unit, and shows the structured data underneath it.

```bash
journalctl -n 10 --no-pager                 # last 10 entries
journalctl -b --no-pager                    # this boot only
journalctl -p err --no-pager                # priority err and worse
logger -t devops-lab "test message"         # write an entry
journalctl -t devops-lab --no-pager         # read it back by tag
journalctl -u systemd-journald --no-pager   # one unit
journalctl -o json-pretty -n 1 --no-pager   # structured fields
journalctl --disk-usage
```

**Output**

```
$ journalctl -n 10 --no-pager               # last 10 entries, newest at the bottom
Sep 17 21:40:16 889ab814ed00 gpasswd[200]: members of group users set by root to testuser2
Sep 17 21:40:16 889ab814ed00 userdel[246]: delete user 'testuser2'
Sep 17 21:40:16 889ab814ed00 userdel[246]: delete 'testuser2' from group 'users'
Sep 17 21:40:16 889ab814ed00 userdel[246]: removed group 'testuser2' owned by 'testuser2'
Sep 17 21:40:16 889ab814ed00 userdel[246]: removed shadow group 'testuser2' owned by 'testuser2'
Sep 17 21:40:16 889ab814ed00 userdel[246]: delete 'testuser2' from shadow group 'users'
Sep 17 21:40:16 889ab814ed00 userdel[254]: delete user 'testuser1'
Sep 17 21:40:16 889ab814ed00 userdel[254]: removed group 'testuser1' owned by 'testuser1'
Sep 17 21:40:16 889ab814ed00 userdel[254]: removed shadow group 'testuser1' owned by 'testuser1'
Sep 17 21:40:29 889ab814ed00 devops-lab[275]: test message from the shell via logger

$ journalctl -b --no-pager | head -5        # this boot only
Sep 17 21:39:18 889ab814ed00 kernel: Linux version 6.18.44-fc-v33 (builder@sandboxing) (gcc (GCC) 15.3.0, GNU ld (GNU Binutils) 2.46) #1 SMP PREEMPT_DYNAMIC @0
Sep 17 21:39:18 889ab814ed00 kernel: Command line: deferred_init=lazy dhash_entries=131072 ihash_entries=65536 console=ttyS0 reboot=k panic=1 nomodule random.trust_cpu=1 ipv6.disable=1 swiotlb=noforce psi=1 rdinit=/process_api -- --firecracker-init --addr 0.0.0.0:2024 --max-ws-buffer-size 32768 --block-local-connections --listen-vsock-port 2024 --log-vsock-port 5002
Sep 17 21:39:18 889ab814ed00 kernel: BIOS-provided physical RAM map:
Sep 17 21:39:18 889ab814ed00 kernel: BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
Sep 17 21:39:18 889ab814ed00 kernel: BIOS-e820: [mem 0x000000000009fc00-0x00000000000fffff] reserved

$ journalctl -p err --no-pager | tail -5    # priority err and worse
-- No entries --

$ journalctl -t devops-lab --no-pager       # filter by syslog tag
Sep 17 21:40:29 889ab814ed00 devops-lab[275]: test message from the shell via logger

$ journalctl -u systemd-journald --no-pager | tail -4   # one unit
Sep 17 21:39:18 889ab814ed00 systemd-journald[23]: Collecting audit messages is disabled.
Sep 17 21:39:18 889ab814ed00 systemd-journald[23]: Journal started
Sep 17 21:39:18 889ab814ed00 systemd-journald[23]: Runtime Journal (/run/log/journal/1fd53bdb1da24aa7be0f536fc6575c5d) is 8.0M, max 160.6M, 152.6M free.

$ journalctl -o json-pretty -n 1 --no-pager | head -14  # structured fields
{
	"__MONOTONIC_TIMESTAMP" : "310315535",
	"_GID" : "0",
	"SYSLOG_FACILITY" : "1",
	"__SEQNUM" : "408",
	"SYSLOG_TIMESTAMP" : "Sep 17 21:40:29 ",
	"SYSLOG_IDENTIFIER" : "devops-lab",
	"_PID" : "275",
	"_TRANSPORT" : "syslog",
	"_MACHINE_ID" : "1fd53bdb1da24aa7be0f536fc6575c5d",
	"_SOURCE_REALTIME_TIMESTAMP" : "1789681229184909",
	"__CURSOR" : "s=a9923c0db8f84d2c91b31b3f1142ca30;i=198;b=d6b41299d3354445b1e83c5e1fc23bf4;m=127f0a0f;t=65bb4a1ed3fc4;x=b2efdbfea0352ebf",
	"MESSAGE" : "test message from the shell via logger",
	"__SEQNUM_ID" : "a9923c0db8f84d2c91b31b3f1142ca30",

$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.
```

Look at the first block: the journal captured **the `userdel` calls from Task 2** without anything
being configured. That is the point of the journal — every unit, the kernel and anything calling
`syslog()` writes to one place automatically.

Some things worth noticing:

- `journalctl -b` starts with the **kernel boot line**. The journal spans kernel and userspace,
  which a plain `/var/log/*.log` file does not.
- `journalctl -p err` returned **`-- No entries --`**. A clean system with nothing to report is a
  valid, useful answer — this is usually the first command to run on a machine behaving oddly.
- `-t devops-lab` found the exact line written with `logger`, showing how a script can put its own
  entries into the journal instead of managing a log file.
- `-o json-pretty` shows the journal is **not text**. It is a binary store of indexed key-value
  records — `_PID`, `_TRANSPORT`, `_MACHINE_ID`, `__CURSOR`. Filtering by unit or priority is an index
  lookup, not a `grep`. That is why `journalctl -u nginx -p err --since "1 hour ago"` is fast on a
  machine with gigabytes of logs.
- `--disk-usage` reports 8.0M. The journal is capped (here 160.6M) and rotates itself, so it cannot
  fill the disk the way an unmanaged log file can.

Priority levels, highest to lowest: `emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info`,
`debug`. `-p err` means "err and everything more severe".

### Flags worth remembering

| Command | Use |
| --- | --- |
| `journalctl -u <unit> -f` | live-tail one service — the `tail -f` of systemd |
| `journalctl -u <unit> --since "10 min ago"` | narrow to an incident window |
| `journalctl -b -1` | the **previous** boot — what happened before the crash |
| `journalctl -p err -b` | all errors this boot |
| `journalctl -k` | kernel messages only (like `dmesg`) |
| `journalctl --disk-usage` / `--vacuum-time=7d` | check and trim journal size |
| `journalctl -o json` | machine-readable, for log shipping |

---

## Task 4 — Linux command cheat sheet

### Files and directories

| Command | What it does |
| --- | --- |
| `ls -lah` | long listing, human sizes, including dotfiles |
| `ls -li` | show inode numbers (used in Task 1) |
| `cd -` | jump back to the previous directory |
| `cp -r src dst` | copy recursively |
| `mv -n a b` | move/rename, **never** overwrite silently |
| `rm -rf dir` | delete recursively — no undo, check twice |
| `mkdir -p a/b/c` | create nested directories, no error if they exist |
| `ln -s target name` | symbolic link |
| `stat file` | inode, links, size, timestamps, permissions |
| `du -sh dir` | total size of a directory |
| `df -h` | free space per filesystem |
| `find . -name "*.log" -mtime +7` | files matching a name, older than 7 days |
| `tree -L 2` | directory structure, 2 levels deep |

### Reading and searching

| Command | What it does |
| --- | --- |
| `cat` / `less` / `head -n 20` / `tail -n 20` | read a file whole, paged, or from either end |
| `tail -f file` | follow a file as it grows |
| `grep -rn "pattern" .` | recursive search with line numbers |
| `grep -i` / `-v` / `-c` | case-insensitive / invert match / count |
| `wc -l` | count lines |
| `sort` / `uniq -c` | sort; count duplicates (use together) |
| `cut -d: -f1 /etc/passwd` | pick a field from delimited text |
| `awk '{print $1, $3}'` | column extraction and arithmetic |
| `sed -i 's/old/new/g' file` | in-place find and replace |
| `diff -u a b` | unified diff between two files |

### Permissions and ownership

| Command | What it does |
| --- | --- |
| `chmod 644 file` | `rw-r--r--` — owner writes, everyone reads |
| `chmod 755 script.sh` | `rwxr-xr-x` — the normal mode for executables |
| `chmod +x script.sh` | add the execute bit |
| `chown user:group file` | change owner and group |
| `umask` | default permission mask for new files |
| `sudo -u user cmd` | run one command as another user |

Octal reads as **owner / group / other**, where `4=read, 2=write, 1=execute`. So `750` is
`rwx` for the owner, `r-x` for the group, nothing for anyone else.

### Users and groups

| Command | What it does |
| --- | --- |
| `whoami` / `id` | current user; UID, GID and all groups |
| `useradd -m -s /bin/bash u` | create a user portably, with a home directory |
| `adduser u` | create a user interactively (Debian/Ubuntu) |
| `userdel -r u` | delete a user **and** their home directory |
| `passwd u` / `passwd -S u` | set a password / show its status |
| `usermod -aG docker u` | add to a group — `-a` is essential, without it you *replace* groups |
| `groups u` | list a user's groups |

### Processes

| Command | What it does |
| --- | --- |
| `ps aux` | every process on the system |
| `ps -ef --forest` | process tree with parentage |
| `top` / `htop` | live resource usage |
| `kill <pid>` | polite stop (SIGTERM) |
| `kill -9 <pid>` | forced kill (SIGKILL) — last resort, no cleanup |
| `pkill -f "pattern"` | kill by command line |
| `pgrep -f "pattern"` | find PIDs by command line |
| `jobs` / `fg` / `bg` / `Ctrl-Z` | shell job control |
| `nohup cmd &` | keep running after logout |

`SIGTERM` asks a process to shut down and lets it clean up; `SIGKILL` cannot be caught or ignored.
Always try `kill` before `kill -9` — the same distinction as a pod's graceful termination period.

### Services (systemd)

| Command | What it does |
| --- | --- |
| `systemctl status <unit>` | is it running, and the last few log lines |
| `systemctl start` / `stop` / `restart` | control a unit now |
| `systemctl enable` / `disable` | control whether it starts at boot |
| `systemctl list-units --failed` | everything currently broken |
| `systemctl daemon-reload` | reload unit files after editing one |
| `journalctl -u <unit> -f` | follow that unit's logs (Task 3) |

`enable` and `start` are independent: `enable` without `start` takes effect only after a reboot.

### Archives and transfer

| Command | What it does |
| --- | --- |
| `tar czf out.tar.gz dir/` | create a gzipped archive |
| `tar xzf out.tar.gz` | extract one |
| `tar tzf out.tar.gz` | list contents without extracting |
| `scp file user@host:/path` | copy over SSH |
| `rsync -avz src/ user@host:dst/` | sync, transferring only differences |

### Pipes and redirection

| Syntax | Meaning |
| --- | --- |
| `cmd > file` | stdout to file, **overwriting** |
| `cmd >> file` | stdout to file, appending |
| `cmd 2> file` | stderr to file |
| `cmd > file 2>&1` | both streams to one file |
| `cmd &> /dev/null` | discard all output |
| `a \| b` | stdout of `a` into stdin of `b` |
| `a && b` | run `b` only if `a` succeeded |
| `a \|\| b` | run `b` only if `a` failed |
| `$(cmd)` | substitute the command's output |

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | Soft vs hard link | shared inode `1335309`; hard link survived `rm`, symlink dangled |
| 2 | `adduser` vs `useradd` | `useradd` made no home dir and a locked account; `adduser` did the lot |
| 3 | `journalctl` | filtered by count, boot, priority, tag, unit; structured JSON underneath |
| 4 | Cheat sheet | files, search, permissions, users, processes, services, archives, redirection |
