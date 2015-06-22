import _ from 'underscore';
import through from 'through2';
import YouAreI from 'youarei';
import select from 'html-select';
import css from 'css';
require('source-map-support').install();

var types = {
  script: 'src',
  link: 'href',
  a: 'href',
  img: 'src'
};

function remove(e) {
  var tr = through.obj(function(row, enc, next) { return next(); });
  return tr.pipe(e.createStream()).pipe(tr);
};

class Transforms {

  constructor (stream, base) {
    this.stream = stream;
    this.base = base;
    this.remove_base = select("base", remove);
  }

  relative_to_absolute(uri, selector="a") {

    return select(selector, function(e) {
      var attrName = types[e.name];
      var target = e.getAttribute(attrName);
      if (target != null ? target.match(/^\//) : void 0) {
        e.setAttribute(attrName, uri.toString());
      }
      return e;
    });
  }

  css_url_to_relative() {
    var rast = this._rewrite_ast;
    return through.obj(function(chunk, enc, cb) {
      var ast = css.parse(chunk.toString());
      rast(ast);
      var ccss = css.stringify(ast);
      this.push(ccss);
      return cb();
    });
  }

  style_blocks_to_relative() {
    var rast = this._rewrite_ast;
    return select("style", function(e) {
      var tr = through.obj( (row, buf, next) => {
        var ast, ccss;
        if (row[0] === 'text') {
          ast = css.parse(String(row[1]));
          rast(ast);
          ccss = css.stringify(ast);
          this.push([row[0], ccss]);
        } else {
          this.push(row);
        }
        return next();
      });

      return tr.pipe(e.createStream()).pipe(tr);

    });

  }

  inline_styles_to_relative() {
    var rast = this._rewrite_ast;
    return select("*[style]", () => {
      var ast, body, ccss;
      body = e.getAttribute('style');
      ast = css.parse(`fake { ${body} }`);
      rast(ast);
      ccss = css.stringify(ast).replace(/^fake \{/, '').replace(/\}$/, '');
      e.setAttribute('style', ccss);
      return e;
    });
  }

  _rewrite_ast(ast) {
    var _rewrite = this.rewrite;

    _.each(ast.stylesheet.rules, (rule) => {
      return _.each(rule.declarations, (dec) => {
        var nval = dec.value.replace(/url\((.*)\)/, function(all, m) {
          var nurl = _rewrite(m);
          if (nurl) {
            return `url(${nurl.path_to_string()})`;
          }
          return all;
        });

        if (nval) { return dec.value = nval; }
      });
    });
    return ast;
  }

  rewrite(target) {
    var remote_url;
    var request_uri = new YouAreI(this.base);

    if (target && !target.match(/data:/)) {
      if (target.match(/^https?:/)) {
        remote_url = new YouAreI(target);
      } else {
        remote_url = request_uri.clone();
        if (target.substr(0, 1) === '/') {
          remote_url.path_set(target);
        } else {
          remote_url.path_set(remote_url.path_to_string() + target);
        }
      }
      this.stream.push([remote_url.toString(), 0]);
      remote_url.path_set([remote_url.host(), remote_url.path_to_string()].join("/"));
      return remote_url;
    }
  }

  deps_to_relative(selector, request_uri) {
    var rewrite = this.rewrite.bind(this, request_uri);
    return select(selector, (e) => {
      var attrName = types[e.name.toLowerCase()];
      var target = e.getAttribute(attrName);
      var nurl = rewrite(target);
      if (nurl) {
        e.setAttribute(attrName, nurl.path_to_string());
      }
    });
  }

  toHTML() {
    return through.obj(function(row, buf, next) {
      this.push(row[1]);
      return next();
    });
  }

}

export default Transforms;
