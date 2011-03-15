module Heroku
  module Command
    class Pg

      def config_vars
        raise 'not implemented'
      end

      class Resolver < Struct.new(:config_vars, :message)
        URL_PATTERN = /_URL$/

        def resolve(db_id)
          @db_id = db_id

          url_deprecation_check
          default_database_check

          config_vars["#{@db_id}_URL"]
        end

        private

        def url_deprecation_check
          return unless @db_id =~ URL_PATTERN
          old_id = @db_id.dup
          @db_id.gsub!(URL_PATTERN,'')
          self.message = "#{old_id} is deprecated, please use #{@db_id}"
        end

        def default_database_check
          return unless @db_id == 'DATABASE'
          @db_id = 'SHARED_DATABASE'
          self.message = 'using SHARED_DATABASE_URL'
        end
      end
    end
  end
end

