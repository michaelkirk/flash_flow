require 'minitest_helper'

module FlashFlow
  class TestBranchInfoStore < Minitest::Test
    def sample_branches
      {
          'origin/branch 1' => { 'branch' => 'branch 1', 'remote' => 'origin', 'status' => 'success', 'stories' => ['123'] },
          'other_origin/branch 2' => { 'branch' => 'branch 2', 'remote' => 'origin', 'status' => 'success', 'stories' => ['456'] }
      }
    end

    def setup
      @storage = BranchInfoStore.new('/dev/null')
    end

    def test_get
      str = StringIO.new(sample_branches.to_json)
      assert_equal(@storage.get(str), sample_branches)
    end

    def test_write
      str = StringIO.new
      @storage.write(sample_branches, str)

      assert_equal(str.string.strip, sample_branches.to_json.strip)
    end


  end
end
