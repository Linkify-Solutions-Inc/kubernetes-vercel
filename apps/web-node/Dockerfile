FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src
COPY public ./public

USER 1000 # node image UID — numeric so runAsNonRoot can verify

EXPOSE 8080

CMD ["npm", "start"]
# build 2026-08-13 v8
