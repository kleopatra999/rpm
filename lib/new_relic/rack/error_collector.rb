# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic::Rack
  class ErrorCollector
    def initialize(app, options={})
      ::NewRelic::Agent.logger.info 'ErrorCollector initialized'
      @app = app
    end

    def call(env)
      ::NewRelic::Agent.logger.info 'ErrorCollector called before'
      @app.call(env)
      ::NewRelic::Agent.logger.info 'ErrorCollector called after'
    rescue Exception => exception
      ::NewRelic::Agent.logger.info '--- exception'
      ::NewRelic::Agent.logger.info exception.class
      ::NewRelic::Agent.logger.info exception.message

      NewRelic::Agent.logger.debug "collecting %p: %s" % [ exception.class, exception.message ]
      request = Rack::Request.new(env)

      ::NewRelic::Agent.logger.info "should_ignore? #{should_ignore_error?(exception, request)}"
      ::NewRelic::Agent.logger.info "instance ignore? #{NewRelic::Agent.instance.error_collector.error_is_ignored?(error)}"
      ::NewRelic::Agent.logger.info "controller ignore? #{ignored_in_controller?(exception, request)}"

      if !should_ignore_error?(exception, request)
        params = begin
          request.params
        rescue => err
          warning = "failed to capture request parameters: %p: %s" % [ err.class, err.message ]
          NewRelic::Agent.logger.warn(warning)
          {'error' => warning}
        end

        NewRelic::Agent.notice_error(exception,
                                      :uri => request.path,
                                      :referer => request.referer,
                                      :request_params => params)
      end
      raise exception
    end

    def should_ignore_error?(error, request)
      NewRelic::Agent.instance.error_collector.error_is_ignored?(error) ||
        ignored_in_controller?(error, request)
    end

    def ignored_in_controller?(exception, request)
      return true if request.env['newrelic.ignored']

      if request.env['action_dispatch.request.parameters']
        ignore_actions = newrelic_ignore_for_controller(request.env['action_dispatch.request.parameters']['controller'])
        action_name = request.env['action_dispatch.request.parameters']['action']

        case ignore_actions
        when nil; false
        when Hash
          only_actions = Array(ignore_actions[:only])
          except_actions = Array(ignore_actions[:except])
          only_actions.include?(action_name.to_sym) ||
            (except_actions.any? &&
             !except_actions.include?(action_name.to_sym))
        else
          true
        end
      end
    end

    def newrelic_ignore_for_controller(controller_name)
      if controller_name
        controller_constant_name = (controller_name + "_controller").camelize
        if Object.const_defined?(controller_constant_name)
          controller = controller_constant_name.constantize
          controller.instance_variable_get(:@do_not_trace)
        end
      end
    rescue NameError
      nil
    end
  end
end
