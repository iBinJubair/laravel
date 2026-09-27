FROM php:8.4-apache-bookworm
SHELL ["/bin/bash", "-c"]


# Install Linux Packages
ENV NODE_MAJOR_VERSION=24
ENV LINUX_PACKAGES='\
    ## User Interaction
        nano \
        sudo \
        wget \
        default-mysql-client \
        mariadb-client \
    ## Version Control
        git \
        subversion \
    ## Packages Maanger
        unzip \
        zip \
        7zip \
        nodejs \
    ## Jobs
        cron \
        logrotate \
        supervisor \
    ## Other
        locales \
        #ghostscript \
    '
RUN set -eux \
    && apt -qq update \
    && apt -qq upgrade -y \
    && curl -fsSL https://deb.nodesource.com/setup_$NODE_MAJOR_VERSION.x | bash - \
    && apt -qq install -y --no-install-recommends $LINUX_PACKAGES \
    && npm install -g npm@latest pnpm@latest \
    && rm -rf /var/lib/apt/lists/*


# Configure Linux Local
RUN set -eux \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8


# Install PHP Composer
ENV PHP_COMPOSER_VERSION=latest-stable
RUN set -eux \
    && curl -s -L -o /usr/local/bin/composer "https://getcomposer.org/download/${PHP_COMPOSER_VERSION}/composer.phar" \
    && chmod +x /usr/local/bin/composer


# Install PHP Extensions 
ENV PHP_EXTENSIONS='\
        bcmath \
        bz2 \
        calendar \
        #core is included \
        #ctype is included \
        #curl is included \
        #date is included \
        #dom is included \
        exif \
        #fileinfo is included \
        #filter is included \
        ftp \
        gd \
        gettext \
        gmp \
        #hash is included \
        #iconv is included \
        igbinary \
        imagick \
        #imap \
        intl \
        #json is included \
        #libxml is included \
        #mbstring is included \
        mysqli \
        #mysqlnd is included \
        #openssl is included \
        #opcache is included \
        pcntl \
        #pcre is included \
        #pdo is included \
        pdo_mysql \
        #pdo_sqlite is included \
        #phar is included \
        #posix is included \
        #random is included \
        redis \
        #readline is included \
        #reflection is included \
        #session is included \
        #SimpleXML is included \
        soap \
        sockets \
        #sodium is included \
        #spl is included \
        #sqlite3 is included \
        #standard is included \
        #tidy \
        #timezonedb \
        #tokenizer is included \
        uuid \
        #xml is included \
        #xmlreader is included \
        xmlrpc \
        #xmlwriter is included \
        xsl \
        zip \
        #zlip is included \
    '
RUN set -eux \
    && curl -s -L -o /usr/local/bin/install-php-extensions "https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions" \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions $PHP_EXTENSIONS \
    && rm -rf /var/lib/apt/lists/*


# Configure Apache & PHP
RUN set -eux; \
    { \
        echo 'opcache.memory_consumption=512'; \
        echo 'opcache.interned_strings_buffer=64'; \
        echo 'opcache.max_accelerated_files=52145'; \
        echo 'opcache.revalidate_freq=2'; \
        echo 'opcache.validate_timestamps=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
    \
    { \
        echo 'memory_limit=512M'; \
        echo 'max_execution_time=300'; \
        echo 'max_input_time=300'; \
        echo 'max_input_var=5000'; \
        echo 'file_uploads=On'; \
        echo 'upload_max_filesize=256M'; \
        echo 'post_max_size=256M'; \
        echo 'expose_php=Off'; \
    } > /usr/local/etc/php/conf.d/php-recommended.ini; \
    \
    { \
        echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_USER_ERROR | E_USER_WARNING | E_USER_DEPRECATED | E_RECOVERABLE_ERROR'; \
        echo 'display_errors = Off'; \
        echo 'display_startup_errors = Off'; \
        echo 'log_errors = On'; \
        echo 'error_log = /var/www/storage/logs/php.log'; \
        echo 'log_errors_max_len = 1024'; \
        echo 'ignore_repeated_errors = On'; \
        echo 'ignore_repeated_source = Off'; \
        echo 'html_errors = Off'; \
    } > /usr/local/etc/php/conf.d/error-logging.ini
	

RUN set -eux \
    && a2enmod rewrite expires ssl \
    && a2ensite default-ssl \
    && openssl req -x509 -out /etc/ssl/certs/ssl-cert-snakeoil.pem -keyout /etc/ssl/private/ssl-cert-snakeoil.key -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <( printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth") \
    && cp /etc/ssl/certs/ssl-cert-snakeoil.pem /usr/local/share/ca-certificates/domain.crt \
    && update-ca-certificates
RUN set -eux \
    && mkdir -p /var/www/public \
    && rm -rf /var/www/html \
    && sed -ri -e 's!/var/www/html!/var/www/public!g' \
        /etc/apache2/apache2.conf \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/conf-available/*.conf \
    && a2enmod remoteip \
    && { \
        echo 'RemoteIPHeader X-Forwarded-For'; \
        # these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
        echo 'RemoteIPInternalProxy 10.0.0.0/8'; \
        echo 'RemoteIPInternalProxy 172.16.0.0/12'; \
        echo 'RemoteIPInternalProxy 192.168.0.0/16'; \
        echo 'RemoteIPInternalProxy 169.254.0.0/16'; \
        echo 'RemoteIPInternalProxy 127.0.0.0/8'; \
    } > /etc/apache2/conf-available/remoteip.conf \
    && a2enconf remoteip \
	&& sed -i '/Alias \/icons\//, /<\/Directory>/ s/^/#/' /etc/apache2/mods-enabled/alias.conf \
    && find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +


# Configure Linux Cron & Supervisor
RUN set -eux \
    && touch /var/log/cron.log \
    && { \
        echo '* * * * * www-data cd /var/www && /usr/local/bin/php artisan schedule:run >> /var/www/storage/logs/schedule.log 2>&1'; \
        echo '5 0 * * * root logrotate -f /etc/logrotate.d/laravel >> /var/www/storage/logs/logrotate.log 2>&1'; \
        # Empty line required at the end of this file for cron to be valid
        echo ''; \
    } > /etc/cron.d/laravel \
	&& chmod 0644 /etc/cron.d/laravel \
    && crontab /etc/cron.d/laravel \
    && cat <<'EOF' > /etc/logrotate.d/laravel
/var/www/storage/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0640 www-data www-data
}
EOF
RUN set -eux \
    && mkdir -p /var/www/storage/logs \
    && touch /var/www/storage/logs/cron.log \
             /var/www/storage/logs/supervisor.log \
             /var/www/storage/logs/schedule.log \
             /var/www/storage/logs/queue.log \
    && cat <<'EOF' > /etc/supervisor/conf.d/laravel.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/www/storage/logs/supervisor.log
pidfile=/var/run/supervisord.pid

[program:cron]
command=cron -f
stdout_logfile=/var/www/storage/logs/cron.log
stderr_logfile=/var/www/storage/logs/cron.log
autorestart=true

[program:apache2]
command=apache2-foreground
stderr_logfile=/var/www/storage/logs/apache2.log
stdout_logfile=/var/www/storage/logs/apache2.log
autostart=true
autorestart=true

[program:laravel-queue]
process_name=%(program_name)s_%(process_num)02d
directory=/var/www
command=php /var/www/artisan --sleep=3 --tries=3 --backoff=10 --max-time=3600 --timeout=120
stdout_logfile=/var/www/storage/logs/queue.log
stderr_logfile=/var/www/storage/logs/queue.log
user=www-data
numprocs=4
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stopwaitsecs=3600
EOF


# Configure Laravel Project
RUN set -eux \
	&& mkdir -p /var/www/.ssh \
	&& chmod 700 /var/www/.ssh \
    && cd /var/www/ \
    && git init \
	## Add git url
    && git remote add origin git@github.com:laravel/laravel.git \
    && { \
        echo 'Host github.com'; \
        echo '    User git'; \
        echo '    IdentityFile /var/www/.ssh/git_deploy_key'; \
        echo '    IdentitiesOnly yes'; \
    } > /var/www/.ssh/config \
    ## Add git deploy key to this file
    && touch /var/www/.ssh/git_deploy_key \
    && chmod 0600 /var/www/.ssh/git_deploy_key


# Configure User Interaction
RUN set -eux \
	&& ln -sf /bin/bash /bin/sh \
	&& usermod -s /bin/bash www-data \
	&& usermod -d /var/www www-data \
	&& passwd -d www-data \
	&& { \
		echo 'export PS1="\[\e[01;32m\]\u@\h\[\e[0m\]:\[\e[01;34m\]\w\[\e[0m\]\$ "'; \
		echo 'alias ls="ls --color=auto"'; \
		echo 'alias grep="grep --color=auto"'; \
		echo 'alias fgrep="fgrep --color=auto"'; \
		echo 'alias egrep="egrep --color=auto"'; \
	}  >> /var/www/.bashrc \
	&& chown -R www-data:www-data /var/www
ENV SHELL=/bin/bash
ENV TERM=xterm-256color
WORKDIR /var/www/
#USER www-data

VOLUME ["/var/www"]
EXPOSE 443 80
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/laravel.conf"]
