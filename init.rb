module Heroku
  module Command
    class Pg

      def ingress
        uri = generate_ingress_uri("Granting ingress for 60s")
        display "Connection info string:"
        display "   \"dbname=#{uri.path[1..-1]} host=#{uri.host} user=#{uri.user} password=#{uri.password}\""
      end

      def psql
        uri = generate_ingress_uri("Connecting")
        ENV["PGPASSWORD"] = uri.password
        system "psql -U #{uri.user} -h #{uri.host} #{uri.path[1..-1]}"
      end

      private

      def generate_ingress_uri(action)
        name, url = resolve_db
        abort " !  Cannot ingress to a shared database" if "SHARED_DATABASE" == name
        hpc = heroku_postgresql_client(url)
        abort " !  The database is not available" unless hpc.get_database[:state] == "available"
        ingress_message = "#{action} to #{name}..."
        redisplay ingress_message
        hpc.ingress
        redisplay "#{ingress_message} done\n"
        return URI.parse(url)
      end

      def resolve_db
        db_id = extract_option("--db") || "DATABASE"
        config_vars = heroku.config_vars(app)

        resolver = Resolver.new(db_id, config_vars)
        display resolver.message
        unless resolver.url
          abort " !  Could not resolve database #{db_id}"
        end

        return resolver.db_id, resolver.url
      end

      def display(message, newline=true)
        super if message
      end

      class Resolver
        attr_reader :url, :db_id

        def initialize(db_id, config_vars)
          @db_id, @config_vars = db_id.upcase, config_vars
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

