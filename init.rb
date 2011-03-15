module Heroku
  module Command
    class Pg

      def config_vars
        raise 'not implemented'
      end

      class Resolver
        URL_PATTERN = /_URL$/

        attr_reader :url, :message

        def initialize(db_id, config_vars)
          @db_id, @config_vars = db_id, config_vars
          parse_config
          resolve
        end

        private

        def parse_config
          @dbs = {}
          @config_vars.each do |key,val|
            case key
            when "DATABASE_URL"
              @dbs['DATABASE'] = val
            when 'SHARED_DATABASE_URL'
              @dbs['SHARED_DATABASE'] = val
            when /^HEROKU_POSTGRESQL_(\w+)_URL$/
              @dbs[$+] = val # $+ is the last match
            end
          end
        end

        def resolve
          url_deprecation_check
          default_database_check
          @url = @dbs[@db_id]
        end

        def url_deprecation_check
          return unless @db_id =~ URL_PATTERN
          old_id = @db_id.dup
          @db_id.gsub!(URL_PATTERN,'')
          @message = "#{old_id} is deprecated, please use #{@db_id}"
        end

        def default_database_check
          return unless @db_id == 'DATABASE'
          @db_id = @dbs.find { |k,v|
            v == @dbs['DATABASE'] && k != 'DATABASE'
          }.first
          @message = "using #{@db_id}"
        end
      end
    end
  end
end

