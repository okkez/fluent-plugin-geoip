require 'fluent/plugin/output'
require 'fluent/mixin/rewrite_tag_name'
require 'fluent/plugin/geoip'
require 'fluent/mixin'

class Fluent::Plugin::GeoipOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('geoip', self)

  helpers :event_emitter

  config_param :geoip_database, :string, default: File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
  config_param :geoip_lookup_key, :string, default: 'host'
  config_param :tag, :string, default: nil
  config_param :skip_adding_null_record, :bool, default: false

  config_param :flush_interval, :time, default: 0
  config_param :log_level, :string, default: 'warn'

  def configure(conf)
    super
    @geoip = Fluent::GeoIP.new(self, conf)
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    es = Fluent::MultiEventStream.new
    tag = ""
    chunk.msgpack_each do |_tag, time, record|
      tag = _tag
      es.add(time, @geoip.add_geoip_field(record))
    end
    router.emit_stream(tag, es)
  end
end
