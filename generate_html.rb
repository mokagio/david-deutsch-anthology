# frozen_string_literal: true

require 'fileutils'
require 'erb'
require 'yaml'

# Load data from YAML file
data = YAML.load_file('list.yml', aliases: true)

# Extract the sections from the YAML file
books = data['books']
talks = data['talks']
podcast_interviews = data['podcast_interviews'].sort_by { |i| i['published_date'] }
other = data['other']

# Load the ERB template
template = File.read(File.join('templates', 'index.erb'))

# Bind the variables and generate the HTML
erb = ERB.new(template)
html_content = erb.result(binding)

# Save the generated HTML to a file
name = File.join('public', 'index.html')
FileUtils.mkdir_p(File.dirname(name))
File.open(name, 'w') do |file|
  file.write(html_content)
end

puts "HTML page generated successfully: #{name}"
