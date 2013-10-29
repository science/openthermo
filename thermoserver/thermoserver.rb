# copyright 2013 Steve Midgley 
# http://www.gnu.org/licenses/gpl-3.0.txt

#     This file is part of the Open Thermostat project.

#     The Open Thermostat project is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.

#     The Open Thermostat project is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.

#     You should have received a copy of the GNU General Public License
#     along with The Open Thermostat project.  
#     If not, see <http://www.gnu.org/licenses/>.

# Credit to Rob Sanders for favicon.ico icon: http://www.iconarchive.com/artist/rob-sanders.html
# Icon may only be used for non-commercial use, with attribution


require 'rubygems'
require 'sinatra'
require 'json'
require 'fileutils'
require 'tempfile'
require 'chronic'
if ENV['RACK_ENV'] == 'testing'
  require 'debugger'
end

module Thermoserver
  class Error < RuntimeError; end
  # set to true during debugging/testing for breakpoints etc
  @@dbg = false
  def self.debug?
    @@dbg
  end
  def self.debug(val)
    @@dbg=val
  end

  def self.dbg(msg)
    puts msg if Thermoserver::Debug.debug
  end
  SERVER_BOOT_FILE = 'boot-server.json'
  ARGV_BOOT_FILE_INDEX = 0
  ENV_BOOT_FILE_KEY = "thermoserver-boot-file-path"
  DEFAULT_CONFIG_FILE = "default-conf.json"
  # TODO Load these values from a config file
  # class instance provides access to config data required to run server
  class Configuration
    attr_reader :port, :base_folder, :api_key, :app_api_key, :images_folder
    
    def initialize(options = {})
      boot_file = ARGV[ARGV_BOOT_FILE_INDEX] || ENV[ENV_BOOT_FILE_KEY] || options[:boot_file] || SERVER_BOOT_FILE
      @config = JSON.parse(File::read(boot_file))
      @base_folder = @config["config"]["base_folder"] || raise(Thermoserver::Error.new("base_folder not found in server boot file"))
      @api_key = @config["config"]["api_key"] || raise(Thermoserver::Error.new("api_key not found in server boot file"))
      @app_api_key = @config["config"]["app_api_key"] || raise(Thermoserver::Error.new("api_key not found in server boot file"))
      @port = @config["config"]["port"] || raise(Thermoserver::Error.new("port not found in server boot file"))
      @images_folder = 'assets/images' 
    end
  end

  def self.filename_is_safe?(filename)
    #checks on filename:
    #  there should be no path - just a filename
    #  filename should have no complex characters in it
    File::basename(filename)==filename && filename.match(/^[a-zA-Z0-9.-_]+$/) && !filename.match(/\.\./)
  end

  # gets filename specified 
  #   if it exists and the file requested passes filename simplification rules
  #   and filename has no path
  # options
  #  :filename
  #  :base_folder
  # returns hash structure with instructions and data
  # returns
  #   status => int (http response code)
  #   file => contents of file requested in string or nil if not authorized
  #   authorized? => true/false - must not proceed if false - return status code and status message to user
  #   status_message => string - error message to return to user explaining why no access
  def self.get_file(options)
    filename = options[:filename]
    base_folder = options[:base_folder] || raise(Thermoserver::Error.new("Base folder required in get_file"))
    rooted_filename = File::join(base_folder, filename)
    html_filename = URI::escape(filename)
    retval = {:authorized => false, :status => 500}
    # file must not contain path information, must exist and must have a simplified character set
    if filename_is_safe?(filename) && File::exists?(rooted_filename)
      File::open(rooted_filename) do |file|
        retval[:file] = file.read
        retval[:status] = 200
        retval[:authorized] = true
      end
    else
      if File::basename(filename)!=filename
        retval[:status] = 403 # not authorized (re-auth won't help)
        retval[:status_message] = "File specified #{html_filename} contains impermissible path."
      elsif !File::exists?(rooted_filename)
        retval[:authorized] = true
        retval[:status] = 404 # not found
        retval[:status_message] = "File specified #{html_filename} does not exist."
      elsif !filename.match(/^[a-zA-Z0-9.]+$/)
        retval[:status] = 403
        retval[:status_message] = "File specified #{html_filename} contains invalid characters."
      else
        retval[:status] = 400 # Bad request / General denial
        retval[:status_message] = "File specified #{html_filename} cannot be obtained for unknown reasons."
      end
    end
    retval
  end

  # returns file if modified date on file is newer than date specified in options
  # options:
  #  :filename
  #  :base_folder
  #  :date_str
  def self.get_file_if_newer_date(options)
    filename = options[:filename]
    base_folder = options[:base_folder]
    rooted_filename = File::join(base_folder, filename)
    date_str = options[:date]
    date = Chronic.parse(date_str)
    retval = {:authorized => false, :status => 500}
    if filename_is_safe?(filename) && File::exists?(rooted_filename)
      if File::mtime(filename) > date
        # if the file has been modified we delegate to get_file to try to retrieve the file
        retval = self.get_file(options)
      else
        # we return 204/OK but no content b/c file has not been modified
        retval = {:authorized => true, :status => 204}
      end
    else
      retval = self.get_file(options) # we call get_file here even though it will fail, just to benefit from status code setting
    end
    retval
  end

  # returns a JSON array (:file_list) list of files matching :pattern in :base_folder
  # options:
  #  :pattern => simple pattern to glob with Dir object a-z0-9 only
  def self.get_list_of_files(options)
    pattern = options[:pattern]
    base_folder = options[:base_folder]
    retval = {:authorized => false, :status => 500, :status_message => "Unknown error in list request processing."}
    if filename_is_safe?(pattern)
      # get files matching pattern in data folder
      list = Dir["*#{pattern}*"]
      if list.length > 0
        results_json = {:file_list => list}.to_json
        retval = {:authorized => true, :status => 200,
          :results_json => results_json}
      else
        retval = {:authorized => true, :status => 404, :status_message => "No files found for pattern #{pattern}"}
      end
    else
      retval = {:authorized => false, :status => 403, :status_message => "Impermissible pattern requested."}
    end
    retval
  end

  def self.post_file(options)
    file = options[:file]
    filename = options[:filename]
    base_folder = options[:base_folder] || raise(Thermoserver::Error.new("Base folder required in post_file"))
    do_not_overwrite = options[:do_not_overwrite] || false
    rooted_filename = File::join(base_folder, filename)
    html_filename = URI::escape(filename)
    retval = {:status_message => "Unknown error", :status => 500}
    if !file || file.size < 1
      retval[:status] = 400
      retval[:status_message] = "File data for file #{html_filename} provided is empty"
    elsif do_not_overwrite && File::exists?(rooted_filename)
      retval[:status] = 409
      retval[:status_message] = "Filename #{html_filename} already exists and this API prohibits overwriting."
    elsif filename_is_safe?(filename)
      FileUtils.copy_file(file.path, rooted_filename)
      if File::exists?(rooted_filename)
        retval[:status] = 200
        retval[:status_message] = "File #{html_filename} uploaded successfully"
      else
        retval[:status] = 500
        retval[:status_message] = "Error writing file #{html_filename}"
      end
    else
      retval[:status] = 500
      retval[:status_message] = "Unknown error occurred when uploading file #{html_filename}"
    end
    retval
  end

  module API
    def self.upload_file(params, config, options = {})
      filename = params[:thermoname]
      file = params[:file][:tempfile] if params[:file]
      Thermoserver::post_file(:file=>file, :filename=>filename, :base_folder => config.base_folder, 
        :do_not_overwrite => options[:do_not_overwrite])
    end

    # requires key to be equal to one of the elements in values_array
    def self.require_field_values_in_json(key, key_descr, values_array, retval)
      case key
        when *values_array 
        else
         retval[:json] = "invalid"
         retval[:fields] << key_descr
      end
    end

    # validate json against rules for 
    def self.validate_config_json(json)
      retval = {:json => "valid", :fields => []}
      require_field_values_in_json(json["operation_mode"], "operation_mode", ["daily_schedule","off","immediate"], retval)
      require_field_values_in_json(json["default_mode"], "default_mode", ["daily_schedule","off"], retval)
      daily_schedule = json["daily_schedule"]
      if daily_schedule
        if !daily_schedule["times_of_operation"]
          retval[:json] = "invalid"
          retval[:fields] << "daily_schedule => times_of_operation"
        end
        timesop = daily_schedule["times_of_operation"]
        if timesop
          timesop_count = 0
          timesop.each do |window|
            if !Chronic.parse(window["start"])
              retval[:json] = 'invalid'
              retval[:fields] << "daily_schedule => times_of_operation => start, array count #{timesop_count}"
            end
            if !Chronic.parse(window["stop"])
              retval[:json] = 'invalid'
              retval[:fields] << "daily_schedule => times_of_operation => stop, array count #{timesop_count}"
            end
            if (window["temp_f"].to_i == 0) && (window["temp_f"] != "0")
              retval[:json] = 'invalid'
              retval[:fields] << "daily_schedule => times_of_operation => temp_f, array count #{timesop_count}"
            end
            timesop_count += 1
          end
        end
        # immediate is optional but must have temp_f as number if exist
        # temp_override is optional but must have temp_f as number and time_stamp as chronic parseable if exist
        # off key must have off value
        # debug is optional and has optional log_level, but log_level must have integer is exist
      end
      retval
    end

  end # API
