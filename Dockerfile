FROM ruby:2.5.1

RUN gem install morpheus-cli -v 4.2.14

ENTRYPOINT ["morpheus"]