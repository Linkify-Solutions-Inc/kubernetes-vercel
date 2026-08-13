FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

USER 1000

EXPOSE 8081

CMD ["npm", "start"]
# build 2026-08-13 v8
