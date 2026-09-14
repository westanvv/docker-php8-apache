FROM php:8.5.10-apache-bookworm

WORKDIR /var/www

#####################################
# System packages
#####################################
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cron \
        curl \
        ghostscript \
        gifsicle \
        git \
        imagemagick \
        jpegoptim \
        less \
        libjpeg-turbo-progs \
        mariadb-client \
        mc \
        msmtp \
        msmtp-mta \
        openssh-server \
        optipng \
        pngquant \
        poppler-utils \
        unzip \
        webp \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    # allow ImageMagick to read/write PDF (disabled by Debian policy)
    && sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml

#####################################
# PHP extensions
# curl, iconv, mbstring, simplexml, tokenizer, xml and opcache
# are already built into the official php:8.5 image.
# -dev packages are removed after the build, runtime libraries are kept.
#####################################
RUN savedAptMark="$(apt-mark showmanual)" \
    && apt-get update && apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libmcrypt-dev \
        libmemcached-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-configure ldap --with-libdir="lib/$(uname -m)-linux-gnu/" \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        ldap \
        mysqli \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        soap \
        xsl \
        zip \
    && pecl install \
        mcrypt-1.0.9 \
        memcached-3.4.0 \
        xdebug-3.5.3 \
    && docker-php-ext-enable \
        mcrypt \
        memcached \
        xdebug \
    # keep only the shared libraries the compiled extensions link against
    && apt-mark auto '.*' > /dev/null \
    && apt-mark manual $savedAptMark > /dev/null \
    && find /usr/local/lib/php/extensions -type f -name '*.so' -exec ldd '{}' ';' \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* /tmp/pear \
    && php -m > /dev/null

######################################
## NodeJS 24, Yarn, Grunt, Gulp
######################################
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm i -g yarn grunt-cli gulp-cli \
    && npm cache clean --force

#####################################
# Composer
#####################################
COPY --from=composer:2.10 /usr/bin/composer /usr/local/bin/composer

#####################################
# FIX Apache
#####################################
RUN rm -R /etc/apache2/sites-enabled/

#####################################
# SSH
# Host keys are generated on container start (see CMD),
# so every container gets its own keys
#####################################
RUN rm -f /etc/ssh/ssh_host_* \
    && echo 'root:root' | chpasswd \
    && mkdir -p /run/sshd \
    && chmod 0755 /run/sshd

#####################################
# Coping configration
#####################################
COPY ./configs/custom.ini /usr/local/etc/php/conf.d/custom.ini
COPY ./configs/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY ./configs/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini
COPY ./configs/sshd_config /etc/ssh/sshd_config
COPY ./configs/apache2.conf /etc/apache2/apache2.conf
COPY ./configs/virtualhost.conf /etc/apache2/sites-enabled/virtualhost.conf
COPY ./configs/ssl/server.crt /etc/apache2/ssl/server.crt
COPY ./configs/ssl/server.key /etc/apache2/ssl/server.key
COPY ./configs/msmtprc /etc/msmtprc

#####################################
# Last touch
#####################################
RUN usermod -u 1000 www-data \
    && rmdir /var/www/html \
    && mkdir -p /tmp/logs /tmp/php /home/www-data \
    && chmod 0600 /etc/msmtprc \
    && chown -R www-data:www-data /var/www /home/www-data /tmp /etc/msmtprc \
    && chmod -R 777 /tmp/logs /tmp/php \
    && chmod 1777 /tmp

# Runs as root so sshd and cron can start; Apache workers (PHP) still run as www-data
EXPOSE 22 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -s -o /dev/null http://127.0.0.1/server-status || exit 1

CMD ["sh", "-c", "ssh-keygen -A >/dev/null; /usr/sbin/sshd || true; cron || true; exec apache2-foreground"]
