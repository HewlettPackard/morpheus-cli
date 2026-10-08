FROM ruby:2.7.5

RUN gem install morpheus-cli -v 9.3.0

ENTRYPOINT ["morpheus"]
