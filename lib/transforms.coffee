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

remove = (e) ->
  tr = through.obj (row, enc, next) -> next()
  tr.pipe(e.createStream()).pipe(tr)

module.exports = class Transforms
  constructor: (@stream, @base) ->

  remove_base: select "base", remove

  #rewrite relative urls to absolutes
  relative_to_absolute: (uri, selector="a") ->
    select selector, (e) ->
      attrName = types[e.name]
      target = e.getAttribute(attrName)
      if target?.match(/^\//) #rooted
        e.setAttribute(attrName, uri.toString())
      e

  css_url_to_relative: =>
    rast = @_rewrite_ast
    through.obj (chunk, enc, cb) ->
      ast = css.parse(chunk.toString())
      rast(ast)
      ccss = css.stringify(ast)
      @push(ccss)
      cb()

  style_blocks_to_relative: =>
    rast = @_rewrite_ast
    select "style", (e) =>
      tr = through.obj (row, buf, next) ->
        if row[0] == 'text'
          ast = css.parse(String(row[1]) )
          rast(ast)
          ccss = css.stringify(ast)
          @push([ row[0], ccss ])
        else
          @push(row)
        next()

      tr.pipe(e.createStream()).pipe(tr)

  inline_styles_to_relative: =>
    rast = @_rewrite_ast

    select "*[style]", (e) =>
      body = e.getAttribute('style')
      ast = css.parse("fake { #{body} }")
      rast(ast)
      #SORRY
      ccss = css.stringify(ast).replace(/^fake \{/, '').replace(/\}$/, '')
      e.setAttribute('style', ccss)
      e

  #search ast for relative urls
  _rewrite_ast: (ast) =>
    _rewrite = @rewrite
    _.each ast.stylesheet.rules, (rule) ->
      _.each rule.declarations, (dec) ->
        nval = dec.value?.replace /url\((.*)\)/, (all, m) ->
          if nurl = _rewrite(m)
            return "url(#{nurl.path_to_string()})"
          all
        dec.value = nval if nval
    ast

  #rewrite required resources to a local source and initiate download
  rewrite: (target) =>
    request_uri = new YouAreI(@base)
    if target and !target.match(/data:/)

      if target.match(/^https?:/)
        remote_url = new YouAreI(target)
      else
        remote_url = request_uri.clone()
        if target.substr(0,1) == '/'
          remote_url.path_set(target)
        else
          remote_url.path_set(remote_url.path_to_string() + target)

      #console.warn "adding #{remote_url.toString()}"
      @stream.push([remote_url.toString(), 0])

      remote_url.path_set( [ remote_url.host(), remote_url.path_to_string()].join("/"))
      remote_url

  deps_to_relative: (selector, request_uri) ->
    rewrite =  @rewrite.bind(@,request_uri)

    select selector, (e) =>
      attrName = types[e.name.toLowerCase()]
      target = e.getAttribute(attrName)
      if nurl = rewrite(target)
        e.setAttribute(attrName, nurl.path_to_string())
      e

  toHTML: ->
    through.obj (row, buf, next) ->
      @push(row[1])
      next()

