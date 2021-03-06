require 'active_record/connection_adapters/mysql_adapter'

module ActiveRecord

  class Base
    class << self
      
      # Establishes a connection to the database that's used by all Active
      # Record objects.
      def mysql_replication_connection(config) # :nodoc:
        config = config.symbolize_keys
        host     = config[:host]
        port     = config[:port]
        socket   = config[:socket]
        username = config[:username] ? config[:username].to_s : 'root'
        password = config[:password].to_s

        if config.has_key?(:database)
          database = config[:database]
        else
          raise ArgumentError, "No database specified. Missing argument: " +
            "database."
        end

        # Require the MySQL driver and define Mysql::Result.all_hashes
        unless defined? Mysql
          begin
            require_library_or_gem('mysql')
          rescue LoadError
            $stderr.puts "!!! The bundled mysql.rb driver has been removed " +
              "from Rails 2.2. Please install the mysql gem and try again: " +
              "gem install mysql."
            raise
          end
        end
        MysqlCompat.define_all_hashes_method!

        mysql = Mysql.init
        mysql.ssl_set(config[:sslkey], config[:sslcert], config[:sslca],
          config[:sslcapath], config[:sslcipher]) if config[:sslca] || 
                                                     config[:sslkey]

        ConnectionAdapters::MysqlReplicationAdapter.new(mysql, logger, 
          [host, username, password, database, port, socket], config)
      end

      def slave_valid(use_slave = nil)
      # logger.debug("checking conn.  use_slave? #{use_slave} in trans? #{Thread.current['open_transactions']}") if logger && logger.debug
        use_slave && 
          connection.is_a?(ConnectionAdapters::MysqlReplicationAdapter) && 
          (Thread.current['open_transactions'] || 0) == 0
      end

      def get_use_slave(arg)
        if arg && arg.is_a?(Hash) then return arg.delete(:use_slave){ true }
        else return arg
        end
      end

      alias_method :old_find_every, :find_every
      # Override the standard find to check for the :use_slave option. When
      # specified, the resulting query will be sent to a slave machine.
      def find_every(options)
        use_slave = options.delete(:use_slave) { true }
        if slave_valid(use_slave) 
          connection.load_balance_query { old_find_every(options) }
        else
          old_find_every(options)
        end
      end
      
      alias_method :old_find_by_sql, :find_by_sql
      # Override find_by_sql so that you can tell it to selectively use a slave
      # machine
      def find_by_sql(sql, use_slave = true)
        use_slave = get_use_slave(use_slave)
        if slave_valid(use_slave)
          connection.load_balance_query { old_find_by_sql sql }
        else
          old_find_by_sql sql
        end
      end

      alias_method :old_count_by_sql, :count_by_sql
      def count_by_sql(sql, use_slave = true)
        use_slave = get_use_slave(use_slave)
        if slave_valid(use_slave)
          connection.load_balance_query { old_count_by_sql sql }
        else
          old_count_by_sql sql
        end
      end

      
      alias_method :old_calculate, :calculate
      def calculate(operation, column_name, options ={})
        use_slave = options.delete(:use_slave) { true }
        if slave_valid(use_slave)
          connection.load_balance_query { 
            old_calculate(operation, column_name, options)
          }
        else
          old_calculate(operation, column_name, options)
        end
      end

    end
    
  end
end
