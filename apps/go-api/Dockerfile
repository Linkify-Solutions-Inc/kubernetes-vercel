FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go .
RUN CGO_ENABLED=0 go build -trimpath -o /out/go-api .

FROM alpine:3.20
RUN adduser -D -u 10001 appuser
COPY --from=build /out/go-api /usr/local/bin/go-api
USER 10001 # numeric — runAsNonRoot needs a numeric UID
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/go-api"]
# build 2026-08-13 v7
