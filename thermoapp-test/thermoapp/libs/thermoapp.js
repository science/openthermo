/*
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

Methods

sendFile(filename, json)
  //post json to post file api for filename
getFile
  //download specified file using api
getListOfStatusFiles
getListOfConfigFiles
  //download list if we don't have it
  //otherwise just hand over json list


Several tasks to accomplish:
  * Server provides list of what heater status files are available
    API: 
      GET TBD
      Populate internal JSON structure with these files
  * App downloads some or all of these status files
    API: GET /api/.../file/..status file name..
    * Each heater status file should indicate what config file that thermostat is consuming
      * Each config file should be downloaded
      API: 
        Obtain config URL & file name from status file json
        GET /api/.../file/..config file name..
    * Each status file should contain user-readable name/descr of that thermostat
  * UI pull down of all heater status files by name
    API: Populate pull down from internal JSON structure
    * Selecting a status file shows operating status of that heater
    * Also provides change status ability
      * Change heater to immediate mode, set temp
      * Change heater to temp override, set temp
      * Change heater to off
      * Edit schedule file for heater (harder)
    * On change status, config file for heater should be edited with new info and uploaded to server
      * API: POST /api/.../file/..config file name..



*/

function getFile(filename, callBack, failcallBack){
  url = "/api/"+getAPIKey()+"/file/"+filename
  request = jQuery.ajax({
    url: url,
    async: false
  });
  request.done(callBack(file_contents));
  request.fail(failCallBack(file_contents));
}

function getListOfStatusFiles() {
  return getFile("status");
}

function getListOfConfigFiles() {
  return getFile("config")
}
