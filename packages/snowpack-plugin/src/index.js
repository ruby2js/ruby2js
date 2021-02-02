//
// A bit of explanation of the approach is in order.  While it certainly is
// possible to shell out a new command every time Snowpack has a file to
// process, the reason people pick Snowpack is speed, and it may take
// literally hundreds of milliseconds even on a relatively fast processor to
// start up the Ruby2JS script (which includes the whitequark parser), and
// that adds up quickly.
//
// The approach taken here is to start a long running HTTP server process that
// takes requests in the form of JSON and produces text/plain responses.  Even
// if that takes a half a second or more to start up, that is only only done
// once, and once that is done, requests can be processed in milliseconds.
//
// The downside of this approach is that there are more moving parts that need
// to be in sync.  The Ruby server could be included in the ruby2js gem and
// the client could be a separate npm module, but that would require
// coordination and installation and running of matching versions to work.
// The alternative adopted here is that the Ruby server is included, inline,
// here in this script as a string.
//
// Continuing with this approach, every attempt is made to minimize
// dependencies, coming as close as possible to a single file deployment.
// Notably, the relevant portions of the get-port module is inlined, and HTTP
// requests are made using the relatively low-level http support provided by
// Node rather than use a higher level interface.  This may be relaxed a bit
// later when this code is released on npm.
//
// So the dependencies needed to run this code:
//   * Node.js and Snowpack
//   * Ruby installed and available in your PATH as `ruby`
//   * Both ruby2js and rack, either installed as gems or in your RUBYLIB path
//
// The next biggest challenge is converting pluginOptions which is sent from
// the JavaScript client to the Ruby server as JSON to a Ruby2JS options hash.
//
// 

const fsp = require('fs').promises;
const path = require('path');
const child_process = require('child_process');
const net = require('net');
const http = require('http');

let port = 0;

// from https://www.npmjs.com/package/get-port
const getAvailablePort = options => new Promise((resolve, reject) => {
  const server = net.createServer();
  server.unref();
  server.on('error', reject);
  server.listen(options, () => {
    const {port} = server.address();
    server.close(() => { resolve(port) });
  });
});


const startServer = async () => {
  port = await getAvailablePort({port: 0});

  const server = `
    require 'rack'
    require 'ruby2js'
    require 'json'

    # require all built-in filters
    mod = Ruby2JS::Filter
    method = mod.instance_method(mod.instance_methods.first)
    filters = Dir[File.expand_path('../filter/*.rb', method.source_location.first)]
    filters.each {|filter| require filter}

    # construct a map of filter names to module names
    filters = {}
    Ruby2JS::Filter::DEFAULTS.each do |mod|
      method = mod.instance_method(mod.instance_methods.first)
      name = method.source_location.first
      filters[File.basename(name, '.rb')] = mod
    end

    # certain option values will need symbolizing, the following template
    # indicates which ones are affected
    template = {
      autoimports: {%i[] => nil},
      comparison: %s{},
      defs: {nil => %i[]},
      exclude: %i[],
      include: %i[],
      include_only: %i[],
      or: %s{},
      template_literal_tags: %i{},
    }

    # process requests
    textPlain = {'Content-Type' => 'text/plain'}
    app = lambda do |env|
      req = Rack::Request.new(env)
      opts = JSON.parse(req.body.read, symbolize_names: true)
      ruby = opts.delete(:ruby) || ''

      # symbolize option values, as required
      opts = opts.map {|key, value|
        pattern = template[key]
        if pattern
          if pattern == %s{} and value.is_a? String
            value = value.to_sym
          elsif pattern.is_a? Array and value.is_a? Array
            value = value.map(&:to_sym)
          elsif pattern.is_a? Hash and value.is_a? Hash
            if pattern.keys.first == %i[]
              value = value.map {|key, value|
                if key =~ /\\A\\[.*\\]\\z/
                  key = key.to_s[2..-2].gsub(':', '').split(/,\\s*/).map(&:to_sym)
                end
                [key, value]
              }.to_h
            end

            if pattern.values.first == %i[]
              value = value.map {|key, value|
                value = value.map(&:to_sym) if value.is_a? Array
                [key, value]
              }.to_h
            end
          end
        end

        [key, value]
      }.to_h

      # map filter names to module names
      opts[:filters] ||= []
      opts[:filters].map! {|filter| filters[filter]}
      opts[:filters].compact!

      [200, textPlain, [Ruby2JS.convert(ruby, opts).to_s]]
    end

    # start server
    server = Rack::Server.start app: app, Port: ${port}
  `;

  // Start server redirecting stdin and stdout to /dev/null, and inheriting
  // stderr from the parent process.  This avoids cluttering the snowpack dev
  // console window, while enabling actual errors to show through.
  let child = child_process.spawn('ruby', ['-e', server],
    { stdio: ['ignore', 'ignore', 'inherit'] })

  // on exit, shutdown server too
  process.on('exit', () => child.kill('SIGINT'))
};

// async RPC version of Ruby2JS
convert = (ruby, options) => new Promise((resolve, reject) => { 
  const data = JSON.stringify({ ...options, ruby });

  const httpOptions = {
    port,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length
    }
  };

  const req = http.request(httpOptions, response => {
    let result = [];
    response.on('data', d => result.push(d));
    response.on('end', () => resolve(result.join()));
  });

  req.on('error', reject);
  req.write(data);
  req.end();
});

// wait for server to start, or raise an exception
waitForServer = limit => new Promise((resolve, reject) => { 
  if (!firstRequest) return true;

  testServer = async limit => {
    try {
      if (port) return resolve(await convert('', {}));
    } catch(error) {
      limit -= 100;
      if (limit <= 0 || error.code !== 'ECONNREFUSED') return reject(error);
    }
    setTimeout(() => testServer(limit), 100);
  };

  return testServer(limit);
});

// start the server, track first request
startServer().catch(console.error);
let firstRequest = true;

module.exports = function (snowpackConfig, pluginOptions) {
  return {
    name: 'ruby2js-plugin',

    resolve: {
      input: ['.js.rb', '.rb'],
      output: ['.js'],
    },

    async load({ filePath }) {
      if (firstRequest) await waitForServer(5000);
      firstRequest = false;
      return await convert(await fsp.readFile(filePath, 'utf8'), pluginOptions);
    },
  };
};
