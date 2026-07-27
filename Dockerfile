FROM nginx:alpine
COPY index.html next_logo.png /usr/share/nginx/html/
EXPOSE 80
