### REMOVE FROM PRODUCTION ###
require 'debugger';     
##############################

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
  class InvalidTemperature < ThermoError; end
  class HWTempRead < ThermoError; end
  class InitializeFailed < ThermoError; end
  class UnknownRunMode < ThermoError; end
  
  BOOT_FILE_NAME = "boot.json"
  HYSTERESIS_DURATION_DEFAULT = "5 minutes"
  MAX_OPERATING_TIME__MINUTES_DEFAULT = "60"
  MAX_TEMP_F_DEFAULT = 80

  # RUN_MODE determines if we are in a testing environment
  # primarily this is used to manage shelling out to run command
  # line commands that don't exist in testing environments
  RUN_MODE = ENV["thermo_run_mode"] || "production"

  # Heater hardware commands
  INITIALIZE_HEATER_HARDWARE = [
     {:cmd => "gpio", :args => ["mode 0 out"]}, 
     {:cmd => "sudo", :args => ["modprobe", "w1-gpio"]}, 
     {:cmd => "sudo", :args => ["modprobe", "w1-therm"]}]
  HEATER_ON_CMD = [{:cmd => "gpio", :args=>["write", "0", "1"]}]
  HEATER_OFF_CMD = [{:cmd => "gpio", :args=>["write", "0", "0"]}]

  
  # Configuration class is responsible for loading and re-loading configurations
  # It starts by loading the boot configuration from disk
  # It then uses that booter to load a more detailed configuration file via URL
  class Configuration
    attr_accessor :boot, :config
    attr_reader :using_url_for_config
    
    # load our default settings from the boot.json file
    # load main config file from url specified in boot file
    def initialize(options = {})
      boot_file = options[:boot_file] || BOOT_FILE_NAME
      @boot = load_boot_config_from_file(boot_file)
      @using_url_for_config = !!options[:config]
      @config = options[:config] || load_config_from_url
    end

    def load_boot_config_from_file(boot_file = BOOT_FILE_NAME)
      JSON.parse(IO.read(boot_file))
    end

    def load_config_from_url(url = @boot["config_source"]["config_url"])
      JSON.parse(Net::HTTP.get(URI(url)))
    end
  end # Configuration

  # Thermostat class is responsible for getting a configuration file from 
  # Configuration class and interpreting it to control the RPi hardware
  # It must correctly read temperature data from RPi, understand scheduling
  # and write relay actions to RPi based on schedule and temperature goal and 
  # actual data
  class Thermostat
    # exposes the configuration object
    attr_accessor :configuration
    # allows testing harness to initiate debug breakpoints and other 
    # communications with test harness
    attr_accessor :debug
    def dbg
      debugger if self.debug
    end

    # safety features
    # holds a time which indicates when the heater is allowed to turn back on
    # this prevents hystersis, where the heater goes on/off rapidly based on
    # small temperature fluctuations
    attr_accessor :max_heater_on_time_minutes
    attr_accessor :max_temp_f
    attr_accessor :hysteresis_duration
    
    # used for testing - if set, we use this value instead of system values
    attr_reader :override_current_time
    attr_accessor :override_current_temp_f
    attr_accessor :override_relay_state
    attr_reader :heater_last_on_time
    attr_reader :goal_temp_f
    
    #holds the last set of commands executed on the command line
    attr_accessor :command_line_history
    # holds a temp root folder for testing - allows
    # us to read temperature files from non-root folder
    # during tests
    attr_accessor :test_hw_temp_root_dir
    
    # start up by loading our configuration
    def initialize(options = {})
      # turn heater off as first initializing step
      # this is to protect against a recurring crash
      # leaving the heater in the permenantly on condition
      self.command_line_history = {}
      set_heater_state(false)
      self.test_hw_temp_root_dir = ""
      begin
        @configuration = Configuration.new(options)
        set_current_time
        setup_safety_config
        initialize_hardware
      rescue Exception => e
        set_heater_state(false)
        raise Thermo::InitializeFailed.new("Heater init failed but heater was turned off. Original class: #{e.class.to_s}. Msg: #{e.message}. #{e.backtrace}")
      end
    end
    
	# set up hardware ports to communicate with relay and thermostat
    def initialize_hardware
      self.execute_system_commands(INITIALIZE_HEATER_HARDWARE)
    end
    
    # Receives an array of hashes which represent command line instructions
    # Format: [{:cmd => 'command', :args => ["arg1","arg2"...]},...]
	def execute_system_commands(cmds)
    if RUN_MODE == "testing"
        # do nothing on the command line in test mode
	  else # assume RUN_MODE == 'production' in all other cases
        cmds.each do |cmd|
          Kernel.system(cmd[:cmd],*cmd[:args])
        end
    end
    self.add_executed_cmds_to_history(cmds)
	end
  
    def add_executed_cmds_to_history(cmds)
      self.command_line_history[self.current_time] = cmds
    end
    
    def setup_safety_config
      @max_heater_on_time_minutes = self.configuration.boot["operating_parameters"]["max_operating_time_minutes"].to_i
      if @max_heater_on_time_minutes == 0
        @max_heater_on_time_minutes = MAX_OPERATING_TIME_MINUTES_DEFAULT
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

    def override_current_time=(time)
      @override_current_time = time
      set_current_time
    end

    # we don't let the clock tick while the application is running
    # we get the current time when we init, or process a schedule
    # during the processing, we keep the time static, to prevent
    # unpredictable errors such if the system clock ticked over 
    # a schedule boundary during processing
    def set_current_time
      @internal_time = (self.override_current_time || Time::now)
    end
    
    def current_time
      @internal_time
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
    def parse_time(time_str, options={})
      options[:now] = options[:now] || self.current_time
      retval = Chronic.parse(time_str, options)
      retval
    end
    
    # we process the schedule periodically - this function uses current
    # time & temp, and compares to scheduled time and temp to determine
    # the action it should take
    def process_schedule
      self.set_current_time
      self.command_line_history = {}
      schedule_mode = self.configuration.config["operation_mode"] || "Undefined"
      schedule = self.configuration.config[schedule_mode] || raise(UnknownSchedule.new("'operation_mode' value in config does not reference an existing configuration in the config file."))

      case schedule_mode
        when "daily_schedule"
          process_daily_schedule(schedule)
        when "immediate"
          process_immediate_schedule(schedule)
        when "off" 
          set_heater_state(false)
        else # error out if we don't know how to handle the schedule file
          raise UnknownSchedule.new("Unknown schedule found in configuration file. Schedule provided: \"#{schedule_mode}\"")
      end
    end

    def process_immediate_schedule(schedule)
      heater_state_modified = false
      new_goal_temp_f = schedule["temp_f"]
      if new_goal_temp_f > self.current_temp_f
        set_heater_state(true, new_goal_temp_f)
        heater_state_modified = true      
      end
      # if we haven't modified the heater state that means we 
      # did not find a matching time window and so should turn
      # the heater off (a gap in the time window = heater off)
      if !heater_state_modified
        set_heater_state(false) 
      end
    end

    # Finds time window within config file that corresponds to current time
    # Finds goal temp for that window
    # Turns heater on/off depending on if goal temp is gt/lt than actual temp
    def process_daily_schedule(schedule)
      # compare current time/temp with config specified in file
      heater_state_modified = false
      times_of_op = schedule["times_of_operation"]
      new_goal_temp_f = nil
      times_of_op.each do |time_window|
        start_time = self.parse_time(time_window["start"])
        end_time = self.parse_time(time_window["stop"])
        # minor hack to make config file more intuitive
        if end_time == self.parse_time("12:00 am")
          end_time = self.parse_time("tomorrow at 12:00 am")
        end
        # this handles override temperature settings from user (via config)
        if temp_override_active_for_time_window?(:end_time => end_time, :start_time => start_time)
          new_goal_temp_f = self.temp_override_goal_temp_f
          if self.temp_override_goal_temp_f && self.current_temp_f < self.temp_override_goal_temp_f
            set_heater_state(true, self.temp_override_goal_temp_f)
            heater_state_modified = true
            break
          end
        end
        # this handles regularly scheduled temp settings from config
        if (start_time <= current_time) && (end_time >= current_time)
          new_goal_temp_f = time_window["temp_f"] if !new_goal_temp_f
          if self.current_temp_f < new_goal_temp_f
            set_heater_state(true, new_goal_temp_f)
            heater_state_modified = true
            break
          end
        end
      end # times_of_op.each do...
      # if we haven't modified the heater state that means we 
      # did not find a matching time window and so should turn
      # the heater off (a gap in the time window = heater off)
      if !heater_state_modified
        set_heater_state(false, new_goal_temp_f)
      end
    end

    # temp_override causes heater to seek new goal temp ignoring existing schedule
    # it only applies within the window of an existing schedule
    # e.g., Schedule window 5/15/22 6:30am-10:00am; goal_f=66. temp_override point 6/15/22 9:15am; goal_f=72
    #   If current time is <9:15am OR >10:00am, regular schedule applies, otherwise temp_override goal_f applies
    def temp_override_active_for_time_window?(options)
      end_time = options[:end_time]
      start_time = options[:start_time]
      override_start_time = self.temp_override_start_time
      cur_time = self.current_time
      # we have to be inside the current time window for temp_override to be possible for this window
      override_start_time && (cur_time >= start_time) && (cur_time >= override_start_time) && (cur_time <= end_time) && (override_start_time >= start_time) && (override_start_time <= end_time)
    end
    
    def temp_override_start_time
      if self.configuration.config["temp_override"]
        Chronic.parse(self.configuration.config["temp_override"]["date-time"])
      end
    end
    
    def temp_override_goal_temp_f
      self.configuration.config["temp_override"]["temp_f"] if self.configuration.config["temp_override"]
    end
    
    def goal_temp_f
      @goal_temp_f
    end
    
    def goal_temp_f=(new_temp_f)
      @goal_temp_f = new_temp_f
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
      retval = @heater_on_state
      retval
    end

    # assigns hardware-obtained temperature in farenheit to 
    # internal state variable
    def current_temp_f
      cur_temp_f = nil
      if RUN_MODE == "testing" && @override_current_temp_f
          cur_temp_f = @override_current_temp_f # return override temp value in test mode
      else # assume RUN_MODE == 'production' in all other cases
          cur_temp_f = get_hw_temp_f
      end
      cur_temp_f
    end
    
    def get_hw_temp_f
      #TODO get correct C to F conversion
      (get_hw_temp_c*3.125)
    end
    
    def get_hw_temp_c
      base_folder = File::join(@test_hw_temp_root_dir,"/sys/bus/w1/devices/28-*")
      folders = Dir[base_folder]
      if folders.size != 1
        raise Thermo::HWTempRead.new("Too many or zero temperature folders in get_hw_temp_c: "+folders.join(" :: "))
      end    
      temp_file = File::join(folders.first, "w1_slave")
      files = Dir[temp_file]
      if files.size != 1
        raise Thermo::HWTempRead.new("Too many or zero temperature files in get_hw_temp_c: "+files.join(" :: "))
      end    
      temperature = nil
      File::open(files.first, "r") do |file|
        if !file.gets.match(/YES/)
          raise Thermo::HWTempRead.new("Temperature file missing 'YES' value. Cannot (should not) read temp.")
        end
        # temp is in hw file as "N+.NNN"
        temperature = file.gets.match(/t=([0-9]+)/)[1]
      end
      # return a float, assumes temperature should be parsed: /[0-9]+.[0-9][0-9][0-9]/
      temperature.insert(temperature.size-3,".").to_f
    end
    
    def heater_on=(state)
      if state
        self.execute_system_commands(HEATER_ON_CMD)
      else
        self.execute_system_commands(HEATER_OFF_CMD)
      end
      @heater_on_state = state
    end

    # Returns true if the measured temp is higher than safety value
    def current_temp_too_hot_to_operate?
      self.current_temp_f >= self.max_temp_f
    end

    # Returns true if the heater should remain off due to hysteresis control
    # This prevents the heater from going on and off too rapidly
    def in_hysteresis?
      # if the heater hasn't been turned on yet, we cannot be in hysteresis
      return false if !self.heater_last_on_time
      # this calculates the current time plus the hysteresis duration
      hys_calc = @hysteresis_duration+ " after"
      hys_window = self.parse_time(hys_calc, :now => self.heater_last_on_time) 
      current_time < hys_window
    end

    # returns the number of minutes the heater has been running
    # returns nil if not running
    def heater_running_time_minutes
      return nil if !heater_on?
      return nil if self.heater_last_on_time >= self.current_time
      (self.current_time - self.heater_last_on_time)/60
    end

    # returns true if heater has been on for longer than allowable period 
    # as provided in boot json file
    def heater_on_too_long?
      retval = true
      return false if !heater_on?
      if self.heater_running_time_minutes && (self.heater_running_time_minutes < self.max_heater_on_time_minutes)
        return false
      end
      retval
    end

    # Returns true if all safety parameters for heater operation
    # allow heater to be on. True = "heater safe to operate"
    # NOTE: If this returns false, the heater MUST be turned off
    # It MUST NOT simply remain in the state it was in.
    def heater_safe_to_turn_on?
      return false if self.in_hysteresis?
      return false if self.heater_on_too_long?
      return false if self.current_temp_too_hot_to_operate?
      true
    end

    # send true to turn heater on, false to turn heater off
    def set_heater_state(turn_heater_on, new_goal_temp_f = nil)
      if !turn_heater_on
        self.heater_on = false
        ## TODO Remove this?
        reset_heater_last_on_time
        self.goal_temp_f = new_goal_temp_f
      # Only change the heater to on if safety parameters are satisfied
      elsif turn_heater_on && self.heater_safe_to_turn_on?
        raise(Thermo::InvalidTemperature, "Temp must be supplied to set_heater_state in order to turn on heater")if !new_goal_temp_f        
        self.heater_on = true
        set_heater_last_on_time
        self.goal_temp_f = new_goal_temp_f
      else
        # this state occurs when heater is unsafe to turn on
        # due to hysteresis, over temp, or running too long
        # or unhandled in some other way
        # Heater *must* be turned off when unhandled
        # We don't reset heater_last_on_time because hysteresis
        # and max runtime safety limits depend on that calculation

        # bring the heater_last_on_time to current time
        # this allows hysteresis to keep the heater off for a period
        # if the heater has been running too long (and that's why it's being 
        # turned off)
        set_heater_last_on_time if self.heater_on?
        self.heater_on = false
        self.goal_temp_f = new_goal_temp_f
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
  "operation_mode": ["daily_schedule"|"weekly_schedule"|"workweekly_schedule"|"immediate"|"off"],
  "daily_schedule": {
    "times-of-operation": [
      {"start": "6:30 am", "stop": "10:00 am", "temp-f": 68},
      {"start": "10:00 am", "stop": "6:00 pm", "temp-f": 62},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp-f": 70},
      {"start": "11:00 pm", "stop": "5:30 am", "temp-f": 62}
  ]},
  "weekly_schedule": {
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
  "immediate": {"temp_f": 62},
  "temp_override": {"date-time": "2013-07-27 23:11:20 -0000", "temp_f": 66},
  "off" : "off"
}

schedule notes:
  If there is a gap between one end time and the following start time, heater will be OFF during that period
  If a scheduled time extends to the following day (or over a following time period of the same day), it will be overridden by any settings for the following day/time period that overlap. It will function if the earliest time the following day is not overlapping.
    In short, the first matching time to the current time will be processed
    So: 
    6:30am-9:00pm followed by 9:00pm-7:30am is the same as
    6:30am-9:00pm followed by 9:00pm-6:30am
  temp_override: Temporarily overrides goal temp, until time window no longer overlaps with date-time
    Override does not have an "operation_mode" - it simply overrides the existing schedule
    Override has no effect on "operation_mode" "immediate" or "off"
    date-time must be a specific point in time, not a parseable generic date
  immediate: Places a permanent hold on goal temp. Heater will maintain this temp until immediate mode is disabled
  
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
