#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'nokogiri'
require 'pp'
require 'open-uri'

def get_response(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  request = Net::HTTP::Get.new(uri.path)
  response = http.request(request)
end

class Project
  attr_accessor :directory
  attr_accessor :dependencies
  attr_accessor :gav
  attr_accessor :latest_version
  attr_accessor :up_to_date

  def initialize(directory, gav)
    @directory = directory
    @dependencies = []
    @gav = gav
    @latest_version = nil
    @up_to_date = false
  end
end

class GAV
  attr_reader :group_id
  attr_reader :artifact_id
  attr_reader :version

  def initialize(group, artifact, version)
    @group_id = group
    @artifact_id = artifact
    @version = version
  end

  def version_string
    "#{@group_id}:#{@artifact_id}:#{@version}"
  end

  def artifact_string
    "#{@group_id}:#{@artifact_id}"
  end

  def central_location_artifact
    "https://repo.maven.apache.org/maven2/#{dot_to_slash(@group_id)}/#{dot_to_slash(@artifact_id)}"
  end

  def dot_to_slash(str)
    str.gsub('.', '/')
  end
end

if ARGV.length == 0
  puts "ERROR: must specify workspace"
  exit 1
end 
workspace = ARGV[0]

dependency_index = {}
projects = {}

print "Looking for repos..."
entries = Dir.entries(workspace)
for entry in entries do
  if Dir.exists?(entry)
    Dir.chdir("#{workspace}/#{entry}") do
      if Dir.exist?(".git") and File.exist?("pom.xml")
        #puts "found git repo with maven project #{entry}" 

        pom_body = IO.read("pom.xml")
        pom = Nokogiri::XML(pom_body).remove_namespaces!
        group_id = pom.xpath("/project/groupId").first.text
        artifact_id = pom.xpath("/project/artifactId").first.text
        version = pom.xpath("/project/version").first.text
        properties_nodes = pom.xpath("/project/properties/*")
        properties = {}
        properties_nodes.each { |node|
          properties[node.name] = node.text
        }
        dependencies = pom.xpath("/project/dependencies//dependency")
        pom_gav = GAV.new(group_id, artifact_id, version)
        project = Project.new("#{workspace}/#{entry}", pom_gav)
        projects[pom_gav.artifact_string] = project
        
        dependencies.each { |dep|
          dep_group_id = dep.xpath("groupId").first.text
          dep_artifact_id = dep.xpath("artifactId").first.text
          dep_version = dep.xpath("version").first.text
          if dep_version[0] == "$" and dep_version[1] == "{" and dep_version[-1] == "}"
            dep_version = properties[dep_version[2..-2]]
          end

          dep_obj = GAV.new(dep_group_id, dep_artifact_id, dep_version)

          project.dependencies << dep_obj
          #pp dep_artifact_version
        }
      end
    end
  end
end
puts " done."
print "Looking up latest versions in central..."

#filter the dependencies to just the workspace projects
for artifact,project in projects do
  project.dependencies.reject! { |d| projects[d.artifact_string].nil? }

  project.dependencies.each { |d| 
    arr = dependency_index[d.artifact_string()] || []
    arr << project
    dependency_index[d.artifact_string()] = arr
  }

  begin
    url = "#{project.gav.central_location_artifact}/maven-metadata.xml"
    versions = Nokogiri::XML(open(url)).remove_namespaces!
    latest = versions.xpath("/metadata/versioning/latest").first.text
    project.latest_version = latest
  rescue OpenURI::HTTPError => e
    next if e.io.status[0] == "404" 
    pp e
  end
end

puts " done."

#pp projects

#response = get_response("https://api.github.com/orgs/arpnetworking/repos")
#if response.code == "200" then
#  resp = JSON.parse(response.body)
#  for repo in resp do
#    name = repo['name']
#    if not Dir.exists?(repo['name'])
#      puts "Cloning #{repo['name']}..."
#      `git clone #{repo['ssh_url']}`
#      puts "done"
#    else
#      Dir.chdir(name) do
#        `git fetch > /dev/null 2>&1`
#      end
#    end
#    print ' ' if count > 0
#    print repo['name']
#    count = count + 1
#    #for key, value in repo do
#    #  puts "#{key} => #{value}"
#    #end
#  end
#  puts ''
#end
