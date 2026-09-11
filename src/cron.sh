#!/usr/bin/env bash

# Configure bash behavior
set -o errexit  # exit on failed command
set -o nounset  # exit on undeclared variables
set -o pipefail # exit on any failed command in pipes

# Verbosity settings
: ${VERBOSE=1}
if [ ${VERBOSE} -ge 2 ]; then
  set -o xtrace
fi

# Prefix each line passed via stdin as formated log and ensure a proper new-line
log_line () {
  LEVEL="${1?No level specified}"
  sed -e "s/^/$(date "+%F %T,%3N") "${LEVEL}" cron: /" -e '$a\'
}

# Call the cron.php job every minute while processing its stdout as INFO,
# and its stderr as ERROR.  Also avoid to exit the loop on error.
while true; do
  { php -f cron.php | log_line INFO; } 3>&1 1>&2 2>&3 | log_line ERROR || true
  sleep 60
done
