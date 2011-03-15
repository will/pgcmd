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
          @config_vars, @db_id = config_vars, db_id
          resolve
        end

        private

        def resolve
          url_deprecation_check
          default_database_check
          @url = @config_vars["#{@db_id}_URL"]
        end

        def url_deprecation_check
          return unless @db_id =~ URL_PATTERN
          old_id = @db_id.dup
          @db_id.gsub!(URL_PATTERN,'')
          @message = "#{old_id} is deprecated, please use #{@db_id}"
        end

        def default_database_check
          return unless @db_id == 'DATABASE'
          @db_id = 'SHARED_DATABASE'
          @message = 'using SHARED_DATABASE_URL'
        end
      end
    end
  end
end

