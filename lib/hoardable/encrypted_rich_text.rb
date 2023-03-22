# frozen_string_literal: true

module Hoardable
  # A {Hoardable} subclass of {ActionText::RichText} like {ActionText::EncryptedRichText}.
  class EncryptedRichText < ActionText::RichText
    include Model
    encrypts :body
  end
end
