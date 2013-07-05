var fs = require('fs');
var dbgmsg = require('util').debug;

// 0 = none, big number = output lots of stuff
var DEBUG_LEVEL = 10;

// from http://stackoverflow.com/questions/3885817/how-to-check-if-a-number-is-float-or-integer
var isInt = function (n) {
  return n===+n && n===(n|0);
}

//write debug messages to stderr using node debug log method
var debuggerMsg = function (debugMsg, level){
  // set level to 10 if not provided or is not a number
  if (!isInt(level)) {level = 10}
  //print debug message if debuggingLevel warrants it
  if (DEBUG_LEVEL >= level){
    dbgmsg(debugMsg);
  }
}

var touchFileSync = function(file){
  fs.utimesSync(file, new Date(), new Date());
}

//Copy a file from source to target
var copyFile = function(source, target, cb) {
  var cbCalled = false;

  var rd = fs.createReadStream(source);
  rd.on("error", function(err) {
    done(err);
  });
  var wr = fs.createWriteStream(target);
  wr.on("error", function(err) {
    done(err);
  });
  wr.on("close", function(ex) {
    done();
  });
  rd.pipe(wr);

  function done(err) {
    if (!cbCalled) {
      cb(err);
      cbCalled = true;
    }
  }
}

function getDateTimeStr() {

    var date = new Date();

    var hour = date.getHours();
    hour = (hour < 10 ? "0" : "") + hour;

    var min  = date.getMinutes();
    min = (min < 10 ? "0" : "") + min;

    var sec  = date.getSeconds();
    sec = (sec < 10 ? "0" : "") + sec;

    var year = date.getFullYear();

    var month = date.getMonth() + 1;
    month = (month < 10 ? "0" : "") + month;

    var day  = date.getDate();
    day = (day < 10 ? "0" : "") + day;

    return year + ":" + month + ":" + day + ":" + hour + ":" + min + ":" + sec;

}

exports.debuggerMsg = debuggerMsg;
exports.isInt = isInt;
exports.touchFileSync = touchFileSync;
exports.getDateTimeStr = getDateTimeStr;
exports.copyFile = copyFile;