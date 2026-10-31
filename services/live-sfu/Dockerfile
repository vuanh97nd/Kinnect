FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go test -buildvcs=false ./... && CGO_ENABLED=0 go build -buildvcs=false -trimpath -o /kinnect-sfu .
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /kinnect-sfu /kinnect-sfu
ENV KINNECT_SFU_LISTEN=0.0.0.0:7885 KINNECT_SFU_UDP_PORT=7886
EXPOSE 7885/tcp 7886/udp
ENTRYPOINT ["/kinnect-sfu"]
