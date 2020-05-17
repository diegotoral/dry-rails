# frozen_string_literal: true

require "rails/railtie"

module Dry
  module Rails
    # The railtie is responsible for setting up a container and handling reloading in dev mode
    #
    # @api public
    class Railtie < ::Rails::Railtie
      # This is needed because `finalize!` can reload code and this hook is called every-time
      # in development env upon a request (in production it's called just once during booting)
      config.to_prepare do
        Railtie.finalize!
      end

      # Code-reloading-aware finalization process
      #
      # This sets up `Container` and `Import` constants, reloads them if this is in reloading mode,
      # and registers default components like the railtie itself or the inflector
      #
      # @api public
      def finalize!
        stop_features if reloading?

        root_path = ::Rails.root

        container = Dry::Rails.create_container(
          root: root_path,
          name: name,
          default_namespace: name.to_s,
          inflector: default_inflector,
          system_dir: root_path.join("config/system")
        )

        container.register(:railtie, self)
        container.register(:inflector, default_inflector)

        set_or_reload(:Container, container)

        Dry::Rails.evaluate_initializer(container)

        set_or_reload(container.auto_inject_constant, container.injector)

        container.features.each do |feature|
          container.boot(feature, from: :rails)
        end

        container.refresh_boot_files if reloading?

        container.finalize!(freeze: !::Rails.env.test?)
      end
      alias_method :reload, :finalize!

      # Stops all configured features (bootable components)
      #
      # This is *crucial* when reloading code in development mode. Every bootable component
      # should be able to clear the runtime from any constants that it created in its `stop`
      # lifecycle step
      #
      # @api public
      def stop_features
        container.features.each do |feature|
          container.stop(feature) if container.booted?(feature)
        end
      end

      # Exposes the container constant
      #
      # @return [Dry::Rails::Container]
      #
      # @api public
      def container
        app_namespace.const_get(:Container)
      end

      # Return true if we're in code-reloading mode
      #
      # @api private
      def reloading?
        app_namespace.const_defined?(:Container)
      end

      # Return the default system name
      #
      # In the dry-system world containers are explicitly named using symbols, so that you can
      # refer to them easily when ie importing one container into another
      #
      # @return [Symbol]
      #
      # @api private
      def name
        app_namespace.name.underscore.to_sym
      end

      # Infer the default application namespace
      #
      # TODO: we had to rename namespace=>app_namespace because
      #       Rake::DSL's Kernel#namespace *sometimes* breaks things.
      #       Currently we are missing specs verifying that rake tasks work
      #       correctly and those must be added!
      #
      # @return [Module]
      #
      # @api public
      def app_namespace
        @app_namespace ||= begin
          top_level_namespace = ::Rails.application.class.to_s.split("::").first
          Object.const_get(top_level_namespace)
        end
      end

      # Sets or reloads a constant within the application namespace
      #
      # @api private
      def default_inflector
        ActiveSupport::Inflector
      end

      # @api private
      def set_or_reload(const_name, const)
        if app_namespace.const_defined?(const_name)
          app_namespace.__send__(:remove_const, const_name)
        end

        app_namespace.const_set(const_name, const)
      end

      # @api private
      def remove_constant(const_name)
        app_namespace.__send__(:remove_const, const_name)
      end
    end
  end
end
