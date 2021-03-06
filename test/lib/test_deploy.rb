require 'minitest_helper'
require 'minitest/stub_any_instance'

module FlashFlow
  class TestDeploy < Minitest::Test

    def setup
      reset_config!
      config!(git: {
                  'merge_branch' => 'test_acceptance',
                  'merge_remote' => 'test_remote',
                  'master_branch' => 'test_master',
                  'remotes' => ['fake_origin'],
                  'use_rerere' => true
              })

      @branch = Branch::Base.from_hash({'ref' => 'pushing_branch', 'remote' => 'origin', 'status' => 'fail', 'stories' => []})
      @deploy = Deploy.new
    end

    def test_print_errors_with_no_errors
      collection = Minitest::Mock.new
      collection.expect(:failures, {})
      assert_equal(@deploy.format_errors, 'Success!')
    end

    def test_print_errors_when_current_branch_cant_merge
      collection = Minitest::Mock.new
      collection.expect(:failures, {'origin/pushing_branch' => @branch})
      @branch.fail!('some_random_sha')

      @deploy.instance_variable_set('@branches'.to_sym, collection)

      current_branch_error = "\nERROR: Your branch did not merge to test_acceptance. Run the following commands to fix the merge conflict and then re-run this script:\n\n  git checkout some_random_sha\n  git merge pushing_branch\n  # Resolve the conflicts\n  git add <conflicted files>\n  git commit --no-edit"

      @deploy.instance_variable_get('@git'.to_sym).stub(:working_branch, 'pushing_branch') do
        assert_equal(current_branch_error, @deploy.format_errors)
      end
    end

    def test_print_errors_when_another_branch_cant_merge
      collection = Minitest::Mock.new
      collection.expect(:failures, {'origin/pushing_branch' => @branch})

      @deploy.instance_variable_set('@branches'.to_sym, collection)

      other_branch_error = "WARNING: Unable to merge branch origin/pushing_branch to test_acceptance due to conflicts."

      assert_equal(@deploy.format_errors, other_branch_error)
    end

    def test_check_out_to_working_branch
      @deploy.stub(:check_repo, true) do
        Lock::Base.stub_any_instance(:with_lock, -> { raise Lock::Error }) do
          assert_output(/Failure!/) { @deploy.run }
        end
      end
    end

    def test_merge_conflict_notification
      collection = Minitest::Mock.new
      collection.expect(:mark_failure, true, [@branch, true])
      @deploy.instance_variable_set('@branches'.to_sym, collection)

      notifier = Minitest::Mock.new
      notifier.expect(:merge_conflict, true, [@branch])
      @deploy.instance_variable_set('@notifier'.to_sym, notifier)

      @deploy.stub(:merge_success?, false) do
        @deploy.stub(:merge_rollback, true) do
          @deploy.git_merge(@branch)
        end
      end
      notifier.verify
    end

    def test_ignore_pushing_master_or_acceptance
      ['test_master', 'test_acceptance'].each do |branch|
        @deploy.instance_variable_get('@git'.to_sym).stub(:working_branch, branch) do
          refute(@deploy.open_pull_request)
        end
      end
    end

    def test_merge_rollback
      git = Minitest::Mock.new
      git.expect(:run, nil, ["reset --hard HEAD"])
      git.expect(:run, nil, ["rev-parse HEAD"])
      git.expect(:last_stdout, "hello\n", [])
      @deploy.instance_variable_set('@git'.to_sym, git)

      assert_equal(@deploy.send(:merge_rollback), 'hello')
      assert(git.verify)
    end
  end
end
