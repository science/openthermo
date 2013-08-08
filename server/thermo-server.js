/*
Thermo-server's job is to:

1) Serve configuration files on its file system and optionally when they change to make them available to the HTTP client requesting them

API

/wait/file-name..
/now/file-name..

If HTTP client calls /wait, the file time is checked immediately and then if it changes, the file is sent to the HTTP client and the connection is closed
If HTTP client calls /now, the file is sent immediately

2) Allow authorized clients to update configuration files (to permit mobile updates)
   Possibly this will be implemented with FTP updates in the short term?

Node.js installation requirements
  restify
  semaphore
  nodeunit

*/

// includes
var restify = require('restify');
var fs = require('fs');
var util = require('util');
var StringDecoder = require('string_decoder').StringDecoder;
var dbg = require('./utils').debuggerMsg;
var getDateTimeStr = require('./utils').getDateTimeStr;

// constants
var FILE_WATCH_TIMEOUT_MSEC = 12*60*60*1000 // each file watch process should wait no longer than 12 hours before giving up and returning nothing
var HTTP_KEEP_ALIVE_TIMEOUT_MSEC = 4 * 1000 //

// global files
// Holds semaphore locks for each file being watched
var files = {};
var server = restify.createServer();


// Pass the file contents back to response object
//   Since this function gets called for *every* change event we have
//   to be careful we only act on change events where the file has content
//   For example, an edit event might be represented by the OS as a delete/create
//   In this case, we'll get two "change" events, but one will have the file at 0 bytes and the other will have it filled with content
var getFileOnChange = function (event,filename){
  if (filename && fs.existsSync(filename)) {
    var fileInfo = fs.statSync(filename);
    if (fileInfo.size > 0) {
      // We have determined we are processing a file with content (as opposed to a delete operation during an update).
      // So we invoke the semaphore we created earlier so we are the only change event
      // that is processing the file contents for this response object
      var semaphore = files[filename].lock;
      semaphore.take(function() {
        // get file contents
        var data = fs.readFileSync(filename, {"encoding":"utf8"});
        var response = files[filename].res;
        dbg(getDateTimeStr()+' File: '+filename);
        response.write(data);
        response.end();
      });
    }
  }
}

// don't call watch file without creating an JSON struct in var files for filename
// e.g. files['myfile.txt'] = {}
function watchFile(filename, req, res, next) {
  dbg('watchFile');
  files[filename] = {};
  files[filename].res = res;
  files[filename].req = req;
  files[filename].lock = require('semaphore')(1);
  fs.watch(filename, getFileOnChange);
}

// kicks off long running process to watch for file changes
// and return file contents to waiting HTTP client when change is detected
function watchFileResponse(req, res, next) {
  res.setTimeout(FILE_WATCH_TIMEOUT_MSEC);
  res.on('close', function(){dbg('unexpected close');});

  filename = req.params.name;
  dbg('watchFileResponse: '+ filename);
  if (filename && fs.existsSync(filename)) {
    dbg('Watching file: '+filename);
    watchFile(filename, req, res, next);
  }
  else {
    dbg('Watch file not found:' + filename||'[undefined]');
    res.statusCode = 404;
    //response.send('{"code": "FileNotFound", "message":"File specified could not be found"}');
    res.end();
  }
}

//simple return function - immediately return contents of file requested
function getFileResponse(req, res, next) {
  res.on('close', function(){dbg('unexpected close');});
  filename = req.params.name;
  if (filename && fs.existsSync(filename)) {
    fileInfo = fs.statSync(filename)
    dbg("File mtime: "+fileInfo.mtime);
    var data = fs.readFileSync(filename, {"encoding":"utf8"});
    dbg(getDateTimeStr()+' - Returning file: '+filename);
    res.write(data);
    res.end();
  }
  else {
    dbg('Get file not found:' + filename||'[undefined]');
    res.statusCode = 404;
    //response.send('{"code": "FileNotFound", "message":"File specified could not be found"}');
    res.end();
  }
}


var startServer = function (callBack) {
  // this line is a restify docs-provided hack to support curl as a client
  server.pre(restify.pre.userAgentConnection());
  server.get('/watchfile/:name', watchFileResponse);
  server.head('/watchfile/:name', watchFileResponse);
  server.get('/now/:name', getFileResponse)
  server.head('/now/:name', getFileResponse)

  server.listen(8080, function() {
    console.log('%s listening at %s', server.name, server.url);
    console.log('Current working directory is %s', process.cwd());
    if (typeof process.send == 'function'){process.send('started');};
    if (typeof callBack == 'function'){callBack();};
  });
  //Set the keep-alive timeout for all connections
  server.addListener("connection",function(stream) {
      stream.setTimeout(HTTP_KEEP_ALIVE_TIMEOUT_MSEC);
  });
}

var stopServer = function (callBack){
  console.log('Shutdown starting: %s listening at %s', server.name, server.url);
  server.on('close', function() {
    console.log('Shutdown complete for server %s', server.name)
    if (typeof process.send == 'function'){process.send('stopped');};
    if (typeof callBack == 'function'){callBack();};
  });
  server.close();
  //wait 1 sec longer than http keep-alive timeout and then force exit from process
  setTimeout(function(){dbg('Server failed to shutdown. Terminating process.');process.exit();},HTTP_KEEP_ALIVE_TIMEOUT_MSEC+1000);
}

// dispatch child_process incoming messages
process.on('message', function(msg){
  if (msg == 'start'){
    dbg('start');
    startServer();
  }
  else if (msg == 'stop'){
    stopServer();
  }
  else {
    dbg('Unknown message received: '+util.inspect(msg))
  };
});

if (process.argv[2]=='start'){startServer()};

exports.start = startServer;
exports.stop = stopServer;

