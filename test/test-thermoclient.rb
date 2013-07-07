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

  def test_thermostat_should_stay_off_early_morning
    # Testing scenario 1:
    #   Time: 12/1/13 5:14am
    #   Room temp: 68
    #   Initial Heater state: off
    #   Goal temp: 62 (12:00am-6:30am)
    #   Outcome: Heater should be off 
    thermostat = Thermo::Thermostat.new
    cur_time = Chronic.parse("12/1/13 5:14am")
    cur_temp = 68
    set_and_test_time_temp(cur_time, cur_temp, thermostat)
    assert_heater_state_time(false, nil, thermostat)
    thermostat.process_schedule
    assert_heater_state_time(false, nil, thermostat)
  end

  def test_thermostat_should_turn_off_due_to_schedule_gap
    # Testing scenario 3:
    #   Time: 12/8/14 6:26pm
    #   Room temp: 50
    #   Initial Heater state: running for 30 minutes
    #   Goal temp: nil (6:00pm-7:00pm)
    #   Outcome: Heater should be off 
    thermostat = Thermo::Thermostat.new
    heater_last_started_time = Chronic.parse("12/8/14 5:56pm")
    thermostat.override_current_time = heater_last_started_time
    assert !thermostat.in_hysteresis?
    thermostat.set_heater_state(true)
    assert thermostat.in_hysteresis?
    assert thermostat.heater_on?
    cur_time = Chronic.parse("12/8/14 6:26pm")
    cur_temp = 50
    set_and_test_time_temp(cur_time, cur_temp, thermostat)
    assert !thermostat.in_hysteresis?
    assert_heater_state_time(true, heater_last_started_time, thermostat)
    thermostat.process_schedule
    assert_heater_state_time(false, heater_last_started_time, thermostat)
  end

  def test_thermostat_should_turn_on
    # Testing scenario 2:
    #   Time: 12/1/17 5:19am
    #   Room temp: 60
    #   Initial Heater state: off
    #   Goal temp: 62 (12:00am-6:30am)
    #   Outcome: Heater should be on
    thermostat = Thermo::Thermostat.new
    cur_time = Chronic.parse("12/1/17 5:19am")
    cur_temp = 60
    set_and_test_time_temp(cur_time, cur_temp, thermostat)
    assert !thermostat.in_hysteresis?
    assert_heater_state_time(false, nil, thermostat)
    thermostat.process_schedule
    assert_heater_state_time(true, cur_time, thermostat)
  end
  
  def assert_heater_state_time(state, last_on_time, thermostat)
    assert_equal state, thermostat.heater_on?, "Heater should be #{state.inspect} but was #{thermostat.heater_on?}"
    assert_equal last_on_time, thermostat.heater_last_on_time, "Heater last on time should be #{last_on_time.inspect} but was #{thermostat.heater_last_on_time.inspect}"
  end
  
  def set_and_test_time_temp(cur_time, cur_temp, thermostat)
    thermostat.override_current_time = cur_time
    assert_equal cur_time, thermostat.current_time, "Thermostat time should be #{cur_time.inspect} but was #{thermostat.current_time.inspect}"
    thermostat.override_current_temp_f = cur_temp
    assert_equal cur_temp, thermostat.current_temp_f, "Thermostat temp should be #{cur_temp.inspect} but was #{thermostat.current_temp_f}"
  end
  
end
