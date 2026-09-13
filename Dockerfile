FROM php:8.5.10-apache-bookworm

WORKDIR /var/www

#####################################
# System packages
#####################################
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cron \
        curl \
        g++ \
        ghostscript \
        gifsicle \
        git \
        gnupg \
        imagemagick \
        jpegoptim \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libjpeg-turbo-progs \
        libldap2-dev \
        libmcrypt-dev \
        libmemcached-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libssl-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
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
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

#####################################
# PHP extensions
# curl, iconv, mbstring, simplexml, tokenizer, xml and opcache
# are already built into the official php:8.5 image
#####################################
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-configure intl \
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
    && rm -rf /tmp/pear

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
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

#####################################
# FIX Apache
#####################################
RUN rm -R /etc/apache2/sites-enabled/

#####################################
# SSH
#####################################
RUN rm -f /etc/ssh/ssh_host_* \
    && ssh-keygen -A \
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
    && mkdir -p /tmp/logs /tmp/php /home/www-data \
    && chmod 0600 /etc/msmtprc \
    && chown -R www-data:www-data /var/www /home/www-data /tmp /etc/msmtprc \
    && chmod -R 777 /var/www /tmp

# Runs as root so sshd can start; Apache workers (PHP) still run as www-data
EXPOSE 22

CMD ["sh", "-c", "/usr/sbin/sshd && exec apache2-foreground"]
