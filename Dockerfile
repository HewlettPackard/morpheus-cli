FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.4.4.1

ENTRYPOINT ["morpheus"]