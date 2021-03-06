#!/usr/bin/env ruby
#===============================================================================
#
#         FILE: file_check-local-stateless.rb
#
#        USAGE: ./file_check-local-stateless.rb
#
#  DESCRIPTION: An exmple of a local, stateless plugin in ruby. Checks a to see
#               a file to see if it exists, and checks the contents.
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Ryan Quinn (RQ)
# ORGANIZATION: OP5
#      VERSION: 0.0.1
#      CREATED: 08/22/2018 10:06:54 PM
#      LICENSE: MIT
#===============================================================================

# Standard libs
require 'optparse'
require 'optparse/uri'
require 'pp'
require 'pathname'
require 'json'
require 'uri'
require 'net/http'
require 'openssl'
require 'json'
require 'resolv-replace'

class OptParsing
  Version = '0.0.1'

  @warning = nil
  @critical = nil
  @filepath = nil
  @timeout = nil
  @account = nil
  @password = nil
  @host = nil
  @check_ssl = nil
  @target = nil

  class ScriptOptions
    attr_accessor :verbose,
                  :delay,
                  :extension,
                  :record_separator,
                  :warning,
                  :critical,
                  :filepath,
                  :timeout,
                  :account,
                  :password,
                  :host,
                  :check_ssl,
                  :target

    def initialize
      self.verbose = false
      self.delay = 0
      self.timeout = 10
      self.warning = Hash.new
      self.warning[:check] = false
      self.warning[:inclusive] = false
      self.critical = Hash.new
      self.critical[:check] = false
      self.critical[:inclusive] = false
      self.host = 'localhost'
      self.check_ssl = true
      self.target = Hash.new
      self.target[:service] = false
    end

    def define_options(parser)
      parser.banner = "Usage: #{$0} [options]"
      parser.separator ""
      parser.separator "Specific options:"

      verbose_enable(parser)
      exec_delay(parser)
      threshold_warning(parser)
      threshold_critical(parser)
      set_filepath(parser)
      set_timeout(parser)
      set_account(parser)
      set_password(parser)
      set_host(parser)
      ssl_disable(parser)
      set_mon_hostname(parser)
      set_mon_servicename(parser)

      parser.separator "Common options:"
      parser.on_tail("-h", "--help", "Show usage information.") do
        puts parser
        exit 3
      end
      parser.on_tail("-V", "--version", "Shows version number.") do
        puts Version
        exit 3
      end
    end

    #TODO: Allow 'v' multiple times to increase the verbosity of the output.
    def verbose_enable(parser)
      parser.on("-v", "Enable more output.") do |v|
        self.verbose = v
      end
    end

    def exec_delay(parser)
      parser.on("-d N", "--delay N", Integer, "Delays the execution of the check for X seconds.") do |n|
        self.delay = n
      end
    end

    def set_timeout(parser)
      parser.on("-t N", "--timeout N", Integer, "Sets the maximum execution time in seconds.") do |n|
        self.timeout = n
      end
    end

    def threshold_warning(parser)
      parser.on("-w", "--warning WARN", String, "Warning thresholds.") do |w|
        self.warning[:string_orig] = w

        if w.include? '@'
          self.warning[:inclusive] = true
          w = w.tr('@', '')
        end

        if w.include? ':'
          range_start, range_end = w.split(':')
          if range_start == '~'
            range_start = nil
          else
            range_start = range_start.to_i
          end
          if range_end != nil
            range_end = range_end.to_i
          end
        else
          range_start = 0
          range_end = w.to_i
        end

        self.warning[:range_start] = range_start
        self.warning[:range_end] = range_end
        self.warning[:check] = true
      end
    end

    def threshold_critical(parser)
      parser.on("-c", "--critical CRIT", String, "Critical thresholds.") do |c|
        self.critical[:string_orig] = c

        if c.include? '@'
          self.critical[:inclusive] = true
          c = c.tr('@', '')
        end

        if c.include? ':'
          range_start, range_end = c.split(':')
          if range_start == '~'
            range_start = nil
          else
            range_start = range_start.to_i
          end
          if range_end != nil
            range_end = range_end.to_i
          end
        else
          range_start = 0
          range_end = c.to_i
        end

        self.critical[:range_start] = range_start
        self.critical[:range_end] = range_end
        self.critical[:check] = true
      end
    end

    def set_filepath(parser)
      parser.on("-f", "--filepath FN", String, "Path to file.") do |f|
        #TODO: Make mandatory
        self.filepath = File.absolute_path(f)
      end
    end

    def set_account(parser)
      parser.on("-l ACCOUNT", "--logname ACCOUNT", String, "Account name.") do |a|
        self.target[:account] = a
      end
    end

    def set_password(parser)
      parser.on("-a PASS", "--authentication PASS", String, "Account password.") do |p|
        self.target[:password] = p
      end
    end

    def set_host(parser)
      parser.on("-u [HOST]", "--url [HOST]", URI, "Sets the hostname.") do |h|
        self.host = h
      end
    end

    def ssl_disable(parser)
      parser.on("--no-ssl", "Disables SSL verification.") do
        self.check_ssl = false
      end
    end

    def set_mon_hostname(parser)
      parser.on('-n NAME', '--host-name NAME', String, "Sets the name of the target host to update in OP5 Monitor.") do |mh|
        self.target[:hostname] = mh
      end
    end

    def set_mon_servicename(parser)
      parser.on('-s SVC', '--service-name SVC', String, "Sets the name of the target service to update in OP5 Monitor.") do |ms|
        self.target[:service] = true
        self.target[:servicename] = ms
      end
    end
  end

  def parse_args(args)
    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      @options.define_options(parser)
      begin
        parser.parse!(args)
      rescue OptionParser::ParseError => error
        puts error
        puts parser
        exit 3
      end
    end
    @options
  end

  attr_reader :parser, :options
