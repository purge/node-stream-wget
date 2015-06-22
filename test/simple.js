var nstatic = require('node-static');
var test = require('tape');
var Wget = require('../index');
var sinon = require('sinon');
require('source-map-support').install();

var base = __dirname + "/.temp"
var file = new nstatic.Server('./test/fixtures');
var wget = new Wget({ target: base, maxConcurrency: 1 })

console.log(base);
var port = 29999;

var server = require('http').createServer((request, response) => {

  request.addListener('end', () => {
    file.serve(request, response);
  }).resume();

}).listen( port, () => {

  test('fetched the right files', (t) => {
    t.plan(1);
    var fetchSpy = sinon.spy(wget, "processStream");
    var mkdirSpy = sinon.spy(wget, "mkdir");
    var res = wget.get("http://localhost:" + port, () => {
      console.warn(fetchSpy.args);
      console.warn(mkdirSpy.args);
      t.ok(fetchSpy.callCount, 1);
      server.close();
    });
  });

});


