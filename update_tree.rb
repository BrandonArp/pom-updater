#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'nokogiri'
require 'pp'
require 'open-uri'
require 'set'

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
  attr_accessor :reverse_dependencies

  def initialize(directory, gav)
    @directory = directory
    @dependencies = []
    @reverse_dependencies = []
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

  def to_s
    version_string
  end
end

if ARGV.length == 0
  puts "ERROR: must specify workspace"
  exit 1
end 
workspace = ARGV[0]

dependency_index = {}
projects = {}
group_whitelist = Set.new(['com.arpnetworking'])

print "Looking for repos..."
entries = Dir.entries(workspace)
poms = []
for entry in entries do
  if Dir.exists?(entry)
    Dir.chdir("#{workspace}/#{entry}") do
      if Dir.exist?(".git") and File.exist?("pom.xml")
        poms << File.expand_path("pom.xml")

      end
    end
  end
end

while poms.size > 0 do
  file = poms.shift
  pom_body = IO.read(file)
  pom = Nokogiri::XML(pom_body).remove_namespaces!
  artifact_id = pom.xpath("/project/artifactId").first.text
  group_id = nil
  if pom.xpath("/project/parent").first
    parent_group = pom.xpath("/project/parent/groupId").first.text
    parent_artifact = pom.xpath("/project/parent/artifactId").first.text
    parent_version = pom.xpath("/project/parent/version").first.text
    parent_gav = GAV.new(parent_group, parent_artifact, parent_version)
  end
  if pom.xpath("/project/groupId").first
    group_id = pom.xpath("/project/groupId").first.text
  else
    group_id = parent_gav.group_id
  end
  version = nil
  if pom.xpath("/project/version").first
    version = pom.xpath("/project/version").first.text
  else
    version = parent_gav.version
  end
  properties_nodes = pom.xpath("/project/properties/*")
  properties = {}
  properties_nodes.each { |node|
    properties[node.name] = node.text
  }

  modules = pom.xpath("/project/modules//module").each { |mod|
    poms << File.dirname(file).concat("/#{mod.text}/pom.xml")
  }

  dependencies = pom.xpath("/project/dependencies//dependency")
  pom.xpath("/project/dependencyManagement//dependency").each { |node| dependencies.push(node)}

  pom_gav = GAV.new(group_id, artifact_id, version)
  project = Project.new("#{workspace}/#{entry}", pom_gav)
  projects[pom_gav.artifact_string] = project

  dependencies.each { |dep|
    dep_group_id = dep.xpath("groupId").first.text

    include = false
    dep_group_id_parts = dep_group_id.split('.')
    for x in 0..dep_group_id_parts.size - 1
      next unless group_whitelist.include? dep_group_id_parts.slice(0, x).join('.')
      include = true
    end

    next unless include

    dep_version = nil
    dep_artifact_id = dep.xpath("artifactId").first.text
    if dep.xpath("version").first
      dep_version = dep.xpath("version").first.text
    else
      dep_version = projects[parent_gav.artifact_string].dependencies.select { |d| d.group_id == dep_group_id && d.artifact_id == dep_artifact_id }.first.version
    end
    if dep_version[0] == "$" and dep_version[1] == "{" and dep_version[-1] == "}"
      dep_version = properties[dep_version[2..-2]]
    end

    dep_obj = GAV.new(dep_group_id, dep_artifact_id, dep_version)

    project.dependencies << dep_obj
  }

end

projects.each {|k, v|
  v.dependencies.each{|dep|
    puts "ERROR, could not find project #{dep.artifact_string} in projects" if projects[dep.artifact_string] == nil
    projects[dep.artifact_string].reverse_dependencies << v
  }
  # puts "k, v: #{k} ====>>>  #{v.dependencies}"
}
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
