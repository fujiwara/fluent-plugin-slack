require_relative '../test_helper'
require 'fluent/plugin/out_slack'
require 'time'

class SlackOutputTest < Test::Unit::TestCase

  def setup
    super
    Fluent::Test.setup
    @icon_url = 'http://www.google.com/s2/favicons?domain=www.google.de'
  end

  CONFIG = %[
    channel channel
    token   XXX-XXX-XXX
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::SlackOutput).configure(conf)
  end

  # old version compatibility with v0.4.0"
  def test_old_config
    # default check
    d = create_driver
    assert_equal true,         d.instance.localtime
    assert_equal 'fluentd',    d.instance.username
    assert_equal 'good',       d.instance.color
    assert_equal ':question:', d.instance.icon_emoji

    # incoming webhook endpoint was changed. api_key option should be ignored
    assert_nothing_raised do
      create_driver(CONFIG + %[api_key testtoken])
    end

    # incoming webhook endpoint was changed. team option should be ignored
    assert_nothing_raised do
      create_driver(CONFIG + %[team sowasowa])
    end

    # rtm? it was not calling `rtm.start`. rtm option was removed and should be ignored
    assert_nothing_raised do
      create_driver(CONFIG + %[rtm true])
    end

    # channel should be URI.unescape-ed
    d = create_driver(CONFIG + %[channel %23test])
    assert_equal '#test', d.instance.channel

    # timezone should work
    d = create_driver(CONFIG + %[timezone Asia/Tokyo])
    assert_equal 'Asia/Tokyo', d.instance.timezone
  end

  def test_configure
    d = create_driver(%[
      channel      channel
      time_format  %Y/%m/%d %H:%M:%S
      username     username
      color        bad
      icon_emoji   :ghost:
      token        XX-XX-XX
      title        slack notice!
      message      %s
      message_keys message
    ])
    assert_equal '#channel', d.instance.channel
    assert_equal '%Y/%m/%d %H:%M:%S', d.instance.time_format
    assert_equal 'username', d.instance.username
    assert_equal 'bad', d.instance.color
    assert_equal ':ghost:', d.instance.icon_emoji
    assert_equal 'XX-XX-XX', d.instance.token
    assert_equal '%s', d.instance.message
    assert_equal ['message'], d.instance.message_keys

    assert_raise(Fluent::ConfigError) do
      create_driver(CONFIG + %[title %s %s\ntitle_keys foo])
    end

    assert_raise(Fluent::ConfigError) do
      create_driver(CONFIG + %[message %s %s\nmessage_keys foo])
    end

    assert_raise(Fluent::ConfigError) do
      create_driver(CONFIG + %[channel %s %s\nchannel_keys foo])
    end

    # One of webhook_url or slackbot_url, or token is required
    assert_raise(Fluent::ConfigError) do
      create_driver(%[channel foo])
    end

    # webhook_url is an empty string
    assert_raise(Fluent::ConfigError) do
      create_driver(%[channel foo\nwebhook_url])
    end

    # webhook_url is an empty string
    assert_raise(Fluent::ConfigError) do
      create_driver(%[channel foo\nslackbot_url])
    end

    # token is an empty string
    assert_raise(Fluent::ConfigError) do
      create_driver(%[channel foo\ntoken])
    end
  end

  def test_timezone_configure
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i

    d = create_driver(CONFIG + %[localtime])
    with_timezone('Asia/Tokyo') do
      assert_equal true,       d.instance.localtime
      assert_equal "07:00:00", d.instance.timef.format(time)
    end

    d = create_driver(CONFIG + %[utc])
    with_timezone('Asia/Tokyo') do
      assert_equal false,      d.instance.localtime
      assert_equal "22:00:00", d.instance.timef.format(time)
    end

    d = create_driver(CONFIG + %[timezone Asia/Taipei])
    with_timezone('Asia/Tokyo') do
      assert_equal "Asia/Taipei", d.instance.timezone
      assert_equal "06:00:00",    d.instance.timef.format(time)
    end
  end

  def test_time_format_configure
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i

    d = create_driver(CONFIG + %[time_format %Y/%m/%d %H:%M:%S])
    with_timezone('Asia/Tokyo') do
      assert_equal "2014/01/02 07:00:00", d.instance.timef.format(time)
    end
  end

  def test_buffer_configure
    assert_nothing_raised do
      create_driver(CONFIG + %[buffer_type file\nbuffer_path tmp/])
    end
  end

  def test_icon_configure
    # default
    d = create_driver(CONFIG)
    assert_equal ':question:', d.instance.icon_emoji
    assert_equal nil, d.instance.icon_url

    # either of icon_emoji or icon_url can be specified
    assert_raise(Fluent::ConfigError) do
      d = create_driver(CONFIG + %[icon_emoji :ghost:\nicon_url #{@icon_url}])
    end

    # icon_emoji
    d = create_driver(CONFIG + %[icon_emoji :ghost:])
    assert_equal ':ghost:', d.instance.icon_emoji
    assert_equal nil, d.instance.icon_url

    # icon_url
    d = create_driver(CONFIG + %[icon_url #{@icon_url}])
    assert_equal nil, d.instance.icon_emoji
    assert_equal @icon_url, d.instance.icon_url
  end

  def test_https_proxy_configure
    # default
    d = create_driver(CONFIG)
    assert_equal nil, d.instance.slack.https_proxy
    assert_equal Net::HTTP, d.instance.slack.proxy_class

    # https_proxy
    d = create_driver(CONFIG + %[https_proxy https://proxy.foo.bar:443])
    assert_equal URI.parse('https://proxy.foo.bar:443'), d.instance.slack.https_proxy
    assert_not_equal Net::HTTP, d.instance.slack.proxy_class # Net::HTTP.Proxy
  end

  def test_mrkwn_configure
    # default
    d = create_driver(CONFIG)
    assert_equal false, d.instance.mrkdwn
    assert_equal nil, d.instance.mrkdwn_in

    # mrkdwn
    d = create_driver(CONFIG + %[mrkdwn true])
    assert_equal true, d.instance.mrkdwn
    assert_equal %w[text fields], d.instance.mrkdwn_in
  end

  def test_default_incoming_webhook
    d = create_driver(%[
      channel channel
      webhook_url https://hooks.slack.com/services/XXX/XXX/XXX
    ])
    assert_equal Fluent::SlackClient::IncomingWebhook, d.instance.slack.class
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: 'test',
        fields:   [{
          title: 'test',
          value: "[07:00:00] sowawa1\n[07:00:00] sowawa2\n",
        }],
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1'}, time)
      d.emit({message: 'sowawa2'}, time)
      d.run
    end
  end

  def test_default_slackbot
    d = create_driver(%[
      channel channel
      slackbot_url https://xxxxx.slack.com/services/hooks/slackbot?token=XXXXXXX
    ])
    assert_equal Fluent::SlackClient::Slackbot, d.instance.slack.class
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "sowawa1\nsowawa2\n",
        text:     "sowawa1\nsowawa2\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1'}, time)
      d.emit({message: 'sowawa2'}, time)
      d.run
    end
  end

  def test_default_slack_api
    d = create_driver(%[
      channel channel
      token   XX-XX-XX
    ])
    assert_equal Fluent::SlackClient::WebApi, d.instance.slack.class
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XX-XX-XX',
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "sowawa1\nsowawa2\n",
        text:     "sowawa1\nsowawa2\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1'}, time)
      d.emit({message: 'sowawa2'}, time)
      d.run
    end
  end

  def test_title_keys
    d = create_driver(CONFIG + %[title %s\ntitle_keys tag])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    # attachments field should be changed to show the title
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: d.tag,
        fields:   [
          {
            title: d.tag,
            value: "sowawa1\nsowawa2\n",
          }
        ],
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1'}, time)
      d.emit({message: 'sowawa2'}, time)
      d.run
    end
  end

  def test_message_keys
    d = create_driver(CONFIG + %[message %s %s\nmessage_keys tag,message])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "test sowawa1\ntest sowawa2\n",
        text:     "test sowawa1\ntest sowawa2\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1'}, time)
      d.emit({message: 'sowawa2'}, time)
      d.run
    end
  end

  def test_channel_keys
    d = create_driver(CONFIG + %[channel %s\nchannel_keys channel])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel1',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "sowawa1\n",
        text:     "sowawa1\n",
      }]
    }, {})
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel2',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "sowawa2\n",
        text:     "sowawa2\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'sowawa1', channel: 'channel1'}, time)
      d.emit({message: 'sowawa2', channel: 'channel2'}, time)
      d.run
    end
  end

  def test_icon_emoji
    d = create_driver(CONFIG + %[icon_emoji :ghost:])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':ghost:',
      attachments: [{
        color:    'good',
        fallback: "foo\n",
        text:     "foo\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'foo'}, time)
      d.run
    end
  end

  def test_icon_url
    d = create_driver(CONFIG + %[icon_url #{@icon_url}])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel',
      username:    'fluentd',
      icon_url:    @icon_url,
      attachments: [{
        color:    'good',
        fallback: "foo\n",
        text:     "foo\n",
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'foo'}, time)
      d.run
    end
  end

  def test_mrkdwn
    d = create_driver(CONFIG + %[mrkdwn true])
    time = Time.parse("2014-01-01 22:00:00 UTC").to_i
    d.tag  = 'test'
    mock(d.instance.slack).post_message({
      token:       'XXX-XXX-XXX',
      channel:     '#channel',
      username:    'fluentd',
      icon_emoji:  ':question:',
      attachments: [{
        color:    'good',
        fallback: "foo\n",
        text:     "foo\n",
        mrkdwn_in: ["text", "fields"],
      }]
    }, {})
    with_timezone('Asia/Tokyo') do
      d.emit({message: 'foo'}, time)
      d.run
    end
  end
end
