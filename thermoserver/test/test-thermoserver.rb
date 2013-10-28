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
    raise if File::exist?(CONFIG_JSON)
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

  def test_webapi_turn_heater_off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    # verify operation mode is not off
    assert_equal "daily_schedule", config_json["operation_mode"]
    get "/app-api/#{@app_api_key}/#{CONFIG_JSON}/operation_mode/off"
    assert_equal 200, last_response.status, last_response.body
    # verify operation mode is off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "off", config_json["operation_mode"]
    assert_equal "off", config_json["off"]

    # turn the operation mode back to "daily_schedule"
    get "/app-api/#{@app_api_key}/#{CONFIG_JSON}/operation_mode/daily_schedule"
    assert_equal 200, last_response.status, last_response.body
    # verify operation mode is off
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "daily_schedule", config_json["operation_mode"]
    assert_equal "off", config_json["off"]
  end

  def test_webapi_turn_heater_off_invalid_config_file
    # verify trying to modify a non-existent heater config file 
    # results in an error
    get "/app-api/#{@app_api_key}/invalid_heater.json/operation_mode/off"
    assert_equal 404, last_response.status, last_response.body
  end

  def test_webapi_turn_heater_to_hold
    get "/app-api/#{@app_api_key}/#{CONFIG_JSON}/override_mode/hold/74"
    assert_equal 200, last_response.status, last_response.body
    config_json = JSON.parse(File::read(CONFIG_JSON))
    assert_equal "74", config_json["immediate"]["temp_f"]
    assert_equal Time::now.to_s, config_json["immediate"]["time_stamp"]
  end

  def test_webapi_turn_heater_to_temp_override

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
  
  def test_functional_config_change
    
  end

  def test_favicon
    get "/favicon.ico"
    assert_equal 200, last_response.status, last_response.body
    favicon_orig_path = File::join(app.settings.public_folder, @config.images_folder, 'favicon.ico')
    assert last_response.body == IO::binread(favicon_orig_path)
  end


end