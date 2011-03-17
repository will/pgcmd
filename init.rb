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

      def info
        if db_flag
          display_db_info Resolver.new(db_flag, config_vars)
        else
          Resolver.all(config_vars).each { |db| display_db_info db }
        end
      end

      private

      def display_db_info(db)
        display("=== #{app} database #{db[:name]} #{"(DATABASE_URL)" if db[:default]}")
        if db[:name] == "SHARED_DATABASE"
          display_info_shared
        else
          display_info_dedicated(db)
        end
      end

      def display_info_shared
        attrs = heroku.info(app)
        display_info("Data size", "#{size_format(attrs[:database_size].to_i)}")
      end

      def display_info_dedicated(db)
        database = heroku_postgresql_client(db[:url]).get_database

        display_info("Plan", database[:plan].capitalize)

        display_info("State",
            "#{database[:state]} for " +
            "#{delta_format(Time.parse(database[:state_updated_at]))}")

        if database[:num_bytes] && database[:num_tables]
          display_info("Data size",
            "#{size_format(database[:num_bytes])} in " +
            "#{database[:num_tables]} table#{database[:num_tables] == 1 ? "" : "s"}")
        end

        if version = database[:postgresql_version]
          display_info("PG version", version)
        end

        display_info("Born", time_format(database[:created_at]))
        display_info("Mem Used", "%0.2f %" % database[:mem_percent_used]) unless [nil, ""].include? database[:mem_percent_used]
        display_info("CPU Used", "%0.2f %" % (100 - database[:cpu_idle].to_f)) unless [nil, ""].include? database[:cpu_idle]
      end

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

      def db_flag
        @db_flag ||= extract_option("--db")
      end

      def resolve_db
        db_id = db_flag || "DATABASE"
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

        def [](arg)
           {:name => db_id, :url => url, :default => url==@dbs['DATABASE']}[arg]
        end

        def self.all(config_vars)
          parsed = parse_config(config_vars)
          default = parsed['DATABASE']
          dbs = []
          parsed.reject{|k,v| k == 'DATABASE'}.each do |name, url|
            dbs << {:name => name, :url => url, :default => url==default}
          end
          dbs.sort {|a,b| a[:default]? -1 : a[:name] <=> b[:name] }
        end

        private

        def parse_config
          @dbs = self.class.parse_config(@config_vars)
        end

        def self.parse_config(config_vars)
          dbs = {}
          config_vars.each do |key,val|
            case key
            when "DATABASE_URL"
              dbs['DATABASE'] = val
            when 'SHARED_DATABASE_URL'
              dbs['SHARED_DATABASE'] = val
            when /^HEROKU_POSTGRESQL_(\w+)_URL$/
              dbs[$+] = val # $+ is the last match
            end
          end
          return dbs
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

