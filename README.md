#thermoruby
_a network-enabled thermostat controller_

# Overview
DIY thermostat project designed to let you operate multiple network controlled thermostats on heaters of various types.

Currently, supported hardware is a Raspberry Pi with particular electronics and driver support. More details on these coming soon.

There are several parts of this project:

* A ruby client = thermoruby.rb and related controller and test files
* A node.js server = this is used for testing and can be used for operations. It does very little - simply returning configurations files when requested

More documentation to come, and contact welcome from interested users or contributors. science@misuse.org

# Installation
To install, be sure you have required libraries which can be found in thermoclient.rb file. GEMSPEC file forthcoming. Ruby 1.9.3 was used in development.

To test, you must also have node.js installed or an equivalent web server exposing the API specified in the boot.json files (named valid-thermo-boot.json.orig in test).
If you wish to use an alternative test webserver, basically that server must make your configuration files available at the URL specified in boot.json for the key "config_url"
For testing, this webserver must make that URL available by mounting the test folder to that location.

Node.js server requires restify, semaphore and nodeunit.

# Testing
If you are using Node.js to run tests, you must first start the webserver prior to running tests. On Windows you can run "startserver.cmd" in the test folder. 
For Linux, you start the server with the command: "node ../server/thermo-stever.js start"

Once the server is running, you can start the tests from within the test folder with: "ruby test-thermoclient.rb"

Tests have been confirmed working on Raspberry Pi Wheezy Debian and Windows 8.

# Operation boot up
The thermoclient_controller.rb is the file you run from the command line to maintain control over your heater.
This file loads the thermostat system itself. The thermostat system (thermoclient.rb) first looks for a boot.json
file stored on the local file system in the current working folder. It MUST find that file in that folder.
From that file it determines several safety features and the URL where it can find its full configuration.
A web server must make a file of the appropriate json format available at that URL. By updating the file at that URL
you can control and change the operation the thermostat system, and thereby the heater itself.

A boot file looks like:
```json
{
  "debug": {"log_level": 0},
  "config_source": {
    "immediate_polling_seconds": 15,
    "config_url": "http://127.0.0.1:8080/now/backbedroom.json",
  },
  "operating_parameters": {
    "max_temp_f": 79,
    "max_operating_time_minutes": "59",
    "hysteresis_duration": "1 minutes"
  }
}
```

A configuration file looks like:
```json
{
  "debug": {"log_level": 9},
  "operation_mode": "daily_schedule",
  "daily_schedule": {
    "times_of_operation": [
      {"start": "12:00 am", "stop": "6:30 am", "temp_f": 60},
      {"start": "6:30 am", "stop": "10:00 am", "temp_f": 72},
      {"start": "10:00 am", "stop": "6:00 pm", "temp_f": 74},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp_f": 73},
      {"start": "11:00 pm", "stop": "12:00 am", "temp_f": 60}
  ]},
  "immediate": {"temp_f": 77, "time_stamp": "9/14/13 10:15am"},
  "off": "off"
}
```

# Operation on-going
Once thermoclient loads the URL from the specified end-point, it will process that file to determine what if any 
actions it should take. Currently three modes are supported:
* daily_schedule
* immediate
* off

## Daily Schedule
The daily schedule configuration allows you to set up a single day's temperature ranges by defining blocks of times and associated "goal" temperatures 
that you wish the thermostat system to maintain by using the heater. The thermostat system will compare the room temperature with these goal temperatures
to determine when to turn the heater on and off.
You can define an unlimited number of periods. The periods can overlap, but if they do, the *first* matching period will be in effect.
If there is a gap between periods, the heater will be off during that time frame. If a period ends with "12:00 am" it is assumed this refers to *tomorrow* at 12:00am 
(ending a period at 12:00am today makes no sense otherwise, as that is the first possible time for any given day).

### Daily Schedule: Temporary override
It is possible to cause the daily schedule to temporarily override the current goal temperature, allowing a user to set a new temperature. 
This new temperature will be in effect until the time period in which it resides within expires. After that time, the regular goal temperatures will be back
in effect. Take this configuration file for example:

```json
{
  "debug": {"log_level": 9},
  "operation_mode": "daily_schedule",
  "daily_schedule": {
    "times_of_operation": [
      {"start": "12:00 am", "stop": "6:30 am", "temp_f": 60},
      {"start": "6:30 am", "stop": "10:00 am", "temp_f": 72},
      {"start": "10:00 am", "stop": "6:00 pm", "temp_f": 65},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp_f": 73},
      {"start": "11:00 pm", "stop": "12:00 am", "temp_f": 60}
  ]},
  "immediate": {"temp_f": 77, "time_stamp": "9/14/13 10:15am"},
  "temp_override": {"time_stamp": "9/14/13 10:15am", "temp_f": 72},
  "off": "off"
}
```

