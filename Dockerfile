ARG PHP_VERSION="8.0"
ARG DEBIAN_VERSION="bullseye"

FROM php:${PHP_VERSION}-fpm-${DEBIAN_VERSION} as pimcore_php_fpm

RUN set -eux; \
    DPKG_ARCH="$(dpkg --print-architecture)"; \
    apt-get update; \
    apt-get install -y lsb-release; \
    echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        autoconf automake libtool nasm make pkg-config libz-dev build-essential openssl g++ \
        zlib1g-dev libicu-dev libbz2-dev zopfli libc-client-dev default-jre \
        libkrb5-dev libxml2-dev libxslt1.1 libxslt1-dev locales locales-all \
        ffmpeg html2text ghostscript libreoffice pngcrush jpegoptim exiftool poppler-utils git wget \
        libx11-dev python3-pip opencv-data facedetect webp graphviz cmake ninja-build unzip cron \
        liblcms2-dev liblqr-1-0-dev libjpeg-turbo-progs libopenjp2-7-dev libtiff-dev \
        libfontconfig1-dev libfftw3-dev libltdl-dev liblzma-dev libopenexr-dev \
        libwmf-dev libdjvulibre-dev libpango1.0-dev libxext-dev libxt-dev librsvg2-dev libzip-dev \
        libpng-dev libfreetype6-dev libjpeg-dev libxpm-dev libwebp-dev libjpeg62-turbo-dev \
        xfonts-75dpi xfonts-base libjpeg62-turbo \
        libonig-dev optipng pngquant inkscape zip; \
    \
    apt-get install -y libavif-dev libheif-dev optipng pngquant chromium chromium-sandbox; \
    docker-php-ext-configure pcntl --enable-pcntl; \
    docker-php-ext-install pcntl intl mbstring mysqli bcmath bz2 soap xsl pdo pdo_mysql fileinfo exif zip opcache sockets; \
    \
    wget https://imagemagick.org/archive/ImageMagick.tar.gz; \
        tar -xvf ImageMagick.tar.gz; \
        cd ImageMagick-7.*; \
        ./configure; \
        make --jobs=$(nproc); \
        make V=0; \
        make install; \
        cd ..; \
        rm -rf ImageMagick*; \
    \
    docker-php-ext-configure gd -enable-gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install gd; \
    pecl install -f xmlrpc imagick apcu redis; \
    docker-php-ext-enable redis imagick apcu; \
    docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
    docker-php-ext-install imap; \
    docker-php-ext-enable imap; \
    ldconfig /usr/local/lib; \
    \
    cd /tmp; \
    \
    wget -O wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.buster_${DPKG_ARCH}.deb; \
        dpkg -i wkhtmltox.deb; \
        rm wkhtmltox.deb; \
    \
    apt-get install -y openssh-client nodejs npm cifs-utils iputils-ping htop nano autoconf automake libtool m4 librabbitmq-dev; \
    pecl install amqp; \
    docker-php-ext-enable amqp; \
    apt-get install -y python; \
    \
    apt-get autoremove -y; \
        apt-get remove -y autoconf automake libtool nasm make cmake ninja-build pkg-config libz-dev build-essential g++; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* ~/.composer || true; \
    sync;

RUN echo "upload_max_filesize = 1024M" >> /usr/local/etc/php/conf.d/20-pimcore.ini; \
    echo "memory_limit = 521M" >> /usr/local/etc/php/conf.d/20-pimcore.ini; \
    echo "post_max_size = 1024M" >> /usr/local/etc/php/conf.d/20-pimcore.ini
    
RUN echo "user = root" >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
    echo "group = root" >> /usr/local/etc/php-fpm.d/zz-docker.conf;

ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_MEMORY_LIMIT -1
COPY --from=composer/composer:2-bin /composer /usr/bin/composer

RUN groupadd -g 1000 app0; \
    useradd -m -d /home/app0 app0 -u 1000 -g app0 -s /bin/bash; \
    chown app0:app0 /home/app0;
    
RUN groupadd -g 1001 app1; \
    useradd -m -d /home/app1 app1 -u 1001 -g app1 -s /bin/bash; \
    chown app1:app1 /home/app1;

RUN groupadd -g 1002 app2; \
    useradd -m -d /home/app2 app2 -u 1002 -g app2 -s /bin/bash; \
    chown app2:app2 /home/app2;

# Soft-link Chromium browser
RUN ln -s /usr/bin/chromium /usr/bin/chromium-browser
# Uninstall node-sass
RUN npm uninstall node-sass
# Download node.js in version 18 and install it (incl. dependencies)
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y gcc g++ make
# Install npm and sass
#RUN apt install -y nodejs && \
#    npm install -g npm && \
#    npm install sass
# Remove puppeteer and re-install it with correct information about chromium installation
#RUN npm remove puppeteer && \
#    PUPPETEER_EXECUTABLE_PATH=`which chromium-browser` PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true npm install puppeteer && \
#    npm install

WORKDIR /var/www/html

CMD ["php-fpm", "--allow-to-run-as-root"]

FROM pimcore_php_fpm as pimcore_php_debug

RUN apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf automake libtool nasm make pkg-config libz-dev build-essential g++ iproute2; \
    pecl install xdebug; \
    docker-php-ext-enable xdebug; \
    apt-get autoremove -y; \
    apt-get remove -y autoconf automake libtool nasm make pkg-config libz-dev build-essential g++; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* ~/.composer || true

# allow container to run as custom user, this won't work otherwise because config is changed in entrypoint.sh
RUN chmod -R 0777 /usr/local/etc/php/conf.d

ENV PHP_IDE_CONFIG serverName=localhost

COPY files/entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "--allow-to-run-as-root"]

FROM pimcore_php_fpm as pimcore_php_supervisord

RUN apt-get update && apt-get install -y supervisor cron
COPY files/supervisord.conf /etc/supervisor/supervisord.conf

RUN chmod gu+rw /var/run
RUN chmod gu+s /usr/sbin/cron

CMD ["/usr/bin/supervisord"]
