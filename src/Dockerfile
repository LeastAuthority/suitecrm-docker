FROM php:8.3-apache-bookworm@sha256:fa8852a2e01747ffe8c8768bfd6bbc2f296f974aa0de90ee157a66664996d263

ENV APACHE_DOCUMENT_ROOT=/var/www/html \
    SUITECRM_STATE_DIR=/var/lib/suitecrm \
    TZ=UTC

RUN apt-get -q clean && \
    apt-get -q update && \
    apt-get install -y --no-install-recommends \
    cron \
    curl \
    default-mysql-client \
    gosu \
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

RUN mkdir -p \
    /var/lib/suitecrm/logs \
    /var/lib/suitecrm/php-sessions \
    /var/lib/suitecrm/tmp \
    /var/log/supervisor \
    /var/run/supervisor

RUN chmod 0644 /etc/cron.d/suitecrm \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && touch /var/log/cron.log \
    && chown -R www-data:www-data /var/lib/suitecrm /var/log/cron.log

USER www-data
ENV SUITECRM_TMP=/tmp/suitecrm
ENV SUITECRM_VERSION=7.15.2
ENV SUITECRM_CHECKSUM=9d66c7f6e14f4f1dc4c4605185be6fb97ad1902c0026ff326a7c20e9a4901180
RUN curl --location --no-progress-meter --output "${SUITECRM_TMP}".zip \
    https://github.com/SuiteCRM/SuiteCRM/releases/download/v"${SUITECRM_VERSION}"/SuiteCRM-"${SUITECRM_VERSION}".zip \
    && test "$(sha256sum "${SUITECRM_TMP}".zip | cut -d' ' -f1)" = "${SUITECRM_CHECKSUM}"
RUN unzip -q "${SUITECRM_TMP}".zip -d "${SUITECRM_TMP}" \
    && mv "${SUITECRM_TMP}"/SuiteCRM*/* /var/www/html/ \
    && rm -rf "${SUITECRM_TMP}"*

USER root

WORKDIR /var/www/html

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 CMD curl -fsS http://127.0.0.1/ >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/suitecrm.conf"]
