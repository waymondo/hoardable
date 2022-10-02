# frozen_string_literal: true

require 'rails/generators'

module Hoardable
  # Generates an initializer file for {Hoardable} configuration.
  class InitializerGenerator < Rails::Generators::Base
    def create_initializer_file
      create_file(
        'config/initializers/hoardable.rb',
        <<~TEXT
          # Hoardable configuration defaults are below. Learn more at https://github.com/waymondo/hoardable#configuration
          #
          # Hoardable.enabled = true
          # Hoardable.version_updates = true
          # Hoardable.save_trash = true
          # Hoardable.return_everything = true
        TEXT
      )
    end
  end
end
