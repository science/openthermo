require 'json'
require 'net/http'
require 'chronic'

# Design notes
# the code / system that runs Thermo::Thermostat
# must always turn the heater off when Thermostat exits
# This is to protect against unexpected exceptions
# that might leave the heater turned on


module Thermo
  class ThermoError < RuntimeError; end
  class ConfigFileNotFound < ThermoError; end
  class UnknownSchedule < ThermoError; end
  BOOT_FILE_NAME = "boot.json"
  HYSTERESIS_DURATION_DEFAULT = "5 minutes"
  MAX_OPERATING_TIME_DEFAULT = "60 minutes"
  MAX_TEMP_F_DEFAULT = 80

  # Configuration class is responsible for loading and re-loading configurations
  # It starts by loading the boot configuration from disk
  # It then uses that booter to load a more detailed configuration file via URL
  class Configuration
    attr_accessor :boot, :config
    
    # load our default settings from the boot.json file
    def initialize(boot_file = BOOT_FILE_NAME)
      load_boot_config_from_file(boot_file)
      load_config_from_url
    end

    def load_boot_config_from_file(boot_file = BOOT_FILE_NAME)
      @boot = JSON.parse(IO.read(boot_file))
    end

    def load_config_from_url(url = @boot["config_source"]["config_url"])
      @config = JSON.parse(Net::HTTP.get(URI(url)))
    end
  end # Configuration

  # Thermostat class is responsible for getting a configuration file from 
  # Configuration class and interpreting it to control the RPi hardware
  # It must correctly read temperature data from RPi, understand scheduling
  # and write relay actions to RPi based on schedule and temperature goal and 
  # actual data
  class Thermostat
    attr_accessor :configuration

    # safety features
    # holds a time which indicates when the heater is allowed to turn back on
    # this prevents hystersis, where the heater goes on/off rapidly based on
    # small temperature fluctuations
    attr_accessor :max_heater_on_time
    attr_accessor :max_temp_f
    attr_accessor :hysteresis_duration
    
    # used for testing - if set, we use this value instead of system values
    attr_accessor :override_current_time
    attr_accessor :override_current_temp_f
    attr_accessor :override_relay_state
    attr_reader :heater_last_on_time
    attr_reader :goal_temp
    
    # start up by loading our configuration
    def initialize
      # turn heater off as first initializing step
      # this is to protect against a recurring crash
      # leaving the heater in the permenantly on condition
      set_heater_state(false)
      @configuration = Configuration.new
      setup_safety_config
    end
    
    def setup_safety_config
      @max_heater_on_time = self.configuration.boot["operating_parameters"]["max_operating_time"]
      if !self.parse_time(@max_heater_on_time+ " from now").kind_of?(Time)
        @max_heater_on_time = MAX_OPERATING_TIME_DEFAULT
      end
      @hysteresis_duration = self.configuration.boot["operating_parameters"]["hysteresis_duration"]
      if !self.parse_time(@hysteresis_duration+ " from now")
        @hysteresis_duration = HYSTERESIS_DURATION_DEFAULT 
      end
      @max_temp_f = self.configuration.boot["operating_parameters"]["max_temp_f"]
      if !@max_temp_f.is_a? Integer
        @max_temp_f = MAX_TEMP_F_DEFAULT
      end
    end

    def current_time
      @override_current_time || Time::now
    end

    def current_hour_min_sec_str
      cur_time = self.current_time
      hour = cur_time.hour
      min = cur_time.min
      sec = cur_time.sec
      "#{hour}:#{min}:#{sec}"
    end

    def current_year_month_day_str
      cur_time = self.current_time
      year = cur_time.year
      month = cur_time.month
      day = cur_time.day
      "#{year}-#{month}-#{day}"
    end
    
    # Returns Chronic-parsed Time object
    # we set the current time to base the parsing on 
    # using our internal time, which permits testing
    # using alternate times to the current system clock
    def parse_time(time_str)
      Chronic.parse(time_str, :now => Chronic.parse(self.current_year_month_day_str))
    end
    
    # assigns hardware-obtained temperature in farenheit to internal state variable
    def current_temp_f
      #TODO hardware call to obtain temperature reading
      @override_current_temp_f # || get_hw_temp_f
    end
    

    # we process the schedule periodically - this function uses current
    # time & temp, and compares to scheduled time and temp to determine
    # the action it should take
    def process_schedule
      # error out if we don't know how to handle the schedule file
      raise UnknownSchedule, "Unknown schedule found in configuration file. Currently we only handle 'daily_schedule' type" unless self.configuration.config["daily_schedule"]

      # safety checks
      # heater should not run more than max heater on time
      # heater should not run hotter than max temp
      
      # compare current time/temp with config specified in file
      self.configuration.config["daily_schedule"]["daily"]["times_of_operation"].each do |time_window|
        start_time = self.parse_time(time_window["start"])
        end_time = self.parse_time(time_window["stop"])
        goal_temp = time_window["temp_f"]

        if (start_time < current_time) && (end_time > current_time)
          if self.current_temp_f < goal_temp
            set_heater_state(true)
          else
            set_heater_state(false)
          end
        end
      end
    end
    
    # this records the time at which the heater was last turned on
    # used when heater is turned on
    def set_heater_last_on_time
      @heater_last_on_time = self.current_time
    end

    # this clears the time at which the heater was last turned on
    # used when heater is turned off
    def reset_heater_last_on_time
      @heater_on_time = nil
    end

    def heater_on?
      # TODO add hardware call to determine relay state
      # get_hardware_heater_activity_state || _
      @override_heater_activity_state  || @heater_on
    end

    def heater_on=(state)
      @heater_on = state
      # TODO add hardware call to set heater relay to on or off
    end

    # Returns true if the heater should remain off due to hysteresis control
    # This prevents the heater from going on and off too rapidly
    def in_hysteresis?
      # we don't use "Time::now" here b/c current_time may be overridden in tests
      time = self.current_hour_min_sec_str
      # this calculate the current time plus the hysteresis duration
      hys_window = self.parse_time(@hysteresis_duration+ " from "+time) 
      current_time >= hys_window
    end

    # send true to turn heater on, false to turn heater off
    def set_heater_state(setting = true)
      # Only change the hardware state to on if hysteresis_window is satisfied
      if setting && !in_hysteresis?
        heater_on = true
        set_heater_last_on_time
      elsif !setting 
        heater_on = false
        reset_heater_last_on_time
      end
    end

  end # Thermostat

