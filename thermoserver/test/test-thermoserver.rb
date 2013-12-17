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

ENV['RACK_ENV'] = 'test'
gem "minitest"


require 'minitest/autorun'
require '../thermoserver.rb'
require 'rack/test'
require 'fileutils'
require 'tempfile'
require 'debugger'
require 'chronic'
require 'uri'

VALID_CONFIG_JSON_ORIG = 'valid-backbedroom.confg.json.orig'
VALID_CONFIG_DEFAULT_OFF_JSON_ORIG = 'valid-backbedroom.default-off.confg.json.orig'

STATUS_JSON = 'backbedroom.status.json'
CONFIG_JSON = 'backbedroom.config.json'
SECOND_CONFIG_JSON = 'livingroom.config.json'
CONFIG_PATTERN = 'config'

class ThermoserverTest < Minitest::Test
  include Rack::Test::Methods
  
  # used as a signling function into server to indicate debugging
  # makes it easy to cause the debugger to break only when hitting a line of code
  # when a specific test method is running
  
  # debug(true)

  def setup
    FileUtils::cp(VALID_CONFIG_JSON_ORIG, CONFIG_JSON)
    @config = Thermoserver::Configuration.new
    @api_key = @config.api_key
    @app_api_key = @config.app_api_key
  end
  
  def teardown
    FileUtils::safe_unlink(CONFIG_JSON)
    raise if File::exists?(CONFIG_JSON)
  end

  def app
    Sinatra::Application
  end

  # this just makes sure the test file boot-server.json has expected data
  def test_api_alignment
    assert_equal @api_key, 'abc123def'
    assert_equal @app_api_key, "xyz789xyz"
  end

  ## Web App page tests

  def test_webapp_get_file
    get "/app/dashboard/#{@app_api_key}"
    assert_equal 200, last_response.status, last_response.body
    get "/app/dashboard"
    assert_equal 404, last_response.status, last_response.body
  end

  ## App API tests

  def test_publicapi_validate_config
    filedata = File::read(CONFIG_JSON)
    tempfile = Tempfile.new('validate_config')
    tempfile.write(filedata)
    tempfile.rewind
    upload_file = Rack::Test::UploadedFile.new(tempfile.path, "text/json")    
    post "/public-api/validate/config", "file" => upload_file
    assert_equal 200, last_response.status, last_response.body
    retval = JSON.parse(last_response.body)
    assert_equal "valid", retval["json"], retval.inspect
    assert_equal [], retval["fields"], retval.inspect
    tempfile.unlink
  end

  def test_publicapi_validate_invalid_config
    filedata = File::read(CONFIG_JSON)
    json = JSON.parse(filedata)
    # test removing various elements of times of operation
    json["daily_schedule"]["times_of_operation"].first.delete("start")
    json["daily_schedule"]["times_of_operation"].last.delete("stop")
    json["daily_schedule"]["times_of_operation"][1]["temp_f"] = "Non-int"
    json["daily_schedule"]["times_of_operation"][2].delete("temp_f")
    json_test_data = [{json => ["daily_schedule => times_of_operation => start, array count 0", 
      "daily_schedule => times_of_operation => temp_f, array count 1", 
      "daily_schedule => times_of_operation => temp_f, array count 2", 
      "daily_schedule => times_of_operation => stop, array count #{json["daily_schedule"]["times_of_operation"].size-1}"]}]
    # test removing times_of_op 
    json = JSON.parse(filedata)
    json["daily_schedule"].delete("times_of_operation")
    json_test_data << {json => ["daily_schedule => times_of_operation"]}
    # test removing daily_schedule
    json = JSON.parse(filedata)
    json.delete("daily_schedule")
    json_test_data << {json => ["daily_schedule"]}
    # test removing operation mode and default mode
    json = JSON.parse(filedata)
    json.delete("operation_mode")
    json.delete("default_mode")
    json_test_data << {json => ["operation_mode","default_mode"]}
    # test operation mode has invalid mode
    json = JSON.parse(filedata)
    json["operation_mode"] = "foobar"
    json_test_data << {json => ["operation_mode"]}

    json_test_data.each do |test_hash|
      json = test_hash.first.first
      invalid_fields = test_hash.first.last
      filedata = JSON.generate(json)
      tempfile = Tempfile.new('validate_config')
      tempfile.write(filedata)
      tempfile.rewind
      upload_file = Rack::Test::UploadedFile.new(tempfile.path, "text/json")    
      post "/public-api/validate/config", "file" => upload_file
      assert_equal 200, last_response.status, last_response.body
      retval = JSON.parse(last_response.body)
      assert_equal "invalid", retval["json"], retval.inspect+"\nExpected invalid fields:"+invalid_fields.inspect
      assert_equal invalid_fields, retval["fields"], retval.inspect
      tempfile.unlink
    end
  end

  def test_webapi_turn_heater_off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    # verify operation mode is not off
    assert_equal "daily_schedule", config_json["operation_mode"]
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/operation_mode/off"
    assert_equal 200, last_response.status, last_response.body
    # verify operation mode is off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "off", config_json["operation_mode"]
    assert_equal "off", config_json["off"]

    # turn the operation mode back to "daily_schedule"
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/operation_mode/daily_schedule"
    assert_equal 200, last_response.status, last_response.body
    # verify operation mode is off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "daily_schedule", config_json["operation_mode"]
    assert_equal "off", config_json["off"]
  end

  def test_webapi_turn_heater_off_invalid_config_file
    # verify trying to modify a non-existent heater config file 
    # results in an error
    put "/app-api/#{@app_api_key}/invalid_heater.json/operation_mode/off"
    assert_equal 404, last_response.status, last_response.body
  end

  def test_webapi_turn_heater_to_hold
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/override_mode/hold/74"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    # we don't test seconds so not to fail by 1 second boundary errors
    assert_equal Time::now.strftime("%Y-%m-%d H%:%M %z"), Chronic.parse(config_json["immediate"]["time_stamp"]).strftime("%Y-%m-%d H%:%M %z")
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert_equal "immediate", config_json["operation_mode"]
  end

  def test_webapi_turn_heater_to_temp_override
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/override_mode/temp_override/68"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal Time::now.strftime("%Y-%m-%d H%:%M %z"), Chronic.parse(config_json["temp_override"]["time_stamp"]).strftime("%Y-%m-%d H%:%M %z")
    assert_equal "68", config_json["temp_override"]["temp_f"]
    assert_equal "daily_schedule", config_json["operation_mode"]
    assert_equal "daily_schedule", config_json["default_mode"]
  end

  def test_webapi_resume_normal_operations
    # first we turn on hold mode
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/override_mode/hold/74"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert_equal Time::now.to_s, config_json["immediate"]["time_stamp"]
    assert_equal "immediate", config_json["operation_mode"]
    assert_equal "daily_schedule", config_json["default_mode"]
    # then we call resume_default
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/resume/default"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert !config_json["temp_override"], "temp_override key should have been deleted but was not."
    assert_equal "daily_schedule", config_json["operation_mode"]
    assert_equal "daily_schedule", config_json["default_mode"]
    # verify that if we set default_operation to "off", resuming will leave heater in off state
    FileUtils::cp(VALID_CONFIG_DEFAULT_OFF_JSON_ORIG, CONFIG_JSON)
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/override_mode/hold/74"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert_equal Time::now.to_s, config_json["immediate"]["time_stamp"]
    assert_equal "immediate", config_json["operation_mode"]
    assert_equal "off", config_json["default_mode"]
    # then we call resume_default
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/resume/default"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert !config_json["temp_override"], "temp_override key should have been deleted but was not."
    assert_equal "off", config_json["operation_mode"]
    assert_equal "off", config_json["default_mode"]
  end

  def test_webapi_set_default_mode
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "daily_schedule", config_json["default_mode"]
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/default/off"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "off", config_json["default_mode"]
    put "/app-api/#{@app_api_key}/#{CONFIG_JSON}/default/daily_schedule"
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "daily_schedule", config_json["default_mode"]
  end

  def test_webapi_initialize_new_heater
    assert !File::exists?(SECOND_CONFIG_JSON)
    begin
      post "/app-api/#{@app_api_key}/#{SECOND_CONFIG_JSON}/initialize"
      assert_equal 200, last_response.status, last_response.body
      assert File::exists?(SECOND_CONFIG_JSON)
      config_json = JSON.parse(File::read(SECOND_CONFIG_JSON))
      assert_equal "daily_schedule", config_json["operation_mode"]
      # change an element so we can test that re-posting doesn't overwrite existing config file
      config_json["operation_mode"] = "off"
      File::write(SECOND_CONFIG_JSON, JSON.generate(config_json))
      config_json = JSON.parse(File::read(SECOND_CONFIG_JSON))
      assert_equal "off", config_json["operation_mode"]      
      # post to the same config file, and verify that it doesn't overwrite existing file
      post "/app-api/#{@app_api_key}/#{SECOND_CONFIG_JSON}/initialize"
      assert_equal 409, last_response.status, last_response.body
      assert File::exists?(SECOND_CONFIG_JSON)
      config_json = JSON.parse(File::read(SECOND_CONFIG_JSON))
      assert_equal "off", config_json["operation_mode"]      
    ensure
      FileUtils::safe_unlink(SECOND_CONFIG_JSON)
    end
  end

  ## Thermoclient API tests

  def test_get_file
    get "/api/#{@api_key}/file/#{CONFIG_JSON}"
    assert_equal 200, last_response.status, last_response.body
    assert_equal File::read(CONFIG_JSON), last_response.body
  end

  def test_get_list
    # test for one file
    get "/api/#{@api_key}/list/#{CONFIG_PATTERN}"
    assert_equal 200, last_response.status, last_response.body
    file_list = {"file_list" => [CONFIG_JSON]}
    assert_equal file_list, JSON.parse(last_response.body)
    assert_match "application/json", last_response.content_type
    # test results for multiple files
    begin
      FileUtils::cp(VALID_CONFIG_JSON_ORIG, SECOND_CONFIG_JSON)
      get "/api/#{@api_key}/list/#{CONFIG_PATTERN}"
      assert_equal 200, last_response.status, last_response.body
      file_list = {"file_list" => [CONFIG_JSON, SECOND_CONFIG_JSON]}
      assert_equal file_list, JSON.parse(last_response.body)
      assert_match "application/json", last_response.content_type
    ensure
      FileUtils::safe_unlink(SECOND_CONFIG_JSON)
    end
    # test for no files
    get "/api/#{@api_key}/list/abcmatchnofilesabc"
    assert_equal 404, last_response.status, last_response.body
  end

  def test_get_file_if_newer
    # set CONFIG_JSON on disk to known time and run the test in/around that time period
    orig_file_time_str = "10-1-22 8:44am"
    orig_file_time = Chronic::parse(orig_file_time_str)
    File::utime(orig_file_time, orig_file_time, CONFIG_JSON)
    assert_equal orig_file_time, File::atime(CONFIG_JSON)
    newer_time_str = "10-1-22 8:45am"
    newer_time_esc = URI::escape(newer_time_str)
    newer_time = Chronic::parse(newer_time_str)
    older_time_str = "10-1-22 8:43am"
    older_time_esc = URI::escape(older_time_str)
    # check that we get the file if file is newer than request
    get "/api/#{@api_key}/if-file/newer-than/#{older_time_esc}/#{CONFIG_JSON}"
    assert_equal 200, last_response.status, last_response.body
    assert_equal File::read(CONFIG_JSON), last_response.body
    # check that we don't get the file if the file is older than request
    get "/api/#{@api_key}/if-file/newer-than/#{newer_time_esc}/#{CONFIG_JSON}"
    assert_equal 204, last_response.status, last_response.body
    assert_equal "", last_response.body, last_response.inspect
  end

  def test_post_config_file
    filedata = File::read(CONFIG_JSON)
    filename = CONFIG_JSON
    FileUtils::safe_unlink(CONFIG_JSON)
    tempfile = Tempfile.new('config_json')
    tempfile.write(filedata)
    assert !File::exists?(CONFIG_JSON)
    assert File::exists?(tempfile.path)
    tempfile.rewind
    assert_equal filedata.size, tempfile.read.size
    upload_file = Rack::Test::UploadedFile.new(tempfile.path, "text/json")    
    post "/api/#{@api_key}/file/#{CONFIG_JSON}", "file" => upload_file
    assert_equal 200, last_response.status, last_response.body
    assert_equal filedata, File::read(CONFIG_JSON)
    tempfile.unlink
  end
  
  def test_post_config_file_with_no_data
    filedata = File::read(CONFIG_JSON)
    filename = CONFIG_JSON
    FileUtils::safe_unlink(CONFIG_JSON)
    begin
      assert !File.exist?(CONFIG_JSON)
      post "/api/#{@api_key}/file/#{CONFIG_JSON}"      
      assert_equal 400, last_response.status, last_response.body
      assert !File::exists?(CONFIG_JSON)
    ensure
      # delete file but ignore exception if file doesn't exist
      begin FileUtils::safe_unlink(CONFIG_JSON) rescue NameError ; end
      File::write(CONFIG_JSON, filedata)
    end
  end  
  
  def test_favicon
    get "/favicon.ico"
    assert_equal 200, last_response.status, last_response.body
    favicon_orig_path = File::join(app.settings.public_folder, @config.images_folder, 'favicon.ico')
    assert last_response.body == IO::binread(favicon_orig_path)
  end


end