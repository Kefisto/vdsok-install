FROM alpine:3.20 AS builder

RUN apk add --no-cache git build-base
RUN git clone --depth 1 https://github.com/Wind4/vlmcsd.git /src
WORKDIR /src
RUN make

FROM alpine:3.20

RUN apk add --no-cache busybox-extras
COPY --from=builder /src/bin/vlmcsd /usr/local/bin/vlmcsd

EXPOSE 1688/tcp

ENTRYPOINT ["/usr/local/bin/vlmcsd", "-D", "-d", "-e"]
