require 'helper'
require 'fluent/plugin/out_geoip'
require 'fluent/test/driver/output'

class GeoipOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    geoip_lookup_key  host
    enable_key_city   geoip_city
    remove_tag_prefix input.
    tag               geoip.${tag}
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::GeoipOutput).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('enable_key_cities')
    }
    d = create_driver %[
      enable_key_city   geoip_city
      remove_tag_prefix input.
      tag               geoip.${tag}
    ]
    assert_equal 'geoip_city', d.instance.config['enable_key_city']

    # multiple key config
    d = create_driver %[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      tag               geoip.${tag}
    ]
    assert_equal 'from_city, to_city', d.instance.config['enable_key_city']

    # multiple key config (bad configure)
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city
        enable_key_region from_region
        remove_tag_prefix input.
        tag               geoip.${tag}
      ]
    }

    # invalid json structure
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        geoip_lookup_key  host
        <record>
          invalid_json    {"foo" => 123}
        </record>
        remove_tag_prefix input.
        tag               geoip.${tag}
      ]
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        geoip_lookup_key  host
        <record>
          invalid_json    {"foo" : string, "bar" : 123}
        </record>
        remove_tag_prefix input.
        tag               geoip.${tag}
      ]
    }
  end

  def test_emit
    d1 = create_driver(CONFIG)
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['geoip_city']
    assert_equal nil, events[1][2]['geoip_city']
  end

  def test_emit_tag_option
    d1 = create_driver(%[
      geoip_lookup_key  host
      <record>
        geoip_city      ${city['host']}
      </record>
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['geoip_city']
    assert_equal nil, events[1][2]['geoip_city']
  end

  def test_emit_tag_parts
    d1 = create_driver(%[
      geoip_lookup_key  host
      <record>
        geoip_city      ${city['host']}
      </record>
      tag               geoip.${tag_parts[1]}.${tag_parts[2..3]}.${tag_parts[-1]}
    ])
    d1.run(default_tag: '0.1.2.3') do
      d1.feed({'host' => '66.102.3.80'})
    end
    events = d1.events
    assert_equal 1, events.length
    assert_equal 'geoip.1.2.3.3', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['geoip_city']
  end

  def test_emit_with_dot_key
    d1 = create_driver(%[
      geoip_lookup_key  ip.origin, ip.dest
      <record>
        origin_country  ${country_code['ip.origin']}
        dest_country    ${country_code['ip.dest']}
      </record>
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'})
    end
    events = d1.events
    assert_equal 1, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'US', events[0][2]['origin_country']
    assert_equal 'US', events[0][2]['dest_country']
  end

  def test_emit_nested_attr
    d1 = create_driver(%[
      geoip_lookup_key  host.ip
      enable_key_city   geoip_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['geoip_city']
    assert_equal nil, events[1][2]['geoip_city']
  end

  def test_emit_with_unknown_address
    d1 = create_driver(%[
      geoip_lookup_key  host
      <record>
        geoip_city      ${city['host']}
        geopoint        ["${longitude['host']}", "${latitude['host']}"]
      </record>
      skip_adding_null_record false
      remove_tag_prefix input.
      tag               geoip.${tag[1]}
    ])
    d1.run(default_tag: 'input.access') do
      # 203.0.113.1 is a test address described in RFC5737
      d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
      d1.feed({'host' => '0', 'message' => 'invalid ip'})
    end
    events = d1.events
    assert_equal 2, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal nil, events[0][2]['geoip_city']
    assert_equal 'geoip.access', events[1][0] # tag
    assert_equal nil, events[1][2]['geoip_city']
  end

  def test_emit_with_skip_unknown_address
    d1 = create_driver(%[
      geoip_lookup_key  host
      <record>
        geoip_city      ${city['host']}
        geopoint        [${longitude['host']}, ${latitude['host']}]
      </record>
      skip_adding_null_record true
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      # 203.0.113.1 is a test address described in RFC5737
      d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
      d1.feed({'host' => '0', 'message' => 'invalid ip'})
      d1.feed({'host' => '8.8.8.8', 'message' => 'google public dns'})
    end
    events = d1.events
    assert_equal 3, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal nil, events[0][2]['geoip_city']
    assert_equal nil, events[0][2]['geopoint']
    assert_equal 'geoip.access', events[1][0] # tag
    assert_equal nil, events[1][2]['geoip_city']
    assert_equal nil, events[1][2]['geopoint']
    assert_equal 'Mountain View', events[2][2]['geoip_city']
    assert_equal [-122.08380126953125, 37.38600158691406], events[2][2]['geopoint']
  end

  def test_emit_multiple_key
    d1 = create_driver(%[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['from_city']
    assert_equal 'Tokorozawa', events[0][2]['to_city']
    assert_equal nil, events[1][2]['from_city']
    assert_equal nil, events[1][2]['to_city']
  end

  def test_emit_multiple_key_multiple_record
    d1 = create_driver(%[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      enable_key_country_name from_country, to_country
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
      d1.feed({'from' => {'ip' => '66.102.3.80'}})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 3, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['from_city']
    assert_equal 'United States', events[0][2]['from_country']
    assert_equal 'Tokorozawa', events[0][2]['to_city']
    assert_equal 'Japan', events[0][2]['to_country']

    assert_equal 'Mountain View', events[1][2]['from_city']
    assert_equal 'United States', events[1][2]['from_country']
    assert_equal nil, events[1][2]['to_city']
    assert_equal nil, events[1][2]['to_country']

    assert_equal nil, events[2][2]['from_city']
    assert_equal nil, events[2][2]['from_country']
    assert_equal nil, events[2][2]['to_city']
    assert_equal nil, events[2][2]['to_country']
  end

  def test_emit_record_directive
    d1 = create_driver(%[
      geoip_lookup_key  from.ip
      <record>
        from_city       ${city['from.ip']}
        from_country    ${country_name['from.ip']}
        latitude        ${latitude['from.ip']}
        longitude       ${longitude['from.ip']}
        float_concat    ${latitude['from.ip']},${longitude['from.ip']}
        float_array     [${longitude['from.ip']}, ${latitude['from.ip']}]
        float_nest      { "lat" : ${latitude['from.ip']}, "lon" : ${longitude['from.ip']}}
        string_concat   ${latitude['from.ip']},${longitude['from.ip']}
        string_array    [${city['from.ip']}, ${country_name['from.ip']}]
        string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
        unknown_city    ${city['unknown_key']}
        undefined       ${city['undefined']}
        broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
        broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
      </record>
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'from' => {'ip' => '66.102.3.80'}})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length

    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['from_city']
    assert_equal 'United States', events[0][2]['from_country']
    assert_equal 37.4192008972168, events[0][2]['latitude']
    assert_equal -122.05740356445312, events[0][2]['longitude']
    assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['float_concat']
    assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['float_array']
    float_nest = {"lat" => 37.4192008972168, "lon" => -122.05740356445312 }
    assert_equal float_nest, events[0][2]['float_nest']
    assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['string_concat']
    assert_equal ["Mountain View", "United States"], events[0][2]['string_array']
    string_nest = {"city" => "Mountain View", "country_name" => "United States"}
    assert_equal string_nest, events[0][2]['string_nest']
    assert_equal nil, events[0][2]['unknown_city']
    assert_equal nil, events[0][2]['undefined']
    assert_equal [-122.05740356445312, nil], events[0][2]['broken_array1']
    assert_equal [nil, nil], events[0][2]['broken_array2']

    assert_equal nil, events[1][2]['from_city']
    assert_equal nil, events[1][2]['from_country']
    assert_equal nil, events[1][2]['latitude']
    assert_equal nil, events[1][2]['longitude']
    assert_equal ',', events[1][2]['float_concat']
    assert_equal [nil, nil], events[1][2]['float_array']
    float_nest = {"lat" => nil, "lon" => nil}
    assert_equal float_nest, events[1][2]['float_nest']
    assert_equal ',', events[1][2]['string_concat']
    assert_equal [nil, nil], events[1][2]['string_array']
    string_nest = {"city" => nil, "country_name" => nil}
    assert_equal string_nest, events[1][2]['string_nest']
    assert_equal nil, events[1][2]['unknown_city']
    assert_equal nil, events[1][2]['undefined']
    assert_equal [nil, nil], events[1][2]['broken_array1']
    assert_equal [nil, nil], events[1][2]['broken_array2']
  end

  def test_emit_record_directive_multiple_record
    d1 = create_driver(%[
      geoip_lookup_key  from.ip, to.ip
      <record>
        from_city       ${city['from.ip']}
        to_city         ${city['to.ip']}
        from_country    ${country_name['from.ip']}
        to_country      ${country_name['to.ip']}
        string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
      </record>
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
      d1.feed({'message' => 'missing field'})
    end
    events = d1.events
    assert_equal 2, events.length

    assert_equal 'geoip.access', events[0][0] # tag
    assert_equal 'Mountain View', events[0][2]['from_city']
    assert_equal 'United States', events[0][2]['from_country']
    assert_equal 'Tokorozawa', events[0][2]['to_city']
    assert_equal 'Japan', events[0][2]['to_country']
    assert_equal ['United States','Japan'], events[0][2]['string_array']

    assert_equal nil, events[1][2]['from_city']
    assert_equal nil, events[1][2]['to_city']
    assert_equal nil, events[1][2]['from_country']
    assert_equal nil, events[1][2]['to_country']
    assert_equal [nil, nil], events[1][2]['string_array']
  end

  CONFIG_QUOTED_RECORD = %[
    geoip_lookup_key  host
    <record>
      location_properties  '{ "country_code" : "${country_code["host"]}", "lat": ${latitude["host"]}, "lon": ${longitude["host"]} }'
      location_string      ${latitude['host']},${longitude['host']}
      location_string2     ${country_code["host"]}
      location_array       "[${longitude['host']},${latitude['host']}]"
      location_array2      '[${longitude["host"]},${latitude["host"]}]'
      peculiar_pattern     '[GEOIP] message => {"lat":${latitude["host"]}, "lon":${longitude["host"]}}'
    </record>
    remove_tag_prefix input.
    tag               geoip.${tag}
  ]

  def test_emit_quoted_record
    d1 = create_driver(CONFIG_QUOTED_RECORD)
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
    end
    events = d1.events
    assert_equal 1, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    location_properties = { "country_code" => "US", "lat" => 37.4192008972168, "lon"=> -122.05740356445312 }
    assert_equal location_properties, events[0][2]['location_properties']
    assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['location_string']
    assert_equal 'US', events[0][2]['location_string2']
    assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array']
    assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array2']
    assert_equal '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}', events[0][2]['peculiar_pattern']
  end

  def test_emit_v1_config_compatibility
    d1 = create_driver(CONFIG_QUOTED_RECORD)
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
    end
    events = d1.events
    assert_equal 1, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    location_properties = { "country_code" => "US", "lat" => 37.4192008972168, "lon"=> -122.05740356445312 }
    assert_equal location_properties, events[0][2]['location_properties']
    assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['location_string']
    assert_equal 'US', events[0][2]['location_string2']
    assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array']
    assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array2']
    assert_equal '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}', events[0][2]['peculiar_pattern']
  end

  def test_emit_multiline_v1_config
    d1 = create_driver(%[
      geoip_lookup_key  host
      <record>
        location_properties  {
          "city": "${city['host']}",
          "country_code": "${country_code['host']}",
          "latitude": "${latitude['host']}",
          "longitude": "${longitude['host']}"
        }
      </record>
      remove_tag_prefix input.
      tag               geoip.${tag}
    ])
    d1.run(default_tag: 'input.access') do
      d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
    end
    events = d1.events
    assert_equal 1, events.length
    assert_equal 'geoip.access', events[0][0] # tag
    location_properties = { "city"=>"Mountain View", "country_code"=>"US", "latitude"=>37.4192008972168, "longitude"=>-122.05740356445312 }
    assert_equal location_properties, events[0][2]['location_properties']
  end
end

