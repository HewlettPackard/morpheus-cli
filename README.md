<img src="https://morpheusdata.com/wp-content/uploads/2020/04/morpheus-logo-v2.svg" width="200px">

# Morpheus CLI

- Website: https://www.morpheusdata.com/
- Guide: [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki)
- Docs: [Morpheus CLI Documentation](https://clidocs.morpheusdata.com)
- Support: [Morpheus Support](https://support.morpheusdata.com)

This library is a Ruby gem that provides a command line interface for interacting with the Morpheus Data appliance. The features provided include provisioning clusters, hosts, and containers, deploying and monitoring applications, automating tasks, and much more.

## Installation

Install it using rubygems

```shell
gem install morpheus-cli
```

Or add this line to your application's Gemfile:

```ruby
gem 'morpheus-cli'
```

And then execute:

```shell
bundle install
```

## Usage

### morpheus command

This gem installs the [morpheus](https://github.com/gomorpheus/morpheus-cli/wiki/CLI-Manual) binary for running commands in your terminal shell. 

```shell
morpheus remote add
morpheus instances list
```

### ruby code

If you are interested in interfacing with the Morpheus appliance in ruby directly, you can use [Morpheus::APIClient](https://github.com/gomorpheus/morpheus-cli/wiki/APIClient) or [Morpheus::Terminal](https://github.com/gomorpheus/morpheus-cli/wiki/Terminal).

For more detailed usage information, visit the [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki).


## Development

New API interfaces get added under the library directory: `lib/morpheus/api/`.
New CLI commands get added under the library directory: `lib/morpheus/cli/commands/`.

While developing, you can quickly reload your code changes in a morpheus shell while developing:

```shell
bundle exec morpheus shell —debug
```

Then to reload changes without restarting the morpheus shell (and the ruby process), use:

```shell
reload
```

Don't forget to add unit tests for your new commands under the directory: `test/`.




## Testing

To run the CLI unit tests, first create a `test_config.yaml` and then run `rake test`.

### Prepare Test Environment

Create a `test_config.yaml` like this:

```shell
touch test_config.yaml
```

Enter your test environment url and credentials in `test_config.yaml` like so:

```yaml
url: 'http://localhost:8080'
username: testrunner
password: 'SecretPassword123$' 
```

### Run Tests

```shell
rake test
```

