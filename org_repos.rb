#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'nokogiri'

def get_response(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  request = Net::HTTP::Get.new(uri.path)
  response = http.request(request)
end

count = 0
response = get_response("https://api.github.com/orgs/arpnetworking/repos")
if response.code == "200" then
  resp = JSON.parse(response.body)
  for repo in resp do
    name = repo['name']
    if not Dir.exists?(repo['name'])
      puts "Cloning #{repo['name']}..."
      `git clone #{repo['ssh_url']}`
      puts "done"
    else
      Dir.chdir(name) do
        `git fetch > /dev/null 2>&1`
      end
    end
    print ' ' if count > 0
    print repo['name']
    count = count + 1
    #for key, value in repo do
    #  puts "#{key} => #{value}"
    #end
  end
  puts ''
end
