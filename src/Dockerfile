FROM php:8.3-apache-bookworm@sha256:fa8852a2e01747ffe8c8768bfd6bbc2f296f974aa0de90ee157a66664996d263

ENV WEB_USER=www-data \
    WEB_GROUP=www-data \
    SUITECRM_STATE_DIR=/var/lib/suitecrm \
    SUITECRM_SRC_DIR=/src/suitecrm \
    TZ=UTC

RUN apt-get -q clean && \
    apt-get -q update && \
    apt-get install -y --no-install-recommends \
    cron \
    curl \
    default-mysql-client \
    libcurl4-openssl-dev \
    libfreetype6-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libonig-dev \
    libpng-dev \
    libxml2-dev \
    libzip-dev \
    supervisor \
    unzip \
    && \
    apt-get -q clean

RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install -j"$(nproc)" \
    curl \
    gd \
    intl \
    mbstring \
    mysqli \
    opcache \
    pdo_mysql \
    soap \
    zip \
    && \
    pecl install apcu && \
    docker-php-ext-enable apcu && \
    a2enmod expires headers rewrite

COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY php.ini /usr/local/etc/php/conf.d/zz-suitecrm.ini
COPY crontab /etc/cron.d/suitecrm
COPY supervisord.conf /etc/supervisor/conf.d/suitecrm.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY suitecrmsilentinstall.php /usr/local/bin/suitecrmsilentinstall.php

RUN mkdir -p \
    "${SUITECRM_SRC_DIR}" \
    "${SUITECRM_STATE_DIR}" \
    /var/log/supervisor \
    /var/run/supervisor

RUN chmod 0644 /etc/cron.d/suitecrm \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && touch /var/log/cron.log \
    && chown -R "${WEB_USER}:${WEB_GROUP}" \
    "${SUITECRM_SRC_DIR}" \
    "${SUITECRM_STATE_DIR}" \
    /var/log/cron.log

USER www-data
ENV SUITECRM_VERSION=7.15.1 \
    SUITECRM_CHECKSUM=468b811addd21dfb29d411ee6e815dbdf7099f912347e88cd3e8d010d829db7a
ENV SUITECRM_ZIP=SuiteCRM-"${SUITECRM_VERSION}".zip
RUN curl --location --no-progress-meter --output "${SUITECRM_SRC_DIR}"/"${SUITECRM_ZIP}" \
    https://github.com/SuiteCRM/SuiteCRM/releases/download/v"${SUITECRM_VERSION}"/"${SUITECRM_ZIP}" \
    && test "$(sha256sum "${SUITECRM_SRC_DIR}"/"${SUITECRM_ZIP}" | cut -d' ' -f1)" = "${SUITECRM_CHECKSUM}"

ENV SUITECRM_UPGRADE_VERSION=7.14.x \
    SUITECRM_UPGRADE_CHECKSUM=1541575052121d878a8981a1cead521a89cca1191946e2b7f886baef16b00b74
ENV SUITECRM_UPGRADE_ZIP="SuiteCRM-Upgrade-${SUITECRM_UPGRADE_VERSION}-to-${SUITECRM_VERSION}.zip"
RUN curl --location --no-progress-meter --output "${SUITECRM_SRC_DIR}"/"${SUITECRM_UPGRADE_ZIP}" \
    https://github.com/SuiteCRM/SuiteCRM/releases/download/v"${SUITECRM_VERSION}"/"${SUITECRM_UPGRADE_ZIP}" \
    && test "$(sha256sum "${SUITECRM_SRC_DIR}"/"${SUITECRM_UPGRADE_ZIP}" | cut -d' ' -f1)" = "${SUITECRM_UPGRADE_CHECKSUM}"

# OCI annotations to image
LABEL org.opencontainers.image.authors="LeastAuthority" \
      org.opencontainers.image.title="SuiteCRM" \
      org.opencontainers.image.description="SuiteCRM - Open source CRM for the world" \
      org.opencontainers.image.documentation="https://github.com/LeastAuthority/suitecrm-docker" \
      org.opencontainers.image.base.name="docker.io/library/php:8.3-apache-bookworm" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      org.opencontainers.image.source="https://github.com/LeastAuthority/suitecrm-docker" \
      org.opencontainers.image.vendor="LeastAuthority" \
      org.opencontainers.image.version="${SUITECRM_VERSION}" \
      org.opencontainers.image.url="https://github.com/LeastAuthority/suitecrm-docker"

USER root

WORKDIR /var/lib/suitecrm

ENV SUITECRM_HTTP_PORT=8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 CMD curl -fsS "http://127.0.0.1:${SUITECRM_HTTP_PORT}/index.php" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/suitecrm.conf"]
