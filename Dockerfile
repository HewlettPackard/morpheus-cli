FROM ruby:2.7.5

RUN gem install morpheus-cli -v 8.0.3

ENTRYPOINT ["morpheus"]