FROM szabacsik/php-fpm-phalcon-nginx-bookworm:latest

LABEL org.opencontainers.image.title="PHP Boilerplate (Nginx + PHP-FPM + Phalcon)"
LABEL org.opencontainers.image.description="Minimal image to run with AWS App Runner using szabacsik/php-fpm-phalcon-nginx-bookworm base image."
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.authors="András Szabácsik <https://github.com/szabacsik>"

WORKDIR /var/www/html

# Prepare runtime directories and permissions for non-root Nginx + PHP-FPM before switching USER
RUN set -eux; \
  mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi \
           /var/cache/nginx /var/log/nginx /var/run/nginx /run/php; \
  chown -R www-data:www-data /var/lib/nginx /var/cache/nginx /var/log/nginx /var/run/nginx /run/php /var/www/html

# Silence 'user' warning and move Nginx PID file to a writable path for non-root
RUN set -eux; \
    mkdir -p /var/run/nginx; \
    sed -ri 's/^\s*user\s+[^;]+;/# user disabled for non-root/' /etc/nginx/nginx.conf || true; \
    if grep -q '^\s*pid\s\+' /etc/nginx/nginx.conf; then \
      sed -ri 's|^\s*pid\s+[^;]+;|pid /var/run/nginx/nginx.pid;|' /etc/nginx/nginx.conf; \
    else \
      sed -ri '1a pid /var/run/nginx/nginx.pid;' /etc/nginx/nginx.conf; \
    fi

# Optional: route nginx logs to container logs (stdout/stderr)
RUN ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log

# Copy app code with proper ownership for non-root runtime
COPY --chown=www-data:www-data app/public/ /var/www/html/


# Drop privileges; base image includes www-data
USER www-data

EXPOSE 8080
