# frozen_string_literal: true

module Hoardable
  # A {Hoardable} subclass of {ActionText::EncryptedRichText}.
  class EncryptedRichText < ActionText::EncryptedRichText
    include Model
  end
end
