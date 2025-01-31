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

  test "can reset model level hoardable config to previous value" do
    Thread.new do
      Post.hoardable_config(version_updates: false)
      Post.with_hoardable_config(version_updates: true) do
        assert Post.hoardable_config[:version_updates]
      end
      assert_not Post.hoardable_config[:version_updates]

      # reset
      Post.hoardable_config(version_updates: true)
    end
  end

  test "can reset hoardable version_updates to previous value" do
    skip("testing this is the problem")
    Thread.new do
      Hoardable.version_updates = false
      Hoardable.with(version_updates: true) { assert Hoardable.version_updates }
      assert_not Hoardable.version_updates

      # reset
      Hoardable.version_updates = false
    end
  end
end