end # Thermoserver

config = Thermoserver::Configuration.new
# used in testing

# call debug! in code (in this file) to invoke the debugger. Only 
# invokes debugger if debug variable has been set in Thermoserver
def debug!
  debugger if Thermoserver::debug?
end 
# Convenience method for test framework. Call this with true
# in order to enable debug! to break at checkpoint
def debug(val)
  Thermoserver::debug(val)
end

# setup server
set :server, 'thin'
set :port, config.port

puts "\nBase file folder:\n    #{File::expand_path(config.base_folder)}\n\n"

## Application server (generates user interface from erb templates)

get "/app/:page/#{config.app_api_key}" do
  erb params[:page].to_sym
end

# return open thermo icon
# Credit to Rob Sanders for icon: http://www.iconarchive.com/artist/rob-sanders.html
get "/favicon.ico" do
  favicon_path = File::join(settings.public_folder, config.images_folder, 'favicon.ico')
  send_file(favicon_path)
end

## Web App API (responds to web page inputs to take actions)

# Set the operation mode for the heater
# If the configuration file does not exist, return an error
put "/app-api/#{config.app_api_key}/:thermoname/operation_mode/:mode" do
  # load the heater file for editing
  mode = params[:mode]
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file(:filename=>filename, :base_folder => config.base_folder)
  if file_hash[:authorized] && file_hash[:status] == 200
    file_contents = file_hash[:file]
  else
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
    return retval
  end      
  heater_config = JSON.parse(file_contents)
  # set "operation_mode" key to mode
  heater_config["operation_mode"] = mode
  # save the heater file
  file_contents = JSON.generate(heater_config)
  tempfile = Tempfile.new('thermo-operation-mode')
  tempfile.write(file_contents)
  upload_params = {:thermoname => filename, :file => {:tempfile=>tempfile}}
  file_hash = Thermoserver::API::upload_file(upload_params,config)
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end

