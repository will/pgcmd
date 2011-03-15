module Heroku
  module Command
    class Pg

      def config_vars
        raise 'not implemented'
      end

      def resolve(db_id)
        db_id = url_deprecation_check(db_id)
        if db_id == 'DATABASE'
          db_id = 'SHARED_DATABASE'
          heroku.display('using SHARED_DATABASE_URL')
        end
        db_var = "#{db_id}_URL"
        config_vars[db_var]
      end

      private

      def url_deprecation_check(db_id)
        pattern = /_URL$/
        if db_id =~ pattern
          old_id = db_id.dup
          db_id.gsub!(pattern,'')
          heroku.display("#{old_id} is deprecated, please use #{db_id}")
        end
        db_id
      end
    end
  end
end

