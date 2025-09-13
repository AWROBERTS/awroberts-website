FROM alpine:latest

# Install NGINX
RUN apk add --no-cache nginx

# Remove default config and web files
RUN rm -rf /etc/nginx/conf.d/* /var/www/localhost/htdocs/*

# Copy your custom config and site files
COPY nginx.conf /etc/nginx/nginx.conf
COPY . /usr/share/nginx/html

# Run NGINX in foreground
CMD ["nginx", "-g", "daemon off;"]

EXPOSE 80
