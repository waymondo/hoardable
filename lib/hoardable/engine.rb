# frozen_string_literal: true

module Hoardable
  # A +Rails+ engine for providing support for +ActionText+
  class Engine < ::Rails::Engine
    isolate_namespace Hoardable

    initializer 'hoardable.action_text' do
      ActiveSupport.on_load(:action_text_rich_text) do
        require_relative 'rich_text'
      end
    end
  end
end
