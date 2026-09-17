#!/usr/bin/env bash
#
# System Information Script — DevOps Homework (Shell Scripting)
#
# Demonstrates: variables, command substitution, user input with `read -p`,
# creating a directory with mkdir and a file with touch, and writing the
# running process list into that file using `>` output redirection.

set -u   # treat an unset variable as an error

# ---------------------------------------------------------------------------
# 1. Variables — store values once, reuse them below
# ---------------------------------------------------------------------------
SCRIPT_NAME="System Information Script"
HOSTNAME_VALUE=$(hostname)          # $( ) is command substitution
KERNEL_VALUE=$(uname -r)
OS_VALUE=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
ARCH_VALUE=$(uname -m)
CURRENT_USER=$(whoami)
UPTIME_VALUE=$(uptime -p 2>/dev/null || uptime)
DATE_VALUE=$(date '+%Y-%m-%d %H:%M:%S')
CPU_COUNT=$(nproc)
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')

# ---------------------------------------------------------------------------
# 2. Print the report
# ---------------------------------------------------------------------------
echo "=========================================="
echo "  ${SCRIPT_NAME}"
echo "=========================================="
echo "Date            : ${DATE_VALUE}"
echo "Hostname        : ${HOSTNAME_VALUE}"
echo "Operating system: ${OS_VALUE}"
echo "Kernel          : ${KERNEL_VALUE}"
echo "Architecture    : ${ARCH_VALUE}"
echo "Logged in as    : ${CURRENT_USER}"
echo "Uptime          : ${UPTIME_VALUE}"
echo "CPU cores       : ${CPU_COUNT}"
echo "Memory          : ${MEM_USED} used of ${MEM_TOTAL}"
echo "Disk (/)        : ${DISK_USAGE}"
echo "=========================================="
echo

# ---------------------------------------------------------------------------
# 3. Take user input with `read -p`
#    -r stops backslashes being treated as escapes.
#    If nothing is typed, fall back to a default.
# ---------------------------------------------------------------------------
read -r -p "Enter a name for the output directory [system_info]: " DIR_NAME
DIR_NAME="${DIR_NAME:-system_info}"        # :- supplies the default

read -r -p "Enter a name for the process log file [process.log]: " FILE_NAME
FILE_NAME="${FILE_NAME:-process.log}"

echo

# ---------------------------------------------------------------------------
# 4. Create the directory with mkdir and the file with touch
# ---------------------------------------------------------------------------
mkdir -p "${DIR_NAME}"                     # -p: no error if it already exists
echo "Created directory : ${DIR_NAME}"

touch "${DIR_NAME}/${FILE_NAME}"           # touch creates an empty file
echo "Created file      : ${DIR_NAME}/${FILE_NAME}"

# ---------------------------------------------------------------------------
# 5. Write the running processes into the file with `>` redirection
#    `>` overwrites the file; `>>` would append to it.
# ---------------------------------------------------------------------------
ps aux > "${DIR_NAME}/${FILE_NAME}"

PROC_COUNT=$(($(wc -l < "${DIR_NAME}/${FILE_NAME}") - 1))   # minus the header row
echo "Wrote ${PROC_COUNT} running processes into ${DIR_NAME}/${FILE_NAME}"

# Append the system summary after the process list, to show >> as well
{
  echo
  echo "--- captured $(date '+%Y-%m-%d %H:%M:%S') on ${HOSTNAME_VALUE} ---"
} >> "${DIR_NAME}/${FILE_NAME}"

echo
echo "Done. Preview of the first 5 lines:"
head -n 5 "${DIR_NAME}/${FILE_NAME}"
