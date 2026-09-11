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

# Save the current directory
__CWD="$(pwd)"

# logging functions
# Credits: https://github.com/MariaDB/mariadb-docker/blob/master/docker-entrypoint.sh
suitecrm_log() {
  local type="${1^^}"; shift
  printf '%s %s entrypoint: %s\n' "$(date "+%F %T,%3N")" "$type" "$*"
}
suitecrm_info() {
  suitecrm_log INFO "$@"
}
suitecrm_warn() {
  suitecrm_log WARN "$@" >&2
}
suitecrm_error() {
  suitecrm_log ERROR "$@" >&2
  exit 1
}

# Clean exit
on_exit () {
  cd "${__CWD}"
  suitecrm_info "Initialization process terminated"
}

trap "on_exit" EXIT

fix_perm () {
  [ -f config.php ] || touch config.php
  [ -f config_override.php ] || echo '<?php' > config_override.php
  [ -f .htaccess ] || touch .htaccess
  [ -d php-sessions ] || mkdir php-sessions
  chown -R "${WEB_USER}":"${WEB_GROUP}" .
  chmod -R u+wrX,go+rX,go-w .
  chmod -R ug+wrX cache custom modules themes data upload config_override.php .htaccess php-sessions
  chmod +x vendor/bin/*
}

# Ensure a line is present in a file
ensure_line () {
  LINE="${1:?No line specified!}"
  FILE="${2:?No file specified!}"
  grep -qxF "${LINE}" "${FILE}" || echo "${LINE}" >> "${FILE}"
}

# The configuration needs to be adapted
adapt_config () {
  # We need a new line to work at the end of config_override.php
  sed -i -e '$a\' config_override.php
  # The apache user needs to be accepted for the cron jobs
  ensure_line "\$sugar_config['cron']['allowed_cron_users'][-1] = '${WEB_USER}';" config_override.php
}

suitecrm_info "Initialization process started"

# Ensure work is done in the state directory
[ "${__CWD}" = "${SUITECRM_STATE_DIR}" ] || cd "${SUITECRM_STATE_DIR}"

if [ -s suitecrm_version.php ]; then
  fix_perm
  CURRENT_VERSION="$(grep -Po '(?<=^\$suitecrm_version = ).+' "${SUITECRM_STATE_DIR}"/suitecrm_version.php | cut -d"'" -f2)"
  suitecrm_info "Version ${CURRENT_VERSION} detected"
  if [ ! -s config.php ]; then
    suitecrm_warn "Not yet configured! Visit install.php"
  elif [ "${CURRENT_VERSION}" = "${SUITECRM_VERSION}" ]; then
    suitecrm_info "Nothing to upgrade"
  else
    suitecrm_info "Upgrade required to ${SUITECRM_VERSION}"
    UPGRADE_VERSION_REX=${SUITECRM_UPGRADE_VERSION//./\\.}
    UPGRADE_VERSION_REX=${UPGRADE_VERSION_REX/%x/}
    if [[ "${CURRENT_VERSION}" =~ ${UPGRADE_VERSION_REX} ]]; then
      ./vendor/bin/robo cache:clean --force
      ./vendor/bin/robo upgrade:suite \
      "${SUITECRM_SRC_DIR}"/"${SUITECRM_UPGRADE_ZIP}" \
      ./suitecrm_upgrade.log \
      . "${SUITECRM_ADMIN_USER}"
      fix_perm
    else
      suitecrm_error "Can not upgrade this version!"
    fi
  fi
else
  suitecrm_info "Version not detected. Installing ${SUITECRM_VERSION}..."
  # Create a symlink for the sub-directory we want to skip
  ln -s . SuiteCRM-"${SUITECRM_VERSION}"
  # Extract the archive in the state directory
  unzip -q "${SUITECRM_SRC_DIR}"/"${SUITECRM_ZIP}" -d .
  # Remove the symlink - the sub-directory has been skipped
  rm SuiteCRM-"${SUITECRM_VERSION}"
  fix_perm
  suitecrm_info "Installation completed"
  suitecrm_warn "Not yet configured! Visit install.php"
fi

adapt_config

exec "$@"
