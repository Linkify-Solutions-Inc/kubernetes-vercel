FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

# Run as non-root (REQ-6-5)
USER 1000

EXPOSE 3000

CMD ["npm", "start"]
# build 2026-08-13 v8
