gem "minitest"

require 'minitest/autorun'
require '../thermoclient.rb'
require 'fileutils'
require 'chronic'

VALID_BOOT_JSON_ORIG = 'valid-thermo-boot.json.orig'
VALID_CONFIG_JSON_ORIG = 'backbedroom.json.orig'
# this file must be made available to a webserver at the path specified in VALID_BOOT_JSON_ORIG for config_url and config_url_watch
VALID_CONFIG_JSON = 'backbedroom.json'

class TestThermoClient < Minitest::Test
  def setup
    FileUtils.cp(VALID_BOOT_JSON_ORIG, Thermo::BOOT_FILE_NAME)
    FileUtils.cp(VALID_CONFIG_JSON_ORIG, VALID_CONFIG_JSON)
  end
  
  def teardown
    FileUtils.safe_unlink(Thermo::BOOT_FILE_NAME)
    FileUtils.safe_unlink(VALID_CONFIG_JSON)
    raise Thermo::ConfigFileNotFound if File.exist?(Thermo::BOOT_FILE_NAME)
    raise Thermo::ConfigFileNotFound if File.exist?(VALID_CONFIG_JSON)
  end

  def test_configuration_loader
    config = Thermo::Configuration.new
    assert_equal JSON.parse(IO.read(VALID_BOOT_JSON_ORIG)), config.boot
    assert_equal JSON.parse(IO.read(VALID_CONFIG_JSON_ORIG)), config.config
  end

  def test_thermostat
    thermostat = Thermo::Thermostat.new
    # Testing scenario 1:
    #   Time: 12/1/13 5:14am
    #   Room temp: 68
    #   Goal temp: 62 (12:00am-6:30am)
    #   Outcome: Heater should be off 
puts "Scenario 1"
    cur_time = Chronic.parse("12/1/13 5:14am")
    cur_temp = 68
    set_and_test_time_temp(cur_time, cur_temp, thermostat)
    assert_heater_state_time(false, nil, thermostat)
    thermostat.process_schedule
    assert_heater_state_time(false, nil, thermostat)

puts "Scenario 2"
    # Testing scenario 2:
    #   Time: 12/1/13 5:19am
    #   Room temp: 60
    #   Goal temp: 62 (12:00am-6:30am)
    #   Outcome: Heater should be on
    cur_time = Chronic.parse("12/1/13 5:19am")
    cur_temp = 68
    set_and_test_time_temp(cur_time, cur_temp, thermostat)
    assert_heater_state_time(false, nil, thermostat)
    thermostat.process_schedule
    assert_heater_state_time(true, cur_time, thermostat)
  end
  
  def assert_heater_state_time(state, last_on_time, thermostat)
    assert_equal state, thermostat.heater_on?
    assert_equal last_on_time, thermostat.heater_last_on_time
  end
  
  def set_and_test_time_temp(cur_time, cur_temp, thermostat)
    thermostat.override_current_time = cur_time
    assert_equal cur_time, thermostat.current_time
    thermostat.override_current_temp_f = cur_temp
    assert_equal cur_temp, thermostat.current_temp_f
  end
  
end
