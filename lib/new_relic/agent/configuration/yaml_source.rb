require 'new_relic/agent/configuration'

module NewRelic
  module Agent
    module Configuration
      class YamlSource < DottedHash
        attr_accessor :file_path

        def initialize(path, env)
          config = {}
          begin
            @file_path = File.expand_path(path)
            if !File.exists?(@file_path)
              startup_safe_log.error("Unable to load configuration from #{path}")
              return
            end

            file = File.read(@file_path)

            # Next two are for populating the newrelic.yml via erb binding, necessary
            # when using the default newrelic.yml file
            generated_for_user = ''
            license_key = ''

            erb = ERB.new(file).result(binding)
            config = merge!(YAML.load(erb)[env] || {})
          rescue ScriptError, StandardError => e
            startup_safe_log.warn("Unable to read configuration file #{path}: #{e}")
          end

          if config['transaction_tracer'] &&
              config['transaction_tracer']['transaction_threshold'] =~ /apdex_f/i
            # when value is "apdex_f" remove the config and defer to default
            config['transaction_tracer'].delete('transaction_threshold')
          end

          booleanify_values(config, 'agent_enabled', 'enabled', 'monitor_daemons')

          super(config)
        end

        protected

        # This class specifically gets used at the very top of our startup
        # before we have set up logging. We don't normally wrap the logger
        # but here it makes sense to so we can get some error out if we fail.
        def startup_safe_log
          NewRelic::Agent.logger || ::Logger.new(STDOUT)
        end

        def booleanify_values(config, *keys)
          # auto means defer ro default
          keys.each do |option|
            if config[option] == 'auto'
              config.delete(option)
            elsif !config[option].nil? && !is_boolean?(config[option])
              config[option] = !!(config[option] =~ /yes|on|true/i)
            end
          end
        end

        def is_boolean?(value)
          value == !!value
        end
      end
    end
  end
end
