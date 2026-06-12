# Multi-stage: install gems on ruby:3.3-slim, run on the same slim base as a non-root user. (No clean
# distroless for Ruby/Rails.) Multi-arch via the slim base; native gems (puma) compile per arch in the build
# stage. Rails serves plain HTTP on :8080 (the platform gateway terminates TLS).
FROM ruby:3.3-slim AS build

WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Install gems first so the layer caches across source-only changes.
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/ruby/*/cache

COPY . .

FROM ruby:3.3-slim

WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libyaml-0-2 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --uid 65532 --create-home --shell /usr/sbin/nologin rails

# secret_key_base is NOT baked here — production.rb falls back to an ephemeral key when SECRET_KEY_BASE is unset
# (this healthz API has no sessions/credentials); supply a real one via env/k8s Secret before using cookies.
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production" \
    PORT="8080"

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Rails writes to tmp/ and log/ at runtime; re-assert the binstub exec bit (scaffolder templating can drop it).
RUN mkdir -p tmp log && chown -R 65532:65532 tmp log && chmod +x bin/*
USER 65532:65532

EXPOSE 8080

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "8080"]
