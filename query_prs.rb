#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'optparse'

class GitHubPRChecker
  def initialize(github_token = nil)
    @github_token = github_token || ENV['GITHUB_TOKEN']
    @base_url = 'https://api.github.com'
  end

  def query_pull_requests(repo_owner, repo_name, username)
    uri = URI("#{@base_url}/repos/#{repo_owner}/#{repo_name}/pulls")
    uri.query = URI.encode_www_form({
      state: 'open',
      sort: 'created',
      direction: 'desc'
    })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/vnd.github.v3+json'
    request['User-Agent'] = 'GitHub-PR-Checker'
    request['Authorization'] = "token #{@github_token}" if @github_token

    begin
      response = http.request(request)
      
      if response.code == '200'
        pulls = JSON.parse(response.body)
        user_pulls = pulls.select { |pr| pr['user']['login'].downcase == username.downcase }
        return user_pulls
      else
        puts "Error querying #{repo_owner}/#{repo_name}: #{response.code} - #{response.message}"
        return []
      end
    rescue => e
      puts "Error accessing #{repo_owner}/#{repo_name}: #{e.message}"
      return []
    end
  end

  def extract_repo_info(repo_url)
    # Extract owner and repo name from GitHub URL
    match = repo_url.match(%r{github\.com/([^/]+)/([^/]+)})
    return nil unless match
    
    [match[1], match[2]]
  end

  def run(json_file, username)
    unless File.exist?(json_file)
      puts "Error: JSON file '#{json_file}' not found"
      exit 1
    end

    begin
      data = JSON.parse(File.read(json_file))
      repositories = data['repositories']
    rescue JSON::ParserError => e
      puts "Error parsing JSON file: #{e.message}"
      exit 1
    end

    puts "Checking for open pull requests by user: #{username}"
    puts "=" * 60

    total_prs = 0

    repositories.each do |repo|
      repo_info = extract_repo_info(repo['url'])
      next unless repo_info

      owner, name = repo_info
      puts "\nChecking #{owner}/#{name}..."
      
      user_prs = query_pull_requests(owner, name, username)
      
      if user_prs.empty?
        puts "  No open PRs found for #{username}"
      else
        puts "  Found #{user_prs.length} open PR(s) for #{username}:"
        user_prs.each do |pr|
          puts "    • ##{pr['number']}: #{pr['title']}"
          puts "      Created: #{pr['created_at']}"
          puts "      URL: #{pr['html_url']}"
        end
        total_prs += user_prs.length
      end
    end

    puts "\n" + "=" * 60
    puts "Summary: Found #{total_prs} total open pull requests for #{username}"
  end
end

# Command line argument parsing
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] <username>"

  opts.on("-f", "--file FILE", "JSON file path (default: my-github-repos.json)") do |file|
    options[:file] = file
  end

  opts.on("-t", "--token TOKEN", "GitHub personal access token") do |token|
    options[:token] = token
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

if ARGV.length != 1
  puts "Error: Please provide a GitHub username"
  puts "Usage: #{$0} [options] <username>"
  exit 1
end

username = ARGV[0]
json_file = options[:file] || 'my-github-repos.json'

checker = GitHubPRChecker.new(options[:token])
checker.run(json_file, username)
