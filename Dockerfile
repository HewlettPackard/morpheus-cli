FROM ruby:2.7.5

RUN gem install morpheus-cli -v 7.0.8

ENTRYPOINT ["morpheus"]