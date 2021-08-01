# frozen_string_literal: true

require 'socket'
require_relative './single_thread/http_responder'
require_relative './single_thread/request_parser'

module SingleThread
  class Server
    PORT = ENV.fetch('PORT', 3000)
    HOST = ENV.fetch('HOST', '127.0.0.1').freeze
    # number of incoming connections to keep in a buffer
    SOCKET_READ_BACKLOG = ENV.fetch('TCP_BACKLOG', 12).to_i

    attr_accessor :app

    def initialize(app)
      self.app = app
    end

    def start
      socket = TCPServer.new(HOST, PORT)
      socket.listen(SOCKET_READ_BACKLOG)
      loop do # continuously listen to new connections
        conn, _addr_info = socket.accept
        request = RequestParser.call(conn)
        status, headers, body = app.call(request)
        HttpResponder.call(conn, status, headers, body)
      rescue StandardError => e
        puts e.message
      ensure # always close the connection
        conn&.close
      end
    end

    # private
    #
    # Full implementation w/o TCPServer class
    # def listen_on_socket
    #   Socket.new(:INET, :STREAM)
    #   socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    #   socket.bind(Addrinfo.tcp(HOST, PORT))
    #   socket.listen(SOCKET_READ_BACKLOG)
    # end
  end
end

class FileServingApp
  # read file from the filesystem based on a path from
  # a request, e.g. "/test.txt"
  def call(env)
    # this is totally unsecure, but good enough for the demo
    path = Dir.getwd + env['PATH_INFO']
    if File.exist?(path)
      body = File.read(path)
      [200, { 'Content-Type' => 'text/html' }, [body]]
    else
      [404, { 'Content-Type' => 'text/html' }, ['']]
    end
  end
end

SingleThread::Server.new(FileServingApp.new).start
