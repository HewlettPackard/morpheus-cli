FROM ruby:2.7.5

RUN gem install morpheus-cli -v 9.0.1

ENTRYPOINT ["morpheus"]
