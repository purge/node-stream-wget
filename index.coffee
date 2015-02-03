_ = require 'underscore'
YouAreI = require 'youarei'
#select = require 'html-select'
tokenize = require 'html-tokenize'
mkdirp = require 'mkdirp'
phantom = require 'phantom'
stream = require 'stream'
fs = require 'fs'
request = require 'request'
stream = require 'stream'
through2Concurrent = require 'through2-concurrent'
path = require 'path'
Transforms = require './lib/transforms'

class WgetError
  constructor: (@string) ->

module.exports = class Wget
  constructor: (@config) ->
    resource_stream = stream.Readable()
    resource_stream._read = ->
    @downloader = @fetchResource(@concurrent || 5)
    resource_stream.pipe(@downloader)
    @transforms = new Transforms(resource_stream)
    throw new WgetError("Requires target directory") unless @config.target

  fetchResource: (maxConcurrency) =>
    _fetch = @fetch
    through2Concurrent.obj maxConcurrency: maxConcurrency, (chunk, enc, cb) ->
      @push(_fetch(String(chunk)))

    .on 'data', (data) =>
      #create relative resource
      relpath = path.join(@config.target, data.uri.hostname, data.uri.path)
      #TODO: if the relpath is stylesheet we need to rewrite that too
      @mkdir path.dirname(relpath),  ->
        out = fs.createWriteStream(relpath)
        data.pipe(out)

  get: (url, isIndex) =>
    youarei = new YouAreI(url)
    stream = @fetch(url)

    @mkdir @config.target, (err, target) =>
      #download the target and parse.
      out = fs.createWriteStream(target + '/index.html')
      stream
        .pipe(tokenize())
        .pipe(@transforms.relative_to_absolute(youarei))
        .pipe(@transforms.deps_to_relative("script, link, img", youarei))
        .pipe(@transforms.inline_styles_to_relative(youarei))
        .pipe(@transforms.style_blocks_to_relative(youarei))
        .pipe(@transforms.toHTML())
        .pipe(out)
    stream

  fetch: (url) ->
    console.log "fetching #{url}"
    request(url)

  mkdir: (tar, cb) ->
    mkdirp tar, (err) -> cb(err, tar)

#phantom.create (ph) ->
  #ph.createPage (page) ->
    #page.set 'onResourceReceived', (data, net) ->
      ##save content
      #console.log data
      ##console.log net
      #true

    #page.open url.toString(), (status) ->
      #return cb(status) if status != 'success'
      #page.get 'content', (content) ->
        #rewrite_html(content)
        #ph.exit()

