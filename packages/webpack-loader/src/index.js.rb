import [ spawn ], from: "child_process"
import [ get_options ], from: "loader-utils"

def should_provide_source_maps(loader)
  if loader.source_map
    get_options(loader)[:provide_source_maps].yield_self do |provide_source_maps|
      provide_source_maps.nil? ? true : provide_source_maps
    end
  else
    false
  end
end

def determine_loader_cmd(source_maps)
  source_maps ? "process_with_source_map" : "process"
end

def spawn_ruby2js(loader_cmd)
  spawn 'bundle', ['exec', 'ruby', '-e require "./rb2js.config.rb"; puts Ruby2JS::Loader.' + loader_cmd + '(ARGF.read)']
end

export default def loader(source)
  callback = self.async()
  provide_source_maps = should_provide_source_maps? self
  loader_cmd = determine_loader_cmd provide_source_maps
  result = ""
  error_response = ""

  rb2js = spawn_ruby2js loader_cmd

  rb2js.stdout.on "data" do |data|
    result += data.to_s
  end

  rb2js.stderr.on "data" do |data|
    error_response += data.to_s
  end

  rb2js.on "close" do
    if result.length > 0
      if provide_source_maps
        parsed_output = JSON.parse result
        parsed_output[:source_map][:file] = self.resource_path
        parsed_output[:source_map][:sources] = [self.resource_path]
        parsed_output[:source_map][:sourcesContent] = [source]

        callback nil, parsed_output.code, parsed_output.source_map
      else
        callback nil, result
      end
    else
      callback Error.new(
        error_response.length > 0 ? error_response : "Empty response received by Ruby2JS"
      )
    end
  end

  rb2js.stdin.write source
  rb2js.stdin.end()

  return
end
