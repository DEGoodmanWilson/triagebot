require 'octokit'
require 'jwt'
require 'httparty'

# Notice that the private key must be in PEM format, but the newlines should be stripped and replaced with
# the literal `\n`. This can be done in the terminal as such:
# export GITHUB_PRIVATE_KEY=`awk '{printf "%s\\n", $0}' private-key.pem`
PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n")) # convert newlines
APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']
# some configuration that you should change to reflect your own Recast.AI account
RECASTAI_USERNAME = 'degoodmanwilson'
RECASTAI_BOTNAME = 'triagebot'
RECASTAI_DEV_TOKEN = ENV['RECASTAI_DEV_TOKEN']
RECASTAI_TOKEN = ENV['RECASTAI_TOKEN']


#####################################
# Authenticating a GitHub App


# First we want to create an authenticated GitHub Client.
# We do this so we can get access to more generous rate limits.
payload = {
    # The time that this JWT was issued, _i.e._ now.
    iat: Time.now.to_i,

    # How long is the JWT good for (in seconds)?
    # Let's say it can be used for 10 minutes before it needs to be refreshed.
    # TODO we don't actually cache this token, we regenerate a new one every time!
    exp: Time.now.to_i + (10 * 60),

    # Your GitHub App's identifier number, so GitHub knows who issued the JWT, and know what permissions
    # this token has.
    iss: APP_IDENTIFIER
}

# Cryptographically sign the JWT
jwt = JWT.encode(payload, PRIVATE_KEY, 'RS256')

# Create the Octokit client, using the JWT as the auth token.
# Notice that this client will _not_ have sufficient permissions to do many interesting things!
# We might, for particular endpoints, need to generate an installation token (using the JWT), and instantiate
# a new client object. But we'll cross that bridge when/if we get there!
app_client ||= Octokit::Client.new(bearer_token: jwt)

# get an installation key. This is necessary. It expires after an hour, so we need to refresh it every hour
# For these purposes, just use the first installation we find, because it really doesn't matter.
installations = app_client.find_app_installations()
installation_id = installations[0]['id']
installation_token = app_client.create_app_installation_access_token(installation_id)[:token]
client = Octokit::Client.new(bearer_token: installation_token)


#####################################
# Using the Search API

# We will time each request in order to avoid GitHub's rate limiter.
# We are allowed 30 requests per minute because as you can see above, we have authenticated.
time_between_calls = 60 / 30
calls = 0

# Repeat the following for each label we want to build an intent for:
for label in ['bug', 'enhancement', 'question']

  puts "********* #{label} *********"

  page = 1

  # GitHub currently caps search results to 1,000 entries, but we're not going to count. We'll let GitHub do the
  # counting for us—so, loop forever.
  loop do
    before = Time.now

    begin
      # Here is the centerpiece of this code: The call to the Search API.
      issues = client.search_issues("label:#{label}", page: page)
    rescue Octokit::UnprocessableEntity => ex
      # GitHub will only return 1,000 results. Any requests that page beyond 1,000 will result in a 422 error
      # instead of a 200. Octokit throws an exception when we get a 422. If this happens, it's because we've seen
      # all the results.
      puts "Got all the results for #{label}. Let's move on to the next one."
      break
    rescue Octokit::TooManyRequests => ex
      ending = Time.now
      diff = ending - start
      puts "Rate limit exceeded, called #{calls} endpoints in #{diff} seconds (#{calls / diff} calls/sec)"
      # So, `kernel#sleep` often doesn't sleep for as long as you'd like. So sometimes we hit the rate limit despite
      # taking care. If we do, just sleep a little longer, and try again.
      sleep(time_between_calls)
      next # try endpoint again
    end

    expressions = []
    for expression in issues['items'] do
      # Recast.AI wants to know what language our tagged issue titles are in. GitHub doesn't tell us, so we are going
      # to use a different endpoint on Recast.AI to ask them.
      # Notice that we have to make one API call per each expression to evaluate, and that takes a LOT OF TIME. However,
      # the quality improvement that results is worth taking the time.
      # TODO parallelize this so we can not spend so much time here.

      result = HTTParty.post("https://api.recast.ai/v2/request",
                             body: {text: expression['title']},
                             headers: {'Authorization' => "Token #{RECASTAI_TOKEN}"}
      )
      language = result.parsed_response['results']['language']


      expressions.push({source: expression['title'], language: {isocode: language}})
      puts language + ': ' + expression['title']

    end

    # And now we bulk-post the tagged titles to Recast.AI. Their otherwise excellent gem doesn't support this
    # endpoint, so we need to use raw HTTP requests to upload the data.
    result = HTTParty.post("https://api.recast.ai/v2/users/#{RECASTAI_USERNAME}/bots/#{RECASTAI_BOTNAME}/intents/#{label}/expressions/bulk_create",
                           body: {expressions: expressions},
                           headers: {'Authorization' => "Token #{RECASTAI_DEV_TOKEN}"}
    )

    # Go to the next page of search results from GitHub.
    page += 1

    # Now that we have completed the call to the GitHub Search API and the Recast.AI API, let's measure how long it
    # took. We can always sleep if we need to, in order to avoid hitting the rate limiter.
    after = Time.now
    sleepy_time = time_between_calls - (after - before)
    puts "======== Sleeping for #{sleepy_time}"
    slept = sleep(sleepy_time) unless sleepy_time <= 0
    puts "-------- slept for #{slept}" unless slept.nil?

  end
end
