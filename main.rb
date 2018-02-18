require 'rubyserial'
require 'graphql/client'
require 'graphql/client/http'
require 'open-uri'
require 'dotenv/load'
require 'json'

# Ensure the required environment variables have been set
unless ENV['GITHUB_TOKEN']
  puts 'The GITHUB_TOKEN environment variable must be set.'
  puts 'Ex: GITHUB_TOKEN=<your token> PORT=/dev/tty.usbmodemHIDP1 bundle exec ruby main.rb'
  exit
end
GITHUB_TOKEN = ENV['GITHUB_TOKEN']

unless ENV['SERIALPORT']
  puts 'The SERIALPORT environment variable must be set.'
  puts 'Ex: SERIALPORT=/dev/tty.usbmodemHIDP1 GITHUB_TOKEN=<your token> bundle exec ruby main.rb'
  exit
end
PORT = ENV['SERIALPORT']

LED_COUNT = 24
GITHUB_ENDPOINT = 'https://api.github.com/graphql'.freeze
HTTPAdapter = GraphQL::Client::HTTP.new(GITHUB_ENDPOINT) do
  def headers(_context)
    {
      'Authorization' => "Bearer #{GITHUB_TOKEN}"
    }
  end
end
STATE_COLORS = {
  'EXPECTED' =>    { hue: 120, sat: 255, val: 50 },
  'ERROR' =>       { hue: 120, sat: 255, val: 50 },
  'FAILURE' =>     { hue: 120, sat: 255, val: 50 },
  'PENDING' =>     { hue: 100, sat:   0, val: 21 },
  'MERGEABLE' =>   { hue:   0, sat: 255, val: 50 },
  'SUCCESS' =>     { hue:   0, sat: 255, val: 50 },
  'CONFLICTING' => { hue: 100, sat: 200, val: 50 },
  'NONE' =>        { hue:   0, sat: 255, val: 50 }, # no ci configured, but mergeable
  nil =>           { hue:   0, sat:   0, val:  0 }
}.freeze

Client = GraphQL::Client.new(
  schema: 'schema.json',
  execute: HTTPAdapter
)

PullRequestsQuery = Client.parse <<-'GRAPHQL'
query($owner:String!, $repo:String!, $pr_count:Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequests(first: $pr_count, states: OPEN, orderBy:{ field: CREATED_AT, direction: ASC}) {
      nodes {
        title
        mergeable
        commits(last: 1) {
          nodes {
            commit {
              status {
                state
              }
            }
          }
        }
      }
    }
  }
}
GRAPHQL

def repositories
  path = if ENV['REPOSITORY_CONFIG'] && File.exist?(ENV['REPOSITORY_CONFIG'])
           ENV['REPOSITORY_CONFIG']
         else
           File.join(__dir__, 'repositories.json')
         end

  JSON.parse(File.read(path))
rescue
  []
end

def prs_for(owner:, repo:, count:)
  variables = {
    owner: owner,
    repo: repo,
    pr_count: count
  }
  result = Client.query(PullRequestsQuery, variables: variables)
  result.data.repository.pull_requests.nodes.map { |pr| clean_up_pr(pr) }
rescue Net::OpenTimeout => e
  []
end

def clean_up_pr(pr_data)
  # possible states: EXPECTED, ERROR, FAILURE, PENDING, SUCCESS
  state = pr_data.commits.nodes.first.commit.status&.state || 'NONE'
  # possible values: MERGEABLE, CONFLICTING
  mergeable = pr_data.mergeable

  {
    title: pr_data.title,
    mergeable: mergeable,
    state: state,
    combined_state: mergeable == 'CONFLICTING' ? mergeable : state
  }
end

def update_led(serialport, led_index, color)
  data = [
    led_index,
    color[:hue],
    color[:sat],
    color[:val]
  ].map { |i| i % 256 }.pack('CCCC')

  serialport.write(data)
end

def status_loop
  serialport = Serial.new(PORT)
  loop do
    repos = repositories
    puts "repos to fetch: #{repos.count}"
    pr_lists = repos.map { |r|
      prs_for(owner: r['owner'], repo: r['name'], count: LED_COUNT / repos.count)
    }.map { |pr_list| pr_list.each_with_index }

    puts "received PRs: #{pr_lists.map(&:count).to_json}"
    max_displayed_prs = LED_COUNT / pr_lists.count
    prs = pr_lists.each_with_index.map { |pr_list, list_index|
      pr_list.to_a
             .slice(0, max_displayed_prs)
             .map { |pr, i| pr.merge(led: list_index * max_displayed_prs + i) }
    }.reduce(&:+)

    puts "updating leds"
    prs.each do |pr|
      puts pr.to_json
      color = STATE_COLORS[pr[:combined_state]]
      puts "color: #{color}"
      update_led(serialport, pr[:led], color)
    end

    puts "resetting unused leds"
    unused_leds = (0..(LED_COUNT - 1)).to_a - prs.map { |pr| pr[:led] }
    unused_leds.each { |i| update_led(serialport, i, STATE_COLORS[nil]) }

    puts "sleeping ..."; puts ""
    sleep 60
  end
ensure
  puts "... closing"
  serialport&.close
end

status_loop
