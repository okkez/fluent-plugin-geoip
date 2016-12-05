require 'fluent/plugin/filter'
require 'fluent/plugin/geoip'

module Fluent::Plugin
  class GeoipFilter < Fluent::Plugin::Filter
    Fluent::Plugin.register_filter('geoip', self)

    config_param :geoip_database, :string, default: File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
    config_param :geoip_lookup_key, :string, default: 'host'
    config_param :skip_adding_null_record, :bool, default: false

    config_set_default :include_tag_key, false

    config_param :hostname_command, :string, default: 'hostname'

    config_param :flush_interval, :time, default: 0
    config_param :log_level, :string, default: 'warn'


    def configure(conf)
      super
      @geoip = Fluent::GeoIP.new(self, conf)
    end

    def filter(tag, time, record)
      filtered_record = @geoip.add_geoip_field(record)
      if filtered_record
        record = filtered_record
      end
      record
    end
  end
end
