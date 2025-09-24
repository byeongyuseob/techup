FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

RUN apt-get update && apt-get install -y \
    nginx \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-cli \
    nfs-common \
    stress \
    htop \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/nfs

COPY nginx.conf /etc/nginx/sites-available/default

RUN sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini

EXPOSE 80

COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]