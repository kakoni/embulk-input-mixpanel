require "tzinfo"
require "embulk/input/mixpanel_api/client"

module Embulk
  module Input

    class Mixpanel < InputPlugin
      Plugin.register_input("mixpanel", self)

      PREVIEW_RECORDS_COUNT = 30

      def self.transaction(config, &control)
        task = {}

        task[:params] = config_to_export_params(config)
        task[:api_key] = config.param(:api_key, :string)
        task[:api_secret] = config.param(:api_secret, :string)
        task[:timezone] = config.param(:timezone, :string)
        begin
          # raises exception if timezone is invalid string
          TZInfo::Timezone.get(task[:timezone])
        rescue => e
          Embulk.logger.error "'#{task[:timezone]}' is invalid timezone"
          raise e
        end

        columns = []
        task[:schema] = config.param(:columns, :array)
        task[:schema].each do |column|
          name = column["name"]
          type = column["type"].to_sym

          columns << Column.new(nil, name, type, column["format"])
        end

        resume(task, columns, 1, &control)
      end

      def self.resume(task, columns, count, &control)
        commit_reports = yield(task, columns, count)

        next_config_diff = {}
        return next_config_diff
      end

      def self.guess(config)
        client = MixpanelApi::Client.new(config.param(:api_key, :string), config.param(:api_secret, :string))
        records = client.export(config_to_export_params(config))
        sample_records = records.first(10)
        properties = Guess::SchemaGuess.from_hash_records(sample_records.map{|r| r["properties"]})
        columns = properties.map do |col|
          result = {
            name: col.name,
            type: col.type,
          }
          result[:format] = col.format if col.format
          result
        end
        columns.unshift(name: "event", type: :string)
        return {"columns" => columns}
      end

      def init
        @api_key = task[:api_key]
        @api_secret = task[:api_secret]
        @params = task[:params]
        @timezone = task[:timezone]
        @schema = task[:schema]
      end

      def run
        client = MixpanelApi::Client.new(@api_key, @api_secret)
        records = client.export(@params)
        records = records.first(PREVIEW_RECORDS_COUNT) if preview?
        records.each do |record|
          values = @schema.collect do |column|
            value = column["name"] == "event" ? record["event"] : record["properties"][column["name"]]
            next value if column["name"] != "time"
            # Adjust timezone offset to get UTC time
            # c.f. https://mixpanel.com/docs/api-documentation/exporting-raw-data-you-inserted-into-mixpanel#export
            tz = TZInfo::Timezone.get(@timezone)
            offset = tz.period_for_local(value).offset.utc_offset
            value - offset
          end
          page_builder.add(values)
        end
        page_builder.finish

        commit_report = {}
        return commit_report
      end

      private

      def preview?
        begin
          org.embulk.spi.Exec.isPreview()
        rescue java.lang.NullPointerException => e
          false
        end
      end

      def self.config_to_export_params(config)
        {
          api_key: config.param(:api_key, :string),
          from_date: config.param(:from_date, :string),
          to_date: config.param(:to_date, :string),
          event: config.param(:event, :array, default: nil),
          where: config.param(:where, :string, default: nil),
          bucket: config.param(:bucket, :string, default: nil),
        }
      end
    end

  end
end
