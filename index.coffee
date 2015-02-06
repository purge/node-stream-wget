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
url = require 'url'
Transforms = require './lib/transforms'

class WgetError
  constructor: (@string) ->

module.exports = class Wget
  constructor: (@config) ->
    throw new WgetError("Requires target directory") unless @config.target
    @config.depth ||= 1

    @resource_stream = stream.Readable.call @, objectMode: true
    #hack for streams
    @resource_stream._read = ->
    @resource_stream.pipe(@fetchResource(5,@config.depth))

  filterList: [
    ["\/", 'html']
    ["\.html?$", 'html']
    ["\.css$", 'css']
  ]

  fetchResource: (maxConcurrency, maxDepth) =>
    _processStream = _.partial(@processStream, @fetch, maxDepth)
    through2Concurrent.obj maxConcurrency: @config.maxConcurrency, _processStream
    .on 'data', @createPath

  processStream: (fetch, maxDepth, data) ->
    return data.callback?() if data.depth > maxDepth
    stream = fetch(data.url)
    stream.on('end', data.callback) if data.callback
    @push(stream)

  generatePath: (url) =>
    #if we end in a slash, set path to index.html
    suffix = if url.path.match(/\/$/) then "index.html" else ""
    return path.join(@config.target, url.hostname, url.path, suffix)

  createPath: (data) =>
    #create relative resource
    relpath = @generatePath(data.uri)
    @mkdir path.dirname(relpath), => @applyTransforms(data, relpath)

  applyTransforms: (data, relpath) =>
    transforms = new Transforms(@resource_stream, path.dirname(relpath))
    _.each @filterList, ([re, tar]) =>
      data = @defaultTransforms[tar].call(@,transforms, data) if relpath.match(re)
    @writeFile(data, relpath)

  writeFile: (data, relpath) ->
    out = fs.createWriteStream(relpath)
    data.pipe(out)

  #gets the base resource and iterates directly related resources
  #this is the only depth zero resource
  get: (index, cb = ->) =>
    #src = url.parse(url)

    @resource_stream.push(
      url: index
      depth: 0,
      callback: cb
    )

  defaultTransforms:
    html: (tr, stream) ->
      stream
        .pipe(tokenize())
        .pipe(tr.remove_base)
        .pipe(tr.relative_to_absolute())
        .pipe(tr.deps_to_relative("script, link, img"))
        .pipe(tr.inline_styles_to_relative())
        .pipe(tr.style_blocks_to_relative())
        .pipe(tr.toHTML())

    css: (tr, stream) ->
      stream.pipe(tr.css_url_to_relative())

  fetch: (url) ->
    #TODO: don't fetch if it already exists
    request(url)

  mkdir: (tar, cb) ->
    mkdirp(tar, (err) -> cb(err, tar))

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

