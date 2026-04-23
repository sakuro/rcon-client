# frozen_string_literal: true

require "socket"

module RCon
  class Client
    # Wraps a TCP socket for sending and receiving RCON packets.
    class Connection
      def initialize(host, port)
        @host = host
        @port = port
      end

      # Opens the TCP connection.
      #
      # @return [self]
      # @raise [ConnectionError]
      def open
        @socket = TCPSocket.new(@host, @port)
        self
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
        raise ConnectionError, e.message
      end

      # Closes the connection.
      def close
        @socket&.close
      end

      # @param packet [Packet]
      def send_packet(packet)
        @socket.write(packet.encode)
      end

      # @return [Packet]
      # @raise [ConnectionError] if the server closes the connection
      def receive_packet
        raw_size = @socket.read(4)
        raise ConnectionError, "connection closed by server" unless raw_size&.bytesize == 4

        size = raw_size.unpack1("l<")
        raw_body = @socket.read(size)
        raise ConnectionError, "connection closed by server" unless raw_body&.bytesize == size

        Packet.decode(raw_size + raw_body)
      end
    end
  end
end
