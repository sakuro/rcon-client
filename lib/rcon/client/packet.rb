# frozen_string_literal: true

module RCon
  class Client
    Packet = Data.define(:id, :type, :body)

    # Immutable value object representing a single Source RCON packet.
    class Packet
      # Spec says body is truncated at 511 bytes server-side; raise early to surface the issue.
      BODY_BYTE_LIMIT = 511
      private_constant :BODY_BYTE_LIMIT

      # @param data [String] raw packet bytes including the size field
      # @return [Packet]
      def self.decode(data)
        _size, id, type = data.unpack("l<l<l<")
        # data layout: size(4) + id(4) + type(4) + body + null(1) + empty-string(1)
        body = data.byteslice(12, data.bytesize - 14)
        self[id:, type:, body:]
      end

      def initialize(id:, type:, body: "")
        body = body.b
        super
      end

      # @return [String] binary-encoded packet
      # @raise [Error] if body exceeds 511 bytes
      def encode
        raise Error, "body too long (#{body.bytesize} > #{BODY_BYTE_LIMIT})" if body.bytesize > BODY_BYTE_LIMIT

        size = 8 + body.bytesize + 2 # id(4) + type(4) + body + null(1) + empty-string(1)
        [size, id, type].pack("l<l<l<") + body + "\x00\x00".b
      end
    end
  end
end
