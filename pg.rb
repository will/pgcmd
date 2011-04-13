module Heroku
  module Command
    class Pg
      include PGResolver
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
        new_db = resolve_db(:required => 'pg:promote')
        abort( " !  DATABASE_URL is already set to #{new_db[:name]}") if new_db[:default]

        display "Promoting DATABASE_URL to #{new_db[:name]}"
        return unless confirm_command

        promote_old_to_new(old_db, new_db)
        set_database_url(new_db[:url])

        display_info "DATABASE_URL (#{new_db[:name]})", new_db[:url]
      end

      def reset
        db = resolve_db(:required => 'pg:reset')

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
            if state == "downloading"
              msg = "(#{database[:database_dir_size].to_i} bytes)"
            elsif state == "standby"
                msg = "(#{database[:current_transaction]}/#{database[:target_transaction]})"
                if database[:tracking]
                  redisplay("The #{name} is now tracking", true)
                  break
                end
            else
              msg = ''
            end
            redisplay("#{state.capitalize} #{name} #{spinner(ticks)} #{msg}", false)
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

    end
  end
end

