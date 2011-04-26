require 'heroku/command'
module Heroku
  module Command
    class Addons
      include PGResolver

      alias configure_addon_without_pg configure_addon
      def configure_addon(label, &install_or_upgrade)
        %w[fork track].each do |opt|
          if val = extract_option("--#{opt}")
            resolved = Resolver.new(val, config_vars)
            display resolved.message if resolved.message
            abort_with_database_list(val) unless resolved[:url]

            url = resolved[:url]
            db = HerokuPostgresql::Client10.new(url).get_database
            db_plan = db[:plan]
            version = db[:postgresql_version]

            abort " !  You cannot fork a database unless it is currently available." unless db[:state] == "available"
            abort " !  PostgreSQL v#{version} cannot be #{opt}ed. Please upgrade to a newer version." if '8' == version.split(/\./).first
            addon_plan = args.first.split(/:/)[1] || 'ronin'

            funin = ["ronin", "fugu"]
            if     funin.member?(addon_plan) &&  funin.member?(db_plan)
              # fantastic
            elsif  funin.member?(addon_plan) && !funin.member?(db_plan)
              abort " !  Cannot #{opt} a #{resolved[:name]} to a ronin or a fugu database."
            elsif !funin.member?(addon_plan) &&  funin.member?(db_plan)
              abort " !  Can only #{opt} #{resolved[:name]} to a ronin or a fugu database."
            elsif !funin.member?(addon_plan) && !funin.member?(db_plan)
              # even better!
            end

            args << "#{opt}=#{url}"
          end
        end
        configure_addon_without_pg(label, &install_or_upgrade)
      end
    end
  end
end