## TODO merge replicated code from above and below
# Set the heater to temp_override or immediate ("hold") mode
put "/app-api/#{config.app_api_key}/:thermoname/override_mode/:mode/:temp_f" do
  mode = params[:mode]
  temp_f = params[:temp_f]
  if mode != "temp_override" && mode != "hold" && mode != "immediate"
    response.status = 404
    return "Invalid mode #{mode} specified."
  end
  if mode == "hold" # hold is just an api synonym for immediate
    mode = "immediate" 
  end
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file(:filename=>filename, :base_folder => config.base_folder)
  if file_hash[:authorized] && file_hash[:status] == 200
    file_contents = file_hash[:file]
  else
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
    return retval
  end
  heater_config = JSON.parse(file_contents)
  # create override mode value
  mode_value = {:temp_f => temp_f, :time_stamp => Time::now.to_s}
  # set key to mode
  heater_config[mode] = mode_value
  if mode == "immediate"
    heater_config["operation_mode"] = mode
  end
  # save the heater file
  file_contents = JSON.generate(heater_config)
  tempfile = Tempfile.new('thermo-operation-mode')
  tempfile.write(file_contents)
  upload_params = {:thermoname => filename, :file => {:tempfile=>tempfile}}
  file_hash = Thermoserver::API::upload_file(upload_params,config)
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end

