FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY k8s/static/ /usr/share/nginx/html/
