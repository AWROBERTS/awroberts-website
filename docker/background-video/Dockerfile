FROM nginx:alpine

RUN mkdir -p /usr/share/nginx/html/stream

COPY background.mp4 /videos/background.mp4

COPY ./static/ /usr/share/nginx/html/

# Expose port
EXPOSE 80
