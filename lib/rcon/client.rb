# frozen_string_literal: true

require "concurrent"
require "zeitwerk"
require_relative "client/version"

module RCon
  # TCP client for the Source RCON protocol.
  class Client
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class ConnectionError < Error; end

    loader = Zeitwerk::Loader.new
    loader.push_dir("#{__dir__}/client", namespace: self)
    loader.ignore("#{__dir__}/client/version.rb")
    loader.setup

    DEFAULT_PORT = 27015
    public_constant :DEFAULT_PORT

    # Opens a connection, authenticates, and optionally yields the client.
    #
    # @param host [String]
    # @param port [Integer]
    # @param password [String]
    # @yieldparam client [RCon::Client]
    # @return [RCon::Client]
    def self.open(host, port=DEFAULT_PORT, password:)
      client = new(host, port, password:)
      client.connect
      return client unless block_given?

      begin
        yield client
      ensure
        client.close
      end
    end

    def initialize(host, port=DEFAULT_PORT, password:)
      @host = host
      @port = port
      @password = password
      @id_counter = Concurrent::AtomicFixnum.new(0)
      @connection = nil
      @reader_thread = nil
      @pending = Concurrent::Map.new
      @closing = false
    end

    # Establishes a TCP connection and authenticates.
    #
    # @return [self]
    # @raise [ConnectionError]
    # @raise [AuthenticationError]
    def connect
      @closing = false
      @connection = Connection.new(@host, @port).open
      authenticate
      @reader_thread = Thread.new { reader_loop }
      self
    rescue
      @connection&.close
      @connection = nil
      raise
    end

    # Sends a command and returns the server response.
    #
    # @param command [String]
    # @return [String]
    # @raise [Error] if body exceeds 511 bytes
    def execute(command)
      cmd_id = next_id
      sentinel_id = next_id
      future = Concurrent::Promises.resolvable_future
      @pending[cmd_id] = [[], future]
      @pending[sentinel_id] = cmd_id

      @connection.send_packet(Packet.new(id: cmd_id, type: PacketType::EXECCOMMAND, body: command))
      @connection.send_packet(Packet.new(id: sentinel_id, type: PacketType::EXECCOMMAND, body: ""))

      future.value!
    end

    # Closes the connection.
    def close
      @closing = true
      @connection&.close
      @connection = nil
      @reader_thread&.join
      @reader_thread = nil
    end

    # @return [Boolean]
    def connected? = !@connection.nil?

    private def next_id = @id_counter.increment

    private def authenticate
      auth_id = next_id
      @connection.send_packet(Packet.new(id: auth_id, type: PacketType::AUTH, body: @password))
      @connection.receive_packet # empty RESPONSE_VALUE preceding AUTH_RESPONSE
      response = @connection.receive_packet # AUTH_RESPONSE
      raise AuthenticationError, "authentication failed" if response.id == -1
    end

    private def reader_loop
      loop { dispatch(@connection.receive_packet) }
    rescue ConnectionError, IOError => e
      return if @closing

      error = ConnectionError.new(e.message)
      @pending.each_pair do |_id, entry|
        next if entry.is_a?(Integer)

        _, future = entry
        future.reject(error)
      end
      @pending.clear
    end

    private def dispatch(packet)
      return unless packet.type == PacketType::RESPONSE_VALUE

      entry = @pending[packet.id]
      return unless entry

      if entry.is_a?(Integer)
        cmd_id = entry
        parts, future = @pending.delete(cmd_id)
        @pending.delete(packet.id)
        future.fulfill(parts.join)
      else
        entry[0] << packet.body
      end
    end
  end
end
