FROM ruby:2.7.5

RUN gem install morpheus-cli -v 8.1.2

ENTRYPOINT ["morpheus"]