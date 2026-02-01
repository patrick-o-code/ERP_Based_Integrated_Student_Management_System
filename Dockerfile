# Use PHP 8.1 with Apache
FROM php:8.1-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libpq-dev \
    libmysqlclient-dev \
    locales \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    mysqli \
    pgsql \
    mbstring \
    gettext \
    intl \
    gd \
    curl \
    xml \
    zip \
    opcache

# Install wkhtmltopdf for PDF generation
RUN wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb \
    && dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb \
    && rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Set up locales
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "es_ES.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# Enable Apache mod_rewrite
RUN a2enmod rewrite

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html/

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Create necessary directories with proper permissions
RUN mkdir -p /var/www/html/assets/FileUploads \
    /var/www/html/assets/StudentPhotos \
    /var/www/html/assets/UserPhotos \
    && chown -R www-data:www-data /var/www/html/assets

# Configure PHP
RUN echo "upload_max_filesize = 50M" >> /usr/local/etc/php/conf.d/uploads.ini \
    && echo "post_max_size = 51M" >> /usr/local/etc/php/conf.d/uploads.ini \
    && echo "max_execution_time = 240" >> /usr/local/etc/php/conf.d/timeouts.ini \
    && echo "max_input_vars = 4000" >> /usr/local/etc/php/conf.d/max_input_vars.ini \
    && echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/memory.ini \
    && echo "session.gc_maxlifetime = 3600" >> /usr/local/etc/php/conf.d/session.ini

# Expose port 80
EXPOSE 80

# Start Apache
CMD ["apache2-foreground"]
