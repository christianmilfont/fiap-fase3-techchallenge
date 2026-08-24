FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o auth-service .

FROM alpine:3.19
ENV TZ=America/Sao_Paulo
RUN apk --no-cache add ca-certificates tzdata postgresql16-client && \
    cp /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone
WORKDIR /app
COPY --from=builder /app/auth-service .
COPY db/init.sql .
COPY entrypoint.sh .
RUN chmod +x ./entrypoint.sh
EXPOSE 8001
ENTRYPOINT ["./entrypoint.sh"]
