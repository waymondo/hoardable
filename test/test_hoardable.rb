# frozen_string_literal: true

require 'test_helper'

class TestHoardable < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Hoardable::VERSION
  end
end
