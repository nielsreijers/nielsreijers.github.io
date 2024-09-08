# syntax=docker/dockerfile:1
FROM ruby:3.3.4

WORKDIR /site
COPY ./Gemfile /site
COPY ./Gemfile.lock /site
RUN --mount=type=cache,target=/root/.bundle/cache \
      bundle install

COPY ./_docker/docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["bundle", "exec", "jekyll", "serve", "-H", "0.0.0.0", "-P", "4000"]

EXPOSE 4000
