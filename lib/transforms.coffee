_ = require 'underscore'
through = require 'through2'
YouAreI = require 'youarei'
select = require 'html-select'
css = require 'css'

types =
  script: 'src'
  link: 'href'
  a: 'href'
  img: 'src'

module.exports = class Transforms
  constructor: (@stream) ->

  #rewrite relative urls to absolutes
  relative_to_absolute: (uri, selector="a") ->
    select selector, (e) ->
      attrName = types[e.name]
      target = e.getAttribute(attrName)
      if target?.match(/^\//) #rooted
        e.setAttribute(attrName, uri.toString())
      e

  style_blocks_to_relative: (request_uri) =>
    rast = @_rewrite_ast.bind(@, @rewrite.bind(@,request_uri))
    select "style", (e) =>
      tr = through.obj (row, buf, next) ->
        if row[0] == 'text'
          ast = css.parse(String(row[1]) )
          rast(ast)
          ccss = css.stringify(ast)
          console.log ccss
          @push([ row[0], ccss ])
        else
          @push(row)
        next()

      tr.pipe(e.createStream()).pipe(tr)

  inline_styles_to_relative: (request_uri) =>
    rast = @_rewrite_ast.bind(@, @rewrite.bind(@,request_uri))

    select "*[style]", (e) =>
      body = e.getAttribute('style')
      ast = css.parse("fake { #{body} }")
      rast(ast)
      #SORRY
      ccss = css.stringify(ast).replace(/^fake \{/, '').replace(/\}$/, '')
      e.setAttribute('style', ccss)
      e

  #search ast for relative urls
  _rewrite_ast: (rewrite, ast) =>
    _.each ast.stylesheet.rules, (rule) ->
      _.each rule.declarations, (dec) ->
        console.log dec.value
        nval = dec.value.replace /url\((.*)\)/, (all, m) ->
          if nurl = rewrite(m)
            console.log "XXXX" + nurl.path_to_string()
            return "url(#{nurl.path_to_string()})"
          all
        dec.value = nval if nval
    ast

  #rewrite required resources to a local source and initiate download
  rewrite: (request_uri, target) =>
    if target?.match(/^(http:)|\//)

      if target.match(/^http:/)
        remote_url = new YouAreI(target)
      #if target.substr(0,1) == '/'
      else
        #relative to document
        remote_url = request_uri.clone()
        remote_url.path_set(target)

      @stream.push(remote_url.toString())

      remote_url.path_set( [ remote_url.host(), remote_url.path_to_string()].join("/"))
      remote_url

  deps_to_relative: (selector, request_uri) ->
    select selector, (e) =>
      attrName = types[e.name.toLowerCase()]
      target = e.getAttribute(attrName)

      #TODO: make this always download resource unless config option
      #get all relative or non-secure resources
      if target?.match(/^(http:)|\//)
        if target.match(/^http:/)
          remote_url = new YouAreI(target)
        #if target.substr(0,1) == '/'
        else
          #relative to document
          remote_url = request_uri.clone()
          remote_url.path_set(target)

        @stream.push(remote_url.toString())

        remote_url.path_set( [ remote_url.host(), remote_url.path_to_string()].join("/"))
        e.setAttribute(attrName, remote_url.path_to_string())

      e

  toHTML: ->
    through.obj (row, buf, next) ->
      @push(row[1])
      next()

