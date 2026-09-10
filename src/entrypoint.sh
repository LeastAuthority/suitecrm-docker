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

# Clean exit
on_exit () {
  cd "${__CWD}"
  echo "[Entrypoint]: SuiteCRM init process done."
}

trap "on_exit" EXIT

fix_perm () {
  [ -f config.php ] || touch config.php
  [ -f config_override.php ] || touch config_override.php
  [ -f .htaccess ] || touch .htaccess
  [ -d php-sessions ] || mkdir php-sessions
  chown -R "${WEB_USER}":"${WEB_GROUP}" .
  chmod -R u+wrX,go+rX,go-w .
  chmod -R ug+wrX cache custom modules themes data upload config_override.php .htaccess php-sessions
  chmod +x vendor/bin/*
}

echo "[Entrypoint]: SuiteCRM init process started."

# Ensure work is done in the state directory
[ "${__CWD}" = "${SUITECRM_STATE_DIR}" ] || cd "${SUITECRM_STATE_DIR}"

if [ -s suitecrm_version.php ]; then
  fix_perm  
  CURRENT_VERSION="$(grep -Po '(?<=^\$suitecrm_version = ).+' "${SUITECRM_STATE_DIR}"/suitecrm_version.php | cut -d"'" -f2)"
  echo "[Entrypoint]: Version ${CURRENT_VERSION} detected."
  if [ ! -s config.php ]; then
    echo "[Entrypoint]: Not yet configured! Visit intall.php"
  elif [ "${CURRENT_VERSION}" = "${SUITECRM_VERSION}" ]; then
    echo "[Entrypoint]: Nothing to upgrade."
  else
    echo "[Entrypoint]: Upgrade required to ${SUITECRM_VERSION}."
    UPGRADE_VERSION_REX=${SUITECRM_UPGRADE_VERSION//./\\.}
    UPGRADE_VERSION_REX=${SUITECRM_UPGRADE_VERSION/%x/}
    if [[ "${CURRENT_VERSION}" =~ ${UPGRADE_VERSION_REX} ]]; then
      ./vendor/bin/robo cache:clean --force
      ./vendor/bin/robo upgrade:suite \
      "${SUITECRM_SRC_DIR}"/"${SUITECRM_UPGRADE_ZIP}" \
      ./suitecrm_upgrade.log \
      . "${SUITECRM_ADMIN_USER}"
      fix_perm
    else
      echo "[Entrypoint]: Can not upgrade this version!"
      exit 1
    fi
  fi
else
  echo -n "[Entrypoint]: Version not detected. Installing ${SUITECRM_VERSION}... "
  # Create a symlink for the sub-directory we want to skip
  ln -s . SuiteCRM-"${SUITECRM_VERSION}"
  # Extract the archive in the state directory
  unzip -q "${SUITECRM_SRC_DIR}"/"${SUITECRM_ZIP}" -d .
  # Remove the symlink - the sub-directory has been skipped
  rm SuiteCRM-"${SUITECRM_VERSION}"
  fix_perm
  echo "done"
  /usr/local/bin/apache2-foreground >> apache_si.log 2>&1 &
  APACHE_PID=$!
  # Wait for the install page (10 x 1 sec)
  curl \
    --head \
    --fail \
    --verbose \
    --show-error \
    --no-progress-meter \
    --retry 10 \
    --retry-delay 1 \
    --retry-all-errors \
    --retry-connrefused \
    "http://127.0.0.1:${SUITECRM_HTTP_PORT}/install.php" \
  || { \
    echo "[Entrypoint]: SuiteCRM install page notfound!"; \
    exit 1; \
  }
  php /usr/local/bin/suitecrmsilentinstall.php \
  --install_location "${SUITECRM_STATE_DIR}" \
  --db_host "${SUITECRM_DATABASE_HOST}" \
  --db_user "${SUITECRM_DATABASE_USER}" \
  --db_pass "${SUITECRM_DATABASE_PASSWORD}" \
  --db_name "${SUITECRM_DATABASE_NAME}" \
  --site_username "${SUITECRM_ADMIN_USER}" \
  --site_pass "${SUITECRM_ADMIN_PASSWORD}" \
  --site_host "${SUITECRM_HTTP_HOST}" \
  --site_port "${SUITECRM_HTTP_PORT}" \
  --site_name "SuiteCRM Silent Install"
  # Wait for the login page (10 x 1 sec)
  curl \
    --head \
    --fail \
    --verbose \
    --show-error \
    --no-progress-meter \
    --retry 10 \
    --retry-delay 1 \
    --retry-all-errors \
    --retry-connrefused \
    "http://127.0.0.1:${SUITECRM_HTTP_PORT}/index.php?module=Users&action=Login" \
  || { \
    echo "[Entrypoint]: SuiteCRM login page notfound!"; \
    exit 1; \
  }
  kill -TERM "${APACHE_PID}"
  echo "[Entrypoint]: SuiteCRM configuration completed"; \
fi

echo "[Entrypoint]: SuiteCRM init process completed."

exec "$@"
