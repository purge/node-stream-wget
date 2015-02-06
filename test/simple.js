require('coffee-script/register');

var static = require('node-static');
var test = require('tape');
var Wget = require('../index');
var sinon = require('sinon');

var base = __dirname + "/.temp"
var file = new static.Server('./test/fixtures');
var wget = new Wget({ target: base, maxConcurrency: 1 })

console.log(base);
var port = 29999;

server = require('http').createServer(function (request, response) {

  request.addListener('end', function () {
    file.serve(request, response);
  }).resume();

}).listen( port, function() {

  test('fetched the right files', function (t) {
    t.plan(1);
    var fetchSpy = sinon.spy(wget, "processStream");
    var mkdirSpy = sinon.spy(wget, "mkdir");
    var res = wget.get("http://localhost:" + port, function() {
      console.warn(fetchSpy.args);
      console.warn(mkdirSpy.args);
      t.ok(fetchSpy.callCount, 1);
      server.close();
    });
  });

});


