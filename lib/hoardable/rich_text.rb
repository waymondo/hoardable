# frozen_string_literal: true

module Hoardable
  # A {Hoardable} subclass of {ActionText::RichText}
  class RichText < ActionText::RichText
    include Model
  end
end
