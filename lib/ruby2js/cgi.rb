# Example usage:
#
#   hello.cgi:
#
#     require 'ruby2js/cgi'
#     __END__
#     alert 'Hello World!'
#
# Using an optional filter:
#
#   require 'ruby2js/filter/functions'

require 'ruby2js'

at_exit do
  status = 200
  headers = []

  begin
    require 'time'
    modtime = File.stat($0).mtime.rfc2822
    headers << "Last-Modified: #{modtime}\r\n"
    status = 304 if ENV['HTTP_IF_MODIFIED_SINCE'] == modtime
  rescue
  end

  if status == 200
    require 'digest/md5'
    js = Ruby2JS.convert(DATA.read)
    etag = Digest::MD5.hexdigest(js).inspect
    headers << "Etag: #{etag}\r\n"
    status = 304 if ENV['HTTP_IF_NONE_MATCH'] == etag
  end

  if status == 200
    print "#{headers.join}\r\n#{js}"
  else
    print "Status: 304 Not Modified\r\n\r\n"
  end
end