Assume that the time is 9/14/13 at 10:14am. This falls in the time frame 10am-6pm. The goal temperature would be 65 degrees.
Assume that the time advances to 10:15am. This now coincides with the temp_override option. The thermostat system will use the 
goal temperature specified by "temp_override" (72 degrees) instead of the regularly scheduled temperature. This new temperature
will be in effect until the temp_override option is removed from the file, or the time advances past 6pm, when the system will
revert to normal daily schedule operations.

## Immediate
The immediate function serves to hold the temperature at a constant value for as long as the option is provided (the time_stamp on the option
must be less than the current time as well -- allowing you to set an immediate temperature for some time in the future as well). A 
config file where the immediate function is active looks like:

```json
{
  "debug": {"log_level": 9},
  "operation_mode": "immediate",
  "daily_schedule": {
    "times_of_operation": [
      {"start": "12:00 am", "stop": "6:30 am", "temp_f": 60},
      {"start": "6:30 am", "stop": "10:00 am", "temp_f": 72},
      {"start": "10:00 am", "stop": "6:00 pm", "temp_f": 65},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp_f": 73},
      {"start": "11:00 pm", "stop": "12:00 am", "temp_f": 60}
  ]},
  "immediate": {"temp_f": 74, "time_stamp": "9/14/13 10:15am"},
  "off": "off"
}
```
In this mode of operation, the thermostat system will try to maintain the temperature at 74 degrees until the operation_mode or immediate temp_f value is changed.

## Off
The off function serves to ensure the thermostat system keeps the heater off in all cases. An example of this config file is:

```json
{
  "debug": {"log_level": 9},
  "operation_mode": "off",
  "daily_schedule": {
    "times_of_operation": [
      {"start": "12:00 am", "stop": "6:30 am", "temp_f": 60},
      {"start": "6:30 am", "stop": "10:00 am", "temp_f": 72},
      {"start": "10:00 am", "stop": "6:00 pm", "temp_f": 65},
      {"start": "7:00 pm", "stop": "11:00 pm", "temp_f": 73},
      {"start": "11:00 pm", "stop": "12:00 am", "temp_f": 60}
  ]},
  "immediate": {"temp_f": 74, "time_stamp": "9/14/13 10:15am"},
  "off": "off"
}
```

When operation_mode is set to "off" the heater will never turn on.

# Safety parameters
There are three main safety parameters and they are all defined in the boot.json file. They cannot be configured by URL configuration file.
The three options are:
* Maximum operating temperature
* Maximum operating time
* Hysteresis duration

A boot.json file containing these three (required) safety options is:

```json
{
  "config_source": {
    "immediate_polling_seconds": 15,
    "config_url": "http://127.0.0.1:8080/now/backbedroom.json",
  },
  "operating_parameters": {
    "max_temp_f": 79,
    "max_operating_time_minutes": "59",
    "hysteresis_duration": "1 minutes"
  }
}
```

## Maximum operating temperature
Defines the maximum temperature possible regardless of the configuration file settings or any other operations.

## Maximum operating time
Defines the maximum period the heater is allowed to run before being shut off.

## Hysteresis duration
Defines the period of time that the heater is required to be shut off before it is allowed to be turned on again.
This prevents overly rapid cycles of the heater being turned on or off. This value should be adjusted based on the
insulation characteristics of your house. A house which is poorly insulated and cools off rapidly should probably have a lower
hysteresis duration value than a well insulated house that cools down slowly, in order to maintain a reasonable range of 
temperature in the house.


# License
(c) 2013 Steve Midgley 

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use the files in this project except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

Author's statement on warranties, conditions, guarantees or fitness of software for any purpose

No warranty is expressed or implied, per Apache license. If you use this software it is vital that you understand this.
This software could be used to control expensive heating equipment. There is no guarantee that it will function properly
for your heater, even if the tests are working and you install it correctly. It could damage your heating equipment.
It could cause the heating equipment to malfunction. It could cause damage to property, create fires, gas leaks or electrical malfunctions.
It could harm or kill humans or animals. It could do other, unknown harmful things.
I nor any contributor has any liability for what you do with this software or from the effects of operating this software.
You cannot use this software without agreeing to the Apache license which prevents you from seeking damages or other recourse
for any function or lack of function related to this software, as described above or otherwise.
