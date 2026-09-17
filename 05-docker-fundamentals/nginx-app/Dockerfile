# Static site served by nginx.
# No build step: copy the HTML into the image's default web root.
FROM nginx:1.25-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
# The base image already defines CMD ["nginx", "-g", "daemon off;"]