end # Thermo




=begin
/*
System installation requirements
  modeprobe (default with Rasberian)
  WiringPi GPIO utility (https://projects.drogon.net/raspberry-pi/wiringpi/the-gpio-utility/)

Node.js installation requirements
  restify
  nodeunit

*/

/*
JSON command files
  boot.json
    Boot file defines basic variables such as where to obtain full config file from server
      http://[server-name]/[api-path]/[instance-name].json
    Operating limits
      Provides basic safety parameters for operation
        Always turn off heater above XX temperature
        Never operate heater for more than XX minutes
  [instance-name].json
    Defines network refresh/polling period
    Defines immediate and scheduled operations
      Immediate operations defines simply "on/off"
      Scheduled operations
        Provides schedule information for temperature settings per days/times
        Options:
          Daily: Set of times/temps for operation each day (1 set of config/week)
          Weekly: Set of times/temps unique for operation M-Su (7 sets of configs/week)
          WorkWeekly: Set of times/temps unique for operation M-Fr, Sa-Su (2 sets of configs/week)

File formats

boot.json
{
  "config-source": {
    "immediate-polling-seconds": 300,
    "config-url": "http://localhost:8080/now/backbedroom.json"
    "config-url-watch": "http://localhost:8080/watchfile/backbedroom.json"
    "watch-timeout-minutes": 780
  }
  "operating-parameters": {
    "max-temp-f": 80,
    "max-operating-minutes": 60
  }
}

Note that polling-seconds is usually irrelevant b/c client will hit the immediate polling
url and then hang out on config-url-watch will update immediately upon remote file change


[instance-name].json
{
  "immediate-operation": ["on"|"off"|other value/null="scheduled"],
  "scheduled-operation-mode": ["daily"|"weekly"|"workweekly"],
  "daily-schedule": {
    ["daily"]: {"times-of-operation": [
      {"start": "6:30 am", "stop": "10:00 am", "temp-f": 68},
      {"start": "10:00 am", "stop": "6:00 pm", "temp-f": 62},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp-f": 70},
      {"start": "11:00 pm", "stop": "5:30 am", "temp-f": 62}
  ]}},
  "weekly-schedule": {
    ["monday".."sunday"]: {"times-of-operation": [
      {"start": "6:30 am", "stop": "10:00 am", "temp-f": 68},
      {"start": "10:00 am", "stop": "6:00 pm", "temp-f": 62},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp-f": 70},
      {"start": "11:00 pm", "stop": "5:30 am", "temp-f": 62}
  ]}},
  "workweekly-schedule": {
    ["workday"|"weekend"]: {"times-of-operation": [
      {"start": "6:30 am", "stop": "10:00 am", "temp-f": 68},
      {"start": "10:00 am", "stop": "6:00 pm", "temp-f": 62},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp-f": 70},
      {"start": "11:00 pm", "stop": "5:30 am", "temp-f": 62}
  ]}},
}

schedule notes:
  If there is a gap between one end time and the following start time, heater will be OFF during that period
  If a scheduled time extends to the following day (or over a following time period of the same day), it will be overridden by any settings for the following day/time period that overlap. It will function if the earliest time the following day is not overlapping.
    In short, the first matching time to the current time will be processed
    So: 
    6:30am-9:00pm followed by 9:00pm-7:30am is the same as
    6:30am-9:00pm followed by 9:00pm-6:30am
*/


/*
Command line entries for relay and thermometer hardware

Init for Relay
  gpio mode 0 out

Operation for Relay
  Relay closed:
    gpio write 0 1
  Relay open:
    gpio write 0 0

Init for Thermomometer
sudo modprobe w1-gpio
sudo modprobe w1-therm

Operation for Thermometer
  Look in /sys/bus/w1/devices
    for folder named "28-*"
    Look in folder for file named w1_slave
      pull ascii contents of file into var
      grep var for /YES/
        Continue if found
        Temp read fail/error if not found (try re-init?)
      grep var for /t=[0-9]+/
      place decimal left of the 3rd digit to the right: [0-9]+\.[0-9][0-9][0-9]$
      convert var to float
      temperature can now be read as a celsius float
      bounds check variable within 0 and 45
        If bounds check fails, turn off heater

*/
=end
