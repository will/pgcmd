module Heroku
  module Command
    class Pg
      include PGResolver
      # pg:ingress [DATABASE]
      #
      # allow direct connections to the database from this IP for one minute
      #
      # (dedicated only)
      # defaults to DATABASE_URL databases if no DATABASE is specified
      #
      def ingress
        uri = generate_ingress_uri("Granting ingress for 60s")
        display "Connection info string:"
        display "   \"dbname=#{uri.path[1..-1]} host=#{uri.host} user=#{uri.user} password=#{uri.password} sslmode=required\""
      end

      # pg:psql [DATABASE]
      #
      # open a psql shell to the database
      #
      # (dedicated only)
      # defaults to DATABASE_URL databases if no DATABASE is specified
      #
      def psql
        uri = generate_ingress_uri("Connecting")
        ENV["PGPASSWORD"] = uri.password
        ENV["PGSSLMODE"]  = 'require'
        system "psql -U #{uri.user} -h #{uri.host} -p #{uri.port || 5432} #{uri.path[1..-1]}"
      end

      # pg:info [DATABASE]
      #
      # display database information
      #
      # defaults to all databases if no DATABASE is specified
      #
      def info
        specified_db_or_all { |db| display_db_info db }
      end

      # pg:wait [DATABASE]
      #
      # monitor database creation, exit when complete
      #
      # defaults to all databases if no DATABASE is specified
      #
      def wait
        display "Checking availablity of all databases" unless specified_db?
        specified_db_or_all { |db| wait_for db }
      end

      # pg:promote <DATABASE>
      #
      # sets DATABASE as your DATABASE_URL
      #
      def promote
        follower_db = resolve_db(:required => 'pg:promote')
        abort( " !  DATABASE_URL is already set to #{follower_db[:name]}") if follower_db[:default]

        display "Promoting #{follower_db[:name]} to DATABASE_URL"
        return unless confirm_command

        set_database_url(follower_db[:url])

        display_info "DATABASE_URL (#{follower_db[:name]})", follower_db[:url]
      end

      # pg:unfollow <REPLICA>
      #
      # stop a replica from following and make it a read/write database
      #
      def unfollow
        follower_db = resolve_db(:required => 'pg:unfollow')

        display "Unfollowing the leader #{follower_db[:name]}"
        return unless confirm_command

        return if follower_db[:name].include? "SHARED_DATABASE"
        working_display "Unfollowing" do
          heroku_postgresql_client(follower_db[:url]).unfollow
        end

        display_info "#{follower_db[:name]} stopped following", follower_db[:url]
      end

      # pg:reset <DATABASE>
      #
      # delete all data in DATABASE
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
                  redisplay("The #{name} is now following", true)
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
        display("=== #{db[:pretty_name]}")
        if db[:name] == "SHARED_DATABASE"
          display_info_shared
        else
          display_info_dedicated(db)
        end
      end

      def display_info_shared
        attrs = heroku.info(app)
        display_info("Data Size", "#{size_format(attrs[:database_size].to_i)}")
      end

      def display_info_dedicated(db)
        db_info = heroku_postgresql_client(db[:url]).get_database

        display_info "Plan",        db_info[:plan].capitalize         if db_info[:plan]
        display_info "Status",      db_info[:state].capitalize        if db_info[:state]
        display_info "Data Size",   size_format(db_info[:num_bytes])  if db_info[:num_bytes]
        display_info "Tables",      db_info[:num_tables]              if db_info[:num_tables]
        display_info "Forked From", db_info[:forked_from]             if db_info[:forked_from]
        display_info "Following",   db_info[:tracking]                if db_info[:tracking]
        display_info "PG Version",  db_info[:postgresql_version]      if db_info[:postgresql_version]
        display_info "Created",     time_format(db_info[:created_at]) if db_info[:created_at]
      end

      def generate_ingress_uri(action)
        db = resolve_db(:allow_default => true)
        abort " !  Cannot ingress to a shared database" if "SHARED_DATABASE" == db[:name]
        hpc = heroku_postgresql_client(db[:url])
        state = hpc.get_database[:state]
        abort " !  The database is not available" unless ["available", "standby"].member?(state)
        working_display("#{action} to #{db[:name]}") { hpc.ingress }
        return URI.parse(db[:url])
      end

    end
  end
end

