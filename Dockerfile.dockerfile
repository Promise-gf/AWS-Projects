# Build stage
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

# Runtime stage
FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app .
EXPOSE 80
USER node
CMD ["node", "server.js"]