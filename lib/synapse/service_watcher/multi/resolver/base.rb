require "synapse/log"
require "synapse/statsd"

class Synapse::ServiceWatcher::Resolver
  class BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def initialize(opts, watchers)
      super()

      log.info "creating base resolver"

      @opts = opts
      @watchers = watchers
      validate_opts
    end

    def validate_opts
      raise ArgumentError, "base resolver expects method to be base" unless @opts['method'] == 'base'
      raise ArgumentError, "no watchers provided" unless @watchers.length > 0
    end

    # should be overridden in child classes
    def start
      log.info "starting base resolver"
    end

    # should be overridden in child classes
    def stop
      log.info "stopping base resolver"
    end

    # should be overridden in child classes
    def merged_backends
      return []
    end

    # should be overridden in child classes
    def healthy?
      return true
    end
  end
end
