require 'flash_flow/cmd_runner'

module FlashFlow
  class Git
    ATTRIBUTES = [:merge_remote, :merge_branch, :master_branch, :use_rerere]
    attr_reader *ATTRIBUTES
    attr_reader :working_branch

    UNMERGED_STATUSES = %w{DD AU UD UA DU AA UU}

    def initialize(config, logger=nil)
      @cmd_runner = CmdRunner.new(logger: logger)

      ATTRIBUTES.each do |attr|
        unless config.has_key?(attr.to_s)
          raise RuntimeError.new("git configuration missing. Required config parameters: #{ATTRIBUTES}")
        end

        instance_variable_set("@#{attr}", config[attr.to_s])
      end

      @working_branch = current_branch
    end

    def last_stdout
      @cmd_runner.last_stdout
    end

    def last_command
      @cmd_runner.last_command
    end

    def last_success?
      @cmd_runner.last_success?
    end

    def run(cmd)
      @cmd_runner.run("git #{cmd}")
    end

    def add_and_commit(files, message, opts={})
      files = [files].flatten
      run("add #{'-f ' if opts[:add] && opts[:add][:force]}#{files.join(' ')}")
      run("commit -m '#{message}'")
    end

    def push(branch, options)
      run("push #{'-f' if options[:force]} #{merge_remote} #{branch}")
    end

    def merge(branch)
      run("merge #{branch}")
    end

    def fetch(remote)
      run("fetch #{remote}")
    end

    def master_branch_contains?(ref)
      run("branch --contains #{ref}")
      last_stdout.split("\n").detect { |str| str[2..-1] == master_branch }
    end

    def in_original_merge_branch
      begin
        starting_branch = current_branch
        run("checkout #{merge_remote}/#{merge_branch}")

        yield
      ensure
        run("checkout #{starting_branch}")
      end
    end

    def read_file_from_merge_branch(filename)
      run("show #{merge_remote}/#{merge_branch}:#{filename}")
      last_stdout
    end

    def initialize_rerere
      return unless use_rerere

      @cmd_runner.run('mkdir .git/rr-cache')
      @cmd_runner.run('cp -R rr-cache/* .git/rr-cache/')
    end

    def commit_rerere(current_rereres)
      return unless use_rerere
      @cmd_runner.run('mkdir rr-cache')
      @cmd_runner.run('rm -rf rr-cache/*')
      current_rereres.each do |rerere|
        @cmd_runner.run("cp -R .git/rr-cache/#{rerere} rr-cache/")
      end

      run('add rr-cache/')
      run("commit -m 'Update rr-cache'")
    end

    def rerere_resolve!
      return false unless use_rerere

      if unresolved_conflicts.empty?
        merging_files = staged_and_working_dir_files.select { |s| UNMERGED_STATUSES.include?(s[0..1]) }.map { |s| s[3..-1] }
        conflicts = conflicted_files

        run("add #{merging_files.join(" ")}")
        run('commit --no-edit')

        resolutions(conflicts)
      else
        false
      end
    end

    def unresolved_conflicts
      conflicted_files.map do |file|
        File.open(file) { |f| f.grep(/>>>>/) }.empty? ? nil : file
      end.compact
    end

    def resolutions(files)
      {}.tap do |hash|
        files.map do |file|
          hash[file] = resolution_candidates(file)
        end.flatten
      end
    end

    # git rerere doesn't give you a deterministic way to determine which resolution was used
    def resolution_candidates(file)
      @cmd_runner.run("diff -q --from-file #{file} .git/rr-cache/*/postimage")
      different_files = split_diff_lines(@cmd_runner.last_stdout)

      @cmd_runner.run('ls -la .git/rr-cache/*/postimage')
      all_files = split_diff_lines(@cmd_runner.last_stdout)

      all_files - different_files
    end

    def split_diff_lines(arr)
      arr.split("\n").map { |s| s.split(".git/rr-cache/").last.split("/postimage").first }
    end

    def remotes
      run('remote -v')
      last_stdout.split("\n")
    end

    def remotes_hash
      return @remotes_hash if @remotes_hash

      @remotes_hash = {}
      remotes.each do |r|
        name = r.split[0]
        url = r.split[1]
        @remotes_hash[name] ||= url
      end
      @remotes_hash
    end

    def fetch_remote_for_url(url)
      fetch_remotes = remotes.grep(Regexp.new(url)).grep(/ \(fetch\)/)
      fetch_remotes.map { |remote| remote.to_s.split("\t").first }.first
    end

    def staged_and_working_dir_files
      run("status --porcelain")
      last_stdout.split("\n").reject { |line| line[0..1] == '??' }
    end

    def conflicted_files
      run("diff --name-only --diff-filter=U")
      last_stdout.split("\n")
    end

    def current_branch
      run("rev-parse --abbrev-ref HEAD")
      last_stdout.strip
    end

    def most_recent_commit
      run("show -s --format=%cd head")
    end

    def reset_temp_merge_branch
      in_branch(master_branch) do
        run("fetch #{merge_remote}")
        run("branch -D #{temp_merge_branch}")
        run("checkout -b #{temp_merge_branch}")
        run("reset --hard #{merge_remote}/#{master_branch}")
      end
    end

    def push_merge_branch
      run("push -f #{merge_remote} #{merge_branch}")
    end

    def copy_temp_to_merge_branch
      run("checkout #{temp_merge_branch}")
      run("merge --strategy=ours --no-edit #{merge_branch}")
      run("checkout #{merge_branch}")
      run("merge #{temp_merge_branch}")

      squash_commits
    end

    def commit_message(log)
      "Flash Flow run from branch: #{working_branch}\n\n#{log}".gsub(/'/, '')
    end

    def delete_temp_merge_branch
      in_merge_branch do
        run("branch -d #{temp_merge_branch}")
      end
    end

    def in_temp_merge_branch(&block)
      in_branch(temp_merge_branch, &block)
    end

    def in_merge_branch(&block)
      in_branch(merge_branch, &block)
    end

    def in_branch(branch)
      begin
        starting_branch = current_branch
        run("checkout #{branch}")

        yield
      ensure
        run("checkout #{starting_branch}")
      end
    end

    private

    def squash_commits
      # There are three commits created by flash flow that we don't need in the message
      run("log #{merge_remote}/#{merge_branch}..#{merge_branch}~3")
      log = last_stdout

      # Get all the files that differ between existing acceptance and new acceptance
      run("diff --name-only #{merge_remote}/#{merge_branch} #{merge_branch}")
      files = last_stdout.split("\n")
      run("reset #{merge_remote}/#{merge_branch}")
      run("add #{files.map { |f| "'#{f}'" }.join(" ")}")

      run("commit -m '#{commit_message(log)}'")
    end

    def temp_merge_branch
      "flash_flow/#{merge_branch}"
    end

  end
end
