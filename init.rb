module Heroku
  module Command
    class Pg

      class Resolver
        attr_reader :url

        def initialize(db_id, config_vars)
          @db_id, @config_vars = db_id, config_vars
          @messages = []
          parse_config
          resolve
        end

        def message
          @messages.join("\n") unless @messages.empty?
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
          h_pg_color_check
          @url = @dbs[@db_id]
        end

        def url_deprecation_check
          return unless @db_id =~ /(\w+)_URL$/
          old_id = @db_id
          @db_id = $+
          @messages << "#{old_id} is deprecated, please use #{@db_id}"
        end

        def default_database_check
          return unless @db_id == 'DATABASE'
          @db_id = @dbs.find { |k,v|
            v == @dbs['DATABASE'] && k != 'DATABASE'
          }.first
          @messages << "using #{@db_id}"
        end

        def h_pg_color_check
          return unless @db_id =~ /^HEROKU_POSTGRESQL_(\w+)/
          @db_id = $+
          @messages << "using #{@db_id}"
        end
      end
    end
  end
end

