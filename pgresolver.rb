module PGResolver
  private

  def config_vars
    @config_vars ||= heroku.config_vars(app)
  end

  def resolve_db(options={})
    db_id = db_flag
    unless db_id
      if options[:allow_default]
        db_id = "DATABASE"
      else
        abort(" !  Usage: heroku #{options[:required]} <DATABASE>") if options[:required]
      end
    end

    resolver = Resolver.new(db_id, config_vars)
    display resolver.message
    abort_with_database_list(db_id) unless resolver.url

    return resolver
  end

  def abort_with_database_list(failed_id)
    display " !  Could not resolve database #{failed_id}"
    display " !"
    display " !  Available databases: "
    Resolver.all(config_vars).each do |db|
      display " !   #{db[:pretty_name]}"
    end
    abort
  end

  def specified_db?
    db_flag
  end

  def db_flag
    @db_flag ||= args.shift
  end

  def specified_db_or_all
    if specified_db?
      yield resolve_db
    else
      Resolver.all(config_vars).each { |db| yield db }
    end
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

    def self.addon_prefix
      ENV["HEROKU_POSTGRESQL_ADDON_PREFIX"] || "HEROKU_POSTGRESQL"
    end

    def self.parse_config(config_vars)
      dbs = {}
      config_vars.each do |key,val|
        case key
        when "DATABASE_URL"
          dbs['DATABASE'] = val
        when 'SHARED_DATABASE_URL'
          dbs['SHARED_DATABASE'] = val
        when /^(#{addon_prefix}\w+)_URL$/
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

  end
end
