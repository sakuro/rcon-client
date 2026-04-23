# frozen_string_literal: true

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
      @id_counter = 0
      @connection = nil
    end

    # Establishes a TCP connection and authenticates.
    #
    # @return [self]
    # @raise [ConnectionError]
    # @raise [AuthenticationError]
    def connect
      @connection = Connection.new(@host, @port).open
      authenticate
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
      @connection.send_packet(Packet.new(id: cmd_id, type: PacketType::EXECCOMMAND, body: command))

      sentinel_id = next_id
      @connection.send_packet(Packet.new(id: sentinel_id, type: PacketType::EXECCOMMAND, body: ""))

      parts = []
      loop do
        response = @connection.receive_packet
        next unless response.type == PacketType::RESPONSE_VALUE
        break if response.id == sentinel_id

        parts << response.body if response.id == cmd_id
      end
      parts.join
    end

    # Closes the connection.
    def close
      @connection&.close
      @connection = nil
    end

    # @return [Boolean]
    def connected? = !@connection.nil?

    private def next_id = (@id_counter += 1)

    private def authenticate
      auth_id = next_id
      @connection.send_packet(Packet.new(id: auth_id, type: PacketType::AUTH, body: @password))
      @connection.receive_packet # empty RESPONSE_VALUE preceding AUTH_RESPONSE
      response = @connection.receive_packet # AUTH_RESPONSE
      raise AuthenticationError, "authentication failed" if response.id == -1
    end
  end
end
