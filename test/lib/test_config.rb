require 'minitest_helper'

module FlashFlow
  class TestConfig < Minitest::Test
    def setup
      @yaml = {
          'use_rerere' => true,
          'merge_branch' => 'acceptance',
          'master_branch' => 'master',
          'repo' => 'flashfunders/flash_flow',
          'locking_issue_id' => 1,
          'unmergeable_label' => 'some_label',
          'do_not_merge_label' => 'dont merge',
          'branch_info_file' => 'some_file.txt',
          'hipchat_token' => ENV['HIPCHAT_TOKEN']
      }

      reset_config!
    end

    def test_that_it_sets_all_attrs
      YAML.stub(:load_file, @yaml) do
        Config.configure!('unused_file_name.yml')
        assert(true == Config.configuration.use_rerere)
        assert('acceptance' == Config.configuration.merge_branch)
        assert('master' == Config.configuration.master_branch)
        assert('flashfunders/flash_flow' == Config.configuration.repo)
        assert(1 == Config.configuration.locking_issue_id)
        assert('some_label' == Config.configuration.unmergeable_label)
        assert('dont merge' == Config.configuration.do_not_merge_label)
        assert('some_file.txt' == Config.configuration.branch_info_file)
        assert('hip_token' == Config.configuration.hipchat_token)
      end
    end

    def test_that_it_blows_up
      @yaml.delete('repo')

      YAML.stub(:load_file, @yaml) do
        assert_raises FlashFlow::Config::IncompleteConfiguration do
          Config.configure!('unused_file_name.yml')
        end
      end
    end

    def test_that_it_sets_defaults
      YAML.stub(:load_file, { 'repo' => 'some_repo' }) do
        Config.configure!('unused_file_name.yml')
        assert(true == Config.configuration.use_rerere)
        assert('origin' == Config.configuration.merge_remote)
        assert('acceptance' == Config.configuration.merge_branch)
        assert('master' == Config.configuration.master_branch)
        assert(Config.configuration.locking_issue_id.nil?)
        assert('unmergeable' == Config.configuration.unmergeable_label)
        assert('do not merge' == Config.configuration.do_not_merge_label)
        assert('README.rdoc' == Config.configuration.branch_info_file)
        assert(['origin'] == Config.configuration.remotes)
        assert('hip_token' == Config.configuration.hipchat_token)
      end
    end
  end
end
