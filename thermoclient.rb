require 'json'
require 'net/http'

module Thermo

  class ConfigFileNotFound < RuntimeError; end

  BOOT_FILE_NAME = "boot.json"

  class Configuration
    attr_accessor :boot, :config
    
    # load our default settings from the boot.json file
    def initialize(boot_file = BOOT_FILE_NAME)
      @boot = JSON.parse(IO.read(boot_file))
    end

    def load_config_from_url(url = @boot.config_source.config_url)
      @config = JSON.parse(Net::HTTP.get(URI(url)))
    end

  end # Configuration

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
  If a scheduled time extends to the following day (or over a following time period of the same day),
    it overrides any settings for the following day/time period until it stops/expires
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
