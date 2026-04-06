# Build stage: download Hugo and build the site
FROM alpine:3.21 AS builder

ARG HUGO_VERSION=0.147.0

RUN apk add --no-cache wget git libc6-compat libstdc++

RUN wget -O /tmp/hugo.tar.gz \
      "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz" && \
    tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin/ hugo && \
    rm /tmp/hugo.tar.gz

WORKDIR /site
COPY . .

# Handle git submodules: if PaperMod theme is missing, clone it directly.
# This covers the case where the CI/CD system didn't init submodules.
RUN if [ ! -f themes/PaperMod/theme.toml ]; then \
      rm -rf themes/PaperMod && \
      git clone --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod; \
    fi

RUN hugo --minify

# Serve stage: lightweight nginx to serve the static site
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /site/public /usr/share/nginx/html

EXPOSE 80
