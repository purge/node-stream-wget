import _ from 'underscore';
import tokenize from 'html-tokenize';
import mkdirp from 'mkdirp';
import phantom from 'phantom';
import stream from 'stream';
import fs from 'fs';
import request from 'request';
import through2Concurrent from 'through2-concurrent';
import path from 'path';
import url from 'url';
require('source-map-support').install();

import Transforms from './lib/transforms';

class Wget {

  constructor (config) {
    this.config = config;

    if(!config.target) {
      throw Error("Requires target directory");
    }

    config.depth = config.depth || 1
    this.resource_stream = stream.Readable.call(this, {
      objectMode: true
    });

    //hack for streams
    this.resource_stream._read = function() {};
    this.resource_stream.pipe(this.fetchResource(5, config.depth));
    this.filterList = [["\/", 'html'], ["\.html?$", 'html'], ["\.css$", 'css']];
  }

  fetchResource(maxConcurrency, maxDepth) {
    var _processStream = _.partial(this.processStream, this.fetch, maxDepth);
    return through2Concurrent.obj({
      maxConcurrency: this.config.maxConcurrency
    }, _processStream).on('data', this.createPath.bind(this));
  }

  processStream(fetch, maxDepth, data) {
    if (data.depth > maxDepth && data.callback) {
      return data.callback();
    }

    var stream = fetch(data.url);
    if (data.callback) { stream.on('end', data.callback); }
    return this.push(stream);
  }

  generatePath(url) {
    var suffix = url.path.match(/\/$/) ? "index.html" : "";
    return path.join(this.config.target, url.hostname, url.path, suffix);
  }

  createPath(data) {
    var relpath = this.generatePath(data.uri);

    return this.mkdir(path.dirname(relpath), () => {
      return this.applyTransforms(data, relpath);
    });
  }

  applyTransforms(data, relpath) {
    var transforms = new Transforms(this.resource_stream, path.dirname(relpath));

    _.each(this.filterList, ([re, tar]) => {
      if (relpath.match(re)) {
        return data = this.defaultTransforms()[tar].call(this, transforms, data);
      }
    });
    this.writeFile(data, relpath);
  }

  writeFile(data, relpath) {
    var out = fs.createWriteStream(relpath);
    return data.pipe(out);
  }

  get(index, cb) {
    return this.resource_stream.push({
      url: index,
      depth: 0,
      callback: cb
    });
  }

  defaultTransforms() {
    return {
      html: (tr, stream) => {
        return stream.pipe(
          tokenize())
          .pipe(tr.remove_base)
          .pipe(tr.relative_to_absolute())
          .pipe(tr.deps_to_relative("script, link, img"))
          .pipe(tr.inline_styles_to_relative())
          .pipe(tr.style_blocks_to_relative())
          .pipe(tr.toHTML());
      },
      css: (tr, stream) => {
        return stream.pipe(tr.css_url_to_relative());
      }

    };
  }

  fetch(url) { return request(url); }

  mkdir(tar, cb) {
    return mkdirp(tar, function(err) { return cb(err, tar); });
  }
}

export default Wget;
