FROM nginxinc/nginx-unprivileged:1.31-alpine
COPY k8s/static/ /usr/share/nginx/html/