# causes heater to resume default operation mode
# the mode which is resumed is stored in default_mode key in config file
put "/app-api/#{config.app_api_key}/:thermoname/resume/default" do
  # retrieve heater file
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file(:filename=>filename, :base_folder => config.base_folder)
  if file_hash[:authorized] && file_hash[:status] == 200
    file_contents = file_hash[:file]
  else
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
    return retval
  end
  # process heater file
  heater_config = JSON.parse(file_contents)
  heater_config["temp_override"] = nil
  heater_config["operation_mode"] = heater_config["default_mode"] || "off"
  # save the heater file
  file_contents = JSON.generate(heater_config)
  tempfile = Tempfile.new('thermo-operation-mode')
  tempfile.write(file_contents)
  upload_params = {:thermoname => filename, :file => {:tempfile=>tempfile}}
  file_hash = Thermoserver::API::upload_file(upload_params,config)
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end

put "/app-api/#{config.app_api_key}/:thermoname/default/:mode" do
  mode = params[:mode]
  # retrieve heater file
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file(:filename=>filename, :base_folder => config.base_folder)
  if file_hash[:authorized] && file_hash[:status] == 200
    file_contents = file_hash[:file]
  else
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
    return retval
  end
  # process heater file
  heater_config = JSON.parse(file_contents)
  heater_config["default_mode"] = mode
  # save the heater file
  file_contents = JSON.generate(heater_config)
  tempfile = Tempfile.new('thermo-operation-mode')
  tempfile.write(file_contents)
  upload_params = {:thermoname => filename, :file => {:tempfile=>tempfile}}
  file_hash = Thermoserver::API::upload_file(upload_params,config)
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end

post "/app-api/#{config.app_api_key}/:thermoname/initialize" do
  filename = params[:thermoname]
  if !File::exists?(Thermoserver::DEFAULT_CONFIG_FILE)
    response.status = 404
    return "Default config file #{DEFAULT_CONFIG_FILE} does not exist in folder where this server was started."
  end
  tempfile = Tempfile.new('new-config')
  tempfile.write(File::read(Thermoserver::DEFAULT_CONFIG_FILE))
  upload_params = {:thermoname => filename, :file => {:tempfile => tempfile}}
  file_hash = Thermoserver::API::upload_file(upload_params, config, {:do_not_overwrite => true})
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end

# receives a posted payload under "file" key
# returns json response indicating if it is a valid config file or not
post "/public-api/validate/config" do
  file = params[:file][:tempfile]
  json = JSON.parse(File::read(file))
  retval = Thermoserver::API::validate_config_json(json)
  JSON.generate(retval)
end

## Thermoclient API Server (provides/stores configuration files)

# Return file contents if file exists
get "/api/#{config.api_key}/file/:thermoname" do
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file(:filename=>filename, :base_folder => config.base_folder)
  retval = ""
  if file_hash[:authorized] && file_hash[:status] == 200
    retval = file_hash[:file]
  else # not authorized
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
  end
  retval
end

# returns file specified as :thermoname if newer than :date
# date is a uri encoded Chronic parseable format without slashes (eg 10-18-2013 5:06pm)
get "/api/#{config.api_key}/if-file/newer-than/:date/:thermoname" do
  date = params[:date]
  filename = params[:thermoname]
  file_hash = Thermoserver::get_file_if_newer_date(:filename=>filename, :base_folder => config.base_folder, :date => date)
  if file_hash[:authorized] && file_hash[:status] == 200
    retval = file_hash[:file]
  elsif file_hash[:authorized] && file_hash[:status] == 204
    retval = ""
    response.status = 204
  else # not authorized
    retval = file_hash[:status_message]
    response.status = file_hash[:status]
  end
  retval
end

# returns JSON array of filenames that match :pattern
# pattern can only contain a-z 0-9 dot hyphen underscore
# particularly no path information is permitted
get "/api/#{config.api_key}/list/:pattern" do
  pattern = params[:pattern]
  file_hash = Thermoserver::get_list_of_files({:pattern=>pattern, :base_folder => config.base_folder})
  if file_hash[:authorized] && file_hash[:status] == 200
    response.status = file_hash[:status]
    content_type 'application/json', :charset => 'utf-8'
    retval = file_hash[:results_json]
  else  
    response.status = file_hash[:status]
    retval = file_hash[:status_message]
  end
  retval
end

# Receive a file to store on disk named :thermoname
# expects file contents to be uploaded under POST params key "file"
post "/api/#{config.api_key}/file/:thermoname" do
  file_hash = Thermoserver::API::upload_file(params, config)
  response.status = file_hash[:status]
  file_hash[:status_message] || ""
end
