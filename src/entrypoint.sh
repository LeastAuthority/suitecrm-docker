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
  printf '%s %s entrypoint: %s\n' "$(date "+%F %T.%6N")" "$type" "$*"
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
  [ -d "${SUITECRM_LOG_DIR}" ] || mkdir "${SUITECRM_LOG_DIR}"
  chown --reference /var/log/apache2 "${SUITECRM_LOG_DIR}"
  chmod --reference /var/log/apache2 "${SUITECRM_LOG_DIR}"
  chown -R "${WEB_USER}":"${WEB_GROUP}" .
  chmod -R u+wrX,go+rX,go-w .
  chmod -R ug+wrX cache custom modules themes data upload config_override.php .htaccess php-sessions
  chmod +x vendor/bin/*
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
# Credits: https://github.com/MariaDB/mariadb-docker/blob/master/docker-entrypoint.sh
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo "[Entrypoint]: Both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

echo "[Entrypoint]: SuiteCRM init process started."
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
  # Use a separated directory for the logs
  ensure_line "\$sugar_config['log_dir'] = '${SUITECRM_LOG_DIR}';" config_override.php
  # The apache user needs to be accepted for the cron jobs
  ensure_line "\$sugar_config['cron']['allowed_cron_users'][-1] = '${WEB_USER}';" config_override.php
  # Override database password when supplied through the environment
  ensure_line "if (getenv('SUITECRM_DATABASE_PASSWORD') !== false && getenv('SUITECRM_DATABASE_PASSWORD') !== '') { \$sugar_config['dbconfig']['db_password'] = getenv('SUITECRM_DATABASE_PASSWORD'); }" config_override.php
}

suitecrm_info "Initialization process started"

# Ensure work is done in the state directory
[ "${__CWD}" = "${SUITECRM_STATE_DIR}" ] || cd "${SUITECRM_STATE_DIR}"

# Load secrets as environment variable from files, if provided
file_env SUITECRM_DATABASE_PASSWORD
file_env SUITECRM_ADMIN_PASSWORD

if [ -s suitecrm_version.php ]; then
  fix_perm
  adapt_config
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
      ./vendor/bin/robo upgrade:suite \
      "${SUITECRM_SRC_DIR}"/"${SUITECRM_UPGRADE_ZIP}" \
      "${SUITECRM_LOG_DIR}"/upgrade.log \
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
  adapt_config
  suitecrm_info "Installation completed"
  suitecrm_warn "Not yet configured! Visit install.php"
fi

exec "$@"
