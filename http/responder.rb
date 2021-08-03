# frozen_string_literal: true

module HTTP
  class Responder
    STATUS_MESSAGES = {
      200 => 'OK',
      404 => 'Not Found'
    }.freeze

    def self.call(conn, status, headers, body)
      # status line
      status_text = STATUS_MESSAGES[status]
      conn.send("HTTP/1.1 #{status} #{status_text}\r\n", 0)

      # headers
      content_length = body.sum(&:length)
      conn.send("Content-Length: #{content_length}\r\n", 0)
      headers.each_pair do |name, value|
        conn.send("#{name}: #{value}\r\n", 0)
      end

      conn.send("Connection: close\r\n", 0)
      conn.send("\r\n", 0)

      # body
      body.each do |chunk|
        conn.send(chunk, 0)
      end
    end
  end
end
