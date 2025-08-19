FROM node:22 AS build

# Add build argument for the API URL
ARG VITE_API_URL

# Set it as an environment variable
ENV VITE_API_URL=$VITE_API_URL

WORKDIR /app
COPY . /app
COPY .env /app/.env

COPY package*.json /app/

RUN npm ci
RUN npm run build

FROM nginx:latest

# Install Tini
RUN apt-get update && apt-get install -y tini

COPY --from=build /app/dist /usr/share/nginx/html/
COPY srv/nginx.conf /etc/nginx/nginx.conf
COPY srv/mime.types /etc/nginx/mime.types

# Configure tini as the init system
ENTRYPOINT ["/usr/bin/tini", "--"]

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