end

def get_status(options, data)
  ret_val = 0
  status = "OK"
  description = "Everything is good."

  if options.critical[:check] == true
    if options.critical[:inclusive] == false
      if options.critical[:range_end] == nil
        if data < options.critical[:range_start]
          ret_val = 2
          status = "CRITICAL"
          description = "Service is in a critical state."
          return ret_val, status, description
        end
      elsif options.critical[:range_start] == nil
        if data < options.critical[:range_end]
          ret_val = 2
          status = "CRITICAL"
          description = "Service is in a critical state."
          return ret_val, status, description
        end
      elsif data < options.critical[:range_start] ||
              data > options.critical[:range_end]
        ret_val = 2
        status = "CRITICAL"
        description = "Service is in a critical state."
        return ret_val, status, description
      end
    elsif options.critical[:inclusive] == true
      if data >= options.critical[:range_start] &&
          data <= options.critical[:range_end]
        ret_val = 2
        status = "CRITICAL"
        description = "Service is in a critical state."
        return ret_val, status, description
      end
    end
  end

  if options.warning[:check] == true
    if options.warning[:inclusive] == false
      if options.warning[:range_end] == nil
        if data < options.warning[:range_start]
          ret_val = 1
          status = "WARNING"
          description = "Service is in a warning state."
          return ret_val, status, description
        end
      elsif options.warning[:range_start] == nil
        if data > options.warning[:range_end]
          ret_val = 1
          status = "WARNING"
          description = "Service is in a warning state."
          return ret_val, status, description
        end
      elsif data < options.warning[:range_start] ||
              data > options.warning[:range_end]
        ret_val = 1
        status = "WARNING"
        description = "Service is in a warning state."
        return ret_val, status, description
      end
    elsif options.warning[:inclusive] == true
      if data >= options.warning[:range_start] &&
          data <= options.warning[:range_end]
        ret_val = 1
        status = "WARNING"
        description = "Service is in a warning state."
        return ret_val, status, description
      end
    end
  end

  return ret_val, status, description
end

def json_packer(target, ret_val, description)
  json_payload = Hash.new

  json_payload[:host_name] = target[:hostname]

  if target[:service]
    json_payload[:service_description] = target[:servicename]
  end

  json_payload[:status_code] = ret_val
  json_payload[:plugin_output] = description

  return json_payload
end

def http_post(endpoint, target, check_ssl, json_payload)
  if check_ssl
    verify = 1
  else
    verify = 0
  end

  url = URI(endpoint)
  request = Net::HTTP::Post.new(url)
  request.basic_auth(target[:account], target[:password])
  request["content-type"] = 'application/json'
  request.body = json_payload

  response = Net::HTTP.start(url.host, url.port,
                            :use_ssl => true,
                            :verify_mode => verify) {|http|
    http.request(request)
  }

  return response
end

ret_val = 3

optionparser = OptParsing.new
options = optionparser.parse_args(ARGV)

if options.verbose
  puts "Exec delay: #{options.delay}"
  puts "Warning thresholds: #{options.warning}"
  puts "Critical thresholds: #{options.critical}"
  puts "Path to file: #{options.filepath}"
  puts "Account name: #{options.account}"
  puts "Password: #{options.password}"
  puts "URL: #{options.host}"
  puts "SSL verification: #{options.check_ssl}"
  puts "Target dump: #{options.target}"
  puts ''
  pp options
  puts "ARGV dump: #{ARGV}", ''
end

if options.warning[:check] == false && options.critical[:check] == false
  puts "UNKNOWN - At least one range needs to be defined."
  exit 3
end

begin
  file_obj = Pathname.new(options.filepath)
rescue TypeError => error
  puts "UNKNOWN - #{error}"
  exit 3
end

if file_obj.directory?
  puts "UNKNOWN - Passed file is a directory."
  exit 3
elsif !file_obj.exist?
  puts "UNKNOWN - Passed file does not exist."
  exit 3
end

data = file_obj.read
data = data.to_i

if options.verbose
  puts "Data from file: #{data}"
end

if options.delay
  puts "Delaying for #{options.delay} seconds..."
  sleep options.delay
end

ret_val, service_status, service_description = get_status(options, data)

output = "#{service_description} | 'output'=#{data};#{options.warning[:string_orig]};#{options.critical[:string_orig]}"

json_data = json_packer(options.target, ret_val, output)

if options.verbose
  puts json_data
end

if options.target[:service]
  endpoint = "#{options.host}/api/command/PROCESS_SERVICE_CHECK_RESULT"
else
  endpoint = "#{options.host}/api/command/PROCESS_HOST_CHECK_RESULT"
end

if options.verbose
  puts endpoint
end

http_response = http_post(endpoint,
                          options.target,
                          options.check_ssl,
                          json_data.to_json)

puts http_response.read_body

puts "#{service_status} - #{output}"

exit ret_val
