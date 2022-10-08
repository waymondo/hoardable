# frozen_string_literal: true

module Hoardable
  class RichText < ActionText::RichText
    include Model
  end

  class EncryptedRichText < ActionText::EncryptedRichText
    include Model
  end
end
