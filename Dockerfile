FROM ruby:3.1-slim

ARG APT_MIRROR="mirrors.cloud.tencent.com"
ARG BUNDLER_MIRROR="https://mirrors.cloud.tencent.com/rubygems/"

RUN sed -i -E "s/deb.debian.org/${APT_MIRROR}/g" /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends build-essential git && \
    apt-get clean

RUN gem sources --add ${BUNDLER_MIRROR} --remove https://rubygems.org/ && \
    bundle config set mirror.https://rubygems.org/ ${BUNDLER_MIRROR} && \
    bundle config set --local path "/rubygems"

WORKDIR /app
