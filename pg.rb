module Heroku
  module Command
    class Pg
      def ingress
        uri = generate_ingress_uri("Granting ingress for 60s")
        display "Connection info string:"
        display "   \"dbname=#{uri.path[1..-1]} host=#{uri.host} user=#{uri.user} password=#{uri.password} sslmode=required\""
      end

      def psql
        uri = generate_ingress_uri("Connecting")
        ENV["PGPASSWORD"] = uri.password
        ENV["PGSSLMODE"]  = 'require'
        system "psql -U #{uri.user} -h #{uri.host} #{uri.path[1..-1]}"
      end

      def info
        specified_db_or_all { |db| display_db_info db }
      end

      def wait
        display "Checking availablity of all databases" unless specified_db?
        specified_db_or_all { |db| wait_for db }
      end

      def promote
        old_db = Resolver.new("DATABASE", config_vars)
        new_db = resolve_db(:required => 'promote')
        abort( " !  DATABASE_URL is already set to #{new_db[:name]}") if new_db[:default]

        display "Promoting DATABASE_URL to #{new_db[:name]}"
        return unless confirm_command

        promote_old_to_new(old_db, new_db)
        set_database_url(new_db[:url])

        display_info "DATABASE_URL (#{new_db[:name]})", new_db[:url]
      end

      def reset
        db = resolve_db(:required => 'reset')

        display "Resetting #{db[:pretty_name]}"
        return unless confirm_command

        working_display 'Resetting' do
          if "SHARED_DATABASE" == db[:name]
            heroku.database_reset(app)
          else
            heroku_postgresql_client(db[:url]).reset
          end
        end
      end

      private

      def resolve_db(options={})
        db_id = db_flag
        unless db_id
          if options[:allow_default]
            db_id = "DATABASE"
          else
            abort(" !  Usage: heroku pg:#{options[:required]} --db <DATABASE>") if options[:required]
          end
        end
        config_vars = heroku.config_vars(app)

        resolver = Resolver.new(db_id, config_vars)
        display resolver.message
        unless resolver.url
          display " !  Could not resolve database #{db_id}"
          display " !"
          display " !  Available databases: "
          Resolver.all(config_vars).each do |db|
            display " !   #{db[:pretty_name]}"
          end
          abort
        end

        return resolver
      end

      def promote_old_to_new(old_db, new_db)
        return if [new_db, old_db].map(&:name).include? "SHARED_DATABASE"
        working_display "Promoting" do
          heroku_postgresql_client(old_db[:url]).promote_to new_db[:url]
        end
      end

      def set_database_url(url)
        working_display "Updating DATABASE_URL" do
          heroku.add_config_vars(app, {"DATABASE_URL" => url})
        end
      end

      def working_display(msg)
        redisplay "#{msg}..."
        yield if block_given?
        redisplay "#{msg}... done\n"
      end

      def heroku_postgresql_client(url)
        HerokuPostgresql::Client10.new(url)
      end

      def specified_db?
        db_flag
      end

      def db_flag
        @db_flag ||= extract_option("--db")
      end

      def specified_db_or_all
        if specified_db?
          yield resolve_db
        else
          Resolver.all(config_vars).each { |db| yield db }
        end
      end

      def wait_for(db)
        return if "SHARED_DATABASE" == db[:name]
        name = "database #{db[:pretty_name]}"
        ticking do |ticks|
          database = heroku_postgresql_client(db[:url]).get_database
          state = database[:state]
          if state == "available"
            redisplay("The #{name} is available", true)
            break
          elsif state == "deprovisioned"
            redisplay("The #{name} has been destroyed", true)
            break
          elsif state == "failed"
            redisplay("The #{name} encountered an error", true)
            break
          else
            redisplay("#{state.capitalize} #{name} #{spinner(ticks)}", false)
          end
        end
      end

      def display_db_info(db)
        display("=== #{app} database #{db[:pretty_name]}")
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
        db = resolve_db(:allow_default => true)
        abort " !  Cannot ingress to a shared database" if "SHARED_DATABASE" == db[:name]
        hpc = heroku_postgresql_client(db[:url])
        abort " !  The database is not available" unless hpc.get_database[:state] == "available"
        working_display("#{action} to #{db[:name]}") { hpc.ingress }
        return URI.parse(db[:url])
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
          { :name => name,
            :url => url,
            :pretty_name => pretty_name,
            :default => default?
          }[arg]
        end

        def name
          db_id
        end

        def pretty_name
          "#{db_id}#{ " (DATABASE_URL)" if default? }"
        end

        def self.all(config_vars)
          parsed = parse_config(config_vars)
          default = parsed['DATABASE']
          dbs = []
          parsed.reject{|k,v| k == 'DATABASE'}.each do |name, url|
            dbs << {:name => name, :url => url, :default => url==default, :pretty_name => "#{name}#{' (DATABASE_URL)' if url==default}"}
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

        def default?
          url && url == @dbs['DATABASE']
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
          dbs = @dbs.find { |k,v|
            v == @dbs['DATABASE'] && k != 'DATABASE'
          }

          if dbs
            @db_id = dbs.first
            @messages << "using #{@db_id}"
          else
            @messages << "DATABASE_URL does not match any of your databases"
          end
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

