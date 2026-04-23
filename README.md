# RCon::Client

A Ruby client for the [Source RCON Protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol). Supports concurrent command execution from multiple threads.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rcon-client'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install rcon-client
```

## Usage

### Basic usage

```ruby
require "rcon/client"

# Block form: automatically closes the connection after the block
RCon::Client.open("127.0.0.1", 27015, password: "secret") do |client|
  puts client.execute("status")
end

# Non-block form: caller is responsible for closing
client = RCon::Client.open("127.0.0.1", 27015, password: "secret")
puts client.execute("status")
client.close
```

### Concurrent execution

`execute` is thread-safe. Multiple threads can issue commands simultaneously and each receives the correct response.

```ruby
RCon::Client.open("127.0.0.1", 27015, password: "secret") do |client|
  threads = ["status", "players", "cvarlist"].map do |cmd|
    Thread.new { [cmd, client.execute(cmd)] }
  end
  results = threads.map(&:value).to_h
end
```

### Error handling

```ruby
begin
  client = RCon::Client.new("127.0.0.1", 27015, password: "secret")
  client.connect
rescue RCon::Client::ConnectionError => e
  # TCP connection failed
rescue RCon::Client::AuthenticationError
  # Wrong password
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sakuro/rcon-client.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
