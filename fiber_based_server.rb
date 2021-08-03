# frozen_string_literal: true

require 'socket'
require 'libev_scheduler'
require_relative './http/responder'
require_relative './http/request_parser'

module FiberBased
  class Server
    PORT = ENV.fetch('PORT', 3000)
    HOST = ENV.fetch('HOST', '127.0.0.1').freeze
    SOCKET_READ_BACKLOG = ENV.fetch('TCP_BACKLOG', 12).to_i
    attr_accessor :app

    def initialize(app)
      self.app = app
    end

    def start
      # Fibers are not going to work without a scheduler.
      # A scheduler is on for a current thread.
      # Some scheduler choices:
      # evt: https://github.com/dsh0416/evt
      # libev_scheduler: https://github.com/digital-fabric/libev_scheduler
      # Async: https://github.com/socketry/async
      Fiber.set_scheduler(Libev::Scheduler.new)

      puts "--- Server started on host #{HOST} and port #{PORT}"

      Fiber.schedule do
        server = TCPServer.new(HOST, PORT)
        server.listen(SOCKET_READ_BACKLOG)
        loop do
          conn, _addr_info = server.accept
          # ideally we need to limit number of fibers
          # via a thread pool, as accepting infinite number
          # of request is a bad idea:
          # we can run out of memory or other resources,
          # there are diminishing returns to too many fibers,
          # without backpressure to however is sending the requests it's hard
          # to properly load balance and queue requests
          Fiber.schedule do
            request = HTTP::RequestParser.call(conn)
            status, header, body = app.call(request)
            HTTP::Responder.call(conn, status, header, body)
          rescue StandardError => e
            puts e.message
          ensure
            conn&.close
          end
        end
      end
    end
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

FiberBased::Server.new(FileServingApp.new).start
