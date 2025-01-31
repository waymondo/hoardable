require "helper"

class TestThreadSafety < ActiveSupport::TestCase
  private attr_reader :threads_count

  setup { @threads_count = 5 }

  test "whodunnit respects thread-safety" do
    threads =
      threads_count.times.map do |i|
        Thread.new do
          Hoardable.with(whodunit: i) do
            threads_count.times.map do
              sleep(Random.new.rand(0.5))
              Hoardable.whodunit
            end
          end
        end
      end

    threads.each(&:join)

    assert_equal(
      Array.new(threads_count) { |i| Array.new(threads_count) { i } },
      threads.map { |t| t.value }
    )
  end

  test "with_hoardable_config respects thread-safety" do
    reset_db

    user = User.create!(name: "Joe Schmoe")

    Array
      .new(threads_count) do |i|
        [
          Thread.new do
            sleep(Random.new.rand(0.5))

            user.update!(name: "Joe #{i}")
          end,
          Thread.new do
            User.with_hoardable_config(version_updates: false) do
              sleep(Random.new.rand(0.5))

              user.update!(name: "Joe #{i}")
            end
          end
        ]
      end
      .flatten
      .each(&:join)

    assert_equal 5, user.versions.count
  end
end
