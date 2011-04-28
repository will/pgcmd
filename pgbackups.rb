require "heroku/pgutils"
require "pgbackups/client"

module Heroku::Command
  class Pgbackups < BaseWithApp
    include PGResolver

    # pgbackups:capture [DATABASE]
    #
    # capture a backup from a database id
    #
    # if no DATABASE is specified, defaults to DATABASE_URL
    #
    # -e, --expire  # if no slots are available to capture, delete the oldest backup to make room
    #
    def capture
      db = resolve_db(:allow_default => true)

      from_url  = db[:url]
      from_name = db[:name]
      to_url    = nil # server will assign
      to_name   = "BACKUP"
      opts      = {:expire => extract_option("--expire")}

      backup = transfer!(from_url, from_name, to_url, to_name, opts)

      to_uri = URI.parse backup["to_url"]
      backup_id = to_uri.path.empty? ? "error" : File.basename(to_uri.path, '.*')
      display "\n#{db[:pretty_name]}  ----backup--->  #{backup_id}"

      backup = poll_transfer!(backup)

      if backup["error_at"]
        message  =   " !    An error occurred and your backup did not finish."
        message += "\n !    The database is not yet online. Please try again." if backup['log'] =~ /Name or service not known/
        message += "\n !    The database credentials are incorrect."           if backup['log'] =~ /psql: FATAL:/
        abort(message)
      end
    end

    # pgbackups:restore [BACKUP_ID]
    #
    # restore a backup to a database id
    #
    # if no BACKUP_ID is specified, uses the most recent backup
    #
    # -d, --db DATABASE  # the database id to target for the restore
    #
    
    def restore
      db = resolve_db(:allow_default => true)
      to_name = db[:name]
      to_url  = db[:url]

      backup_id = args.shift

      if backup_id =~ /^http(s?):\/\//
        from_url  = backup_id
        from_name = "EXTERNAL_BACKUP"
        from_uri  = URI.parse backup_id
        backup_id = from_uri.path.empty? ? from_uri : File.basename(from_uri.path)
      else
        if backup_id
          backup = pgbackup_client.get_backup(backup_id)
          abort("Backup #{backup_id} already deleted.") if backup["destroyed_at"]
        else
          backup = pgbackup_client.get_latest_backup
          to_uri = URI.parse backup["to_url"]
          backup_id = File.basename(to_uri.path, '.*')
          backup_id = "#{backup_id} (most recent)"
        end

        from_url  = backup["to_url"]
        from_name = "BACKUP"
      end

      message = "#{db[:pretty_name]}  <---restore---  "
      padding = " " * message.length
      display "\n#{message}#{backup_id}"
      if backup
        display padding + "#{backup['from_name']}"
        display padding + "#{backup['created_at']}"
        display padding + "#{backup['size']}"
      end

      if confirm_command
        restore = transfer!(from_url, from_name, to_url, to_name)
        restore = poll_transfer!(restore)

        if restore["error_at"]
          message  =   " !    An error occurred and your restore did not finish."
          message += "\n !    The backup url is invalid. Use `pgbackups:url` to generate a new temporary URL." if restore['log'] =~ /Invalid dump format: .*: XML  document text/
          abort(message)
        end
      end
    end

  end
end
