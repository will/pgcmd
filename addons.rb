require 'heroku/command'
module Heroku
  module Command
    class Addons
      alias configure_addon_without_pg configure_addon
      def configure_addon(label, &install_or_upgrade)
        %w[fork track].each do |opt|
          if val = extract_option("--#{opt}")
            db = Pg::Resolver.new(val, heroku.config_vars(app))
            display db.message if db.message
            abort("Could not resolve database #{db[:name]}") unless db[:url]
            args << "#{opt}=#{db[:url]}"
          end
        end
        configure_addon_without_pg(label, &install_or_upgrade)
      end
    end
  end
end
