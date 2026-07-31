# Replace this file with your application's Dockerfile.
#
# Requirements:
# - Expose port 8080 (Knative default)
# - Handle the PORT environment variable if provided
#
# Example for a Go application:
#
#   FROM golang:1.23-alpine AS builder
#   WORKDIR /app
#   COPY . .
#   RUN go build -o server .
#
#   FROM alpine:3.20
#   WORKDIR /app
#   COPY --from=builder /app/server .
#   EXPOSE 8080
#   CMD ["./server"]
#
# Example for a Node.js application:
#
#   FROM node:20-alpine
#   WORKDIR /app
#   COPY package*.json ./
#   RUN npm ci --only=production
#   COPY . .
#   EXPOSE 8080
#   CMD ["node", "server.js"]

# Placeholder - replace with your application
FROM stefanprodan/podinfo:6.14.1
CMD ["./podinfo", "--port", "8080"]
