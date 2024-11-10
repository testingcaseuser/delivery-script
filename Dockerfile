FROM golang:1.22-alpine as builder

WORKDIR /app
COPY go.mod main.go ./
RUN go build -o script-server

# Use minimal alpine image for running
FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/script-server ./
COPY script.sh ./

# Make script executable
RUN chmod +x script.sh

EXPOSE 8080

CMD ["./script-server"]
